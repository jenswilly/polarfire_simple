-- Self-checking testbench for qspi_phy
--   A driver feeds a fixed table of transactions (phase descriptors) to the PHY, once per run.
--   Each run has its own SCLK divider (1, 2), sample delay (1-4) and device round-trip delay.
--   A pin-level device stub follows the same table and checks, at every SCLK edge:
--     - CS#/SCLK: first rising edge sclk_div clk cycles after CS# low, exact high/low times,
--       exactly the expected number of SCLK cycles per CS# assertion, CS# high only after the
--       last falling edge and after the last delayed RX sample, CS# high time >= ph_cs_high
--       (exact when the next transaction is already waiting)
--     - TX bit order: SPI1 on IO0/IO4 MSB first, QUAD4 on IO3:0/IO7:4 high nibble first
--     - OE: SPI1 = IO0/IO2/IO3 driven (IO2/IO3 high), QUAD4 TX all driven, QUAD4 RX/NONE released
--   and drives RX data (IO1/IO5 in SPI1, IO3:0/IO7:4 in QUAD4) a delay T after each falling
--   edge that launches an RX cycle, and 'X' otherwise. With T = 10 ns * sample_dly - 5 ns the
--   PHY must return exactly that data; a run with a mismatched T must give wrong data.
--   One run inserts gaps between descriptors (SCLK pauses, PHY state S_WAIT).
--   A monitor checks on every pin event: SCLK toggles only while CS# is low, CS# and OE change
--   only while SCLK is low, and sclk(1)/cs_n(1) equal sclk(0)/cs_n(0).
--   DIE2_I = 1 (default) runs with DIE2_PRESENT = true; -gDIE2_I=0 with false (IO7:4 must stay
--   undriven and their RX nibble must read 0).
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;

entity tb_qspi_phy is
    generic (
        DIE2_I : integer := 1
    );
end entity tb_qspi_phy;

architecture sim of tb_qspi_phy is
    constant DIE2       : boolean := DIE2_I /= 0;
    constant CLK_PERIOD : time    := 10 ns;          -- clk_ctrl 100 MHz

    -- Transaction table: phases, ph_last ends a transaction
    type phase_t is record
        lanes   : lane_mode_t;
        dir     : dir_t;
        nclk    : positive;
        d1, d2  : std_logic_vector(31 downto 0);
        last    : boolean;
        cs_high : positive;
    end record;
    type phase_arr_t is array (natural range <>) of phase_t;

    constant Z32 : std_logic_vector(31 downto 0) := (others => '0');
    constant TABLE : phase_arr_t := (
        -- Read ID: opcode, 32 bits back in SPI1
        (SPI1,  DIR_TX,   8,  x"9F000000", x"9E000000", false, 2),
        (SPI1,  DIR_RX,   32, Z32,         Z32,         true,  2),
        -- EBh read: opcode, address, mode byte, dummy, data
        (SPI1,  DIR_TX,   8,  x"EB000000", x"EB000000", false, 2),
        (QUAD4, DIR_TX,   8,  x"12345678", x"9ABCDEF0", false, 2),
        (QUAD4, DIR_TX,   2,  x"FF000000", x"F0000000", false, 2),
        (QUAD4, DIR_NONE, 4,  Z32,         Z32,         false, 2),
        (QUAD4, DIR_RX,   40, Z32,         Z32,         true,  2),
        -- Quad write, ending with a 1-cycle phase; long CS# high time afterwards
        (SPI1,  DIR_TX,   8,  x"D2000000", x"D2000000", false, 60),
        (QUAD4, DIR_TX,   8,  x"00ABCDEF", x"00FEDCBA", false, 60),
        (QUAD4, DIR_TX,   8,  x"A5C30FF0", x"5A3CF00F", false, 60),
        (QUAD4, DIR_TX,   1,  x"70000000", x"C0000000", true,  60),
        -- Odd lengths, SPI1 latency, SPI1 RX followed by a 1-cycle QUAD4 RX
        (SPI1,  DIR_TX,   5,  x"B8000000", x"40000000", false, 3),
        (SPI1,  DIR_NONE, 3,  Z32,         Z32,         false, 3),
        (SPI1,  DIR_RX,   16, Z32,         Z32,         false, 3),
        (QUAD4, DIR_RX,   1,  Z32,         Z32,         true,  3),
        -- Single-cycle transaction, minimum CS# high time
        (SPI1,  DIR_TX,   1,  x"80000000", x"00000000", true,  1)
    );

    -- Runs: SCLK divider, sample delay, device round-trip delay, expected result, descriptor gaps
    type run_t is record
        div  : positive;
        dly  : positive;
        t_rt : time;
        ok   : boolean;
        gap  : boolean;
    end record;
    type run_arr_t is array (natural range <>) of run_t;
    constant RUNS : run_arr_t := (
        (1, 1,  5 ns, true,  false),
        (1, 2, 15 ns, true,  false),
        (1, 3, 25 ns, true,  false),
        (1, 4, 35 ns, true,  false),
        (2, 1,  5 ns, true,  false),
        (2, 2, 15 ns, true,  false),
        (2, 3, 25 ns, true,  false),
        (2, 4, 35 ns, true,  false),
        (1, 2, 15 ns, true,  true),    -- Gaps between descriptors
        (1, 1, 25 ns, false, false)    -- Sample before the data arrives: must fail
    );

    signal clk         : std_logic := '0';
    signal rstn        : std_logic := '0';
    signal ph_valid    : std_logic := '0';
    signal ph_ready    : std_logic;
    signal ph_lanes    : lane_mode_t := SPI1;
    signal ph_dir      : dir_t := DIR_NONE;
    signal ph_nclk     : unsigned(15 downto 0) := (others => '0');
    signal ph_tx1      : std_logic_vector(31 downto 0) := (others => '0');
    signal ph_tx2      : std_logic_vector(31 downto 0) := (others => '0');
    signal ph_last     : std_logic := '0';
    signal ph_sclk_div : natural range 1 to SCLK_DIV_MAX := 1;
    signal ph_cs_high  : unsigned(7 downto 0) := (others => '0');
    signal sample_dly  : natural range 1 to SAMPLE_DLY_MAX := 1;
    signal rx_valid    : std_logic;
    signal rx_data     : std_logic_vector(7 downto 0);
    signal rx_last     : std_logic;
    signal busy        : std_logic;
    signal sclk        : std_logic_vector(1 downto 0);
    signal cs_n        : std_logic_vector(1 downto 0);
    signal io_o        : std_logic_vector(7 downto 0);
    signal io_oe       : std_logic_vector(7 downto 0);
    signal io_i        : std_logic_vector(7 downto 0) := (others => 'X');

    signal run_idx     : natural := 0;           -- Current run (set by the driver)
    signal done        : boolean := false;

    -- Expected RX words, written by the stub, read by the checker
    constant EXP_MAX : positive := 2048;
    type word_arr_t is array (0 to EXP_MAX - 1) of std_logic_vector(7 downto 0);
    type nat_arr_t  is array (0 to EXP_MAX - 1) of natural;
    signal exp_word  : word_arr_t := (others => (others => '0'));
    signal exp_last  : std_logic_vector(0 to EXP_MAX - 1) := (others => '0');
    signal exp_run   : nat_arr_t := (others => 0);
    signal exp_wr    : natural := 0;

    signal stub_errors, chk_errors, mon_errors : natural := 0;
    signal stub_done   : boolean := false;
    signal chk_count   : natural := 0;
    signal bad_words   : natural := 0;          -- Mismatches in the run that must fail

    -- Next cycle after (p, c) within the same transaction
    procedure next_cycle(p, c : natural; np, nc : out natural; has : out boolean) is
    begin
        has := true;
        if c + 1 < TABLE(p).nclk then
            np := p; nc := c + 1;
        elsif not TABLE(p).last then
            np := p + 1; nc := 0;
        else
            np := p; nc := c; has := false;
        end if;
    end procedure;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.qspi_phy
        generic map (DIE2_PRESENT => DIE2, NCLK_W => 16, CS_HIGH_W => 8)
        port map (
            clk => clk, reset_n => rstn,
            ph_valid => ph_valid, ph_ready => ph_ready, ph_lanes => ph_lanes, ph_dir => ph_dir,
            ph_nclk => ph_nclk, ph_tx1 => ph_tx1, ph_tx2 => ph_tx2, ph_last => ph_last,
            ph_sclk_div => ph_sclk_div, ph_cs_high => ph_cs_high, sample_dly => sample_dly,
            rx_valid => rx_valid, rx_data => rx_data, rx_last => rx_last, busy => busy,
            sclk => sclk, cs_n => cs_n, io_o => io_o, io_oe => io_oe, io_i => io_i);

    -- Descriptor driver
    driver : process
    begin
        rstn <= '0';
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;
        rstn <= '1';

        for r in RUNS'range loop
            -- Change the settings only while the PHY is idle
            wait until rising_edge(clk) and busy = '0';
            run_idx    <= r;
            sample_dly <= RUNS(r).dly;
            wait until rising_edge(clk);

            for i in TABLE'range loop
                ph_lanes    <= TABLE(i).lanes;
                ph_dir      <= TABLE(i).dir;
                ph_nclk     <= to_unsigned(TABLE(i).nclk, 16);
                ph_tx1      <= TABLE(i).d1;
                ph_tx2      <= TABLE(i).d2;
                ph_last     <= '1' when TABLE(i).last else '0';
                ph_sclk_div <= RUNS(r).div;
                ph_cs_high  <= to_unsigned(TABLE(i).cs_high, 8);
                ph_valid    <= '1';
                wait until rising_edge(clk) and ph_ready = '1';
                if RUNS(r).gap then
                    ph_valid <= '0';
                    for k in 1 to 7 loop
                        wait until rising_edge(clk);
                    end loop;
                end if;
            end loop;
            ph_valid <= '0';
        end loop;

        wait until rising_edge(clk) and busy = '0';
        if not stub_done then
            wait until stub_done;
        end if;
        for i in 1 to 10 loop
            wait until rising_edge(clk);
        end loop;
        done <= true;
        wait;
    end process;

    -- Pin-level device stub and checker
    stub : process
        variable errors      : natural := 0;
        variable p, c        : natural;
        variable np, nc      : natural;
        variable has_next    : boolean;
        variable ti          : natural;
        variable div         : positive;
        variable t_cs_fall   : time;
        variable t_cs_rise   : time := 0 ns;
        variable t_rise      : time;
        variable t_fall      : time;
        variable t_launch    : time;
        variable had_rx      : boolean;
        variable first_rise  : boolean;
        variable first_in_run: boolean;
        variable prev_cs_high: natural := 0;
        variable lfsr        : std_logic_vector(15 downto 0) := x"ACE1";
        variable nib1, nib2  : std_logic_vector(3 downto 0);
        variable drive       : std_logic_vector(7 downto 0);
        variable word        : std_logic_vector(7 downto 0);
        variable wr          : natural := 0;
        variable ph          : phase_t;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                report "STUB CHECK FAILED (run " & integer'image(run_idx) & ", phase "
                       & integer'image(p) & ", cycle " & integer'image(c) & "): " & msg
                       severity error;
                errors := errors + 1;
            end if;
        end procedure;

        procedure next_rand is
        begin
            for k in 1 to 8 loop
                lfsr := lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
            end loop;
        end procedure;

        -- Check the pads at a rising edge for cycle c of phase ph
        procedure check_pads is
            variable oe_exp : std_logic_vector(3 downto 0);
        begin
            if ph.lanes = SPI1 then
                oe_exp := "1101";
            elsif ph.dir = DIR_TX then
                oe_exp := "1111";
            else
                oe_exp := "0000";
            end if;
            check(io_oe(3 downto 0) = oe_exp, "die 1 OE: expected " & to_string(oe_exp)
                  & ", got " & to_string(io_oe(3 downto 0)));
            if DIE2 then
                check(io_oe(7 downto 4) = oe_exp, "die 2 OE: expected " & to_string(oe_exp)
                      & ", got " & to_string(io_oe(7 downto 4)));
            else
                check(io_oe(7 downto 4) = "0000", "die 2 not present: IO7:4 must not be driven");
            end if;
            if ph.lanes = SPI1 then
                check(io_o(3 downto 2) = "11", "SPI1: IO3/IO2 (HOLD#/WP#) must be high");
                if DIE2 then
                    check(io_o(7 downto 6) = "11", "SPI1: IO7/IO6 (HOLD#/WP#) must be high");
                end if;
                if ph.dir = DIR_TX then
                    check(io_o(0) = ph.d1(31 - c), "SPI1 die 1 bit on IO0");
                    if DIE2 then
                        check(io_o(4) = ph.d2(31 - c), "SPI1 die 2 bit on IO4");
                    end if;
                end if;
            elsif ph.dir = DIR_TX then
                check(io_o(3 downto 0) = ph.d1(31 - 4 * c downto 28 - 4 * c),
                      "QUAD4 die 1 nibble on IO3:0: expected "
                      & to_hstring(ph.d1(31 - 4 * c downto 28 - 4 * c)) & ", got "
                      & to_hstring(io_o(3 downto 0)));
                if DIE2 then
                    check(io_o(7 downto 4) = ph.d2(31 - 4 * c downto 28 - 4 * c),
                          "QUAD4 die 2 nibble on IO7:4");
                end if;
            end if;
        end procedure;
    begin
        wait until rstn = '1';
        for r in RUNS'range loop
            div := RUNS(r).div;
            ti := 0;
            first_in_run := true;
            while ti <= TABLE'high loop
                -- One transaction: phases ti .. (first with last = true)
                p := ti; c := 0;
                wait until cs_n(0) = '0';
                t_cs_fall := now;
                if t_cs_rise > 0 ns then
                    check(now - t_cs_rise >= prev_cs_high * CLK_PERIOD, "CS# high for "
                          & time'image(now - t_cs_rise) & ", min " & integer'image(prev_cs_high)
                          & " cycles");
                    if not first_in_run and not RUNS(r).gap then
                        check(now - t_cs_rise = prev_cs_high * CLK_PERIOD, "CS# high for "
                              & time'image(now - t_cs_rise) & ", expected exactly "
                              & integer'image(prev_cs_high) & " cycles");
                    end if;
                end if;
                first_rise := true;
                had_rx := false;
                loop
                    ph := TABLE(p);
                    wait until sclk(0) = '1' or cs_n(0) = '1';
                    if cs_n(0) = '1' then
                        check(false, "CS# went high before all SCLK cycles");
                        exit;
                    end if;
                    if first_rise then
                        check(now - t_cs_fall = div * CLK_PERIOD, "first SCLK rise "
                              & time'image(now - t_cs_fall) & " after CS# low");
                    elsif RUNS(r).gap then
                        check(now - t_rise >= 2 * div * CLK_PERIOD, "SCLK period too short");
                    else
                        check(now - t_rise = 2 * div * CLK_PERIOD, "SCLK period "
                              & time'image(now - t_rise));
                    end if;
                    first_rise := false;
                    t_rise := now;
                    check_pads;

                    wait until sclk(0) = '0' or cs_n(0) = '1';
                    if cs_n(0) = '1' then
                        check(false, "CS# went high while SCLK was high");
                        exit;
                    end if;
                    check(now - t_rise = div * CLK_PERIOD, "SCLK high time " & time'image(now - t_rise));
                    t_fall := now;

                    -- This falling edge launches the next cycle: drive its RX data, or X
                    next_cycle(p, c, np, nc, has_next);
                    drive := (others => 'X');
                    if has_next and TABLE(np).dir = DIR_RX then
                        next_rand;
                        if TABLE(np).lanes = SPI1 then
                            nib1 := "000" & lfsr(0);
                            nib2 := "000" & lfsr(1);
                            drive(1) := nib1(0);
                            drive(5) := nib2(0);
                        else
                            nib1 := lfsr(3 downto 0);
                            nib2 := lfsr(7 downto 4);
                            drive(3 downto 0) := nib1;
                            drive(7 downto 4) := nib2;
                        end if;
                        if not DIE2 then
                            nib2 := "0000";
                        end if;
                        word := nib2 & nib1;
                        exp_word(wr) <= word;
                        exp_run(wr)  <= r;
                        if nc = TABLE(np).nclk - 1 then
                            exp_last(wr) <= '1';
                        else
                            exp_last(wr) <= '0';
                        end if;
                        wr := wr + 1;
                        exp_wr <= wr;
                        t_launch := now;
                        had_rx := true;
                    end if;
                    io_i <= transport drive after RUNS(r).t_rt;
                    exit when not has_next;
                    p := np; c := nc;
                end loop;

                -- End of the transaction: no more SCLK, CS# high after the last sample
                wait until cs_n(0) = '1' or sclk(0) = '1';
                if sclk(0) = '1' then
                    check(false, "extra SCLK cycle");
                    wait until cs_n(0) = '1';
                end if;
                check(now - t_fall >= CLK_PERIOD, "CS# high too soon after the last SCLK fall");
                if had_rx then
                    check(now >= t_launch + RUNS(r).dly * CLK_PERIOD,
                          "CS# high before the last RX sample");
                end if;
                t_cs_rise := now;
                prev_cs_high := TABLE(p).cs_high;
                ti := p + 1;
                first_in_run := false;
            end loop;
        end loop;
        stub_errors <= errors;
        stub_done <= true;
        wait;
    end process;

    -- RX word checker
    rx_check : process (clk)
        variable rd     : natural := 0;
        variable errors : natural := 0;
        variable bad    : natural := 0;
    begin
        if rising_edge(clk) and rx_valid = '1' then
            if rd >= exp_wr then
                report "RX CHECK FAILED: unexpected word " & to_hstring(rx_data) severity error;
                errors := errors + 1;
            elsif RUNS(exp_run(rd)).ok then
                if rx_data /= exp_word(rd) or rx_last /= exp_last(rd) then
                    report "RX CHECK FAILED (run " & integer'image(exp_run(rd)) & ", word "
                           & integer'image(rd) & "): expected " & to_hstring(exp_word(rd))
                           & " last " & std_logic'image(exp_last(rd)) & ", got "
                           & to_hstring(rx_data) & " last " & std_logic'image(rx_last)
                           severity error;
                    errors := errors + 1;
                end if;
            elsif rx_data /= exp_word(rd) then
                bad := bad + 1;
            end if;
            rd := rd + 1;
            chk_count  <= rd;
            chk_errors <= errors;
            bad_words  <= bad;
        end if;
    end process;

    -- Pin relationship monitor
    monitor : process (sclk, cs_n, io_oe)
        variable errors : natural := 0;
    begin
        if rstn = '1' then
            if sclk(1) /= sclk(0) or cs_n(1) /= cs_n(0) then
                report "MONITOR: sclk(1)/cs_n(1) differ from sclk(0)/cs_n(0)" severity error;
                errors := errors + 1;
            end if;
            if sclk(0)'event and cs_n(0) /= '0' then
                report "MONITOR: SCLK toggled while CS# high" severity error;
                errors := errors + 1;
            end if;
            if cs_n(0)'event and sclk(0) /= '0' then
                report "MONITOR: CS# changed while SCLK high" severity error;
                errors := errors + 1;
            end if;
            if io_oe'event and sclk(0) /= '0' then
                report "MONITOR: OE changed while SCLK high" severity error;
                errors := errors + 1;
            end if;
            mon_errors <= errors;
        end if;
    end process;

    -- Watchdog: the whole test takes well under 1 ms
    watchdog : process
    begin
        wait for 1 ms;
        if not done then
            report "TB FAILED: timeout (stub at run " & integer'image(run_idx) & ", "
                   & integer'image(exp_wr) & " RX words expected, " & integer'image(chk_count)
                   & " received)" severity error;
            std.env.stop;
        end if;
        wait;
    end process;

    -- Final verdict
    verdict : process
        variable errors : natural;
    begin
        wait until done;
        errors := stub_errors + chk_errors + mon_errors;
        if chk_count /= exp_wr then
            report "CHECK FAILED: " & integer'image(exp_wr) & " RX words expected, "
                   & integer'image(chk_count) & " received" severity error;
            errors := errors + 1;
        end if;
        if bad_words = 0 then
            report "CHECK FAILED: the mismatched-delay run returned correct data" severity error;
            errors := errors + 1;
        end if;
        report "RX words checked: " & integer'image(chk_count) & ", wrong in the must-fail run: "
               & integer'image(bad_words);
        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        wait;
    end process;
end architecture sim;
