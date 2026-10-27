-- run_tb models: qspi_model_pkg qspi_mem_model
-- Self-checking testbench for qspi_read_ctrl (with qspi_xact and qspi_phy) against preloaded models
--   Three configurations side by side: W25Q128JV; AS308G208 with 1 die; AS308G208 with 2 dies.
--   clk_ctrl 200 MHz, SCLK 50 MHz, sample delay 4, 3 ns board delay. init_done is driven by the
--   testbench (qspi_init is tested in tb_qspi_init); the models need no configuration for EBh.
--   Downstream is a byte buffer of CAP bytes (rx_space = CAP - fill) with its own consumer.
--     1. Requests before init_done are dropped with req_err.
--     2. Bad requests: odd address, odd length, length 0, end beyond the device -> req_err, no data.
--     3. Timing: 8 non-contiguous blocks of 880 host bytes, all requested at once, large buffer
--        and a fast consumer. Reports the time from the first request to the last byte, which
--        must be 140.8 us (7040 data clocks) + overhead, at most 150 us.
--     4. Credit starvation: 1000-byte buffer, consumer takes one byte every 16 clk cycles (a
--        quarter of the read rate). Requests must wait for space, counting the bytes of earlier
--        requests still in flight: the buffer must never overflow.
--        Includes a read that ends exactly at the end of the device.
--   Every byte is compared with the preload pattern ({die2_nibble, die1_nibble}, die 2 = 0 with
--   one die), tlast must mark the last byte of each request, the models must report no errors
--   and rx_overflow must never pulse.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;
use work.qspi_model_pkg.all;

entity tb_qspi_read_ctrl is
end entity tb_qspi_read_ctrl;

architecture sim of tb_qspi_read_ctrl is
    constant CLK_PERIOD : time := 5 ns;      -- clk_ctrl 200 MHz
    constant NCFG       : positive := 3;
    constant SEED1      : positive := 5;
    constant SEED2      : positive := 9;
    constant NREQ       : positive := 8;
    constant BLOCK_LEN  : positive := 880;

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
        constant HSIZE : natural  := 2 * dev_params(DEV).size_bytes;   -- Host address space

        signal init_done   : std_logic := '0';
        signal req_tdata   : std_logic_vector(47 downto 0) := (others => '0');
        signal req_tvalid  : std_logic := '0';
        signal req_tready  : std_logic;
        signal req_err     : std_logic;
        signal rx_space    : unsigned(15 downto 0);
        signal rc_busy     : std_logic;

        signal cmd_valid, cmd_ready, cmd_mode_en, cmd_write : std_logic;
        signal cmd_op, cmd_mode : std_logic_vector(7 downto 0);
        signal cmd_lanes   : cmd_lanes_t;
        signal cmd_addr    : std_logic_vector(31 downto 0);
        signal cmd_ab      : natural range 0 to 4;
        signal cmd_lat     : natural range 0 to 15;
        signal cmd_dir     : dir_t;
        signal cmd_len     : unsigned(15 downto 0);
        signal cmd_div     : natural range 1 to SCLK_DIV_MAX;
        signal x_tdata     : std_logic_vector(7 downto 0);
        signal x_tvalid, x_tready, x_tlast, rx_ovf, xact_busy : std_logic;
        signal m_tdata     : std_logic_vector(7 downto 0);
        signal m_tvalid, m_tlast : std_logic;

        signal sclk, cs_n  : std_logic_vector(1 downto 0);
        signal io_o, io_oe : std_logic_vector(7 downto 0);
        signal io          : std_logic_vector(7 downto 0);
        signal err1, err2  : natural := 0;

        -- Downstream buffer: fill level and consumer
        signal cap         : natural := 16384;
        signal fill        : natural := 0;
        signal max_fill    : natural := 0;
        signal slow        : boolean := false;     -- Consumer takes one byte every 16 cycles
        signal overflows   : natural := 0;
        signal ovf_count   : natural := 0;
        signal err_pulses  : natural := 0;

        -- Expected stream: requests queued by the host, checked byte by byte on arrival
        type req_arr_t is array (0 to 31) of natural;
        signal q_addr, q_len : req_arr_t := (others => 0);
        signal q_n           : natural := 0;
        signal chk_errors    : natural := 0;
        signal bytes_in      : natural := 0;
        signal t_last_byte   : time := 0 ns;
    begin
        rc : entity work.qspi_read_ctrl
            generic map (DEVICE => DEV, SCLK_DIV => 2, SPACE_W => 16)
            port map (
                clk => clk, reset_n => rstn, init_done => init_done,
                s_axis_req_tdata => req_tdata, s_axis_req_tvalid => req_tvalid,
                s_axis_req_tready => req_tready, req_err => req_err, rx_space => rx_space,
                busy => rc_busy,
                cmd_valid => cmd_valid, cmd_ready => cmd_ready, cmd_op => cmd_op,
                cmd_lanes => cmd_lanes, cmd_addr => cmd_addr, cmd_addr_bytes => cmd_ab,
                cmd_mode_en => cmd_mode_en, cmd_mode => cmd_mode, cmd_latency => cmd_lat,
                cmd_dir => cmd_dir, cmd_len => cmd_len, cmd_sclk_div => cmd_div,
                cmd_write => cmd_write,
                rx_tdata => x_tdata, rx_tvalid => x_tvalid, rx_tready => x_tready, rx_tlast => x_tlast,
                m_axis_tdata => m_tdata, m_axis_tvalid => m_tvalid, m_axis_tready => '1',
                m_axis_tlast => m_tlast);

        xact : entity work.qspi_xact
            generic map (DEVICE => DEV, DIE2_PRESENT => DIE2, CLK_HZ => 200_000_000)
            port map (
                clk => clk, reset_n => rstn,
                cmd_valid => cmd_valid, cmd_ready => cmd_ready, cmd_op => cmd_op,
                cmd_lanes => cmd_lanes, cmd_addr => cmd_addr, cmd_addr_bytes => cmd_ab,
                cmd_mode_en => cmd_mode_en, cmd_mode => cmd_mode, cmd_latency => cmd_lat,
                cmd_dir => cmd_dir, cmd_len => cmd_len, cmd_sclk_div => cmd_div,
                cmd_write => cmd_write,
                s_axis_tdata => x"00", s_axis_tvalid => '0', s_axis_tready => open,
                m_axis_tdata => x_tdata, m_axis_tvalid => x_tvalid, m_axis_tready => x_tready,
                m_axis_tlast => x_tlast, rx_overflow => rx_ovf,
                sample_dly => 4, busy => xact_busy,
                sclk => sclk, cs_n => cs_n, io_o => io_o, io_oe => io_oe, io_i => io);

        pads : for i in 0 to 7 generate
            io(i) <= io_o(i) when io_oe(i) = '1' else 'Z';
        end generate;

        die1 : entity work.qspi_mem_model
            generic map (DEVICE => DEV, DIE => 1, PRELOAD_SEED => SEED1, T_BOARD => 3 ns, T_PU => 2 us)
            port map (sclk => sclk(0), cs_n => cs_n(0), io => io(3 downto 0), err_count => err1);

        die2_gen : if DIE2 generate
            die2 : entity work.qspi_mem_model
                generic map (DEVICE => DEV, DIE => 2, PRELOAD_SEED => SEED2, T_BOARD => 3 ns, T_PU => 2 us)
                port map (sclk => sclk(1), cs_n => cs_n(1), io => io(7 downto 4), err_count => err2);
        end generate;

        rx_space <= to_unsigned(cap - fill, 16) when fill <= cap else (others => '0');

        -- Downstream buffer, consumer and stream checker
        sink : process (clk)
            variable f       : natural := 0;
            variable mx      : natural := 0;
            variable cyc     : natural := 0;
            variable qi      : natural := 0;       -- Current request
            variable k       : natural := 0;       -- Byte within the request
            variable errors  : natural := 0;
            variable n_in    : natural := 0;
            variable a       : natural;
            variable d1, d2  : std_logic_vector(7 downto 0);
            variable exp     : std_logic_vector(7 downto 0);
        begin
            if rising_edge(clk) then
                if m_tvalid = '1' then
                    f := f + 1;
                    n_in := n_in + 1;
                    t_last_byte <= now;
                    if qi >= q_n then
                        report "CHECK FAILED (config " & integer'image(g) & "): byte without a request"
                               severity error;
                        errors := errors + 1;
                    else
                        a  := q_addr(qi) / 2 + k / 2;
                        d1 := pattern_byte(a, SEED1);
                        d2 := pattern_byte(a, SEED2);
                        if not DIE2 then
                            d2 := x"00";
                        end if;
                        if k mod 2 = 0 then
                            exp := d2(7 downto 4) & d1(7 downto 4);
                        else
                            exp := d2(3 downto 0) & d1(3 downto 0);
                        end if;
                        if m_tdata /= exp or (m_tlast = '1') /= (k = q_len(qi) - 1) then
                            if errors < 10 then
                                report "CHECK FAILED (config " & integer'image(g) & "): request "
                                       & integer'image(qi) & " byte " & integer'image(k) & ": expected "
                                       & to_hstring(exp) & ", got " & to_hstring(m_tdata) & " last "
                                       & std_logic'image(m_tlast) severity error;
                            end if;
                            errors := errors + 1;
                        end if;
                        k := k + 1;
                        if k = q_len(qi) then
                            k  := 0;
                            qi := qi + 1;
                        end if;
                    end if;
                end if;
                cyc := cyc + 1;
                if f > 0 and (not slow or cyc mod 16 = 0) then
                    f := f - 1;
                end if;
                if f > cap then
                    overflows <= overflows + 1;
                end if;
                if f > mx then
                    mx := f;
                end if;
                fill       <= f;
                max_fill   <= mx;
                chk_errors <= errors;
                bytes_in   <= n_in;
                if rx_ovf = '1' then
                    ovf_count <= ovf_count + 1;
                end if;
                if req_err = '1' then
                    err_pulses <= err_pulses + 1;
                end if;
            end if;
        end process;

        host : process
            variable errors : natural := 0;
            variable t0     : time;
            variable n0     : natural;
            variable e0     : natural;

            procedure check(cond : boolean; msg : string) is
            begin
                if not cond then
                    report "CHECK FAILED (config " & integer'image(g) & "): " & msg severity error;
                    errors := errors + 1;
                end if;
            end procedure;

            -- Send a request; expect = true queues it for the checker
            procedure request(addr, len : natural; expect : boolean := true) is
            begin
                req_tdata  <= std_logic_vector(to_unsigned(len, 16)) & std_logic_vector(to_unsigned(addr, 32));
                req_tvalid <= '1';
                if expect then
                    q_addr(q_n) <= addr;
                    q_len(q_n)  <= len;
                    q_n         <= q_n + 1;
                end if;
                wait until rising_edge(clk) and req_tready = '1';
                req_tvalid <= '0';
            end procedure;

            procedure wait_idle is
            begin
                wait until rising_edge(clk);
                wait until rising_edge(clk) and rc_busy = '0' and xact_busy = '0' for 2 ms;
                check(rc_busy = '0' and xact_busy = '0', "did not become idle");
            end procedure;

            impure function block_addr(i : natural) return natural is
            begin
                return i * 16#200000# + i * 16#100#;        -- Non-contiguous, die address % 4 = 0
            end function;
        begin
            wait until rstn = '1';
            wait for 3 us;                                   -- Models' T_PU

            -- 1. Before init_done
            request(16#1000#, 16, false);
            wait for 200 ns;
            check(err_pulses = 1, "request before init_done must give req_err");
            check(bytes_in = 0, "no data before init_done");
            init_done <= '1';

            -- 2. Bad requests
            e0 := err_pulses;
            request(16#1001#, 16, false);                    -- Odd address
            request(16#1000#, 15, false);                    -- Odd length
            request(16#1000#, 0, false);                     -- Length 0
            request(HSIZE - 8, 16, false);                   -- Ends beyond the device
            wait for 200 ns;
            check(err_pulses - e0 = 4, "bad requests: 4 req_err pulses expected, got "
                  & integer'image(err_pulses - e0));
            check(bytes_in = 0, "no data for bad requests");

            -- 3. 8 x 880 host bytes, all requested at once
            t0 := now;
            for i in 0 to NREQ - 1 loop
                request(block_addr(i), BLOCK_LEN);
            end loop;
            wait_idle;
            check(bytes_in = NREQ * BLOCK_LEN, "bytes received: " & integer'image(bytes_in));
            report "Config " & integer'image(g) & " (" & device_t'image(DEV) & ", "
                   & integer'image(1 + boolean'pos(DIE2)) & " die(s)): " & integer'image(NREQ)
                   & " x " & integer'image(BLOCK_LEN) & " host bytes in "
                   & integer'image((t_last_byte - t0) / 10 ns) & "0 ns";
            check(t_last_byte - t0 >= 140.8 us and t_last_byte - t0 <= 150 us,
                  "8 x 880 bytes took " & time'image(t_last_byte - t0) & ", expected 140.8 .. 150 us");

            -- 4. Credit starvation: small buffer, slow consumer
            if fill /= 0 then
                wait until fill = 0;
            end if;
            cap  <= 1000;
            slow <= true;
            n0 := bytes_in;
            for i in 0 to 3 loop
                request(16#400000# + block_addr(i), BLOCK_LEN);
            end loop;
            request(HSIZE - 64, 64);                         -- Ends exactly at the device end
            wait_idle;
            check(bytes_in - n0 = 4 * BLOCK_LEN + 64, "starved: bytes received: "
                  & integer'image(bytes_in - n0));
            check(overflows = 0, "downstream buffer overflowed " & integer'image(overflows) & " times");
            check(max_fill > 500, "starvation test should fill the buffer (max " & integer'image(max_fill) & ")");

            wait for 1 us;
            check(chk_errors = 0, integer'image(chk_errors) & " wrong stream bytes");
            check(err1 + err2 = 0, "model protocol errors: " & integer'image(err1 + err2));
            check(ovf_count = 0, "rx_overflow pulsed " & integer'image(ovf_count) & " times");
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
