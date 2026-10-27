-- QSPI memory controller top: init, read and write front ends sharing one transaction engine
--
--   rd_req / m_axis           --> qspi_read_ctrl --+
--   wr_req / wr_data          --> qspi_write ------+--> arbiter --> qspi_xact (+ qspi_phy) --> pins
--   init_restart, init_*      <-> qspi_init -------+
--
--   Request formats, checks and flow control: see qspi_read_ctrl and qspi_write (host bytes,
--   {die2_nibble, die1_nibble}; host address / 2 = die address). Reads and writes are rejected
--   (rd_req_err / wr_req_err) until init_done.
--
-- Arbiter: one source owns qspi_xact (command port, TX and RX streams) at a time.
--   qspi_init owns it while it runs (after reset and after init_restart). qspi_write keeps it
--   for a whole request (W25Q: erase, program and BUSY polls must not be interleaved with reads).
--   qspi_read_ctrl keeps it while it has a command waiting. The owner only changes while
--   qspi_xact is idle, so RX bytes always reach the source that issued the command. Between
--   read and write, the one that did not go last wins.
--
-- Sample delay: SAMPLE_DLY, or sample_dly_ovr while sample_dly_ovr_valid = '1' (calibration).
-- Change it only while busy = '0'. It is registered (timing at 200 MHz), so a change takes effect
-- one clock later; a command issued in the same cycle reaches the PHY only after that.
--
-- Pins: no tristates inside. With DIE2_PRESENT = false, io_oe(7:4) stays low and io_i(7:4) is
-- ignored; sclk(1)/cs_n(1) still toggle (leave them unconnected). mem_reset_n is the
-- AS308G208 RESET# (always '1' for the W25Q128JV).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;

entity qspi_mram_ctrl is
    generic (
        DEVICE       : device_t := DEV_W25Q128JV;
        DIE2_PRESENT : boolean  := false;
        CLK_CTRL_HZ  : positive := 200_000_000;     -- Input clock frequency
        SCLK_DIV     : positive := 2;               -- SCLK = CLK_CTRL_HZ / (2 * SCLK_DIV)
        SAMPLE_DLY   : positive := 4;               -- Default RX sample delay (clk cycles)
        SPACE_W      : positive := 16;              -- Width of rd_space
        T_POWERUP_NS : natural  := 0;               -- 0 = datasheet value (see qspi_init)
        T_RESET_NS   : natural  := 0
    );
    port (
        clk                  : in  std_logic;
        reset_n              : in  std_logic;       -- Synchronous, active low

        -- Init / status
        init_restart         : in  std_logic;
        init_done            : out std_logic;
        init_err             : out std_logic;
        init_err_code        : out std_logic_vector(1 downto 0);
        init_step            : out std_logic_vector(4 downto 0);
        busy                 : out std_logic;       -- Any request or command in progress

        -- Read requests and data
        rd_req_tdata         : in  std_logic_vector(47 downto 0);   -- {len[15:0], addr[31:0]}
        rd_req_tvalid        : in  std_logic;
        rd_req_tready        : out std_logic;
        rd_req_err           : out std_logic;
        rd_space             : in  unsigned(SPACE_W - 1 downto 0);  -- Free bytes downstream
        m_axis_tdata         : out std_logic_vector(7 downto 0);
        m_axis_tvalid        : out std_logic;
        m_axis_tready        : in  std_logic;
        m_axis_tlast         : out std_logic;

        -- Write requests and data
        wr_req_tdata         : in  std_logic_vector(47 downto 0);   -- {len[15:0], addr[31:0]}
        wr_req_tvalid        : in  std_logic;
        wr_req_tready        : out std_logic;
        wr_req_err           : out std_logic;
        wr_done              : out std_logic;
        s_axis_wr_tdata      : in  std_logic_vector(7 downto 0);
        s_axis_wr_tvalid     : in  std_logic;
        s_axis_wr_tready     : out std_logic;

        -- Calibration
        sample_dly_ovr_valid : in  std_logic;
        sample_dly_ovr       : in  natural range 1 to SAMPLE_DLY_MAX;

        -- Pins
        sclk                 : out std_logic_vector(1 downto 0);
        cs_n                 : out std_logic_vector(1 downto 0);
        io_o                 : out std_logic_vector(7 downto 0);
        io_oe                : out std_logic_vector(7 downto 0);
        io_i                 : in  std_logic_vector(7 downto 0);
        mem_reset_n          : out std_logic
    );
end entity qspi_mram_ctrl;

architecture rtl of qspi_mram_ctrl is

    type owner_t is (OWN_INIT, OWN_READ, OWN_WRITE);

    -- One command port (source side)
    type cmd_t is record
        valid   : std_logic;
        op      : std_logic_vector(7 downto 0);
        lanes   : cmd_lanes_t;
        addr    : std_logic_vector(31 downto 0);
        ab      : natural range 0 to 4;
        mode_en : std_logic;
        mode    : std_logic_vector(7 downto 0);
        lat     : natural range 0 to 15;
        dir     : dir_t;
        len     : unsigned(15 downto 0);
        div     : natural range 1 to SCLK_DIV_MAX;
        wr      : std_logic;
    end record;

    signal ci, cr, cw, cx : cmd_t;                 -- init, read, write, to qspi_xact
    signal x_cmd_ready    : std_logic;

    signal owner          : owner_t := OWN_INIT;
    signal last_rw        : owner_t := OWN_READ;   -- Read or write, whichever went last

    signal init_done_i, init_err_i : std_logic;
    signal init_active    : std_logic;
    signal r_busy, w_busy : std_logic;
    signal xact_busy      : std_logic;
    signal smp_dly        : natural range 1 to SAMPLE_DLY_MAX;

    -- Streams
    signal i_tx_tdata, w_tx_tdata, x_tx_tdata : std_logic_vector(7 downto 0);
    signal i_tx_tvalid, w_tx_tvalid, x_tx_tvalid, x_tx_tready : std_logic;
    signal x_rx_tdata  : std_logic_vector(7 downto 0);
    signal x_rx_tvalid, x_rx_tready, x_rx_tlast : std_logic;
    signal i_rx_tready, r_rx_tready, w_rx_tready : std_logic;
    signal own_i, own_r, own_w : std_logic;
begin
    init_done   <= init_done_i;
    init_err    <= init_err_i;
    init_active <= not (init_done_i or init_err_i);
    busy        <= init_active or r_busy or w_busy or xact_busy;

    process (clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' or sample_dly_ovr_valid = '0' then
                smp_dly <= SAMPLE_DLY;
            else
                smp_dly <= sample_dly_ovr;
            end if;
        end if;
    end process;

    -------------------------------------------------------------------------------------------
    -- Arbiter
    -------------------------------------------------------------------------------------------
    process (clk)
        variable hold    : boolean;
        variable want_r  : boolean;
        variable want_w  : boolean;
    begin
        if rising_edge(clk) then
            case owner is
                when OWN_INIT  => hold := init_active = '1';
                when OWN_WRITE => hold := w_busy = '1';
                when OWN_READ  => hold := cr.valid = '1';
            end case;
            if xact_busy = '0' and not hold then
                want_r := cr.valid = '1';
                want_w := w_busy = '1';
                if init_active = '1' then
                    owner <= OWN_INIT;
                elsif want_w and (not want_r or last_rw = OWN_READ) then
                    owner   <= OWN_WRITE;
                    last_rw <= OWN_WRITE;
                elsif want_r then
                    owner   <= OWN_READ;
                    last_rw <= OWN_READ;
                end if;
            end if;
            if reset_n = '0' then
                owner   <= OWN_INIT;
                last_rw <= OWN_READ;
            end if;
        end if;
    end process;

    own_i <= '1' when owner = OWN_INIT else '0';
    own_r <= '1' when owner = OWN_READ else '0';
    own_w <= '1' when owner = OWN_WRITE else '0';

    with owner select cx <=
        ci when OWN_INIT,
        cr when OWN_READ,
        cw when OWN_WRITE;

    with owner select x_tx_tdata <=
        i_tx_tdata when OWN_INIT,
        w_tx_tdata when others;
    x_tx_tvalid <= (i_tx_tvalid and own_i) or (w_tx_tvalid and own_w);

    x_rx_tready <= (i_rx_tready and own_i) or (r_rx_tready and own_r) or (w_rx_tready and own_w);

    -------------------------------------------------------------------------------------------
    -- Sources
    -------------------------------------------------------------------------------------------
    init : entity work.qspi_init
        generic map (DEVICE => DEVICE, DIE2_PRESENT => DIE2_PRESENT, CLK_HZ => CLK_CTRL_HZ,
                     SCLK_DIV => SCLK_DIV, T_POWERUP_NS => T_POWERUP_NS, T_RESET_NS => T_RESET_NS)
        port map (
            clk => clk, reset_n => reset_n, init_restart => init_restart,
            init_done => init_done_i, init_err => init_err_i, err_code => init_err_code,
            step => init_step, mem_reset_n => mem_reset_n,
            cmd_valid => ci.valid, cmd_ready => x_cmd_ready and own_i, cmd_op => ci.op,
            cmd_lanes => ci.lanes, cmd_addr => ci.addr, cmd_addr_bytes => ci.ab,
            cmd_mode_en => ci.mode_en, cmd_mode => ci.mode, cmd_latency => ci.lat,
            cmd_dir => ci.dir, cmd_len => ci.len, cmd_sclk_div => ci.div, cmd_write => ci.wr,
            xact_busy => xact_busy,
            tx_tdata => i_tx_tdata, tx_tvalid => i_tx_tvalid, tx_tready => x_tx_tready and own_i,
            rx_tdata => x_rx_tdata, rx_tvalid => x_rx_tvalid and own_i, rx_tready => i_rx_tready,
            rx_tlast => x_rx_tlast);

    rd : entity work.qspi_read_ctrl
        generic map (DEVICE => DEVICE, SCLK_DIV => SCLK_DIV, SPACE_W => SPACE_W)
        port map (
            clk => clk, reset_n => reset_n, init_done => init_done_i,
            s_axis_req_tdata => rd_req_tdata, s_axis_req_tvalid => rd_req_tvalid,
            s_axis_req_tready => rd_req_tready, req_err => rd_req_err, rx_space => rd_space,
            busy => r_busy,
            cmd_valid => cr.valid, cmd_ready => x_cmd_ready and own_r, cmd_op => cr.op,
            cmd_lanes => cr.lanes, cmd_addr => cr.addr, cmd_addr_bytes => cr.ab,
            cmd_mode_en => cr.mode_en, cmd_mode => cr.mode, cmd_latency => cr.lat,
            cmd_dir => cr.dir, cmd_len => cr.len, cmd_sclk_div => cr.div, cmd_write => cr.wr,
            rx_tdata => x_rx_tdata, rx_tvalid => x_rx_tvalid and own_r, rx_tready => r_rx_tready,
            rx_tlast => x_rx_tlast,
            m_axis_tdata => m_axis_tdata, m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready, m_axis_tlast => m_axis_tlast);

    wr : entity work.qspi_write
        generic map (DEVICE => DEVICE, DIE2_PRESENT => DIE2_PRESENT, SCLK_DIV => SCLK_DIV)
        port map (
            clk => clk, reset_n => reset_n, init_done => init_done_i,
            s_axis_req_tdata => wr_req_tdata, s_axis_req_tvalid => wr_req_tvalid,
            s_axis_req_tready => wr_req_tready,
            s_axis_data_tdata => s_axis_wr_tdata, s_axis_data_tvalid => s_axis_wr_tvalid,
            s_axis_data_tready => s_axis_wr_tready,
            req_err => wr_req_err, wr_done => wr_done, busy => w_busy,
            cmd_valid => cw.valid, cmd_ready => x_cmd_ready and own_w, cmd_op => cw.op,
            cmd_lanes => cw.lanes, cmd_addr => cw.addr, cmd_addr_bytes => cw.ab,
            cmd_mode_en => cw.mode_en, cmd_mode => cw.mode, cmd_latency => cw.lat,
            cmd_dir => cw.dir, cmd_len => cw.len, cmd_sclk_div => cw.div, cmd_write => cw.wr,
            xact_busy => xact_busy,
            tx_tdata => w_tx_tdata, tx_tvalid => w_tx_tvalid, tx_tready => x_tx_tready and own_w,
            rx_tdata => x_rx_tdata, rx_tvalid => x_rx_tvalid and own_w, rx_tready => w_rx_tready,
            rx_tlast => x_rx_tlast);

    -------------------------------------------------------------------------------------------
    -- Transaction engine and PHY
    -------------------------------------------------------------------------------------------
    xact : entity work.qspi_xact
        generic map (DEVICE => DEVICE, DIE2_PRESENT => DIE2_PRESENT, CLK_HZ => CLK_CTRL_HZ)
        port map (
            clk => clk, reset_n => reset_n,
            cmd_valid => cx.valid, cmd_ready => x_cmd_ready, cmd_op => cx.op,
            cmd_lanes => cx.lanes, cmd_addr => cx.addr, cmd_addr_bytes => cx.ab,
            cmd_mode_en => cx.mode_en, cmd_mode => cx.mode, cmd_latency => cx.lat,
            cmd_dir => cx.dir, cmd_len => cx.len, cmd_sclk_div => cx.div, cmd_write => cx.wr,
            s_axis_tdata => x_tx_tdata, s_axis_tvalid => x_tx_tvalid, s_axis_tready => x_tx_tready,
            m_axis_tdata => x_rx_tdata, m_axis_tvalid => x_rx_tvalid, m_axis_tready => x_rx_tready,
            m_axis_tlast => x_rx_tlast, rx_overflow => open,
            sample_dly => smp_dly, busy => xact_busy,
            sclk => sclk, cs_n => cs_n, io_o => io_o, io_oe => io_oe, io_i => io_i);
end architecture rtl;
