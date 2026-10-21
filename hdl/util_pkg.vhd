-- General helper functions shared by the hdl/ sources
--   clog2        ceil(log2(n)): bits needed to count 0 .. n-1 (0 for n <= 1)
--   reverse      Bit-reverse a byte (LSB-first SPI)
--   ns_to_cycles Time in ns -> clock cycles, rounded up (for timing constants from datasheets)

library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

package util_pkg is

    function clog2(n : natural) return natural;
    function reverse(v : std_logic_vector(7 downto 0)) return std_logic_vector;
    function ns_to_cycles(ns : natural; clk_hz : positive) return natural;

end package util_pkg;

package body util_pkg is

    function clog2(n : natural) return natural is
        variable r : natural := 0;
        variable v : natural := 1;
    begin
        while v < n loop
            v := v * 2;
            r := r + 1;
        end loop;
        return r;
    end function;

    function reverse(v : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable r : std_logic_vector(7 downto 0);
    begin
        for i in 0 to 7 loop
            r(i) := v(7 - i);
        end loop;
        return r;
    end function;

    function ns_to_cycles(ns : natural; clk_hz : positive) return natural is
    begin
        -- Real arithmetic, because e.g. 25 ms at 100 MHz overflows a 32-bit integer product.
        -- The small offset keeps exact results (e.g. 20 ns at 100 MHz = 2.0) from rounding up
        -- because of floating-point noise. Only used for constants (elaboration time).
        return natural(ceil(real(ns) * real(clk_hz) / 1.0e9 - 1.0e-6));
    end function;

end package body util_pkg;
