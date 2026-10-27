-- run_tb models: qspi_model_pkg qspi_mem_model
-- Self-checking testbench for qspi_write: write patterns, read them back with qspi_read_ctrl
--   Three configurations side by side: W25Q128JV; AS308G208 with 1 die; AS308G208 with 2 dies.
--   qspi_write and qspi_read_ctrl share one qspi_xact; the testbench switches the command port
--   and the streams between them (owner), as qspi_mram_ctrl does. The models are
--   preloaded with a pattern. clk_ctrl 200 MHz, SCLK 50 MHz, sample delay 4, 3 ns board delay;
--   short W25Q busy times (erase 5 us, page program 3 us).
--     1. Requests before init_done and bad requests (odd address/length, length 0, past the end)
--        give req_err and write nothing.
--     2. Write 880 host bytes, read them back. W25Q: the block crosses a sector and three pages
--        (die bytes 0F80h..1137h); the rest of both erased sectors must read FFh.
--     3. A second, overlapping write of 64 host bytes; read back the whole area.
--     4. AS: the bytes around the written block must still hold the preload pattern.
--   With one die the upper nibble of each written host byte is ignored and reads back as 0.
--   The models must report no protocol errors (WEL, BUSY, CS# high times, byte boundaries).
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;
use work.qspi_model_pkg.all;

entity tb_qspi_write is
end entity tb_qspi_write;

architecture sim of tb_qspi_write is
    constant CLK_PERIOD : time := 5 ns;      -- clk_ctrl 200 MHz
    constant NCFG       : positive := 3;
    constant SEED1      : positive := 5;
    constant SEED2      : positive := 9;

    type nat_arr_t is array (0 to NCFG - 1) of natural;
    signal tb_errors : nat_arr_t := (others => 0);
    signal finished  : boolean_vector(0 to NCFG - 1) := (others => false);

    signal clk  : std_logic := '0';
    signal rstn : std_logic := '0';
    signal done : boolean := false;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done;

    cfg : for g in 0 to NCFG - 1 generate
        constant DEV   : device_t := device_t'val(boolean'pos(g > 0));
        constant DIE2  : boolean  := g = 2;
        constant W25   : boolean  := DEV = DEV_W25Q128JV;
        constant HSIZE : natural  := 2 * dev_params(DEV).size_bytes;

        -- Expected die content: written bytes override the preload (or FFh after an erase)
        constant SHADOW : natural := 16#3000#;                 -- Shadowed die bytes 0 .. SHADOW-1
        type shadow_t is array (0 to SHADOW - 1) of std_logic_vector(7 downto 0);

        signal owner_wr    : boolean := true;                  -- Command port owner
        signal own_w       : std_logic;
        signal init_done   : std_logic := '0';

        signal wreq_tdata, rreq_tdata : std_logic_vector(47 downto 0) := (others => '0');
        signal wreq_tvalid, rreq_tvalid : std_logic := '0';
        signal wreq_tready, rreq_tready : std_logic;
        signal wdat_tdata  : std_logic_vector(7 downto 0) := (others => '0');
        signal wdat_tvalid : std_logic := '0';
        signal wdat_tready : std_logic;
        signal w_err, r_err, w_done, w_busy, r_busy : std_logic;

        -- Command ports: w_* from qspi_write, r_* from qspi_read_ctrl, x_* to qspi_xact
        signal w_cmd_valid, r_cmd_valid, x_cmd_valid, x_cmd_ready : std_logic;
        signal w_cmd_op, r_cmd_op, x_cmd_op, w_cmd_mode, r_cmd_mode, x_cmd_mode : std_logic_vector(7 downto 0);
        signal w_cmd_lanes, r_cmd_lanes, x_cmd_lanes : cmd_lanes_t;
        signal w_cmd_addr, r_cmd_addr, x_cmd_addr : std_logic_vector(31 downto 0);
        signal w_cmd_ab, r_cmd_ab, x_cmd_ab : natural range 0 to 4;
        signal w_cmd_mode_en, r_cmd_mode_en, x_cmd_mode_en : std_logic;
        signal w_cmd_lat, r_cmd_lat, x_cmd_lat : natural range 0 to 15;
        signal w_cmd_dir, r_cmd_dir, x_cmd_dir : dir_t;
        signal w_cmd_len, r_cmd_len, x_cmd_len : unsigned(15 downto 0);
        signal w_cmd_div, r_cmd_div, x_cmd_div : natural range 1 to SCLK_DIV_MAX;
        signal w_cmd_write, r_cmd_write, x_cmd_write : std_logic;
        signal x_tx_tdata  : std_logic_vector(7 downto 0);
        signal x_tx_tvalid, x_tx_tready : std_logic;
        signal x_rx_tdata  : std_logic_vector(7 downto 0);
        signal x_rx_tvalid, x_rx_tready, x_rx_tlast, w_rx_tready, r_rx_tready : std_logic;
        signal w_rx_tvalid, r_rx_tvalid : std_logic;
        signal xact_busy   : std_logic;

        signal m_tdata     : std_logic_vector(7 downto 0);
        signal m_tvalid, m_tlast : std_logic;

        signal sclk, cs_n  : std_logic_vector(1 downto 0);
        signal io_o, io_oe : std_logic_vector(7 downto 0);
        signal io          : std_logic_vector(7 downto 0);
        signal err1, err2  : natural := 0;
        signal err_pulses  : natural := 0;

        -- Read-back capture
        constant LOG_MAX : positive := 32768;
        type log_t is array (0 to LOG_MAX - 1) of std_logic_vector(7 downto 0);
        signal rx_log    : log_t;
        signal rx_lastv  : std_logic_vector(0 to LOG_MAX - 1);
        signal rx_n      : natural := 0;
    begin
        wr : entity work.qspi_write
            generic map (DEVICE => DEV, DIE2_PRESENT => DIE2, SCLK_DIV => 2)
            port map (
                clk => clk, reset_n => rstn, init_done => init_done,
                s_axis_req_tdata => wreq_tdata, s_axis_req_tvalid => wreq_tvalid,
                s_axis_req_tready => wreq_tready,
                s_axis_data_tdata => wdat_tdata, s_axis_data_tvalid => wdat_tvalid,
                s_axis_data_tready => wdat_tready,
                req_err => w_err, wr_done => w_done, busy => w_busy,
                cmd_valid => w_cmd_valid, cmd_ready => x_cmd_ready and own_w,
                cmd_op => w_cmd_op, cmd_lanes => w_cmd_lanes, cmd_addr => w_cmd_addr,
                cmd_addr_bytes => w_cmd_ab, cmd_mode_en => w_cmd_mode_en, cmd_mode => w_cmd_mode,
                cmd_latency => w_cmd_lat, cmd_dir => w_cmd_dir, cmd_len => w_cmd_len,
                cmd_sclk_div => w_cmd_div, cmd_write => w_cmd_write, xact_busy => xact_busy,
                tx_tdata => x_tx_tdata, tx_tvalid => x_tx_tvalid, tx_tready => x_tx_tready,
                rx_tdata => x_rx_tdata, rx_tvalid => w_rx_tvalid, rx_tready => w_rx_tready,
                rx_tlast => x_rx_tlast);

        rd : entity work.qspi_read_ctrl
            generic map (DEVICE => DEV, SCLK_DIV => 2, SPACE_W => 16)
            port map (
                clk => clk, reset_n => rstn, init_done => init_done,
                s_axis_req_tdata => rreq_tdata, s_axis_req_tvalid => rreq_tvalid,
                s_axis_req_tready => rreq_tready, req_err => r_err,
                rx_space => to_unsigned(65535, 16), busy => r_busy,
                cmd_valid => r_cmd_valid, cmd_ready => x_cmd_ready and not own_w,
                cmd_op => r_cmd_op, cmd_lanes => r_cmd_lanes, cmd_addr => r_cmd_addr,
                cmd_addr_bytes => r_cmd_ab, cmd_mode_en => r_cmd_mode_en, cmd_mode => r_cmd_mode,
                cmd_latency => r_cmd_lat, cmd_dir => r_cmd_dir, cmd_len => r_cmd_len,
                cmd_sclk_div => r_cmd_div, cmd_write => r_cmd_write,
                rx_tdata => x_rx_tdata, rx_tvalid => r_rx_tvalid, rx_tready => r_rx_tready,
                rx_tlast => x_rx_tlast,
                m_axis_tdata => m_tdata, m_axis_tvalid => m_tvalid, m_axis_tready => '1',
                m_axis_tlast => m_tlast);

        -- Command port and stream switch (testbench stand-in for qspi_mram_ctrl)
        own_w         <= '1' when owner_wr else '0';
        x_cmd_valid   <= w_cmd_valid   when owner_wr else r_cmd_valid;
        x_cmd_op      <= w_cmd_op      when owner_wr else r_cmd_op;
        x_cmd_lanes   <= w_cmd_lanes   when owner_wr else r_cmd_lanes;
        x_cmd_addr    <= w_cmd_addr    when owner_wr else r_cmd_addr;
        x_cmd_ab      <= w_cmd_ab      when owner_wr else r_cmd_ab;
        x_cmd_mode_en <= w_cmd_mode_en when owner_wr else r_cmd_mode_en;
        x_cmd_mode    <= w_cmd_mode    when owner_wr else r_cmd_mode;
        x_cmd_lat     <= w_cmd_lat     when owner_wr else r_cmd_lat;
        x_cmd_dir     <= w_cmd_dir     when owner_wr else r_cmd_dir;
        x_cmd_len     <= w_cmd_len     when owner_wr else r_cmd_len;
        x_cmd_div     <= w_cmd_div     when owner_wr else r_cmd_div;
        x_cmd_write   <= w_cmd_write   when owner_wr else r_cmd_write;
        w_rx_tvalid   <= x_rx_tvalid and own_w;
        r_rx_tvalid   <= x_rx_tvalid and not own_w;
        x_rx_tready   <= w_rx_tready   when owner_wr else r_rx_tready;

        xact : entity work.qspi_xact
            generic map (DEVICE => DEV, DIE2_PRESENT => DIE2, CLK_HZ => 200_000_000)
            port map (
                clk => clk, reset_n => rstn,
                cmd_valid => x_cmd_valid, cmd_ready => x_cmd_ready, cmd_op => x_cmd_op,
                cmd_lanes => x_cmd_lanes, cmd_addr => x_cmd_addr, cmd_addr_bytes => x_cmd_ab,
                cmd_mode_en => x_cmd_mode_en, cmd_mode => x_cmd_mode, cmd_latency => x_cmd_lat,
                cmd_dir => x_cmd_dir, cmd_len => x_cmd_len, cmd_sclk_div => x_cmd_div,
                cmd_write => x_cmd_write,
                s_axis_tdata => x_tx_tdata, s_axis_tvalid => x_tx_tvalid, s_axis_tready => x_tx_tready,
                m_axis_tdata => x_rx_tdata, m_axis_tvalid => x_rx_tvalid, m_axis_tready => x_rx_tready,
                m_axis_tlast => x_rx_tlast, rx_overflow => open,
                sample_dly => 4, busy => xact_busy,
                sclk => sclk, cs_n => cs_n, io_o => io_o, io_oe => io_oe, io_i => io);

        pads : for i in 0 to 7 generate
            io(i) <= io_o(i) when io_oe(i) = '1' else 'Z';
        end generate;

        die1 : entity work.qspi_mem_model
            generic map (DEVICE => DEV, DIE => 1, PRELOAD_SEED => SEED1, T_BOARD => 3 ns,
                         T_PU => 2 us, T_PP => 3 us, T_SE => 5 us)
            port map (sclk => sclk(0), cs_n => cs_n(0), io => io(3 downto 0), err_count => err1);

        die2_gen : if DIE2 generate
            die2 : entity work.qspi_mem_model
                generic map (DEVICE => DEV, DIE => 2, PRELOAD_SEED => SEED2, T_BOARD => 3 ns, T_PU => 2 us)
                port map (sclk => sclk(1), cs_n => cs_n(1), io => io(7 downto 4), err_count => err2);
        end generate;

        capture : process (clk)
        begin
            if rising_edge(clk) then
                if m_tvalid = '1' then
                    rx_log(rx_n)   <= m_tdata;
                    rx_lastv(rx_n) <= m_tlast;
                    rx_n <= rx_n + 1;
                end if;
                if w_err = '1' or r_err = '1' then
                    err_pulses <= err_pulses + 1;
                end if;
            end if;
        end process;

        host : process
            variable errors : natural := 0;
            variable sh1, sh2 : shadow_t;                       -- Expected die 1 / die 2 bytes
            variable t0     : time;

            procedure check(cond : boolean; msg : string) is
            begin
                if not cond then
                    report "CHECK FAILED (config " & integer'image(g) & "): " & msg severity error;
                    errors := errors + 1;
                end if;
            end procedure;

            -- Host byte i of a write: distinct nibbles for both dies
            function wbyte(i, seed : natural) return std_logic_vector is
            begin
                return std_logic_vector(to_unsigned((i * 37 + seed * 11 + 3) mod 256, 8));
            end function;

            procedure wait_idle is
            begin
                wait until rising_edge(clk);
                wait until rising_edge(clk) and w_busy = '0' and r_busy = '0' and xact_busy = '0' for 5 ms;
                check(w_busy = '0' and r_busy = '0' and xact_busy = '0', "did not become idle");
            end procedure;

            -- Write len host bytes at host address addr (data wbyte(i, seed)) and update the shadow
            procedure write(addr, len, seed : natural; expect_ok : boolean := true) is
                variable d, s, e : natural;
                variable b       : std_logic_vector(7 downto 0);
            begin
                wait_idle;
                owner_wr   <= true;
                wreq_tdata <= std_logic_vector(to_unsigned(len, 16)) & std_logic_vector(to_unsigned(addr, 32));
                wreq_tvalid <= '1';
                wait until rising_edge(clk) and wreq_tready = '1';
                wreq_tvalid <= '0';
                if not expect_ok then
                    wait for 100 ns;
                    return;
                end if;
                -- W25Q: the touched sectors are erased
                if W25 then
                    s := (addr / 2) - (addr / 2) mod 4096;
                    e := (addr / 2 + len / 2 - 1) - (addr / 2 + len / 2 - 1) mod 4096 + 4095;
                    for k in s to e loop
                        sh1(k) := x"FF";
                    end loop;
                end if;
                for i in 0 to len - 1 loop
                    b := wbyte(i, seed);
                    wdat_tdata  <= b;
                    wdat_tvalid <= '1';
                    wait until rising_edge(clk) and wdat_tready = '1';
                    d := addr / 2 + i / 2;
                    if i mod 2 = 0 then
                        sh1(d)(7 downto 4) := b(3 downto 0);
                        sh2(d)(7 downto 4) := b(7 downto 4);
                    else
                        sh1(d)(3 downto 0) := b(3 downto 0);
                        sh2(d)(3 downto 0) := b(7 downto 4);
                    end if;
                end loop;
                wdat_tvalid <= '0';
                wait until w_done = '1' for 5 ms;
                check(w_done = '1', "no wr_done");
            end procedure;

            -- Read len host bytes at host address addr and compare with the shadow
            procedure read_check(addr, len : natural; msg : string) is
                variable base : natural;
                variable d    : natural;
                variable e1, e2, exp : std_logic_vector(7 downto 0);
                variable bad  : natural := 0;
            begin
                wait_idle;
                owner_wr <= false;
                base := rx_n;
                rreq_tdata  <= std_logic_vector(to_unsigned(len, 16)) & std_logic_vector(to_unsigned(addr, 32));
                rreq_tvalid <= '1';
                wait until rising_edge(clk) and rreq_tready = '1';
                rreq_tvalid <= '0';
                wait until rx_n >= base + len for 1 ms;
                check(rx_n = base + len, msg & ": " & integer'image(rx_n - base) & " bytes received");
                for i in 0 to len - 1 loop
                    d  := addr / 2 + i / 2;
                    e1 := sh1(d);
                    e2 := sh2(d);
                    if not DIE2 then
                        e2 := x"00";
                    end if;
                    if i mod 2 = 0 then
                        exp := e2(7 downto 4) & e1(7 downto 4);
                    else
                        exp := e2(3 downto 0) & e1(3 downto 0);
                    end if;
                    if rx_log(base + i) /= exp or (rx_lastv(base + i) = '1') /= (i = len - 1) then
                        if bad < 5 then
                            check(false, msg & ": byte " & integer'image(i) & " (die "
                                  & to_hstring(to_unsigned(d, 16)) & "h) expected " & to_hstring(exp)
                                  & ", got " & to_hstring(rx_log(base + i)));
                        else
                            errors := errors + 1;
                        end if;
                        bad := bad + 1;
                    end if;
                end loop;
            end procedure;
        begin
            for k in 0 to SHADOW - 1 loop
                sh1(k) := pattern_byte(k, SEED1);
                sh2(k) := pattern_byte(k, SEED2);
            end loop;
            wait until rstn = '1';
            wait for 3 us;                                   -- Models' T_PU

            -- 1. Before init_done, bad requests
            write(16#1000#, 16, 1, false);
            init_done <= '1';
            write(16#1001#, 16, 1, false);
            write(16#1000#, 15, 1, false);
            write(16#1000#, 0, 1, false);
            write(HSIZE - 8, 16, 1, false);
            check(err_pulses = 5, "req_err pulses: expected 5, got " & integer'image(err_pulses));

            -- 2. 880 host bytes from die byte 0F80h (W25Q: sectors 0 and 1, pages 0F00h, 1000h, 1100h)
            t0 := now;
            write(16#1F00#, 880, 1);
            report "Config " & integer'image(g) & ": 880-byte write took " & time'image(now - t0);
            read_check(16#1F00#, 880, "first write");
            if W25 then
                read_check(0, 16#1F00#, "erased sector 0 before the block");
                read_check(16#1F00# + 880, 16#4000# - 16#1F00# - 880, "erased sector 1 after the block");
            end if;

            -- 3. Overlapping second write
            write(16#2000#, 64, 2);
            read_check(16#1E00#, 1400, "second write");

            -- 4. AS: bytes around the block are untouched
            if not W25 then
                read_check(16#1E00#, 256, "before the block");
                read_check(16#1F00# + 880, 512, "after the block");
            end if;

            wait_idle;
            wait for 1 us;
            check(err1 + err2 = 0, "model protocol errors: " & integer'image(err1 + err2));
            check(err_pulses = 5, "unexpected req_err pulses: " & integer'image(err_pulses));
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
