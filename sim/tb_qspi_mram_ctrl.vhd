-- run_tb models: qspi_model_pkg qspi_mem_model
-- Full-system testbench for qspi_mram_ctrl: init -> write -> 8 x 880 read
--   Three configurations side by side: W25Q128JV; AS308G208 with 1 die; AS308G208 with 2 dies.
--   clk_ctrl 100 MHz, SCLK 50 MHz, 3 ns board delay, preloaded models with short power-up,
--   reset, erase and program times (and the same short times in the DUT).
--   The SAMPLE_DLY generic is 3, which does not fit the board delay: everything runs with
--   sample_dly_ovr = 2, and one read without the override must return wrong data.
--     1. Init after reset must end with init_done (models: no protocol errors, e.g. 9Fh speed).
--     2. Write 8 blocks of 880 host bytes (W25Q: one block per sector). While the first write is
--        running, a read of an unwritten area is requested: the arbiter must let it wait until
--        the write is done (otherwise the W25Q would see a read while BUSY).
--        Then a write is requested while a read is still delivering data: the read must
--        arrive complete (the owner may only change once qspi_xact is idle).
--     3. Read the 8 blocks back to back and report the time (8 x 880 host bytes, ~145 us).
--     4. One read with the override off (SAMPLE_DLY = 3): must return wrong data.
--     5. init_restart: requests during init give rd_req_err / wr_req_err; after init_done a read
--        works again.
--   All read data and tlast are checked against the written data / erased flash / preload.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;
use work.qspi_model_pkg.all;

entity tb_qspi_mram_ctrl is
end entity tb_qspi_mram_ctrl;

architecture sim of tb_qspi_mram_ctrl is
    constant CLK_PERIOD : time := 10 ns;
    constant NCFG       : positive := 3;
    constant SEED1      : positive := 5;
    constant SEED2      : positive := 9;
    constant NBLK       : positive := 8;
    constant BLK_LEN    : positive := 880;
    constant BLK_STRIDE : positive := 16#4000#;        -- Host bytes = 2 W25Q sectors per block slot
    constant FREE_AREA  : positive := 16#100000#;       -- Never written

    type nat_arr_t is array (0 to NCFG - 1) of natural;
    signal tb_errors : nat_arr_t := (others => 0);
    signal finished  : boolean_vector(0 to NCFG - 1) := (others => false);

    signal clk  : std_logic := '0';
    signal rstn : std_logic := '0';
    signal done : boolean := false;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done;

    cfg : for g in 0 to NCFG - 1 generate
        constant DEV  : device_t := device_t'val(boolean'pos(g > 0));
        constant DIE2 : boolean  := g = 2;
        constant W25  : boolean  := DEV = DEV_W25Q128JV;

        signal init_restart : std_logic := '0';
        signal init_done, init_err, busy : std_logic;
        signal init_code    : std_logic_vector(1 downto 0);
        signal rd_req_tdata, wr_req_tdata : std_logic_vector(47 downto 0) := (others => '0');
        signal rd_req_tvalid, wr_req_tvalid : std_logic := '0';
        signal rd_req_tready, wr_req_tready, rd_req_err, wr_req_err, wr_done : std_logic;
        signal m_tdata      : std_logic_vector(7 downto 0);
        signal m_tvalid, m_tlast : std_logic;
        signal wd_tdata     : std_logic_vector(7 downto 0) := (others => '0');
        signal wd_tvalid    : std_logic := '0';
        signal wd_tready    : std_logic;
        signal ovr_valid    : std_logic := '1';
        signal sclk, cs_n   : std_logic_vector(1 downto 0);
        signal io_o, io_oe  : std_logic_vector(7 downto 0);
        signal io           : std_logic_vector(7 downto 0);
        signal mem_reset_n  : std_logic;
        signal err1, err2   : natural := 0;
        signal rd_errs, wr_errs : natural := 0;

        constant LOG_MAX : positive := 16384;
        type log_t is array (0 to LOG_MAX - 1) of std_logic_vector(7 downto 0);
        signal rx_log   : log_t;
        signal rx_lastv : std_logic_vector(0 to LOG_MAX - 1);
        signal rx_n     : natural := 0;
        signal t_rx     : time := 0 ns;          -- Time of the last received byte
    begin
        dut : entity work.qspi_mram_ctrl
            generic map (DEVICE => DEV, DIE2_PRESENT => DIE2, CLK_CTRL_HZ => 100_000_000,
                         SCLK_DIV => 1, SAMPLE_DLY => 3, SPACE_W => 16,
                         T_POWERUP_NS => 25_000, T_RESET_NS => 2_000)
            port map (
                clk => clk, reset_n => rstn,
                init_restart => init_restart, init_done => init_done, init_err => init_err,
                init_err_code => init_code, init_step => open, busy => busy,
                rd_req_tdata => rd_req_tdata, rd_req_tvalid => rd_req_tvalid,
                rd_req_tready => rd_req_tready, rd_req_err => rd_req_err,
                rd_space => to_unsigned(65535, 16),
                m_axis_tdata => m_tdata, m_axis_tvalid => m_tvalid, m_axis_tready => '1',
                m_axis_tlast => m_tlast,
                wr_req_tdata => wr_req_tdata, wr_req_tvalid => wr_req_tvalid,
                wr_req_tready => wr_req_tready, wr_req_err => wr_req_err, wr_done => wr_done,
                s_axis_wr_tdata => wd_tdata, s_axis_wr_tvalid => wd_tvalid, s_axis_wr_tready => wd_tready,
                sample_dly_ovr_valid => ovr_valid, sample_dly_ovr => 2,
                sclk => sclk, cs_n => cs_n, io_o => io_o, io_oe => io_oe, io_i => io,
                mem_reset_n => mem_reset_n);

        pads : for i in 0 to 7 generate
            io(i) <= io_o(i) when io_oe(i) = '1' else 'Z';
        end generate;

        die1 : entity work.qspi_mem_model
            generic map (DEVICE => DEV, DIE => 1, PRELOAD_SEED => SEED1, T_BOARD => 3 ns,
                         T_PU => 20 us, T_RST => 1500 ns, T_PP => 3 us, T_SE => 5 us)
            port map (sclk => sclk(0), cs_n => cs_n(0), reset_n => mem_reset_n,
                      io => io(3 downto 0), err_count => err1);

        die2_gen : if DIE2 generate
            die2 : entity work.qspi_mem_model
                generic map (DEVICE => DEV, DIE => 2, PRELOAD_SEED => SEED2, T_BOARD => 3 ns, T_PU => 20 us)
                port map (sclk => sclk(1), cs_n => cs_n(1), reset_n => mem_reset_n,
                          io => io(7 downto 4), err_count => err2);
        end generate;

        capture : process (clk)
        begin
            if rising_edge(clk) then
                if m_tvalid = '1' then
                    rx_log(rx_n mod LOG_MAX)   <= m_tdata;
                    rx_lastv(rx_n mod LOG_MAX) <= m_tlast;
                    rx_n <= rx_n + 1;
                    t_rx <= now;
                end if;
                if rd_req_err = '1' then
                    rd_errs <= rd_errs + 1;
                end if;
                if wr_req_err = '1' then
                    wr_errs <= wr_errs + 1;
                end if;
            end if;
        end process;

        host : process
            variable errors : natural := 0;
            variable base   : natural;
            variable b0, b1 : natural;
            variable t0     : time;
            variable bad    : natural;

            procedure check(cond : boolean; msg : string) is
            begin
                if not cond then
                    report "CHECK FAILED (config " & integer'image(g) & "): " & msg severity error;
                    errors := errors + 1;
                end if;
            end procedure;

            function blk_addr(k : natural) return natural is
            begin
                return k * BLK_STRIDE;
            end function;

            -- Written host byte i of block k
            function wbyte(k, i : natural) return std_logic_vector is
            begin
                return std_logic_vector(to_unsigned((i * 37 + k * 59 + 3) mod 256, 8));
            end function;

            -- Expected read value of host byte a
            function expected(a : natural) return std_logic_vector is
                variable d      : natural := a / 2;
                variable k      : natural := a / BLK_STRIDE;
                variable d1, d2 : std_logic_vector(7 downto 0);
                variable b      : std_logic_vector(7 downto 0);
            begin
                if k < NBLK and a - blk_addr(k) < BLK_LEN then
                    b := wbyte(k, a - blk_addr(k));
                    if not DIE2 then
                        b(7 downto 4) := "0000";
                    end if;
                    return b;
                end if;
                if W25 and k < NBLK and (a - blk_addr(k)) < 2 * 4096 then
                    d1 := x"FF";                              -- Rest of the erased sector
                else
                    d1 := pattern_byte(d, SEED1);
                end if;
                d2 := pattern_byte(d, SEED2);
                if not DIE2 then
                    d2 := x"00";
                end if;
                if a mod 2 = 0 then
                    return d2(7 downto 4) & d1(7 downto 4);
                end if;
                return d2(3 downto 0) & d1(3 downto 0);
            end function;

            procedure read_req(addr, len : natural) is
            begin
                rd_req_tdata  <= std_logic_vector(to_unsigned(len, 16)) & std_logic_vector(to_unsigned(addr, 32));
                rd_req_tvalid <= '1';
                wait until rising_edge(clk) and rd_req_tready = '1';
                rd_req_tvalid <= '0';
            end procedure;

            -- Wait for len bytes from log position from, return the number of wrong ones
            procedure verify(from, addr, len : natural; msg : string; nbad : out natural;
                             report_errors : boolean := true) is
                variable n : natural := 0;
                variable got : std_logic_vector(7 downto 0);
            begin
                if rx_n < from + len then
                    wait until rx_n >= from + len for 2 ms;
                end if;
                check(rx_n >= from + len, msg & ": only " & integer'image(rx_n - from) & " bytes");
                for i in 0 to len - 1 loop
                    got := rx_log((from + i) mod LOG_MAX);
                    if got /= expected(addr + i) or (rx_lastv((from + i) mod LOG_MAX) = '1') /= (i = len - 1) then
                        if report_errors and n < 5 then
                            report "CHECK FAILED (config " & integer'image(g) & "): " & msg & ": byte "
                                   & integer'image(i) & " expected " & to_hstring(expected(addr + i))
                                   & ", got " & to_hstring(got) severity error;
                        end if;
                        n := n + 1;
                    end if;
                end loop;
                if report_errors then
                    errors := errors + n;
                end if;
                nbad := n;
            end procedure;

            procedure write_block(k : natural) is
            begin
                wr_req_tdata  <= std_logic_vector(to_unsigned(BLK_LEN, 16)) & std_logic_vector(to_unsigned(blk_addr(k), 32));
                wr_req_tvalid <= '1';
                wait until rising_edge(clk) and wr_req_tready = '1';
                wr_req_tvalid <= '0';
                for i in 0 to BLK_LEN - 1 loop
                    wd_tdata  <= wbyte(k, i);
                    wd_tvalid <= '1';
                    wait until rising_edge(clk) and wd_tready = '1';
                end loop;
                wd_tvalid <= '0';
                if wr_done /= '1' then
                    wait until wr_done = '1' for 5 ms;
                end if;
                check(wr_done = '1', "no wr_done for block " & integer'image(k));
            end procedure;
        begin
            -- 1. Init
            wait until rstn = '1';
            wait until init_done = '1' or init_err = '1' for 1 ms;
            check(init_done = '1', "init failed: err=" & std_logic'image(init_err) & " code="
                  & to_string(init_code));

            -- 2. Writes, with a read requested during the first one
            wr_req_tdata  <= std_logic_vector(to_unsigned(BLK_LEN, 16)) & std_logic_vector(to_unsigned(blk_addr(0), 32));
            wr_req_tvalid <= '1';
            wait until rising_edge(clk) and wr_req_tready = '1';
            wr_req_tvalid <= '0';
            b0 := rx_n;
            read_req(FREE_AREA, 64);                           -- Must wait for the write
            for i in 0 to BLK_LEN - 1 loop
                wd_tdata  <= wbyte(0, i);
                wd_tvalid <= '1';
                wait until rising_edge(clk) and wd_tready = '1';
            end loop;
            wd_tvalid <= '0';
            wait until wr_done = '1' for 5 ms;
            check(rx_n = b0, "read data arrived while the write was running");
            verify(b0, FREE_AREA, 64, "read during write", bad);
            for k in 1 to NBLK - 1 loop
                write_block(k);
            end loop;

            -- Write requested while a read is still delivering data: the read must complete
            -- (the owner may only change once qspi_xact is idle); rewrites block 7 unchanged
            wait until rising_edge(clk) and busy = '0';
            base := rx_n;
            read_req(blk_addr(0), BLK_LEN);
            wait until rx_n > base + 100;
            write_block(NBLK - 1);
            verify(base, blk_addr(0), BLK_LEN, "read overlapping a write request", bad);

            -- 3. 8 x 880 read
            wait until rising_edge(clk) and busy = '0';
            base := rx_n;
            t0 := now;
            for k in 0 to NBLK - 1 loop
                read_req(blk_addr(k), BLK_LEN);
            end loop;
            for k in 0 to NBLK - 1 loop
                verify(base + k * BLK_LEN, blk_addr(k), BLK_LEN, "block " & integer'image(k), bad);
            end loop;
            report "Config " & integer'image(g) & " (" & device_t'image(DEV) & ", "
                   & integer'image(1 + boolean'pos(DIE2)) & " die(s)): 8 x 880 host bytes read in "
                   & time'image(t_rx - t0);
            check(t_rx - t0 <= 150 us, "8 x 880 read took " & time'image(t_rx - t0));
            base := rx_n;
            read_req(blk_addr(1) - 32, 64);                    -- Across the start of block 1
            verify(base, blk_addr(1) - 32, 64, "block 1 start", bad);

            -- 4. Without the sample delay override (SAMPLE_DLY = 3): wrong data
            wait until rising_edge(clk) and busy = '0';
            ovr_valid <= '0';
            base := rx_n;
            read_req(blk_addr(2), 64);
            verify(base, blk_addr(2), 64, "SAMPLE_DLY 3", bad, false);
            check(bad > 0, "SAMPLE_DLY 3 should give wrong data with this board delay");
            wait until rising_edge(clk) and busy = '0';
            ovr_valid <= '1';

            -- 5. init_restart
            init_restart <= '1';
            wait until rising_edge(clk);
            init_restart <= '0';
            wait until rising_edge(clk);
            check(init_done = '0', "init_done must drop on init_restart");
            read_req(blk_addr(3), 16);
            wr_req_tdata  <= std_logic_vector(to_unsigned(16, 16)) & std_logic_vector(to_unsigned(blk_addr(3), 32));
            wr_req_tvalid <= '1';
            wait until rising_edge(clk) and wr_req_tready = '1';
            wr_req_tvalid <= '0';
            wait until init_done = '1' or init_err = '1' for 1 ms;
            check(init_done = '1', "init after restart failed");
            check(rd_errs = 1 and wr_errs = 1, "requests during init: rd_req_err "
                  & integer'image(rd_errs) & ", wr_req_err " & integer'image(wr_errs));
            base := rx_n;
            read_req(blk_addr(3), 64);
            verify(base, blk_addr(3), 64, "read after restart", bad);

            wait until rising_edge(clk) and busy = '0';
            wait for 1 us;
            check(err1 + err2 = 0, "model protocol errors: " & integer'image(err1 + err2));
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
        wait until finished = (0 to NCFG - 1 => true) for 20 ms;
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
