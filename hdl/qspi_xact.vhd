-- QSPI transaction engine: one command -> one CS# assertion, via qspi_phy
--
--   cmd_* (valid/ready) --> phase descriptors --> qspi_phy --> pins
--   s_axis (TX bytes)   -->                      qspi_phy
--   m_axis (RX bytes)   <--                      qspi_phy
--
--   A command is: opcode (8 clocks on IO0), optional address (cmd_addr_bytes bytes, MSB first),
--   optional mode byte, optional latency/dummy clocks, optional data. cmd_lanes selects where
--   address and data go:
--     L111: address, mode, latency and data on 1 line (data in on IO1)
--     L114: address on 1 line; latency and data on 4 lines
--     L144: address, mode, latency and data on 4 lines
--   One die (one CS#, IO3:0). The address is the die byte address.
--
-- Data, cmd_len and the streams:
--   cmd_len = number of data bytes (one stream byte = one device byte).
--   4-line data: 2 SCLK cycles per byte, high nibble first. 1-line data: 8 SCLK cycles per byte,
--     MSB first. RX phases are at most 2**17 - 1 clocks: 4-line any cmd_len, 1-line <= 16383.
--   m_axis_tlast marks the last stream byte of a command. TX commands take exactly the stream
--     bytes they need; s_axis_tlast is ignored.
--   RX has no real backpressure (the PHY can't stop SCLK): a 4-entry FIFO absorbs short stalls,
--   and rx_overflow pulses when a byte had to be dropped. The consumer must keep up.
--   TX: the next 32-bit chunk (4 bytes) is collected while the previous one is sent; if the TX
--   stream is late, SCLK pauses (CS# stays low).
--
-- CS# high time after the command: the device's write value if cmd_write = '1' (WREN, writes,
-- erase, register writes), else the read value (device_facts.md §1), converted with CLK_HZ.
--
-- cmd_ready is high when idle. A command with RX data is finished after its last RX byte, a
-- command without RX data after its last phase has gone to the PHY, so the next command's
-- opcode follows directly (the PHY keeps the CS# high time).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.qspi_pkg.all;

entity qspi_xact is
    generic (
        DEVICE       : device_t := DEV_W25Q128JV;
        CLK_HZ       : positive := 200_000_000    -- clk (clk_ctrl) frequency
    );
    port (
        clk            : in  std_logic;
        reset_n        : in  std_logic;             -- Synchronous, active low

        -- Command
        cmd_valid      : in  std_logic;
        cmd_ready      : out std_logic;
        cmd_op         : in  std_logic_vector(7 downto 0);
        cmd_lanes      : in  cmd_lanes_t;
        cmd_addr       : in  std_logic_vector(31 downto 0);   -- Die byte address
        cmd_addr_bytes : in  natural range 0 to 4;            -- 0: no address
        cmd_mode_en    : in  std_logic;                       -- Send cmd_mode after the address
        cmd_mode       : in  std_logic_vector(7 downto 0);
        cmd_latency    : in  natural range 0 to 15;           -- Dummy/latency clocks
        cmd_dir        : in  dir_t;                           -- Data: none, TX or RX
        cmd_len        : in  unsigned(15 downto 0);           -- Data bytes; >= 1 if cmd_dir /= DIR_NONE
        cmd_sclk_div   : in  natural range 1 to SCLK_DIV_MAX; -- SCLK = CLK_HZ / (2 * div)
        cmd_write      : in  std_logic;                       -- Long CS# high time afterwards

        -- TX data
        s_axis_tdata   : in  std_logic_vector(7 downto 0);
        s_axis_tvalid  : in  std_logic;
        s_axis_tready  : out std_logic;

        -- RX data
        m_axis_tdata   : out std_logic_vector(7 downto 0);
        m_axis_tvalid  : out std_logic;
        m_axis_tready  : in  std_logic;
        m_axis_tlast   : out std_logic;
        rx_overflow    : out std_logic;                       -- One-cycle pulse: RX byte dropped

        sample_dly     : in  natural range 1 to SAMPLE_DLY_MAX;
        busy           : out std_logic;                       -- Command, PHY or RX output active

        -- Pins (see qspi_phy)
        sclk           : out std_logic;
        cs_n           : out std_logic;
        io_o           : out std_logic_vector(3 downto 0);
        io_oe          : out std_logic_vector(3 downto 0);
        io_i           : in  std_logic_vector(3 downto 0)
    );
end entity qspi_xact;

architecture rtl of qspi_xact is

    constant P     : dev_params_t := dev_params(DEVICE);
    -- +1 cycle margin: CS# rises slower than it falls at the device pin, so the high time there
    -- is a few ns shorter than in the fabric (hardware: 6-8 ns for 10 ns, 46-48 ns for 50 ns)
    constant CS_RD : positive := ns_to_cycles(P.t_cs_rd_ns, CLK_HZ) + 1;
    constant CS_WR : positive := ns_to_cycles(P.t_cs_wr_ns, CLK_HZ) + 1;
    constant NCLK_W : positive := 17;    -- PHY clock count: 2 * 65535 data clocks (4-line RX)

    type state_t is (X_IDLE, X_ISSUE, X_RXWAIT);
    type ph_sel_t is (PH_OP, PH_ADDR, PH_MODE, PH_LAT, PH_DATA, PH_DONE);

    -- The phase that follows ph for a command with these fields
    function next_ph(ph : ph_sel_t; ab : natural; mode_en : std_logic; lat : natural;
                     dir : dir_t) return ph_sel_t is
    begin
        if ph = PH_OP and ab > 0 then
            return PH_ADDR;
        elsif (ph = PH_OP or ph = PH_ADDR) and mode_en = '1' then
            return PH_MODE;
        elsif (ph = PH_OP or ph = PH_ADDR or ph = PH_MODE) and lat > 0 then
            return PH_LAT;
        elsif ph /= PH_DATA and ph /= PH_DONE and dir /= DIR_NONE then
            return PH_DATA;
        else
            return PH_DONE;
        end if;
    end function;

    function lanes_of(quad : boolean) return lane_mode_t is
    begin
        if quad then
            return QUAD4;
        end if;
        return SPI1;
    end function;

    -- Bytes in the next TX chunk: min(len, 4)
    function chunk_bytes(len : unsigned(15 downto 0)) return natural is
    begin
        if len > 4 then
            return 4;
        end if;
        return to_integer(len);
    end function;

    -- Latched command
    signal c_op      : std_logic_vector(7 downto 0) := (others => '0');
    signal c_lanes   : cmd_lanes_t := L111;
    signal c_addr    : std_logic_vector(31 downto 0) := (others => '0');
    signal c_ab      : natural range 0 to 4 := 0;
    signal c_mode_en : std_logic := '0';
    signal c_mode    : std_logic_vector(7 downto 0) := (others => '0');
    signal c_lat     : natural range 0 to 15 := 0;
    signal c_dir     : dir_t := DIR_NONE;
    signal c_div     : natural range 1 to SCLK_DIV_MAX := 1;
    signal c_cs_high : unsigned(7 downto 0) := (others => '0');

    signal state     : state_t := X_IDLE;
    signal cur_ph    : ph_sel_t := PH_DONE;
    signal data_left : unsigned(15 downto 0) := (others => '0');   -- TX bytes still to issue
    -- data_left = col_target (the chunk being collected is the last), one cycle behind: both
    -- change only on a handshake or a command latch, and the next TX data handshake is at least
    -- two cycles later. Registered for timing at 200 MHz.
    signal last_chunk : std_logic := '0';

    -- TX chunk collector (up to 4 bytes, first byte in bits 31:24)
    signal col_active : std_logic := '0';
    signal col_target : natural range 0 to 4 := 0;                 -- Bytes in the current chunk
    signal col_k      : natural range 0 to 4 := 0;                 -- Bytes collected
    signal chunk_full : std_logic := '0';
    signal chunk_tx   : std_logic_vector(31 downto 0) := (others => '0');

    -- PHY descriptor registers
    signal ph_valid   : std_logic := '0';
    signal ph_ready   : std_logic;
    signal ph_lanes   : lane_mode_t := SPI1;
    signal ph_dir     : dir_t := DIR_NONE;
    signal ph_nclk    : unsigned(NCLK_W - 1 downto 0) := (others => '0');
    signal ph_tx      : std_logic_vector(31 downto 0) := (others => '0');
    signal ph_last    : std_logic := '0';
    signal ph_cs_high : unsigned(7 downto 0) := (others => '0');

    signal rx_valid   : std_logic;
    signal rx_data    : std_logic_vector(3 downto 0);
    signal rx_last    : std_logic;
    signal phy_busy   : std_logic;

    -- RX: byte assembly (2 nibbles or 8 bits) and the output FIFO ({last, data})
    signal acc        : std_logic_vector(7 downto 0) := (others => '0');
    signal acc_n      : natural range 0 to 7 := 0;                 -- Words in acc
    -- RX FIFO: capacity 4, but 8 slots, so an incoming byte can be written before the overflow
    -- check without touching unread entries (keeps pop / f_cnt out of the write enable)
    type fifo_t is array (0 to 7) of std_logic_vector(8 downto 0);
    signal fifo       : fifo_t := (others => (others => '0'));
    attribute syn_ramstyle : string;
    attribute syn_ramstyle of fifo : signal is "registers";      -- 8 entries: flip-flops, not RAM
    signal f_rd, f_wr : unsigned(2 downto 0) := (others => '0');
    signal f_cnt      : natural range 0 to 4 := 0;
    signal ovf        : std_logic := '0';
    signal rx_done    : std_logic := '0';                          -- Last RX byte queued

    signal s_ready_i  : std_logic;
begin
    cmd_ready     <= '1' when state = X_IDLE else '0';
    s_ready_i     <= col_active and not chunk_full;
    s_axis_tready <= s_ready_i;
    busy          <= '0' when state = X_IDLE and phy_busy = '0' and f_cnt = 0 else '1';

    m_axis_tvalid <= '1' when f_cnt /= 0 else '0';
    m_axis_tdata  <= fifo(to_integer(f_rd))(7 downto 0);
    m_axis_tlast  <= fifo(to_integer(f_rd))(8);
    rx_overflow   <= ovf;

    -------------------------------------------------------------------------------------------
    -- Command FSM, descriptor issue and TX chunk collection
    -------------------------------------------------------------------------------------------
    process (clk)
        variable nph     : ph_sel_t;
        variable quad_ad : boolean;     -- Address / mode on 4 lines
        variable quad_d  : boolean;     -- Latency / data on 4 lines
        variable n_bytes : natural range 0 to 4;
        variable left    : unsigned(15 downto 0);
        variable hs      : boolean;

        -- Present the descriptor for phase ph of the latched command (TX data from the chunk)
        procedure present(ph : ph_sel_t) is
        begin
            quad_ad := c_lanes = L144;
            quad_d  := c_lanes /= L111;
            ph_valid   <= '1';
            ph_dir     <= DIR_TX;
            ph_tx      <= (others => '0');
            ph_last    <= '0';
            ph_cs_high <= c_cs_high;
            case ph is
                when PH_OP =>
                    ph_lanes <= SPI1;
                    ph_nclk  <= to_unsigned(8, NCLK_W);
                    ph_tx(31 downto 24) <= c_op;
                when PH_ADDR =>
                    ph_lanes <= lanes_of(quad_ad);
                    ph_nclk  <= to_unsigned(c_ab * (2 + 6 * boolean'pos(not quad_ad)), NCLK_W);
                    ph_tx    <= std_logic_vector(shift_left(unsigned(c_addr), 32 - 8 * c_ab));
                when PH_MODE =>
                    ph_lanes <= lanes_of(quad_ad);
                    ph_nclk  <= to_unsigned(2 + 6 * boolean'pos(not quad_ad), NCLK_W);
                    ph_tx(31 downto 24) <= c_mode;
                when PH_LAT =>
                    ph_lanes <= lanes_of(quad_d);
                    ph_dir   <= DIR_NONE;
                    ph_nclk  <= to_unsigned(c_lat, NCLK_W);
                when others =>                                   -- PH_DATA
                    ph_lanes <= lanes_of(quad_d);
                    ph_dir   <= c_dir;
                    if c_dir = DIR_RX then
                        if quad_d then
                            ph_nclk <= shift_left(resize(data_left, NCLK_W), 1);
                        else
                            ph_nclk <= shift_left(resize(data_left, NCLK_W), 3);
                        end if;
                    else
                        if quad_d then
                            ph_nclk <= to_unsigned(2 * col_target, NCLK_W);
                        else
                            ph_nclk <= to_unsigned(8 * col_target, NCLK_W);
                        end if;
                        ph_tx <= chunk_tx;
                    end if;
            end case;
        end procedure;
    begin
        if rising_edge(clk) then
            hs := ph_valid = '1' and ph_ready = '1';
            if data_left = col_target then
                last_chunk <= '1';
            else
                last_chunk <= '0';
            end if;

            ---------------------------------------------------------------- TX chunk collector
            -- Same byte layout for 4 lines (high nibble first) and 1 line (MSB first)
            if s_ready_i = '1' and s_axis_tvalid = '1' then
                for i in 0 to 3 loop
                    if i = col_k then
                        chunk_tx(31 - 8 * i downto 24 - 8 * i) <= s_axis_tdata;
                    end if;
                end loop;
                col_k <= col_k + 1;
                if col_k + 1 = col_target then
                    chunk_full <= '1';
                end if;
            end if;

            ---------------------------------------------------------------- Command FSM
            case state is
                when X_IDLE =>
                    if cmd_valid = '1' then
                        c_op      <= cmd_op;
                        c_lanes   <= cmd_lanes;
                        c_addr    <= cmd_addr;
                        c_ab      <= cmd_addr_bytes;
                        c_mode_en <= cmd_mode_en;
                        c_mode    <= cmd_mode;
                        c_lat     <= cmd_latency;
                        c_dir     <= cmd_dir;
                        c_div     <= cmd_sclk_div;
                        if cmd_write = '1' then
                            c_cs_high <= to_unsigned(CS_WR, 8);
                        else
                            c_cs_high <= to_unsigned(CS_RD, 8);
                        end if;
                        data_left <= cmd_len;
                        -- Start collecting the first TX chunk now
                        if cmd_dir = DIR_TX then
                            col_active <= '1';
                            col_k      <= 0;
                            chunk_full <= '0';
                            col_target <= chunk_bytes(cmd_len);
                        end if;
                        -- The opcode phase is presented in the next cycle (fields latched)
                        cur_ph <= PH_OP;
                        state  <= X_ISSUE;
                    end if;

                when X_ISSUE =>
                    if hs then
                        ph_valid <= '0';
                        nph := next_ph(cur_ph, c_ab, c_mode_en, c_lat, c_dir);
                        if cur_ph = PH_DATA and c_dir = DIR_TX then
                            -- Chunk sent: next chunk or done
                            n_bytes := col_target;
                            left  := data_left - n_bytes;
                            data_left <= left;
                            chunk_full <= '0';
                            col_k      <= 0;
                            chunk_tx   <= (others => '0');
                            if last_chunk = '0' then
                                nph := PH_DATA;
                                col_target <= chunk_bytes(left);
                            else
                                col_active <= '0';
                            end if;
                        end if;
                        cur_ph <= nph;
                        if nph = PH_DONE then
                            if c_dir = DIR_RX then
                                state <= X_RXWAIT;
                            else
                                state <= X_IDLE;
                            end if;
                        elsif not (nph = PH_DATA and c_dir = DIR_TX) then
                            present(nph);
                            -- Last phase?
                            if next_ph(nph, c_ab, c_mode_en, c_lat, c_dir) = PH_DONE then
                                ph_last <= '1';
                            end if;
                        end if;
                    elsif ph_valid = '0' and cur_ph /= PH_DONE then
                        -- First phase of the command, or TX data waiting for its chunk
                        if cur_ph = PH_DATA and c_dir = DIR_TX then
                            if chunk_full = '1' then
                                present(PH_DATA);
                                if last_chunk = '1' then
                                    ph_last <= '1';
                                end if;
                            end if;
                        else
                            present(cur_ph);
                            if next_ph(cur_ph, c_ab, c_mode_en, c_lat, c_dir) = PH_DONE then
                                ph_last <= '1';
                            end if;
                        end if;
                    end if;

                when X_RXWAIT =>
                    if rx_done = '1' then
                        state <= X_IDLE;
                    end if;
            end case;

            if reset_n = '0' then
                state      <= X_IDLE;
                cur_ph     <= PH_DONE;
                ph_valid   <= '0';
                col_active <= '0';
                chunk_full <= '0';
            end if;
        end if;
    end process;

    -------------------------------------------------------------------------------------------
    -- RX: PHY words -> bytes -> FIFO
    --   4 lines: two nibbles per byte, high nibble first. 1 line: eight bits, MSB first.
    --   Every RX phase is a whole number of bytes, so acc_n is 0 at the start of each command.
    -------------------------------------------------------------------------------------------
    process (clk)
        variable push : boolean;
        variable d0   : std_logic_vector(8 downto 0);
        variable pop  : boolean;
        variable cnt  : natural range 0 to 4;
        variable b    : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            push    := false;
            ovf     <= '0';
            rx_done <= '0';
            if rx_valid = '1' then
                if c_lanes /= L111 then
                    b := acc(3 downto 0) & rx_data;
                    push := acc_n = 1;
                else
                    b := acc(6 downto 0) & rx_data(0);
                    push := acc_n = 7;
                end if;
                acc <= b;
                d0  := rx_last & b;
                if push then
                    acc_n <= 0;
                else
                    acc_n <= acc_n + 1;
                end if;
                if rx_last = '1' then
                    rx_done <= '1';
                end if;
            end if;

            -- Unread entries are f_rd .. f_rd + 3 at most, so f_wr is always free. The byte only
            -- advances f_wr if it fits; otherwise it is dropped (rx_overflow).
            if push then
                fifo(to_integer(f_wr)) <= d0;
            end if;
            pop := f_cnt /= 0 and m_axis_tready = '1';
            cnt := f_cnt - boolean'pos(pop);
            if push and cnt = 4 then
                ovf  <= '1';
                push := false;
            end if;
            if push then
                f_wr  <= f_wr + 1;
                f_cnt <= cnt + 1;
            else
                f_cnt <= cnt;
            end if;
            if pop then
                f_rd <= f_rd + 1;
            end if;

            if reset_n = '0' then
                f_rd  <= (others => '0');
                f_wr  <= (others => '0');
                f_cnt <= 0;
                acc_n <= 0;
            end if;
        end if;
    end process;

    phy : entity work.qspi_phy
        generic map (NCLK_W => NCLK_W, CS_HIGH_W => 8)
        port map (
            clk => clk, reset_n => reset_n,
            ph_valid => ph_valid, ph_ready => ph_ready, ph_lanes => ph_lanes, ph_dir => ph_dir,
            ph_nclk => ph_nclk, ph_tx => ph_tx, ph_last => ph_last,
            ph_sclk_div => c_div, ph_cs_high => ph_cs_high, sample_dly => sample_dly,
            rx_valid => rx_valid, rx_data => rx_data, rx_last => rx_last, busy => phy_busy,
            sclk => sclk, cs_n => cs_n, io_o => io_o, io_oe => io_oe, io_i => io_i);
end architecture rtl;
