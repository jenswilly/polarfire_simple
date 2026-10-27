-- Self-checking testbench for axis_spi_master
--   A behavioural SPI slave checks every MOSI byte against the TX sequence, drives a known
--   MISO sequence (5 ns clock-to-out) and checks that every cs_n assertion carries exactly
--   FRAME_BYTES * 8 bits with sclk idle at both cs_n edges.
--   A timing monitor checks the sclk half-periods and the cs_n setup/hold/idle times.
--   The RX monitor checks m_axis data and tlast. Random stalls are applied to s_axis_tvalid
--   and m_axis_tready, plus regular long m_axis_tready stalls (several byte times).
--   The last frame has a wrong s_axis_tlast and must give frame_err_out pulses.
--   Finally reset_n is pulsed mid-frame and the DUT must return to idle.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).
--
-- Defaults: 10-byte frames, CLK_DIV 7, 200 MHz (the fabric clock). Integer generics can be
-- overridden from the command line to cover other modes, e.g.
--   sim/run_tb.sh tb_axis_spi_master -gCPOL_I=1 -gCPHA_I=1 -gMSB_I=0

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_axis_spi_master is
    generic (
        CPOL_I      : integer  := 0;
        CPHA_I      : integer  := 0;
        MSB_I       : integer  := 1;
        FRAME_BYTES : positive := 10;
        CLK_DIV     : positive := 7;
        NFRAMES     : positive := 20;   -- Good frames; one frame with a bad tlast follows
        STALLS      : integer  := 1;    -- 1: random tvalid/tready stalls
        MISO_SYNC_I : natural  := 2
    );
end entity tb_axis_spi_master;

architecture sim of tb_axis_spi_master is

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
    constant NBYTES     : natural   := (NFRAMES + 1) * FRAME_BYTES;
    constant CLK_PERIOD : time      := 5 ns;    -- 200 MHz, same as the fabric clock

    constant CS_SETUP   : natural   := 1;
    constant CS_HOLD    : natural   := 1;
    constant CS_IDLE    : natural   := 2;
    constant HALF_T     : time      := CLK_DIV * CLK_PERIOD;
    constant SETUP_T    : time      := ((CS_SETUP + 1) * CLK_DIV + 2) * CLK_PERIOD;
    constant HOLD_T     : time      := (CS_HOLD * CLK_DIV + 1) * CLK_PERIOD;
    constant IDLE_T     : time      := (CS_IDLE * CLK_DIV + 1) * CLK_PERIOD;

    -- Bad tlast in the last frame: tlast on byte 0 and not on the last byte
    function exp_ferr return natural is
    begin
        if FRAME_BYTES = 1 then
            return 1;
        else
            return 2;
        end if;
    end function;

    -- Data sequences
    function tx_byte(i : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned((i * 13 + 7) mod 256, 8));
    end function;

    function rx_byte(i : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned((i * 37 + 5) mod 256, 8)) xor x"A5";
    end function;

    signal clk      : std_logic := '0';
    signal rstn     : std_logic := '0';

    signal s_tdata  : std_logic_vector(7 downto 0) := (others => '0');
    signal s_tvalid : std_logic := '0';
    signal s_tready : std_logic;
    signal s_tlast  : std_logic := '0';

    signal m_tdata  : std_logic_vector(7 downto 0);
    signal m_tvalid : std_logic;
    signal m_tready : std_logic := '0';
    signal m_tlast  : std_logic;

    signal sclk, mosi, cs_n : std_logic;
    signal miso             : std_logic := 'Z';
    signal busy, frame_err  : std_logic;

    signal tx_done, rx_done, slv_done : boolean := false;
    signal reset_phase                : boolean := false;   -- Set by p_ctrl for the reset test
    signal done                       : boolean := false;
    signal ferr_count                 : natural := 0;

    -- Per-process error counts, summed at the end
    signal err_slv, err_rx, err_tim : natural := 0;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.axis_spi_master
        generic map (
            FRAME_BYTES => FRAME_BYTES,
            CLK_DIV     => CLK_DIV,
            CPOL        => CPOL,
            CPHA        => CPHA,
            MSB_FIRST   => MSBF,
            CS_SETUP    => CS_SETUP,
            CS_HOLD     => CS_HOLD,
            CS_IDLE     => CS_IDLE,
            MISO_SYNC   => MISO_SYNC_I)
        port map (
            clk => clk, reset_n => rstn,
            s_axis_tdata => s_tdata, s_axis_tvalid => s_tvalid,
            s_axis_tready => s_tready, s_axis_tlast => s_tlast,
            m_axis_tdata => m_tdata, m_axis_tvalid => m_tvalid,
            m_axis_tready => m_tready, m_axis_tlast => m_tlast,
            spi_sclk => sclk, spi_mosi => mosi, spi_miso => miso, spi_cs_n => cs_n,
            busy_out => busy, frame_err_out => frame_err);

    -- TX driver: NBYTES bytes, then keeps a byte offered until the reset test is over
    p_tx : process
        variable seed1, seed2 : positive := 11;
        variable r            : real;
        variable bad_frame    : boolean;
        variable first, last  : boolean;
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
            bad_frame := i >= NFRAMES * FRAME_BYTES;
            first     := (i mod FRAME_BYTES) = 0;
            last      := (i mod FRAME_BYTES) = FRAME_BYTES - 1;
            s_tdata   <= tx_byte(i);
            if bad_frame then
                s_tlast <= to_sl(first and not last);
            else
                s_tlast <= to_sl(last);
            end if;
            s_tvalid <= '1';
            wait until rising_edge(clk) and s_tready = '1';
        end loop;
        s_tvalid <= '0';
        s_tlast  <= '0';
        tx_done  <= true;

        -- Reset test: start a new frame and keep feeding bytes until p_ctrl resets the DUT
        wait until reset_phase;
        s_tdata  <= x"FF";
        s_tvalid <= '1';
        wait until rstn = '0';
        s_tvalid <= '0';
        wait;
    end process;

    -- RX monitor
    p_rx : process
        variable seed1, seed2 : positive := 77;
        variable r            : real;
        variable i            : natural := 0;
        variable errs         : natural := 0;
        variable exp_last     : std_logic;
        variable stall_left   : natural := 0;
        variable stalled_at   : integer := -1;
    begin
        m_tready <= '0';
        wait until rstn = '1';
        
        while i < NBYTES loop
            wait until rising_edge(clk);
            if m_tvalid = '1' and m_tready = '1' then
                if m_tdata /= rx_byte(i) then
                    report "RX data mismatch at byte " & integer'image(i) severity error;
                    errs := errs + 1;
                end if;
                exp_last := to_sl((i mod FRAME_BYTES) = FRAME_BYTES - 1);
                if m_tlast /= exp_last then
                    report "RX tlast mismatch at byte " & integer'image(i) severity error;
                    errs := errs + 1;
                end if;
                i := i + 1;
            end if;
            if STALLS /= 0 then
                -- Every 7th byte: hold tready low for about 3 byte times (overrun check)
                if i mod 7 = 3 and stalled_at /= i then
                    stalled_at := i;
                    stall_left := 3 * 16 * CLK_DIV;
                end if;
                if stall_left > 0 then
                    stall_left := stall_left - 1;
                    m_tready   <= '0';
                else
                    uniform(seed1, seed2, r);
                    m_tready <= to_sl(r < 0.6);
                end if;
            else
                m_tready <= '1';
            end if;
        end loop;

        m_tready <= '1';
        err_rx   <= errs;
        rx_done  <= true;
        wait;
    end process;

    -- Behavioural SPI slave
    p_slave : process
        variable byte_i  : natural := 0;    -- Global byte index
        variable bit_i   : natural;         -- Bit within the byte, 0..7
        variable bits    : natural;         -- Bits in this cs_n assertion
        variable rx_sh   : std_logic_vector(7 downto 0);
        variable tx_b    : std_logic_vector(7 downto 0);
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
        miso <= 'Z';
        wait until rstn = '1';
        while byte_i < NBYTES loop
            wait until cs_n = '0';
            if sclk /= CPOL then
                report "Sclk not idle at cs_n fall" severity error;
                errs := errs + 1;
            end if;
            bits  := 0;
            bit_i := 0;
            tx_b  := rx_byte(byte_i);
            if CPHA = '0' then
                miso <= tx_b(wire_bit(0)) after 5 ns;
            end if;

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
                        tx_b   := rx_byte(byte_i);
                    end if;
                else
                    -- Shift edge: present the next bit (for CPHA = 0 at a byte boundary,
                    -- this is bit 0 of the next byte)
                    miso <= tx_b(wire_bit(bit_i)) after 5 ns;
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
            miso <= 'Z' after 5 ns;
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
                    -- Exact without stalls; an m_axis stall can hold the first byte back
                    check(now - t_cs_fall = SETUP_T or (STALLS /= 0 and now - t_cs_fall > SETUP_T), "cs_n setup " & time'image(now - t_cs_fall)
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

    p_ferr : process (clk)
    begin
        if rising_edge(clk) then
            if frame_err = '1' then
                ferr_count <= ferr_count + 1;
            end if;
        end if;
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

        wait until (tx_done and rx_done and slv_done) for 50 ms;
        check(tx_done and rx_done and slv_done, "timeout");
        clocks(20 * CLK_DIV);
        check(busy = '0' and cs_n = '1' and sclk = CPOL, "DUT not idle after the data phase");
        check(ferr_count = exp_ferr, "bad tlast frame: expected " & integer'image(exp_ferr)
              & " frame_err_out pulse(s), got " & integer'image(ferr_count));

        -- Reset in the middle of a byte
        reset_phase <= true;
        wait until cs_n = '0' for 1 ms;
        check(cs_n = '0', "reset test: frame did not start");
        clocks((CS_SETUP + 1) * CLK_DIV + 2 + 5 * CLK_DIV);   -- A few sclk edges into byte 0
        rstn <= '0';
        clocks(1);
        wait for 1 ns;
        check(cs_n = '1' and sclk = CPOL and busy = '0' and m_tvalid = '0' and s_tready = '0',
              "reset test: DUT not idle during reset");
        clocks(2);
        rstn <= '1';
        clocks(10 * CLK_DIV);
        check(cs_n = '1' and busy = '0', "reset test: DUT not idle after reset");

        errors := errors + err_slv + err_rx + err_tim;
        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture sim;
