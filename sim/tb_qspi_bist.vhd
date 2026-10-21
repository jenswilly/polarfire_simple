-- run_tb models: qspi_model_pkg qspi_mem_model
-- Self-checking testbench for qspi_bist + qspi_mram_ctrl against the device models
--   Five configurations side by side (4 blocks of 880 host bytes, clk_ctrl 100 MHz, SCLK 50 MHz,
--   short model times). Sample points are 10 ns apart; the device data is valid from
--   tCO/tCLQV + board delay to one SCLK period + tOH/tCLQX + board delay after the falling edge.
--     0  W25Q128JV, no calibration, SAMPLE_DLY 2, board 3 ns          -> pass
--     1  W25Q128JV, calibration, board 3.5 ns (valid 9.5..25 ns)      -> window {1,2}, delay 1, pass
--     2  AS308G208, 2 dies, calibration, SAMPLE_DLY 1, board 8 ns
--        (valid 17..29 ns): init fails with delay 1, retried with 2   -> window {2}, delay 2, pass
--     3  AS308G208, 1 die, model ignores array writes, no calibration -> fail (data mismatch)
--     4  AS308G208, 1 die, wrong ID, calibration                      -> fail (all init retries)
--   Checks: pass and fail stay off until the first round ends (pass_count >= 1 when pass rises); pass and fail are never both on;
--   passing configurations keep passing (pass_count grows to 3 with fail off); fail stays latched;
--   cal_window and cal_dly as expected; no model protocol errors in the passing configurations.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;

entity tb_qspi_bist is
end entity tb_qspi_bist;

architecture sim of tb_qspi_bist is
    constant CLK_PERIOD : time := 10 ns;

    type cfg_t is record
        dev       : device_t;
        die2      : boolean;
        calibrate : boolean;
        smp_dly   : positive;
        t_board   : time;
        mem_ign   : boolean;
        as_id     : std_logic_vector(31 downto 0);
        pass      : boolean;                       -- Expected result
        window    : std_logic_vector(4 downto 1);  -- Expected cal_window (calibrate only)
        dly       : positive;                      -- Expected cal_dly (calibrate only)
    end record;
    type cfg_arr_t is array (natural range <>) of cfg_t;
    constant CFGS : cfg_arr_t := (
        (DEV_W25Q128JV, false, false, 2, 3 ns,   false, x"E6212C01", true,  "0000", 1),
        (DEV_W25Q128JV, false, true,  2, 3.5 ns, false, x"E6212C01", true,  "0011", 1),
        (DEV_AS308G208, true,  true,  1, 8 ns,   false, x"E6212C01", true,  "0010", 2),
        (DEV_AS308G208, false, false, 2, 3 ns,   true,  x"E6212C01", false, "0000", 1),
        (DEV_AS308G208, false, true,  2, 3 ns,   false, x"E6212801", false, "0000", 1)
    );
    constant NCFG : positive := CFGS'length;

    type nat_arr_t is array (0 to NCFG - 1) of natural;
    signal tb_errors : nat_arr_t := (others => 0);
    signal finished  : boolean_vector(0 to NCFG - 1) := (others => false);

    signal clk  : std_logic := '0';
    signal rstn : std_logic := '0';
    signal done : boolean := false;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done;

    cfg : for g in 0 to NCFG - 1 generate
        constant C : cfg_t := CFGS(g);

        signal init_restart, init_done, init_err, busy : std_logic;
        signal rd_req_tdata, wr_req_tdata : std_logic_vector(47 downto 0);
        signal rd_req_tvalid, rd_req_tready, rd_req_err : std_logic;
        signal wr_req_tvalid, wr_req_tready, wr_req_err, wr_done : std_logic;
        signal rd_space    : unsigned(15 downto 0);
        signal rd_tdata, wr_tdata : std_logic_vector(7 downto 0);
        signal rd_tvalid, rd_tready, rd_tlast, wr_tvalid, wr_tready : std_logic;
        signal ovr_valid   : std_logic;
        signal ovr         : natural range 1 to SAMPLE_DLY_MAX;
        signal pass, fail  : std_logic;
        signal cal_window  : std_logic_vector(4 downto 1);
        signal cal_dly     : natural range 1 to SAMPLE_DLY_MAX;
        signal pass_count  : unsigned(15 downto 0);
        signal sclk, cs_n  : std_logic_vector(1 downto 0);
        signal io_o, io_oe : std_logic_vector(7 downto 0);
        signal io          : std_logic_vector(7 downto 0);
        signal mem_reset_n : std_logic;
        signal err1, err2  : natural := 0;
    begin
        bist : entity work.qspi_bist
            generic map (DIE2_PRESENT => C.die2, NBLK => 4, BLK_LEN => 880, BLK_STRIDE => 16#4000#,
                         BASE_ADDR => 0, CALIBRATE => C.calibrate, SPACE_W => 16)
            port map (
                clk => clk, reset_n => rstn,
                init_restart => init_restart, init_done => init_done, init_err => init_err,
                ctrl_busy => busy,
                rd_req_tdata => rd_req_tdata, rd_req_tvalid => rd_req_tvalid,
                rd_req_tready => rd_req_tready, rd_req_err => rd_req_err, rd_space => rd_space,
                rd_tdata => rd_tdata, rd_tvalid => rd_tvalid, rd_tready => rd_tready, rd_tlast => rd_tlast,
                wr_req_tdata => wr_req_tdata, wr_req_tvalid => wr_req_tvalid,
                wr_req_tready => wr_req_tready, wr_req_err => wr_req_err, wr_done => wr_done,
                wr_tdata => wr_tdata, wr_tvalid => wr_tvalid, wr_tready => wr_tready,
                sample_dly_ovr_valid => ovr_valid, sample_dly_ovr => ovr,
                pass => pass, fail => fail, cal_window => cal_window, cal_dly => cal_dly,
                pass_count => pass_count, state_dbg => open);

        ctrl : entity work.qspi_mram_ctrl
            generic map (DEVICE => C.dev, DIE2_PRESENT => C.die2, CLK_CTRL_HZ => 100_000_000,
                         SCLK_DIV => 1, SAMPLE_DLY => C.smp_dly, SPACE_W => 16,
                         T_POWERUP_NS => 25_000, T_RESET_NS => 2_000)
            port map (
                clk => clk, reset_n => rstn,
                init_restart => init_restart, init_done => init_done, init_err => init_err,
                init_err_code => open, init_step => open, busy => busy,
                rd_req_tdata => rd_req_tdata, rd_req_tvalid => rd_req_tvalid,
                rd_req_tready => rd_req_tready, rd_req_err => rd_req_err, rd_space => rd_space,
                m_axis_tdata => rd_tdata, m_axis_tvalid => rd_tvalid, m_axis_tready => rd_tready,
                m_axis_tlast => rd_tlast,
                wr_req_tdata => wr_req_tdata, wr_req_tvalid => wr_req_tvalid,
                wr_req_tready => wr_req_tready, wr_req_err => wr_req_err, wr_done => wr_done,
                s_axis_wr_tdata => wr_tdata, s_axis_wr_tvalid => wr_tvalid, s_axis_wr_tready => wr_tready,
                sample_dly_ovr_valid => ovr_valid, sample_dly_ovr => ovr,
                sclk => sclk, cs_n => cs_n, io_o => io_o, io_oe => io_oe, io_i => io,
                mem_reset_n => mem_reset_n);

        pads : for i in 0 to 7 generate
            io(i) <= io_o(i) when io_oe(i) = '1' else 'Z';
        end generate;

        die1 : entity work.qspi_mem_model
            generic map (DEVICE => C.dev, DIE => 1, PRELOAD_SEED => 5, AS_ID => C.as_id,
                         MEM_WRITE_IGNORE => C.mem_ign, T_BOARD => C.t_board,
                         T_PU => 20 us, T_RST => 1500 ns, T_PP => 3 us, T_SE => 5 us)
            port map (sclk => sclk(0), cs_n => cs_n(0), reset_n => mem_reset_n,
                      io => io(3 downto 0), err_count => err1);

        die2_gen : if C.die2 generate
            die2 : entity work.qspi_mem_model
                generic map (DEVICE => C.dev, DIE => 2, PRELOAD_SEED => 9, T_BOARD => C.t_board, T_PU => 20 us)
                port map (sclk => sclk(1), cs_n => cs_n(1), reset_n => mem_reset_n,
                          io => io(7 downto 4), err_count => err2);
        end generate;

        host : process
            variable errors : natural := 0;

            procedure check(cond : boolean; msg : string) is
            begin
                if not cond then
                    report "CHECK FAILED (config " & integer'image(g) & "): " & msg severity error;
                    errors := errors + 1;
                end if;
            end procedure;
        begin
            wait until rstn = '1';
            -- Nothing shown while init and the first round run
            if not C.pass then
                wait until fail = '1' for 3 ms;
                check(fail = '1', "fail expected");
                check(pass = '0' and pass_count = 0, "pass must stay off");
                wait for 200 us;
                check(fail = '1' and pass = '0', "fail must stay latched");
            else
                wait until pass = '1' or fail = '1' for 3 ms;
                check(pass = '1' and fail = '0', "pass expected, got pass=" & std_logic'image(pass)
                      & " fail=" & std_logic'image(fail));
                check(pass_count >= 1, "pass must only come on after a complete round");
                check(init_done = '1', "init_done expected");
                if C.calibrate then
                    check(cal_window = C.window, "cal_window: expected " & to_string(C.window)
                          & ", got " & to_string(cal_window));
                    check(cal_dly = C.dly, "cal_dly: expected " & integer'image(C.dly)
                          & ", got " & integer'image(cal_dly));
                end if;
                wait until pass_count >= 3 or fail = '1' for 2 ms;
                check(pass_count >= 3 and pass = '1' and fail = '0', "should keep passing (count "
                      & integer'image(to_integer(pass_count)) & ")");
                check(err1 + err2 = 0, "model protocol errors: " & integer'image(err1 + err2));
            end if;
            tb_errors(g) <= errors;
            finished(g)  <= true;
            wait;
        end process;

        never_both : process (pass, fail)
        begin
            assert not (pass = '1' and fail = '1')
                report "CHECK FAILED (config " & integer'image(g) & "): pass and fail both on"
                severity failure;
        end process;
    end generate;

    control : process
        variable errors : natural;
    begin
        rstn <= '0';
        wait for 50 ns;
        wait until rising_edge(clk);
        rstn <= '1';
        wait until finished = (0 to NCFG - 1 => true) for 10 ms;
        errors := 0;
        for i in 0 to NCFG - 1 loop
            errors := errors + tb_errors(i);
            if not finished(i) then
                report "CHECK FAILED: configuration " & integer'image(i) & " did not finish" severity error;
                errors := errors + 1;
            end if;
        end loop;
        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;
end architecture sim;
