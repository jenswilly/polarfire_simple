-- QSPI PHY / bit engine (SPI mode 0, SDR), both dies in lockstep
--
--   phase descriptors (valid/ready) --> SCLK, CS#, IO out/OE   (pins)
--   pins (io_i)                     --> rx_* (one word per RX SCLK cycle)
--
--   A transaction is a sequence of phases between CS# low and CS# high. Each phase is a number
--   of SCLK cycles with one lane mode and direction; ph_last marks the last phase. The PHY knows
--   nothing about commands (qspi_xact builds the phases).
--     SPI1  TX: data on IO0 (die 1) / IO4 (die 2), MSB first, ph_tx1/ph_tx2(31) first.
--     QUAD4 TX: data on IO3:0 / IO7:4, 4 bits per cycle, ph_tx(31 downto 28) first (IO3 = bit 31).
--     RX: in SPI1 the bit comes from IO1 / IO5, in QUAD4 from IO3:0 / IO7:4.
--     NONE: dummy/latency cycles.
--   TX phases carry at most 32 bits per die (SPI1 <= 32 cycles, QUAD4 <= 8 cycles); longer
--   writes are several phases. RX and NONE phases can be up to 2**NCLK_W - 1 cycles.
--
-- Pins:
--   SCLK idles low and toggles every sclk_div clk cycles, so it has an exact 50 % duty cycle.
--   sclk_div (1 .. SCLK_DIV_MAX) is taken from the first phase of a transaction. IO out and OE
--   change together with the SCLK falling edge (and with CS# going low), so the device sees
--   sclk_div clk cycles of setup and hold around each rising edge. CS# goes low together with
--   the first data bit, and high at least one clk cycle after the last SCLK falling edge.
--   In SPI1 phases IO2/IO3 and IO6/IO7 are driven high (WP#/HOLD# inactive, device_facts.md
--   §4.7) and IO0/IO4 are driven ('0' when not transmitting). After reset the pads have this
--   SPI1 pattern. When CS# goes high the pads keep the state of the last cycle, so after a
--   QUAD4 read IO3:0 stay released (no contention while the device turns its outputs off)
--   until the next transaction drives them again together with CS# low.
--   QUAD4 RX/NONE phases release OE on all four lanes; the release happens on the falling edge
--   that starts the phase (the turnaround before latency cycles).
--   sclk(1)/cs_n(1) are copies of sclk(0)/cs_n(0) with their own pad flops.
--   With DIE2_PRESENT = false, IO7:4 are never driven, and their input is read as "0000".
--
-- RX sampling:
--   The device drives a new bit/nibble after each SCLK falling edge. For every RX cycle the PHY
--   uses the input register value captured sample_dly clk cycles after the falling edge that
--   launched it (sample_dly = 1 .. SAMPLE_DLY_MAX, compensates the round-trip delay). CS# stays
--   low until the last sample has been captured. Each RX cycle gives one rx_data word
--   {die2_nibble, die1_nibble}; in SPI1 each nibble is "000" & bit. rx_last marks the last word
--   of an RX phase. There is no backpressure: the receiver must take a word every cycle.
--   Change sample_dly only while busy = '0'.
--
-- CS# high time:
--   After CS# goes high it stays high for at least ph_cs_high clk cycles (>= 1). The value is
--   taken from the last loaded phase of the transaction.
--
-- Flow control:
--   ph_ready is high in the clk cycle where the PHY loads a descriptor: when idle, and at the end
--   of the last SCLK cycle of the current phase. If no descriptor is valid then, SCLK stays low
--   (CS# low) until one arrives. Keep the next descriptor valid to get a gap-free SCLK.
--
-- All pad-facing signals (sclk, cs_n, io_o, io_oe and the io_i capture) are single registers
-- with the same clock and synchronous reset, kept separate (syn_preserve) so each one can be
-- combined into its I/O cell (set_ioff in constraints/qspi_ioreg.ndc).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;

entity qspi_phy is
    generic (
        DIE2_PRESENT : boolean  := true;
        NCLK_W       : positive := 16;   -- Width of ph_nclk
        CS_HIGH_W    : positive := 8     -- Width of ph_cs_high
    );
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;     -- Synchronous, active low

        -- Phase descriptors
        ph_valid    : in  std_logic;
        ph_ready    : out std_logic;
        ph_lanes    : in  lane_mode_t;
        ph_dir      : in  dir_t;
        ph_nclk     : in  unsigned(NCLK_W - 1 downto 0);          -- SCLK cycles, >= 1
        ph_tx1      : in  std_logic_vector(31 downto 0);          -- Die 1 TX data, MSB first
        ph_tx2      : in  std_logic_vector(31 downto 0);          -- Die 2 TX data, MSB first
        ph_last     : in  std_logic;                              -- Last phase: CS# high afterwards
        ph_sclk_div : in  natural range 1 to SCLK_DIV_MAX;        -- Used from the first phase
        ph_cs_high  : in  unsigned(CS_HIGH_W - 1 downto 0);       -- Min CS# high clk cycles, >= 1

        sample_dly  : in  natural range 1 to SAMPLE_DLY_MAX;

        -- RX words
        rx_valid    : out std_logic;
        rx_data     : out std_logic_vector(7 downto 0);           -- {die2_nibble, die1_nibble}
        rx_last     : out std_logic;                              -- Last word of an RX phase

        busy        : out std_logic;     -- Low when idle and the CS# high time is over

        -- Pins
        sclk        : out std_logic_vector(1 downto 0);
        cs_n        : out std_logic_vector(1 downto 0);
        io_o        : out std_logic_vector(7 downto 0);
        io_oe       : out std_logic_vector(7 downto 0);
        io_i        : in  std_logic_vector(7 downto 0)
    );
end entity qspi_phy;

architecture rtl of qspi_phy is

    type state_t is (S_IDLE, S_RUN, S_WAIT, S_END);

    -- Pad pattern for one die (IO3 .. IO0) for a cycle with the given mode and data
    function lane_oe(quad : std_logic; dir : dir_t) return std_logic_vector is
    begin
        if quad = '0' then
            return "1101";                       -- IO3/IO2 high, IO1 = device output, IO0 = data
        elsif dir = DIR_TX then
            return "1111";
        else
            return "0000";
        end if;
    end function;

    function lane_o(quad : std_logic; dir : dir_t; sh : std_logic_vector(31 downto 0))
        return std_logic_vector is
    begin
        if quad = '0' then
            if dir = DIR_TX then
                return "110" & sh(31);
            else
                return "1100";
            end if;
        elsif dir = DIR_TX then
            return sh(31 downto 28);
        else
            return "0000";
        end if;
    end function;

    function shift_tx(quad : std_logic; sh : std_logic_vector(31 downto 0))
        return std_logic_vector is
    begin
        if quad = '0' then
            return sh(30 downto 0) & '0';
        else
            return sh(27 downto 0) & "0000";
        end if;
    end function;

    constant NSTAGE : positive := SAMPLE_DLY_MAX + 1;

    signal state     : state_t := S_IDLE;
    signal half      : std_logic := '0';                          -- 0: SCLK low half, 1: high half
    signal div_l     : natural range 1 to SCLK_DIV_MAX := 1;
    signal div_cnt   : natural range 0 to SCLK_DIV_MAX - 1 := 0;
    signal clk_left  : unsigned(NCLK_W - 1 downto 0) := (others => '0');   -- Incl. current cycle
    signal cur_quad  : std_logic := '0';
    signal cur_dir   : dir_t := DIR_NONE;
    signal cur_last  : std_logic := '0';
    signal sh1, sh2  : std_logic_vector(31 downto 0) := (others => '0');
    signal cs_high_l : unsigned(CS_HIGH_W - 1 downto 0) := (others => '0');
    signal cs_cnt    : unsigned(CS_HIGH_W - 1 downto 0) := (others => '0');

    -- RX sample tokens: entered at the launching falling edge, shifted every clk cycle. A token
    -- in stage sample_dly + 1 means io_i_r holds its sample.
    signal tok_v     : std_logic_vector(1 to NSTAGE) := (others => '0');
    signal tok_q     : std_logic_vector(1 to NSTAGE) := (others => '0');   -- QUAD4 cycle
    signal tok_l     : std_logic_vector(1 to NSTAGE) := (others => '0');   -- Last of RX phase

    -- Pad registers
    signal sclk_r    : std_logic_vector(1 downto 0) := "00";
    signal cs_n_r    : std_logic_vector(1 downto 0) := "11";
    signal io_o_r    : std_logic_vector(7 downto 0) := (others => '0');
    signal io_oe_r   : std_logic_vector(7 downto 0) := (others => '0');
    signal io_i_r    : std_logic_vector(7 downto 0) := (others => '0');

    -- Every pad gets its own flip-flop so it can be packed into its I/O cell. Synthesis would
    -- otherwise merge equal ones (sclk(1) with sclk(0), the OEs of IO0/IO2/IO3, ...).
    attribute syn_preserve : boolean;
    attribute syn_preserve of sclk_r  : signal is true;
    attribute syn_preserve of cs_n_r  : signal is true;
    attribute syn_preserve of io_o_r  : signal is true;
    attribute syn_preserve of io_oe_r : signal is true;

    signal rx_valid_r : std_logic := '0';
    signal rx_data_r  : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_last_r  : std_logic := '0';

    signal end_tick  : std_logic;
begin
    end_tick <= '1' when div_cnt = div_l - 1 else '0';

    ph_ready <= '1' when (state = S_IDLE and cs_cnt = 0) or state = S_WAIT
                         or (state = S_RUN and half = '1' and end_tick = '1' and clk_left = 1
                             and cur_last = '0')
                else '0';

    busy <= '0' when state = S_IDLE and cs_cnt = 0 else '1';

    process (clk)
        -- Drive the pads for one SCLK cycle (both dies)
        procedure set_pads(quad : std_logic; dir : dir_t; d1, d2 : std_logic_vector(31 downto 0)) is
        begin
            io_oe_r(3 downto 0) <= lane_oe(quad, dir);
            io_o_r(3 downto 0)  <= lane_o(quad, dir, d1);
            if DIE2_PRESENT then
                io_oe_r(7 downto 4) <= lane_oe(quad, dir);
                io_o_r(7 downto 4)  <= lane_o(quad, dir, d2);
            else
                io_oe_r(7 downto 4) <= "0000";
                io_o_r(7 downto 4)  <= "0000";
            end if;
        end procedure;

        -- Launch an RX cycle: its sample is taken sample_dly clk cycles from now
        procedure launch(quad : std_logic; last : boolean) is
        begin
            tok_v(1) <= '1';
            tok_q(1) <= quad;
            if last then
                tok_l(1) <= '1';
            else
                tok_l(1) <= '0';
            end if;
        end procedure;

        -- Load a phase descriptor; its first SCLK cycle (low half) starts now
        procedure load_phase is
            variable quad : std_logic;
        begin
            if ph_lanes = QUAD4 then
                quad := '1';
            else
                quad := '0';
            end if;
            cur_quad  <= quad;
            cur_dir   <= ph_dir;
            cur_last  <= ph_last;
            clk_left  <= ph_nclk;
            sh1       <= ph_tx1;
            sh2       <= ph_tx2;
            cs_high_l <= ph_cs_high;
            half      <= '0';
            div_cnt   <= 0;
            set_pads(quad, ph_dir, ph_tx1, ph_tx2);
            if ph_dir = DIR_RX then
                launch(quad, ph_nclk = 1);
            end if;
        end procedure;

        variable nsh1, nsh2 : std_logic_vector(31 downto 0);
        variable pending    : boolean;
    begin
        if rising_edge(clk) then
            -- Input capture (pad register) and RX sample pipeline
            io_i_r <= io_i;
            if not DIE2_PRESENT then
                io_i_r(7 downto 4) <= "0000";
            end if;
            tok_v <= '0' & tok_v(1 to NSTAGE - 1);
            tok_q <= '0' & tok_q(1 to NSTAGE - 1);
            tok_l <= '0' & tok_l(1 to NSTAGE - 1);

            rx_valid_r <= '0';
            if tok_v(sample_dly + 1) = '1' then
                rx_valid_r <= '1';
                rx_last_r  <= tok_l(sample_dly + 1);
                if tok_q(sample_dly + 1) = '1' then
                    rx_data_r <= io_i_r;
                else
                    rx_data_r <= "000" & io_i_r(5) & "000" & io_i_r(1);
                end if;
            end if;

            case state is
                when S_IDLE =>
                    if cs_cnt /= 0 then
                        cs_cnt <= cs_cnt - 1;
                    elsif ph_valid = '1' then
                        cs_n_r <= "00";
                        div_l  <= ph_sclk_div;
                        load_phase;
                        state  <= S_RUN;
                    end if;

                when S_RUN =>
                    if end_tick = '1' then
                        div_cnt <= 0;
                    else
                        div_cnt <= div_cnt + 1;
                    end if;

                    if end_tick = '1' and half = '0' then
                        sclk_r <= "11";
                        half   <= '1';
                    elsif end_tick = '1' then               -- Falling edge: next SCLK cycle
                        sclk_r <= "00";
                        half   <= '0';
                        if clk_left > 1 then
                            clk_left <= clk_left - 1;
                            nsh1 := shift_tx(cur_quad, sh1);
                            nsh2 := shift_tx(cur_quad, sh2);
                            sh1  <= nsh1;
                            sh2  <= nsh2;
                            set_pads(cur_quad, cur_dir, nsh1, nsh2);
                            if cur_dir = DIR_RX then
                                launch(cur_quad, clk_left = 2);
                            end if;
                        elsif cur_last = '1' then
                            state <= S_END;
                        elsif ph_valid = '1' then
                            load_phase;
                        else
                            state <= S_WAIT;
                        end if;
                    end if;

                when S_WAIT =>
                    if ph_valid = '1' then
                        load_phase;
                        state <= S_RUN;
                    end if;

                when S_END =>
                    -- CS# high once every launched RX cycle has been captured
                    pending := false;
                    for i in 1 to SAMPLE_DLY_MAX loop
                        if i <= sample_dly and tok_v(i) = '1' then
                            pending := true;
                        end if;
                    end loop;
                    if not pending then
                        -- The pads keep their state: after a QUAD4 read the device needs its
                        -- output disable time (tSHQZ/tHZCS) before IO may be driven again.
                        -- The next transaction sets them together with CS# low.
                        cs_n_r <= "11";
                        cs_cnt <= cs_high_l - 1;
                        state  <= S_IDLE;
                    end if;
            end case;

            if reset_n = '0' then
                state    <= S_IDLE;
                sclk_r   <= "00";
                cs_n_r   <= "11";
                cs_cnt   <= (others => '0');
                tok_v    <= (others => '0');
                rx_valid_r <= '0';
                io_i_r     <= (others => '0');   -- Same reset as the output/OE registers, so all
                                                 -- three can be combined into one I/O cell
                set_pads('0', DIR_NONE, (others => '0'), (others => '0'));
            end if;
        end if;
    end process;

    rx_valid <= rx_valid_r;
    rx_data  <= rx_data_r;
    rx_last  <= rx_last_r;

    sclk  <= sclk_r;
    cs_n  <= cs_n_r;
    io_o  <= io_o_r;
    io_oe <= io_oe_r;
end architecture rtl;
