-- run_tb models: qspi_model_pkg qspi_mem_model
-- Self-checking testbench for qspi_init (with qspi_xact and qspi_phy) against the device models
--   Eight configurations run side by side, each with its own DUT and models (short power-up and
--   reset times in both the DUT and the models):
--     0  W25Q128JV                                        -> init_done
--     1  W25Q128JV with QE = 0                            -> ERR_CFG
--     2  W25Q128JV with ID EF 70 18                       -> ERR_ID
--     3  AS308G208, 1 die, CR2 = 10 and SR protected at reset -> init_done (init writes fix both)
--     4  AS308G208, 2 dies, die 2 CR2 = 12 at reset       -> init_done
--     5  AS308G208, 2 dies, die 2 ignores register writes, CR2 = 10 -> ERR_CFG
--     6  AS308G208, 2 dies, die 2 ID with density 1 Gb    -> ERR_ID
--     7  AS308G208, 1 die, ignores register writes, SR protected -> ERR_CFG
--   Each configuration is run twice: after reset and again after init_restart. The models must
--   report no protocol errors (power-up/reset timing, CS# high times, SCLK limits such as 9Fh at
--   <= 40 MHz on the AS), RESET# must stay high for the W25Q and must have been pulsed for the AS.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;

entity tb_qspi_init is
end entity tb_qspi_init;

architecture sim of tb_qspi_init is
    constant CLK_PERIOD : time := 10 ns;

    type result_t is (R_DONE, R_ERR_ID, R_ERR_CFG);
    type cfg_t is record
        dev        : device_t;
        die2       : boolean;
        qe         : std_logic;                       -- W25Q QE_INIT
        w25_id     : std_logic_vector(23 downto 0);
        id2        : std_logic_vector(31 downto 0);   -- AS die 2 ID
        sr1, sr2   : std_logic_vector(7 downto 0);    -- AS SR at reset, die 1 / die 2
        cr2_1      : natural;                         -- AS CR2 at reset, die 1 / die 2
        cr2_2      : natural;
        ign1, ign2 : boolean;                         -- Ignore register writes, die 1 / die 2
        result     : result_t;
    end record;
    type cfg_arr_t is array (natural range <>) of cfg_t;
    constant CFGS : cfg_arr_t := (
        (DEV_W25Q128JV, false, '1', x"EF4018", x"E6212C01", x"00", x"00", 8, 8,  false, false, R_DONE),
        (DEV_W25Q128JV, false, '0', x"EF4018", x"E6212C01", x"00", x"00", 8, 8,  false, false, R_ERR_CFG),
        (DEV_W25Q128JV, false, '1', x"EF7018", x"E6212C01", x"00", x"00", 8, 8,  false, false, R_ERR_ID),
        (DEV_AS308G208, false, '1', x"EF4018", x"E6212C01", x"1C", x"00", 10, 8, false, false, R_DONE),
        (DEV_AS308G208, true,  '1', x"EF4018", x"E6212A01", x"00", x"00", 8, 12, false, false, R_DONE),
        (DEV_AS308G208, true,  '1', x"EF4018", x"E6212C01", x"00", x"00", 8, 10, false, true,  R_ERR_CFG),
        (DEV_AS308G208, true,  '1', x"EF4018", x"E6212801", x"00", x"00", 8, 8,  false, false, R_ERR_ID),
        (DEV_AS308G208, false, '1', x"EF4018", x"E6212C01", x"04", x"00", 8, 8,  true,  false, R_ERR_CFG)
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

        signal cmd_valid, cmd_ready, cmd_mode_en, cmd_write : std_logic;
        signal cmd_op, cmd_mode : std_logic_vector(7 downto 0);
        signal cmd_lanes   : cmd_lanes_t;
        signal cmd_addr    : std_logic_vector(31 downto 0);
        signal cmd_ab      : natural range 0 to 4;
        signal cmd_lat     : natural range 0 to 15;
        signal cmd_dir     : dir_t;
        signal cmd_len     : unsigned(15 downto 0);
        signal cmd_div     : natural range 1 to SCLK_DIV_MAX;
        signal tx_tdata, rx_tdata : std_logic_vector(7 downto 0);
        signal tx_tvalid, tx_tready, rx_tvalid, rx_tready, rx_tlast : std_logic;
        signal xact_busy   : std_logic;
        signal init_restart : std_logic := '0';
        signal init_done, init_err : std_logic;
        signal err_code    : std_logic_vector(1 downto 0);
        signal mem_reset_n : std_logic;
        signal sclk, cs_n  : std_logic_vector(1 downto 0);
        signal io_o, io_oe : std_logic_vector(7 downto 0);
        signal io          : std_logic_vector(7 downto 0);
        signal err1, err2  : natural := 0;
        signal reset_pulses : natural := 0;
    begin
        init : entity work.qspi_init
            generic map (DEVICE => C.dev, DIE2_PRESENT => C.die2, CLK_HZ => 100_000_000,
                         SCLK_DIV => 1, T_POWERUP_NS => 25_000, T_RESET_NS => 2_000)
            port map (
                clk => clk, reset_n => rstn, init_restart => init_restart,
                init_done => init_done, init_err => init_err, err_code => err_code, step => open,
                mem_reset_n => mem_reset_n,
                cmd_valid => cmd_valid, cmd_ready => cmd_ready, cmd_op => cmd_op,
                cmd_lanes => cmd_lanes, cmd_addr => cmd_addr, cmd_addr_bytes => cmd_ab,
                cmd_mode_en => cmd_mode_en, cmd_mode => cmd_mode, cmd_latency => cmd_lat,
                cmd_dir => cmd_dir, cmd_len => cmd_len, cmd_sclk_div => cmd_div,
                cmd_write => cmd_write, xact_busy => xact_busy,
                tx_tdata => tx_tdata, tx_tvalid => tx_tvalid, tx_tready => tx_tready,
                rx_tdata => rx_tdata, rx_tvalid => rx_tvalid, rx_tready => rx_tready,
                rx_tlast => rx_tlast);

        xact : entity work.qspi_xact
            generic map (DEVICE => C.dev, DIE2_PRESENT => C.die2, CLK_HZ => 100_000_000)
            port map (
                clk => clk, reset_n => rstn,
                cmd_valid => cmd_valid, cmd_ready => cmd_ready, cmd_op => cmd_op,
                cmd_lanes => cmd_lanes, cmd_addr => cmd_addr, cmd_addr_bytes => cmd_ab,
                cmd_mode_en => cmd_mode_en, cmd_mode => cmd_mode, cmd_latency => cmd_lat,
                cmd_dir => cmd_dir, cmd_len => cmd_len, cmd_sclk_div => cmd_div,
                cmd_write => cmd_write,
                s_axis_tdata => tx_tdata, s_axis_tvalid => tx_tvalid, s_axis_tready => tx_tready,
                m_axis_tdata => rx_tdata, m_axis_tvalid => rx_tvalid, m_axis_tready => rx_tready,
                m_axis_tlast => rx_tlast, rx_overflow => open,
                sample_dly => 2, busy => xact_busy,
                sclk => sclk, cs_n => cs_n, io_o => io_o, io_oe => io_oe, io_i => io);

        pads : for i in 0 to 7 generate
            io(i) <= io_o(i) when io_oe(i) = '1' else 'Z';
        end generate;

        die1 : entity work.qspi_mem_model
            generic map (DEVICE => C.dev, DIE => 1, PRELOAD_SEED => 3, QE_INIT => C.qe,
                         W25_ID => C.w25_id, AS_SR_INIT => C.sr1, AS_CR2_INIT => C.cr2_1,
                         REG_WRITE_IGNORE => C.ign1, T_BOARD => 3 ns, T_PU => 20 us,
                         T_RST => 1500 ns)
            port map (sclk => sclk(0), cs_n => cs_n(0), reset_n => mem_reset_n,
                      io => io(3 downto 0), err_count => err1);

        die2_gen : if C.die2 generate
            die2 : entity work.qspi_mem_model
                generic map (DEVICE => C.dev, DIE => 2, PRELOAD_SEED => 4, AS_ID => C.id2,
                             AS_SR_INIT => C.sr2, AS_CR2_INIT => C.cr2_2,
                             REG_WRITE_IGNORE => C.ign2, T_BOARD => 3 ns, T_PU => 20 us)
                port map (sclk => sclk(1), cs_n => cs_n(1), reset_n => mem_reset_n,
                          io => io(7 downto 4), err_count => err2);
        end generate;

        count_resets : process (mem_reset_n)
        begin
            if falling_edge(mem_reset_n) then
                reset_pulses <= reset_pulses + 1;
            end if;
        end process;

        host : process
            variable errors : natural := 0;

            procedure check(cond : boolean; msg : string) is
            begin
                if not cond then
                    report "CHECK FAILED (config " & integer'image(g) & "): " & msg severity error;
                    errors := errors + 1;
                end if;
            end procedure;

            procedure check_result(run : string) is
            begin
                if init_done = '0' and init_err = '0' then
                    wait until init_done = '1' or init_err = '1' for 1 ms;
                end if;
                case C.result is
                    when R_DONE =>
                        check(init_done = '1' and init_err = '0', run & ": init_done expected, got done="
                              & std_logic'image(init_done) & " err=" & std_logic'image(init_err)
                              & " code=" & to_string(err_code));
                    when R_ERR_ID =>
                        check(init_err = '1' and err_code = "01", run & ": ERR_ID expected, got done="
                              & std_logic'image(init_done) & " err=" & std_logic'image(init_err)
                              & " code=" & to_string(err_code));
                    when R_ERR_CFG =>
                        check(init_err = '1' and err_code = "10", run & ": ERR_CFG expected, got done="
                              & std_logic'image(init_done) & " err=" & std_logic'image(init_err)
                              & " code=" & to_string(err_code));
                end case;
            end procedure;
        begin
            wait until rstn = '1';
            wait until rising_edge(clk);
            check(init_done = '0' and init_err = '0', "busy right after reset");
            check_result("after reset");

            -- Run again
            wait for 1 us;
            init_restart <= '1';
            wait until rising_edge(clk);
            init_restart <= '0';
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            check(init_done = '0' and init_err = '0', "restart clears done/err");
            check_result("after restart");

            wait until rising_edge(clk) and xact_busy = '0';
            wait for 1 us;
            check(err1 + err2 = 0, "model protocol errors: " & integer'image(err1 + err2));
            if C.dev = DEV_W25Q128JV then
                check(reset_pulses = 0, "RESET# must stay high for the W25Q");
            else
                check(reset_pulses = 2, "RESET# pulses: expected 2, got " & integer'image(reset_pulses));
            end if;
            tb_errors(g) <= errors;
            finished(g)  <= true;
            wait;
        end process;
    end generate;

    control : process
        variable errors : natural;
    begin
        rstn <= '0';
        wait for 50 ns;
        wait until rising_edge(clk);
        rstn <= '1';
        wait until finished = (0 to NCFG - 1 => true) for 5 ms;
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
