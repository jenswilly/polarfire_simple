-- run_tb models: qspi_model_pkg qspi_mem_model
-- Self-checking testbench for the QSPI device model (sim/models/qspi_mem_model.vhd)
--   One model per device, each on its own bus, driven by a bit-banged SPI host (SCLK 50 MHz,
--   25 MHz for the AS308G208's 40 MHz commands). The host samples at the SCLK rising edge.
--   W25Q128JV: reset (66h/99h), JEDEC ID, SR1/2/3, EBh read of erased flash, WREN/WEL,
--     sector erase with BUSY polling, quad page program wrapping inside the page, 1-1-1 program
--     ANDing into the array.
--   AS308G208: RESET#, JEDEC ID and RDSR at 25 MHz, RDAR (CR1, CR2, FSR, ID), EBh reads of the
--     preloaded pattern with latency 8 and 10 (CR2 written with WRAR), D2h and 02h writes,
--     WREN cleared after writes.
--   Protocol violations that must each raise the model's err_count: program without WREN,
--   command while BUSY, continuous-read mode byte, CS# high too short, partial-byte program,
--   write without WREN, 9Fh at 50 MHz, address outside the die, XIP byte, CS# high too short
--   after a write, command during tPU after RESET#, bus contention.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;
use work.qspi_model_pkg.all;

entity tb_qspi_mem_model is
end entity tb_qspi_mem_model;

architecture sim of tb_qspi_mem_model is
    constant AS_SEED : positive := 7;

    type nat_arr_t is array (0 to 1) of natural;
    signal tb_errors : nat_arr_t := (others => 0);
    signal finished  : boolean_vector(0 to 1) := (others => false);

    subtype byte_t8 is std_logic_vector(7 downto 0);
    type bytes_t is array (natural range <>) of byte_t8;
begin
    dev : for g in 0 to 1 generate
        constant DEV  : device_t := device_t'val(g);      -- 0 = W25Q128JV, 1 = AS308G208
        constant SEED : natural  := g * AS_SEED;           -- W25Q: erased (FFh), AS: pattern

        signal sclk      : std_logic := '0';
        signal cs_n      : std_logic := '1';
        signal rst_n     : std_logic := '1';
        signal io        : std_logic_vector(3 downto 0) := (others => 'Z');
        signal err_count : natural;
    begin
        model : entity work.qspi_mem_model
            generic map (
                DEVICE => DEV, DIE => 1, PRELOAD_SEED => SEED,
                T_PU => 2 us, T_RST => 1 us, T_W => 2 us, T_PP => 3 us, T_SE => 5 us)
            port map (sclk => sclk, cs_n => cs_n, reset_n => rst_n, io => io, err_count => err_count);

        host : process
            variable errors  : natural := 0;
            variable exp_err : natural := 0;
            variable t_half  : time := 10 ns;            -- 50 MHz
            variable s       : std_logic_vector(3 downto 0);
            variable b       : byte_t8;
            variable polls   : natural;

            procedure check(cond : boolean; msg : string) is
            begin
                if not cond then
                    report "CHECK FAILED (" & device_t'image(DEV) & "): " & msg severity error;
                    errors := errors + 1;
                end if;
            end procedure;

            -- One SCLK cycle: drive io, rising edge after t_half (sample), falling edge after t_half
            procedure cycle(d : std_logic_vector(3 downto 0); smp : out std_logic_vector(3 downto 0)) is
            begin
                io <= d;
                wait for t_half;
                sclk <= '1';
                smp := io;
                wait for t_half;
                sclk <= '0';
            end procedure;

            procedure start is
            begin
                io   <= "11Z0";                       -- SPI: IO3/IO2 high, IO1 from the device
                cs_n <= '0';
            end procedure;

            procedure stop(t_high : time := 100 ns) is
            begin
                wait for 5 ns;
                cs_n <= '1';                          -- IO unchanged, like qspi_phy
                wait for t_high;
            end procedure;

            procedure spi_out(v : std_logic_vector) is
                variable x : std_logic_vector(3 downto 0);
            begin
                for i in v'range loop
                    cycle("11Z" & v(i), x);
                end loop;
            end procedure;

            procedure spi_in(v : out byte_t8) is
                variable x : std_logic_vector(3 downto 0);
            begin
                for i in 7 downto 0 loop
                    cycle("11Z0", x);
                    v(i) := x(1);
                end loop;
            end procedure;

            procedure quad_out(v : std_logic_vector) is   -- v'length multiple of 4, MSB first
                variable x : std_logic_vector(3 downto 0);
                variable w : std_logic_vector(v'length - 1 downto 0) := v;
            begin
                for i in v'length / 4 - 1 downto 0 loop
                    cycle(w(4 * i + 3 downto 4 * i), x);
                end loop;
            end procedure;

            procedure quad_in(v : out byte_t8) is
                variable x : std_logic_vector(3 downto 0);
            begin
                cycle("ZZZZ", x);
                v(7 downto 4) := x;
                cycle("ZZZZ", x);
                v(3 downto 0) := x;
            end procedure;

            procedure dummy(n : natural; quad : boolean) is
                variable x : std_logic_vector(3 downto 0);
            begin
                for i in 1 to n loop
                    if quad then
                        cycle("ZZZZ", x);
                    else
                        cycle("11Z0", x);
                    end if;
                end loop;
            end procedure;

            -- Single-byte commands and register reads
            procedure cmd(op : byte_t8) is
            begin
                start;  spi_out(op);  stop;
            end procedure;

            procedure read_reg(op : byte_t8; v : out byte_t8) is
            begin
                start;  spi_out(op);  spi_in(v);  stop;
            end procedure;

            -- EBh read of n bytes, compared with exp (or with the AS preload pattern if exp is empty)
            procedure read_check(a : natural; abytes : positive; lat : natural; exp : bytes_t;
                                 msg : string; mode : byte_t8 := x"FF") is
                variable d : byte_t8;
            begin
                start;
                spi_out(x"EB");
                quad_out(std_logic_vector(to_unsigned(a, 8 * abytes)));
                quad_out(mode);
                dummy(lat, true);
                for i in exp'range loop
                    quad_in(d);
                    check(d = exp(i), msg & ": byte " & integer'image(i) & " expected "
                          & to_hstring(exp(i)) & ", got " & to_hstring(d));
                end loop;
                stop;
            end procedure;

            function pattern(a : natural; n : positive) return bytes_t is
                variable r : bytes_t(0 to n - 1);
            begin
                for i in r'range loop
                    r(i) := pattern_byte(a + i, AS_SEED);
                end loop;
                return r;
            end function;

            function fill(v : byte_t8; n : positive) return bytes_t is
            begin
                return (0 to n - 1 => v);
            end function;

            -- The model must have reported exactly n more errors
            procedure expect_errors(n : natural; msg : string) is
            begin
                wait for 1 ns;
                exp_err := exp_err + n;
                check(err_count = exp_err, msg & ": model errors expected " & integer'image(exp_err)
                      & ", got " & integer'image(err_count));
                exp_err := err_count;
            end procedure;

            -- W25Q: poll SR1 until BUSY = 0, returns the number of polls that saw BUSY = 1
            procedure wait_busy(n : out natural) is
                variable sr : byte_t8;
                variable k  : natural := 0;
            begin
                loop
                    read_reg(x"05", sr);
                    exit when sr(W25_SR1_BUSY) = '0';
                    k := k + 1;
                    wait for 500 ns;
                end loop;
                n := k;
            end procedure;

            procedure as_write_reg(a : natural; v : byte_t8) is
            begin
                cmd(x"06");
                start;
                spi_out(x"71");
                spi_out(std_logic_vector(to_unsigned(a, 32)));
                spi_out(v);
                stop(1 us);
            end procedure;

            procedure as_read_reg(a : natural; lat : natural; v : out byte_t8) is
            begin
                start;
                spi_out(x"65");
                spi_out(std_logic_vector(to_unsigned(a, 32)));
                dummy(lat, false);
                spi_in(v);
                stop;
            end procedure;

            variable d4 : bytes_t(0 to 3);
        begin
            if DEV = DEV_W25Q128JV then
                ---------------------------------------------------------------- W25Q128JV
                wait for 3 us;                                       -- > T_PU (tPUW)
                cmd(x"66");
                cmd(x"99");
                wait for 2 us;                                       -- > T_RST
                expect_errors(0, "reset");

                start;  spi_out(x"9F");
                for i in 0 to 3 loop
                    spi_in(d4(i));
                end loop;
                stop;
                check(d4 = (x"EF", x"40", x"18", x"EF"), "JEDEC ID EF 40 18 (repeating)");

                read_reg(x"05", b);  check(b = x"00", "SR1 = 00, got " & to_hstring(b));
                read_reg(x"35", b);  check(b = x"02", "SR2 = 02 (QE), got " & to_hstring(b));
                read_reg(x"15", b);  check(b = x"60", "SR3 = 60, got " & to_hstring(b));

                read_check(16#000100#, 3, 4, fill(x"FF", 4), "erased flash");

                cmd(x"06");
                read_reg(x"05", b);  check(b = x"02", "WEL after WREN, SR1 = " & to_hstring(b));

                -- Sector erase, BUSY polling
                cmd(x"06");
                start;  spi_out(x"20");  spi_out(x"001234");  stop;
                wait_busy(polls);
                check(polls >= 5, "erase BUSY seen in " & integer'image(polls) & " polls (T_SE 5 us)");
                read_reg(x"05", b);  check(b = x"00", "SR1 after erase = " & to_hstring(b));

                -- Quad page program of 20 bytes from 0x0010F0: the last 4 wrap to 0x001000
                cmd(x"06");
                start;
                spi_out(x"32");
                spi_out(x"0010F0");
                for i in 0 to 19 loop
                    quad_out(std_logic_vector(to_unsigned(16#10# + i, 8)));
                end loop;
                stop;
                wait_busy(polls);
                check(polls >= 2, "program BUSY seen in " & integer'image(polls) & " polls (T_PP 3 us)");
                read_check(16#0010F0#, 3, 4,
                           (x"10", x"11", x"12", x"13", x"14", x"15", x"16", x"17",
                            x"18", x"19", x"1A", x"1B", x"1C", x"1D", x"1E", x"1F", x"FF"),
                           "programmed page end");
                read_check(16#001000#, 3, 4, (x"20", x"21", x"22", x"23", x"FF"), "wrapped bytes");

                -- 1-1-1 program ANDs into the array
                cmd(x"06");
                start;  spi_out(x"02");  spi_out(x"0010F1");  spi_out(x"0F");  stop;
                wait_busy(polls);
                read_check(16#0010F0#, 3, 4, (x"10", x"01", x"12"), "AND programming");
                expect_errors(0, "normal operation");

                -- Violations
                start;  spi_out(x"02");  spi_out(x"002000");  spi_out(x"00");  stop;
                expect_errors(1, "program without WREN");
                read_check(16#002000#, 3, 4, fill(x"FF", 1), "unchanged after refused program");

                cmd(x"06");
                start;  spi_out(x"20");  spi_out(x"003000");  stop;
                read_reg(x"9F", b);
                expect_errors(1, "command while BUSY");
                wait_busy(polls);

                read_check(16#000000#, 3, 4, fill(x"FF", 1), "continuous-read mode byte", x"20");
                expect_errors(1, "mode byte 20h");

                start;  spi_out(x"05");  spi_in(b);  stop(5 ns);
                read_reg(x"05", b);
                expect_errors(1, "CS# high 5 ns");

                cmd(x"06");
                start;  spi_out(x"32");  spi_out(x"004000");  quad_out(x"ABC");  stop;
                expect_errors(1, "partial-byte program");
                cmd(x"04");
            else
                ---------------------------------------------------------------- AS308G208
                rst_n <= '0';
                wait for 100 ns;
                rst_n <= '1';
                wait for 3 us;                                       -- > T_PU

                t_half := 20 ns;                                     -- 25 MHz for 9Fh / 05h
                start;  spi_out(x"9F");
                for i in 0 to 3 loop
                    spi_in(d4(i));
                end loop;
                stop;
                check(d4 = (x"E6", x"21", x"2C", x"01"), "device ID E6 21 2C 01");
                read_reg(x"05", b);  check(b = x"00", "SR = 00, got " & to_hstring(b));
                t_half := 10 ns;

                as_read_reg(16#03#, 8, b);  check(b = x"08", "CR2 = 08, got " & to_hstring(b));
                as_read_reg(16#02#, 8, b);  check(b = x"60", "CR1 = 60, got " & to_hstring(b));
                as_read_reg(16#0A#, 8, b);  check(b = x"80", "FSR = 80, got " & to_hstring(b));
                as_read_reg(16#30#, 8, b);  check(b = x"E6", "ID register = E6, got " & to_hstring(b));

                read_check(16#00001000#, 4, 8, pattern(16#00001000#, 8), "pattern, latency 8");

                as_write_reg(16#03#, x"0A");
                as_read_reg(16#03#, 10, b);  check(b = x"0A", "CR2 = 0A after WRAR, got " & to_hstring(b));
                read_check(16#10000000#, 4, 10, pattern(16#10000000#, 8), "pattern, latency 10");
                as_write_reg(16#03#, x"08");
                read_check(16#1FFFFFFE#, 4, 8,
                           (pattern_byte(16#1FFFFFFE#, AS_SEED), pattern_byte(16#1FFFFFFF#, AS_SEED),
                            pattern_byte(0, AS_SEED)), "wrap at the end of the die");

                -- D2h quad write, 02h 1-1-1 write
                cmd(x"06");
                t_half := 20 ns;                                     -- 05h: max 40 MHz
                read_reg(x"05", b);  check(b = x"02", "WREN bit after 06h, SR = " & to_hstring(b));
                t_half := 10 ns;
                start;
                spi_out(x"D2");
                quad_out(x"00002000");
                quad_out(x"FF");
                quad_out(x"0123456789ABCDEF");
                stop(1 us);
                read_check(16#00002000#, 4, 8,
                           (x"01", x"23", x"45", x"67", x"89", x"AB", x"CD", x"EF",
                            pattern_byte(16#2008#, AS_SEED)), "D2h write");
                cmd(x"06");
                start;  spi_out(x"02");  spi_out(x"00002004");  spi_out(x"AA55");  stop(1 us);
                read_check(16#00002002#, 4, 8, (x"45", x"67", x"AA", x"55", x"CD"), "02h write");
                t_half := 20 ns;
                read_reg(x"05", b);  check(b = x"00", "WREN cleared after the write, SR = " & to_hstring(b));
                t_half := 10 ns;
                expect_errors(0, "normal operation");

                -- Violations
                start;  spi_out(x"D2");  quad_out(x"00003000");  quad_out(x"FF");  quad_out(x"00");  stop(1 us);
                expect_errors(1, "write without WREN");
                read_check(16#00003000#, 4, 8, pattern(16#3000#, 1), "unchanged after refused write");

                read_reg(x"9F", b);
                expect_errors(1, "9Fh at 50 MHz");

                read_check(16#20000000#, 4, 8, pattern(0, 1), "address outside the die");
                expect_errors(1, "address 20000000h");

                read_check(16#00001000#, 4, 8, pattern(16#1000#, 1), "XIP byte", x"A0");
                expect_errors(1, "XIP byte A0h");

                cmd(x"06");
                start;  spi_out(x"D2");  quad_out(x"00004000");  quad_out(x"FF");  quad_out(x"11");  stop(100 ns);
                read_check(16#00004000#, 4, 8, (0 => x"11"), "write then short CS# high");
                expect_errors(1, "CS# high 100 ns after a write");

                rst_n <= '0';
                wait for 100 ns;
                rst_n <= '1';
                wait for 1 us;                                       -- < T_PU
                as_read_reg(16#03#, 8, b);
                expect_errors(1, "command during tPU");
                wait for 2 us;
                as_read_reg(16#03#, 8, b);  check(b = x"08", "CR2 after RESET# = " & to_hstring(b));

                -- Contention: the host keeps driving IO3:0 while the model outputs data
                start;
                spi_out(x"EB");
                quad_out(x"00001000");
                quad_out(x"FF");
                dummy(8, true);
                for i in 1 to 4 loop
                    cycle("0101", s);
                end loop;
                stop;
                wait for 1 ns;
                check(err_count > exp_err, "contention must be reported");
                exp_err := err_count;
            end if;

            wait for 1 us;
            check(err_count = exp_err, "model errors at the end: expected " & integer'image(exp_err)
                  & ", got " & integer'image(err_count));
            tb_errors(g) <= errors;
            finished(g)  <= true;
            wait;
        end process;
    end generate;

    verdict : process
        variable errors : natural;
    begin
        wait until finished = (true, true);
        errors := tb_errors(0) + tb_errors(1);
        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        wait;
    end process;

    watchdog : process
    begin
        wait for 2 ms;
        if finished /= (true, true) then
            report "TB FAILED: timeout" severity error;
            std.env.stop;
        end if;
        wait;
    end process;
end architecture sim;
