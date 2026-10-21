-- Self-checking testbench for util_pkg
--   Checks clog2 (including n = 0 and 1, which the SPI masters rely on via maximum(1, ...)),
--   reverse, and ns_to_cycles at 100 MHz and 50 MHz (exact values and rounding up).
--   No clock or DUT: everything is a function call.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

entity tb_util_pkg is
end entity tb_util_pkg;

architecture sim of tb_util_pkg is
begin
    process
        variable errors : natural := 0;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                report "CHECK FAILED: " & msg severity error;
                errors := errors + 1;
            end if;
        end procedure;

        procedure check_clog2(n : natural; expected : natural) is
        begin
            check(clog2(n) = expected, "clog2(" & integer'image(n) & "): expected "
                  & integer'image(expected) & ", got " & integer'image(clog2(n)));
        end procedure;

        -- ns_to_cycles(ns, clk_hz) must equal expected
        procedure check_cycles(ns : natural; clk_hz : positive; expected : natural) is
            constant got : natural := ns_to_cycles(ns, clk_hz);
        begin
            check(got = expected, "ns_to_cycles(" & integer'image(ns) & " ns, "
                  & integer'image(clk_hz) & " Hz): expected " & integer'image(expected)
                  & ", got " & integer'image(got));
        end procedure;

        variable v, r : std_logic_vector(7 downto 0);

        constant HZ_100M : positive := 100_000_000;
        constant HZ_50M  : positive := 50_000_000;
    begin
        -- 1. clog2
        check_clog2(0, 0);
        check_clog2(1, 0);
        check_clog2(2, 1);
        check_clog2(3, 2);
        check_clog2(4, 2);
        check_clog2(5, 3);
        check_clog2(7, 3);
        check_clog2(880, 10);
        check_clog2(1024, 10);
        check_clog2(1025, 11);
        check_clog2(2 ** 29, 29);
        check_clog2(2 ** 29 + 1, 30);

        -- 2. reverse: every byte value, bit i must land in bit 7 - i
        for n in 0 to 255 loop
            v := std_logic_vector(to_unsigned(n, 8));
            r := reverse(v);
            for i in 0 to 7 loop
                check(r(7 - i) = v(i), "reverse(" & integer'image(n) & "): bit "
                      & integer'image(i) & " not mirrored");
            end loop;
        end loop;
        check(reverse(x"01") = x"80", "reverse(01) should be 80");
        check(reverse(x"A5") = x"A5", "reverse(A5) should be A5");

        -- 3. ns_to_cycles at 100 MHz (10 ns per cycle): exact values and rounding up
        check_cycles(0,          HZ_100M, 0);
        check_cycles(1,          HZ_100M, 1);
        check_cycles(10,         HZ_100M, 1);
        check_cycles(11,         HZ_100M, 2);
        check_cycles(15,         HZ_100M, 2);
        check_cycles(20,         HZ_100M, 2);
        check_cycles(50,         HZ_100M, 5);
        check_cycles(600,        HZ_100M, 60);
        check_cycles(1_000,      HZ_100M, 100);
        check_cycles(30_000,     HZ_100M, 3_000);
        check_cycles(5_000_000,  HZ_100M, 500_000);
        check_cycles(25_000_000, HZ_100M, 2_500_000);

        -- 4. ns_to_cycles at 50 MHz (20 ns per cycle)
        check_cycles(0,          HZ_50M, 0);
        check_cycles(1,          HZ_50M, 1);
        check_cycles(10,         HZ_50M, 1);
        check_cycles(20,         HZ_50M, 1);
        check_cycles(21,         HZ_50M, 2);
        check_cycles(50,         HZ_50M, 3);
        check_cycles(600,        HZ_50M, 30);
        check_cycles(30_000,     HZ_50M, 1_500);
        check_cycles(5_000_000,  HZ_50M, 250_000);
        check_cycles(25_000_000, HZ_50M, 1_250_000);

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        wait;
    end process;
end architecture sim;
