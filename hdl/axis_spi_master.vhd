-- AXI4-Stream SPI master with fixed-length frames
--
--   s_axis (TX bytes) --> SPI (sclk/mosi/cs_n/miso) --> m_axis (RX bytes)
--
--   Every frame is exactly FRAME_BYTES bytes. spi_cs_n goes low before the first byte and
--   high after the last one. Each byte taken from s_axis gives one byte on m_axis (full
--   duplex), and m_axis_tlast marks the last byte of a frame.
--
-- Flow control:
--   - If s_axis runs dry mid-frame, sclk pauses at its idle level with spi_cs_n held low
--     until the next byte arrives (SPI allows this, but check the slave). To avoid such
--     pauses, only start a frame once the upstream FIFO holds FRAME_BYTES bytes.
--   - If m_axis is not ready, the next byte does not start until the previous RX byte
--     has been accepted. No data is ever dropped.
--
-- s_axis_tlast is optional. If the producer drives it, frame_err_out pulses for one clock
-- whenever tlast does not match the last byte of a frame. It does not affect framing.
-- If tlast is not driven (default '0'), frame_err_out pulses on every frame: leave it open.
--
-- Timing (in clk cycles):
--   Sclk half-period        = CLK_DIV                 (f_sclk = f_clk / (2*CLK_DIV))
--   Gap between bytes       = CLK_DIV + 1 at the idle level
--   Cs_n low -> first edge  = CS_SETUP * CLK_DIV + CLK_DIV + 2 (longer if m_axis is stalled)
--   Last edge -> cs_n high  = CS_HOLD  * CLK_DIV + 1
--   Cs_n high min. time     = CS_IDLE  * CLK_DIV + 1
--
-- MISO goes through MISO_SYNC flip-flops before it is sampled. The round trip
-- (clk-to-sclk pad + slave tCO + miso pad + sync) must fit inside one sclk half-period:
--   CLK_DIV > MISO_SYNC + 1 + ceil((t_pad_out + t_slave + t_pad_in) / t_clk)
-- Set MISO_SYNC = 0 only if MISO is already synchronous to clk.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

entity axis_spi_master is
    generic (
        FRAME_BYTES : positive  := 10;     -- Bytes per cs_n assertion
        CLK_DIV     : positive  := 7;      -- Clk cycles per sclk half-period (14.29 MHz at 200 MHz)
        CPOL        : std_logic := '0';    -- Sclk idle level
        CPHA        : std_logic := '0';    -- 0: sample on leading edge, 1: on trailing edge
        MSB_FIRST   : boolean   := true;
        CS_SETUP    : natural   := 1;      -- Extra half-periods cs_n low before the first edge
        CS_HOLD     : natural   := 1;      -- Half-periods after the last edge before cs_n high
        CS_IDLE     : natural   := 2;      -- Min. half-periods cs_n high between frames
        MISO_SYNC   : natural   := 2       -- MISO synchronizer stages
    );
    port (
        clk           : in  std_logic;
        reset_n       : in  std_logic;           -- Synchronous, active low

        -- TX bytes in (AXI4-Stream target)
        s_axis_tdata  : in  std_logic_vector(7 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;
        s_axis_tlast  : in  std_logic := '0';

        -- RX bytes out (AXI4-Stream initiator)
        m_axis_tdata  : out std_logic_vector(7 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic := '1';
        m_axis_tlast  : out std_logic;

        -- SPI
        spi_sclk      : out std_logic;
        spi_mosi      : out std_logic;
        spi_miso      : in  std_logic := '0';
        spi_cs_n      : out std_logic;

        -- Status
        busy_out      : out std_logic;           -- High from frame start until the cs_n idle time is over
        frame_err_out : out std_logic            -- One-cycle pulse on tlast mismatch
    );
end entity axis_spi_master;

architecture rtl of axis_spi_master is

    -- Counter widths (maximum() is predefined in VHDL-2008)
    constant DIV_W  : positive := maximum(1, clog2(CLK_DIV));
    constant WAIT_W : positive := maximum(1, clog2(maximum(maximum(CS_SETUP, CS_HOLD), CS_IDLE) + 1));
    constant BYTE_W : positive := maximum(1, clog2(FRAME_BYTES));

    type state_t is (S_IDLE, S_SETUP, S_LOAD, S_XFER, S_HOLD, S_GAP);

    signal state     : state_t := S_IDLE;

    signal div_cnt   : unsigned(DIV_W - 1 downto 0) := (others => '0');
    signal tick      : std_logic;                                  -- Half-period strobe
    signal wait_cnt  : unsigned(WAIT_W - 1 downto 0) := (others => '0');
    signal edge_cnt  : unsigned(3 downto 0) := (others => '0');    -- 16 edges per byte
    signal byte_cnt  : unsigned(BYTE_W - 1 downto 0) := (others => '0');

    signal sclk_r    : std_logic := CPOL;
    signal mosi_r    : std_logic := '0';
    signal cs_n_r    : std_logic := '1';
    signal tx_shift  : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_shift  : std_logic_vector(7 downto 0) := (others => '0');

    signal rx_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid  : std_logic := '0';
    signal rx_last   : std_logic := '0';

    signal s_ready   : std_logic;
    signal ferr_r    : std_logic := '0';

    signal miso_s    : std_logic;
    signal last_byte : std_logic;

begin

    -- Elaboration-time check: the MISO round trip must fit in a half-period.
    -- This only covers the internal latency; pad and slave delays come on top.
    assert (CLK_DIV > MISO_SYNC + 1)
        report "axis_spi_master: CLK_DIV too small for MISO_SYNC; RX data will be sampled late"
        severity warning;

    -- MISO synchronizer
    g_sync : if MISO_SYNC > 0 generate
        signal sync_r : std_logic_vector(MISO_SYNC - 1 downto 0) := (others => '0');
    begin
        sync_proc : process (clk)
        begin
            if rising_edge(clk) then
                if MISO_SYNC = 1 then
                    sync_r(0) <= spi_miso;
                else
                    sync_r <= sync_r(MISO_SYNC - 2 downto 0) & spi_miso;
                end if;
            end if;
        end process;
        miso_s <= sync_r(MISO_SYNC - 1);
    end generate;

    g_nosync : if MISO_SYNC = 0 generate
        miso_s <= spi_miso;
    end generate;

    tick      <= '1' when div_cnt = CLK_DIV - 1 else '0';
    last_byte <= '1' when byte_cnt = FRAME_BYTES - 1 else '0';

    -- Accept a TX byte only in S_LOAD and only when the RX holding register is free,
    -- so the byte about to be received always has somewhere to go.
    s_ready <= '1' when state = S_LOAD and (rx_valid = '0') else '0';

    fsm_proc : process (clk)
        variable rx_next : std_logic_vector(7 downto 0);
        variable tx_v    : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            ferr_r <= '0';

            -- RX handshake
            if rx_valid = '1' and m_axis_tready = '1' then
                rx_valid <= '0';
            end if;

            -- The divider runs in the timed states and is held at 0 otherwise,
            -- so every timed phase starts with a full half-period.
            if state = S_SETUP or state = S_XFER or state = S_HOLD or state = S_GAP then
                if tick = '1' then
                    div_cnt <= (others => '0');
                else
                    div_cnt <= div_cnt + 1;
                end if;
            else
                div_cnt <= (others => '0');
            end if;

            if reset_n = '0' then
                state    <= S_IDLE;
                sclk_r   <= CPOL;
                mosi_r   <= '0';
                cs_n_r   <= '1';
                wait_cnt <= (others => '0');
                edge_cnt <= (others => '0');
                byte_cnt <= (others => '0');
                rx_valid <= '0';
                rx_last  <= '0';
                div_cnt  <= (others => '0');
            else
                case state is

                    when S_IDLE =>
                        sclk_r   <= CPOL;
                        byte_cnt <= (others => '0');
                        if s_axis_tvalid = '1' then
                            cs_n_r   <= '0';
                            wait_cnt <= to_unsigned(CS_SETUP, WAIT_W);
                            state    <= S_SETUP;
                        end if;

                    when S_SETUP =>
                        if wait_cnt = 0 then
                            state <= S_LOAD;
                        elsif tick = '1' then
                            wait_cnt <= wait_cnt - 1;
                        end if;

                    when S_LOAD =>
                        if s_ready = '1' and s_axis_tvalid = '1' then
                            -- Tlast check (informational only)
                            if s_axis_tlast /= last_byte then
                                ferr_r <= '1';
                            end if;
                            -- Normalize to MSB first; the shifter always shifts out bit 7
                            if MSB_FIRST then
                                tx_v := s_axis_tdata;
                            else
                                tx_v := reverse(s_axis_tdata);
                            end if;
                            if CPHA = '0' then
                                -- CPHA = 0: the first bit must be on MOSI before the leading edge
                                mosi_r   <= tx_v(7);
                                tx_shift <= tx_v(6 downto 0) & '0';
                            else
                                tx_shift <= tx_v;
                            end if;
                            edge_cnt <= (others => '0');
                            state    <= S_XFER;
                        end if;

                    when S_XFER =>
                        if tick = '1' then
                            sclk_r <= not sclk_r;

                            if sclk_r = CPOL then
                                -- Leading edge
                                if CPHA = '0' then
                                    rx_shift <= rx_shift(6 downto 0) & miso_s;
                                else
                                    mosi_r   <= tx_shift(7);
                                    tx_shift <= tx_shift(6 downto 0) & '0';
                                end if;
                            else
                                -- Trailing edge
                                if CPHA = '0' then
                                    if edge_cnt /= 15 then
                                        mosi_r   <= tx_shift(7);
                                        tx_shift <= tx_shift(6 downto 0) & '0';
                                    end if;
                                else
                                    rx_shift <= rx_shift(6 downto 0) & miso_s;
                                end if;
                            end if;

                            if edge_cnt = 15 then
                                -- Byte complete; the final RX byte includes this edge's sample
                                if CPHA = '1' then
                                    rx_next := rx_shift(6 downto 0) & miso_s;
                                else
                                    rx_next := rx_shift;
                                end if;

                                if MSB_FIRST then
                                    rx_data <= rx_next;
                                else
                                    rx_data <= reverse(rx_next);
                                end if;
                                rx_valid <= '1';
                                rx_last  <= last_byte;

                                if last_byte = '1' then
                                    wait_cnt <= to_unsigned(CS_HOLD, WAIT_W);
                                    state    <= S_HOLD;
                                else
                                    byte_cnt <= byte_cnt + 1;
                                    state    <= S_LOAD;
                                end if;
                            else
                                edge_cnt <= edge_cnt + 1;
                            end if;
                        end if;

                    when S_HOLD =>
                        if wait_cnt = 0 then
                            cs_n_r   <= '1';
                            wait_cnt <= to_unsigned(CS_IDLE, WAIT_W);
                            state    <= S_GAP;
                        elsif tick = '1' then
                            wait_cnt <= wait_cnt - 1;
                        end if;

                    when S_GAP =>
                        if wait_cnt = 0 then
                            state <= S_IDLE;
                        elsif tick = '1' then
                            wait_cnt <= wait_cnt - 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

    s_axis_tready <= s_ready;

    m_axis_tdata  <= rx_data;
    m_axis_tvalid <= rx_valid;
    m_axis_tlast  <= rx_last;

    spi_sclk      <= sclk_r;
    spi_mosi      <= mosi_r;
    spi_cs_n      <= cs_n_r;

    busy_out      <= '0' when state = S_IDLE else '1';
    frame_err_out <= ferr_r;

end architecture rtl;
