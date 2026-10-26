-- Self-checking testbench for axis_spi_wo_master (write-only SPI master)
--   A behavioural SPI slave checks every MOSI byte against the TX sequence and checks that
--   every cs_n assertion carries exactly FRAME_BYTES * 8 bits with sclk idle at both cs_n edges.
--   A timing monitor checks the sclk half-periods and the cs_n setup/hold/idle times.
--   Random stalls are applied to s_axis_tvalid.
--   Finally reset_n is pulsed mid-frame and the DUT must return to idle.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).
--
-- Defaults match the design (10-byte frames, CLK_DIV 7, 125 MHz). Integer generics can be
-- overridden from the command line to cover other modes, e.g.
--   sim/run_tb.sh tb_axis_spi_wo_master -gCPOL_I=1 -gCPHA_I=1 -gMSB_I=0

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_axis_spi_wo_master is
    generic (
        CPOL_I      : integer  := 0;
        CPHA_I      : integer  := 0;
        MSB_I       : integer  := 1;
        FRAME_BYTES : positive := 10;
        CLK_DIV     : positive := 7;
        NFRAMES     : positive := 20;
        STALLS      : integer  := 1     -- 1: random tvalid stalls
    );
end entity tb_axis_spi_wo_master;

architecture sim of tb_axis_spi_wo_master is

    function to_sl(b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function;

    constant CPOL       : std_logic := to_sl(CPOL_I /= 0);
    constant CPHA       : std_logic := to_sl(CPHA_I /= 0);
    constant MSBF       : boolean   := MSB_I /= 0;
    constant NBYTES     : natural   := NFRAMES * FRAME_BYTES;
    constant CLK_PERIOD : time      := 8 ns;    -- 125 MHz, same as the fabric clock

    constant CS_SETUP   : natural   := 1;
    constant CS_HOLD    : natural   := 1;
    constant CS_IDLE    : natural   := 2;
    constant HALF_T     : time      := CLK_DIV * CLK_PERIOD;
    constant SETUP_T    : time      := ((CS_SETUP + 1) * CLK_DIV + 2) * CLK_PERIOD;
    constant HOLD_T     : time      := (CS_HOLD * CLK_DIV + 1) * CLK_PERIOD;
    constant IDLE_T     : time      := (CS_IDLE * CLK_DIV + 1) * CLK_PERIOD;

    -- Data sequence
    function tx_byte(i : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned((i * 13 + 7) mod 256, 8));
    end function;

    signal clk      : std_logic := '0';
    signal rstn     : std_logic := '0';

    signal s_tdata  : std_logic_vector(7 downto 0) := (others => '0');
    signal s_tvalid : std_logic := '0';
    signal s_tready : std_logic;

    signal sclk, mosi, cs_n : std_logic;
    signal busy             : std_logic;

    signal tx_done, slv_done : boolean := false;
    signal reset_phase       : boolean := false;   -- Set by p_ctrl for the reset test
    signal done              : boolean := false;

    -- Per-process error counts, summed at the end
    signal err_slv, err_tim : natural := 0;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.axis_spi_wo_master
        generic map (
            FRAME_BYTES => FRAME_BYTES,
            CLK_DIV     => CLK_DIV,
            CPOL        => CPOL,
            CPHA        => CPHA,
            MSB_FIRST   => MSBF,
            CS_SETUP    => CS_SETUP,
            CS_HOLD     => CS_HOLD,
            CS_IDLE     => CS_IDLE)
        port map (
            clk => clk, reset_n => rstn,
            s_axis_tdata => s_tdata, s_axis_tvalid => s_tvalid,
            s_axis_tready => s_tready,
            spi_sclk => sclk, spi_mosi => mosi, spi_cs_n => cs_n,
            busy_out => busy);

    -- TX driver: NBYTES bytes, then keeps a byte offered until the reset test is over
    p_tx : process
        variable seed1, seed2 : positive := 11;
        variable r            : real;
    begin
        wait until rising_edge(clk) and rstn = '1';
        for i in 0 to NBYTES - 1 loop
            -- Random idle cycles
            if STALLS /= 0 then
                uniform(seed1, seed2, r);
                if r < 0.3 then
                    s_tvalid <= '0';
                    for k in 0 to integer(r * 400.0) loop
                        wait until rising_edge(clk);
                    end loop;
                end if;
            end if;
            s_tdata  <= tx_byte(i);
            s_tvalid <= '1';
            wait until rising_edge(clk) and s_tready = '1';
        end loop;
        s_tvalid <= '0';
        tx_done  <= true;

        -- Reset test: start a new frame and keep feeding bytes until p_ctrl resets the DUT
        wait until reset_phase;
        s_tdata  <= x"FF";
        s_tvalid <= '1';
        wait until rstn = '0';
        s_tvalid <= '0';
        wait;
    end process;

    -- Behavioural SPI slave (receive only)
    p_slave : process
        variable byte_i  : natural := 0;    -- Global byte index
        variable bit_i   : natural;         -- Bit within the byte, 0..7
        variable bits    : natural;         -- Bits in this cs_n assertion
        variable rx_sh   : std_logic_vector(7 downto 0);
        variable errs    : natural := 0;
        variable leading : boolean;

        -- Bit number on the wire (0 = first) -> bit index in the byte
        function wire_bit(n : natural) return natural is
        begin
            if MSBF then
                return 7 - n;
            else
                return n;
            end if;
        end function;
    begin
        wait until rstn = '1';
        while byte_i < NBYTES loop
            wait until cs_n = '0';
            if sclk /= CPOL then
                report "Sclk not idle at cs_n fall" severity error;
                errs := errs + 1;
            end if;
            bits  := 0;
            bit_i := 0;

            loop
                wait on sclk, cs_n;
                exit when cs_n = '1';
                leading := sclk /= CPOL;

                if leading = (CPHA = '0') then
                    -- Sample edge
                    rx_sh(wire_bit(bit_i)) := mosi;
                    bits  := bits + 1;
                    bit_i := bit_i + 1;
                    if bit_i = 8 then
                        if rx_sh /= tx_byte(byte_i) then
                            report "MOSI mismatch at byte " & integer'image(byte_i) severity error;
                            errs := errs + 1;
                        end if;
                        byte_i := byte_i + 1;
                        bit_i  := 0;
                    end if;
                end if;
            end loop;

            if sclk /= CPOL then
                report "Sclk not idle at cs_n rise" severity error;
                errs := errs + 1;
            end if;
            if bits /= FRAME_BYTES * 8 then
                report "Frame had " & integer'image(bits) & " bits, expected "
                       & integer'image(FRAME_BYTES * 8) severity error;
                errs := errs + 1;
            end if;
        end loop;
        err_slv  <= errs;
        slv_done <= true;
        wait;
    end process;

    -- Timing monitor (only during the data phase, not the reset test)
    p_timing : process
        variable errs       : natural := 0;
        variable t_cs_fall  : time    := 0 ns;
        variable t_cs_rise  : time    := -1 ns;   -- Negative: no frame yet
        variable t_sclk     : time    := 0 ns;
        variable first_edge : boolean := false;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errs := errs + 1;
                report msg severity error;
            end if;
        end procedure;
    begin
        wait until rstn = '1';
        while not slv_done loop
            wait on sclk, cs_n, slv_done;
            if cs_n'event and cs_n = '0' then
                if t_cs_rise >= 0 ns then
                    check(now - t_cs_rise >= IDLE_T, "cs_n high for " & time'image(now - t_cs_rise)
                          & ", min. " & time'image(IDLE_T));
                end if;
                t_cs_fall  := now;
                first_edge := true;
            elsif cs_n'event and cs_n = '1' then
                check(now - t_sclk = HOLD_T, "cs_n hold " & time'image(now - t_sclk)
                      & ", expected " & time'image(HOLD_T));
                t_cs_rise := now;
            elsif sclk'event and cs_n = '0' then
                if first_edge then
                    -- Always exact: a frame only starts when the first byte is already offered
                    check(now - t_cs_fall = SETUP_T, "cs_n setup " & time'image(now - t_cs_fall)
                          & ", expected " & time'image(SETUP_T));
                    first_edge := false;
                elsif sclk = CPOL then
                    -- End of an active half-period: always exactly CLK_DIV
                    check(now - t_sclk = HALF_T, "sclk active half-period " & time'image(now - t_sclk));
                else
                    -- End of an idle-level half-period: CLK_DIV, or longer between bytes/stalls
                    check(now - t_sclk >= HALF_T, "sclk idle half-period " & time'image(now - t_sclk));
                end if;
                t_sclk := now;
            elsif sclk'event then
                check(false, "sclk toggled with cs_n high");
            end if;
        end loop;
        err_tim <= errs;
        wait;
    end process;

    -- Control, reset test and summary
    p_ctrl : process
        variable errors : natural := 0;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errors := errors + 1;
                report "CHECK FAILED: " & msg severity error;
            end if;
        end procedure;

        procedure clocks(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;
    begin
        clocks(10);
        rstn <= '1';

        wait until (tx_done and slv_done) for 50 ms;
        check(tx_done and slv_done, "timeout");
        clocks(20 * CLK_DIV);
        check(busy = '0' and cs_n = '1' and sclk = CPOL, "DUT not idle after the data phase");

        -- Reset in the middle of a byte
        reset_phase <= true;
        wait until cs_n = '0' for 1 ms;
        check(cs_n = '0', "reset test: frame did not start");
        clocks((CS_SETUP + 1) * CLK_DIV + 2 + 5 * CLK_DIV);   -- A few sclk edges into byte 0
        rstn <= '0';
        clocks(1);
        wait for 1 ns;
        check(cs_n = '1' and sclk = CPOL and busy = '0' and s_tready = '0',
              "reset test: DUT not idle during reset");
        clocks(2);
        rstn <= '1';
        clocks(10 * CLK_DIV);
        check(cs_n = '1' and busy = '0', "reset test: DUT not idle after reset");

        errors := errors + err_slv + err_tim;
        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture sim;
