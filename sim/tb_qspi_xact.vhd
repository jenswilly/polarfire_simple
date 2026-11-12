-- run_tb models: qspi_model_pkg qspi_mem_model
-- Self-checking testbench for qspi_xact (with qspi_phy) against the device models
--   Two configurations run side by side, each with its own qspi_xact and model (one die):
--     0: W25Q128JV
--     1: AS308G208 (one port/die)
--   clk_ctrl 200 MHz, SCLK 50 MHz (33 MHz for the AS 9Fh), sample delay 4, 3 ns board delay.
--   W25Q: reset, JEDEC ID, status registers, EBh read of an odd length, sector erase + BUSY
--     polling, quad page program (1-1-4) wrapping in the page, 1-1-1 program, read back.
--   AS: device ID, RDAR, EBh reads with latency 8 and 10 (CR2 written with WRAR) and across the
--     end of the die, D2h (1-4-4, odd length) and 02h (1-1-1) writes over several TX chunks, two
--     queued EBh reads (880 + 21 bytes) back to back.
--   Every RX byte (4 lines: two nibbles, high nibble first) and tlast are checked; the models
--   must report no protocol errors and rx_overflow must never pulse.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;
use work.qspi_model_pkg.all;

entity tb_qspi_xact is
end entity tb_qspi_xact;

architecture sim of tb_qspi_xact is
    constant CLK_PERIOD : time := 5 ns;      -- clk_ctrl 200 MHz
    constant NCFG       : positive := 2;

    subtype byte8 is std_logic_vector(7 downto 0);
    type bytes_t is array (natural range <>) of byte8;

    type nat_arr_t is array (0 to NCFG - 1) of natural;
    signal tb_errors : nat_arr_t := (others => 0);
    signal finished  : boolean_vector(0 to NCFG - 1) := (others => false);

    signal clk  : std_logic := '0';
    signal rstn : std_logic := '0';
    signal done : boolean := false;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done;

    cfg : for g in 0 to NCFG - 1 generate
        constant DEV   : device_t := device_t'val(g);
        constant SEED1 : positive := 5 - 2 * boolean'pos(g = 0);   -- W25Q 3, AS 5

        signal cmd_valid, cmd_ready : std_logic := '0';
        signal cmd_op      : std_logic_vector(7 downto 0) := (others => '0');
        signal cmd_lanes   : cmd_lanes_t := L111;
        signal cmd_addr    : std_logic_vector(31 downto 0) := (others => '0');
        signal cmd_ab      : natural range 0 to 4 := 0;
        signal cmd_mode_en : std_logic := '0';
        signal cmd_mode    : std_logic_vector(7 downto 0) := x"FF";
        signal cmd_lat     : natural range 0 to 15 := 0;
        signal cmd_dir     : dir_t := DIR_NONE;
        signal cmd_len     : unsigned(15 downto 0) := (others => '0');
        signal cmd_div     : natural range 1 to SCLK_DIV_MAX := 2;
        signal cmd_write   : std_logic := '0';
        signal s_tdata     : std_logic_vector(7 downto 0) := (others => '0');
        signal s_tvalid    : std_logic := '0';
        signal s_tready    : std_logic;
        signal m_tdata     : std_logic_vector(7 downto 0);
        signal m_tvalid    : std_logic;
        signal m_tlast     : std_logic;
        signal rx_ovf      : std_logic;
        signal busy        : std_logic;
        signal sclk, cs_n  : std_logic;
        signal io_o, io_oe : std_logic_vector(3 downto 0);
        signal io          : std_logic_vector(3 downto 0);
        signal err1        : natural := 0;
        signal ovf_count   : natural := 0;

        -- Received stream bytes
        constant LOG_MAX : positive := 2048;
        signal rx_log    : bytes_t(0 to LOG_MAX - 1);
        signal rx_lastv  : std_logic_vector(0 to LOG_MAX - 1);
        signal rx_n      : natural := 0;
    begin
        dut : entity work.qspi_xact
            generic map (DEVICE => DEV, CLK_HZ => 200_000_000)
            port map (
                clk => clk, reset_n => rstn,
                cmd_valid => cmd_valid, cmd_ready => cmd_ready, cmd_op => cmd_op,
                cmd_lanes => cmd_lanes, cmd_addr => cmd_addr, cmd_addr_bytes => cmd_ab,
                cmd_mode_en => cmd_mode_en, cmd_mode => cmd_mode, cmd_latency => cmd_lat,
                cmd_dir => cmd_dir, cmd_len => cmd_len, cmd_sclk_div => cmd_div,
                cmd_write => cmd_write,
                s_axis_tdata => s_tdata, s_axis_tvalid => s_tvalid, s_axis_tready => s_tready,
                m_axis_tdata => m_tdata, m_axis_tvalid => m_tvalid, m_axis_tready => '1',
                m_axis_tlast => m_tlast, rx_overflow => rx_ovf,
                sample_dly => 4, busy => busy,
                sclk => sclk, cs_n => cs_n, io_o => io_o, io_oe => io_oe, io_i => io);

        -- Board: tristate pads
        pads : for i in 0 to 3 generate
            io(i) <= io_o(i) when io_oe(i) = '1' else 'Z';
        end generate;

        die1 : entity work.qspi_mem_model
            generic map (DEVICE => DEV, DIE => 1, PRELOAD_SEED => SEED1, T_BOARD => 3 ns,
                         T_PU => 2 us, T_RST => 1 us, T_W => 2 us, T_PP => 3 us, T_SE => 5 us)
            port map (sclk => sclk, cs_n => cs_n, io => io, err_count => err1);

        rx_collect : process (clk)
        begin
            if rising_edge(clk) then
                if m_tvalid = '1' then
                    rx_log(rx_n)   <= m_tdata;
                    rx_lastv(rx_n) <= m_tlast;
                    rx_n <= rx_n + 1;
                end if;
                if rx_ovf = '1' then
                    ovf_count <= ovf_count + 1;
                end if;
            end if;
        end process;

        host : process
            variable errors  : natural := 0;
            variable rx_base : natural := 0;
            variable b       : byte8;
            variable got     : bytes_t(0 to 1);

            procedure check(cond : boolean; msg : string) is
            begin
                if not cond then
                    report "CHECK FAILED (config " & integer'image(g) & "): " & msg severity error;
                    errors := errors + 1;
                end if;
            end procedure;

            procedure issue(op : byte8; lanes : cmd_lanes_t; addr : natural; ab : natural;
                            mode_en : std_logic; lat : natural; dir : dir_t; len : natural;
                            div : positive := 2; wr : std_logic := '0') is
            begin
                cmd_op      <= op;
                cmd_lanes   <= lanes;
                cmd_addr    <= std_logic_vector(to_unsigned(addr, 32));
                cmd_ab      <= ab;
                cmd_mode_en <= mode_en;
                cmd_lat     <= lat;
                cmd_dir     <= dir;
                cmd_len     <= to_unsigned(len, 16);
                cmd_div     <= div;
                cmd_write   <= wr;
                cmd_valid   <= '1';
                wait until rising_edge(clk) and cmd_ready = '1';
                cmd_valid   <= '0';
            end procedure;

            procedure send(v : bytes_t) is
            begin
                for i in v'range loop
                    s_tdata  <= v(i);
                    s_tvalid <= '1';
                    wait until rising_edge(clk) and s_tready = '1';
                end loop;
                s_tvalid <= '0';
            end procedure;

            -- Wait for the next exp'length stream bytes and compare them
            procedure expect(exp : bytes_t; msg : string) is
                variable i : natural := 0;
            begin
                if rx_n < rx_base + exp'length then
                    wait until rx_n >= rx_base + exp'length for 100 us;
                end if;
                check(rx_n = rx_base + exp'length, msg & ": " & integer'image(exp'length)
                      & " bytes expected, " & integer'image(rx_n - rx_base) & " received");
                for k in exp'range loop
                    if rx_base + i < rx_n then
                        check(rx_log(rx_base + i) = exp(k), msg & ": byte " & integer'image(i)
                              & " expected " & to_hstring(exp(k)) & ", got "
                              & to_hstring(rx_log(rx_base + i)));
                        check((rx_lastv(rx_base + i) = '1') = (k = exp'high),
                              msg & ": tlast wrong at byte " & integer'image(i));
                    end if;
                    i := i + 1;
                end loop;
                rx_base := rx_n;
            end procedure;

            function pat(a : natural; n : positive; seed : positive) return bytes_t is
                variable r : bytes_t(0 to n - 1);
            begin
                for i in r'range loop
                    r(i) := pattern_byte((a + i) mod (2 ** 29), seed);
                end loop;
                return r;
            end function;

            function rep(v : byte8; n : positive) return bytes_t is
            begin
                return (0 to n - 1 => v);
            end function;

            procedure w25_wait_busy is
            begin
                loop
                    issue(x"05", L111, 0, 0, '0', 0, DIR_RX, 1);
                    wait until rx_n >= rx_base + 1 for 100 us;
                    b := rx_log(rx_base);
                    rx_base := rx_n;
                    exit when b(0) = '0';
                    wait for 500 ns;
                end loop;
            end procedure;

            constant W1 : bytes_t := (x"12", x"34", x"56", x"78");
            constant A1 : bytes_t := (x"01", x"23", x"45", x"67", x"89", x"AB", x"CD");
            constant S1 : bytes_t := (x"AA", x"55", x"0F", x"F0", x"C3", x"3C");
        begin
            if g = 0 then
                wait until rstn = '1';
            end if;
            wait for 3 us;                                       -- Models' T_PU

            if DEV = DEV_W25Q128JV then
                issue(x"66", L111, 0, 0, '0', 0, DIR_NONE, 0);
                issue(x"99", L111, 0, 0, '0', 0, DIR_NONE, 0);
                wait for 2 us;
                issue(x"9F", L111, 0, 0, '0', 0, DIR_RX, 3);
                expect((x"EF", x"40", x"18"), "JEDEC ID");
                issue(x"05", L111, 0, 0, '0', 0, DIR_RX, 1);
                expect((0 => x"00"), "SR1");
                issue(x"35", L111, 0, 0, '0', 0, DIR_RX, 1);
                expect((0 => x"02"), "SR2");

                issue(x"EB", L144, 16#000123#, 3, '1', 4, DIR_RX, 5);
                expect(pat(16#123#, 5, SEED1), "EBh read");

                issue(x"06", L111, 0, 0, '0', 0, DIR_NONE, 0, wr => '1');
                issue(x"20", L111, 16#001000#, 3, '0', 0, DIR_NONE, 0, wr => '1');
                w25_wait_busy;
                issue(x"EB", L144, 16#0010FE#, 3, '1', 4, DIR_RX, 2);
                expect(rep(x"FF", 2), "erased");

                -- Quad page program of 4 bytes at 0x10FE: the last 2 wrap to 0x1000
                issue(x"06", L111, 0, 0, '0', 0, DIR_NONE, 0, wr => '1');
                issue(x"32", L114, 16#0010FE#, 3, '0', 0, DIR_TX, 4, wr => '1');
                send(W1);
                w25_wait_busy;
                issue(x"EB", L144, 16#0010FE#, 3, '1', 4, DIR_RX, 2);
                expect(W1(0 to 1), "programmed, page end");
                issue(x"EB", L144, 16#001000#, 3, '1', 4, DIR_RX, 3);
                expect((x"56", x"78", x"FF"), "programmed, wrapped");

                -- 1-1-1 program of 6 bytes (two TX chunks)
                issue(x"06", L111, 0, 0, '0', 0, DIR_NONE, 0, wr => '1');
                issue(x"02", L111, 16#001010#, 3, '0', 0, DIR_TX, 6, wr => '1');
                send(S1);
                w25_wait_busy;
                issue(x"EB", L144, 16#001010#, 3, '1', 4, DIR_RX, 6);
                expect(S1, "1-1-1 program");
            else
                issue(x"9F", L111, 0, 0, '0', 0, DIR_RX, 4, div => 3);
                expect((x"E6", x"21", x"2C", x"01"), "device ID");
                issue(x"65", L111, 16#03#, 4, '0', 8, DIR_RX, 1);
                expect((0 => x"08"), "RDAR CR2");

                issue(x"EB", L144, 16#100#, 4, '1', 8, DIR_RX, 8);
                expect(pat(16#100#, 8, SEED1), "EBh latency 8");

                issue(x"06", L111, 0, 0, '0', 0, DIR_NONE, 0);
                issue(x"71", L111, 16#03#, 4, '0', 0, DIR_TX, 1, wr => '1');
                send((0 => x"0A"));
                issue(x"65", L111, 16#03#, 4, '0', 10, DIR_RX, 1);
                expect((0 => x"0A"), "RDAR CR2 after WRAR");
                issue(x"EB", L144, 16#1FFFFFFE#, 4, '1', 10, DIR_RX, 3);
                expect(pat(16#1FFFFFFE#, 3, SEED1), "EBh latency 10, end of die");
                issue(x"06", L111, 0, 0, '0', 0, DIR_NONE, 0);
                issue(x"71", L111, 16#03#, 4, '0', 0, DIR_TX, 1, wr => '1');
                send((0 => x"08"));

                -- D2h: 7 bytes, two TX chunks (4 + 3)
                issue(x"06", L111, 0, 0, '0', 0, DIR_NONE, 0);
                issue(x"D2", L144, 16#2000#, 4, '1', 0, DIR_TX, 7, wr => '1');
                send(A1);
                issue(x"EB", L144, 16#1FFF#, 4, '1', 8, DIR_RX, 9);
                expect(pat(16#1FFF#, 1, SEED1) & A1 & pat(16#2007#, 1, SEED1), "D2h write");

                -- 02h: 6 bytes, two TX chunks
                issue(x"06", L111, 0, 0, '0', 0, DIR_NONE, 0);
                issue(x"02", L111, 16#3000#, 4, '0', 0, DIR_TX, 6, wr => '1');
                send(S1);
                issue(x"EB", L144, 16#2FFF#, 4, '1', 8, DIR_RX, 8);
                expect(pat(16#2FFF#, 1, SEED1) & S1 & pat(16#3006#, 1, SEED1), "02h write");

                -- Two queued reads
                issue(x"EB", L144, 16#100000#, 4, '1', 8, DIR_RX, 880);
                issue(x"EB", L144, 16#200001#, 4, '1', 8, DIR_RX, 21);
                expect(pat(16#100000#, 880, SEED1), "880-byte read");
                expect(pat(16#200001#, 21, SEED1), "queued read");
            end if;

            wait until rising_edge(clk) and busy = '0';
            wait for 1 us;
            check(err1 = 0, "model protocol errors: " & integer'image(err1));
            check(ovf_count = 0, "rx_overflow pulsed " & integer'image(ovf_count) & " times");
            check(rx_n = rx_base, "unexpected extra RX bytes: " & integer'image(rx_n - rx_base));
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
