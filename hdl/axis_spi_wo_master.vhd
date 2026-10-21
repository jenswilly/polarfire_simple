-- AXI4-Stream SPI master with fixed-length frames, write only
--
--   s_axis (TX bytes) --> SPI (sclk/mosi/cs_n)
--
--   Every frame is exactly FRAME_BYTES bytes. spi_cs_n goes low before the first byte and
--   high after the last one. There is no MISO input and no RX path: this is a write-only
--   version of axis_spi_master.
--
-- Flow control:
--   If s_axis runs dry mid-frame, sclk pauses at its idle level with spi_cs_n held low
--   until the next byte arrives (SPI allows this, but check the slave). To avoid such
--   pauses, only start a frame once the upstream FIFO holds FRAME_BYTES bytes.
--
-- s_axis_tlast is optional. If the producer drives it, frame_err_out pulses for one clock
-- whenever tlast does not match the last byte of a frame. It does not affect framing.
-- If tlast is not driven (default '0'), frame_err_out pulses on every frame: leave it open.
--
-- Timing (in clk cycles):
--   Sclk half-period        = CLK_DIV                 (f_sclk = f_clk / (2*CLK_DIV))
--   Gap between bytes       = CLK_DIV + 1 at the idle level
--   Cs_n low -> first edge  = CS_SETUP * CLK_DIV + CLK_DIV + 2
--   Last edge -> cs_n high  = CS_HOLD  * CLK_DIV + 1
--   Cs_n high min. time     = CS_IDLE  * CLK_DIV + 1

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_spi_wo_master is
    generic (
        FRAME_BYTES : positive  := 10;     -- Bytes per cs_n assertion
        CLK_DIV     : positive  := 3;      -- Clk cycles per sclk half-period (20.83 MHz at 125 MHz)
        CPOL        : std_logic := '0';    -- Sclk idle level
        CPHA        : std_logic := '0';    -- 0: slave samples on leading edge, 1: on trailing edge
        MSB_FIRST   : boolean   := true;
        CS_SETUP    : natural   := 0;      -- Extra half-periods cs_n low before the first edge
        CS_HOLD     : natural   := 0;      -- Half-periods after the last edge before cs_n high
        CS_IDLE     : natural   := 2       -- Min. half-periods cs_n high between frames
    );
    port (
        clk           : in  std_logic;
        reset_n       : in  std_logic;           -- Synchronous, active low

        -- TX bytes in (AXI4-Stream target)
        s_axis_tdata  : in  std_logic_vector(7 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;
        s_axis_tlast  : in  std_logic := '0';

        -- SPI
        spi_sclk      : out std_logic;
        spi_mosi      : out std_logic;
        spi_cs_n      : out std_logic;

        -- Status
        busy_out      : out std_logic;           -- High from frame start until the cs_n idle time is over
        frame_err_out : out std_logic            -- One-cycle pulse on tlast mismatch
    );
end entity axis_spi_wo_master;

architecture rtl of axis_spi_wo_master is

    function clog2(n : natural) return natural is
        variable r : natural := 0;
        variable v : natural := 1;
    begin
        while v < n loop
            v := v * 2;
            r := r + 1;
        end loop;
        return r;
    end function;

    function reverse(v : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable r : std_logic_vector(7 downto 0);
    begin
        for i in 0 to 7 loop
            r(i) := v(7 - i);
        end loop;
        return r;
    end function;

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

    signal s_ready   : std_logic;
    signal ferr_r    : std_logic := '0';

    signal last_byte : std_logic;

begin

    tick      <= '1' when div_cnt = CLK_DIV - 1 else '0';
    last_byte <= '1' when byte_cnt = FRAME_BYTES - 1 else '0';

    -- Accept a TX byte only in S_LOAD
    s_ready <= '1' when state = S_LOAD else '0';

    fsm_proc : process (clk)
        variable tx_v : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            ferr_r <= '0';

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

                            -- MOSI changes on the leading edge for CPHA = 1 and on the
                            -- trailing edge for CPHA = 0 (except after the last bit)
                            if sclk_r = CPOL then
                                if CPHA = '1' then
                                    mosi_r   <= tx_shift(7);
                                    tx_shift <= tx_shift(6 downto 0) & '0';
                                end if;
                            else
                                if CPHA = '0' and edge_cnt /= 15 then
                                    mosi_r   <= tx_shift(7);
                                    tx_shift <= tx_shift(6 downto 0) & '0';
                                end if;
                            end if;

                            if edge_cnt = 15 then
                                -- Byte complete
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

    spi_sclk      <= sclk_r;
    spi_mosi      <= mosi_r;
    spi_cs_n      <= cs_n_r;

    busy_out      <= '0' when state = S_IDLE else '1';
    frame_err_out <= ferr_r;

end architecture rtl;
