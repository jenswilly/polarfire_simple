-- Self-checking testbench for qspi_pkg
--   Checks the device parameters through the util_pkg helpers (the device timings converted with
--   ns_to_cycles at the 200 MHz clk_ctrl, and that they fit the counters of qspi_xact / qspi_init),
--   address widths with clog2, read_overhead_clocks and id_ok.
--   The helpers themselves are tested in tb_util_pkg.
--   No clock or DUT: everything is a function call.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use work.util_pkg.all;
use work.qspi_pkg.all;

entity tb_qspi_pkg is
end entity tb_qspi_pkg;

architecture sim of tb_qspi_pkg is
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

        constant HZ_200M : positive := 200_000_000;
        constant W25 : dev_params_t := dev_params(DEV_W25Q128JV);
        constant AS  : dev_params_t := dev_params(DEV_AS308G208);
    begin
        -- 1. The device timings the controller converts, at 200 MHz
        check(ns_to_cycles(W25.t_cs_rd_ns,   HZ_200M) = 2,         "W25Q tSHSL1 at 200 MHz");
        check(ns_to_cycles(W25.t_cs_wr_ns,   HZ_200M) = 10,        "W25Q tSHSL2 at 200 MHz");
        check(ns_to_cycles(W25.t_reset_ns,   HZ_200M) = 6_000,     "W25Q tRST at 200 MHz");
        check(ns_to_cycles(W25.t_powerup_ns, HZ_200M) = 1_000_000, "W25Q tPUW at 200 MHz");
        check(ns_to_cycles(AS.t_cs_rd_ns,    HZ_200M) = 4,         "AS tCS1 at 200 MHz");
        check(ns_to_cycles(AS.t_cs_wr_ns,    HZ_200M) = 120,       "AS tCS3 at 200 MHz");
        check(ns_to_cycles(AS.t_powerup_ns,  HZ_200M) = 5_000_000, "AS tPU at 200 MHz");
        -- They must fit qspi_xact's 8-bit CS# high count (+ 1 cycle) and qspi_init's 26-bit counter
        check(ns_to_cycles(AS.t_cs_wr_ns, HZ_200M) + 1 < 2 ** 8, "AS tCS3 + 1 must fit 8 bits");
        check(ns_to_cycles(AS.t_powerup_ns, HZ_200M) < 2 ** 26, "AS tPU must fit 26 bits");

        -- 2. Address widths from the device sizes
        check(clog2(W25.size_bytes) = 24, "W25Q size should need 24 address bits");
        check(clog2(AS.size_bytes) = 29, "AS size should need 29 address bits");

        -- 3. EBh overhead: W25Q 8 + 6 + 2 + 4 = 20, AS 8 + 8 + 2 + 8 = 26 (device_facts.md §1)
        check(read_overhead_clocks(DEV_W25Q128JV) = 20, "W25Q EBh overhead should be 20 clocks");
        check(read_overhead_clocks(DEV_AS308G208) = 26, "AS EBh overhead should be 26 clocks");

        -- 4. ID matching
        check(id_ok(DEV_W25Q128JV, x"EF4018FF"),     "W25Q: EF 40 18 should match");
        check(id_ok(DEV_W25Q128JV, x"EF401800"),     "W25Q: 4th byte must be ignored");
        check(not id_ok(DEV_W25Q128JV, x"EF7018FF"), "W25Q: EF 70 18 (-IM) must not match");
        check(not id_ok(DEV_W25Q128JV, x"FFFFFFFF"), "W25Q: FF FF FF (no device) must not match");
        check(id_ok(DEV_AS308G208, x"E6212C01"),     "AS: density 8 Gb should match");
        check(id_ok(DEV_AS308G208, x"E6212A01"),     "AS: density 4 Gb should match");
        check(not id_ok(DEV_AS308G208, x"E6212801"), "AS: density 1 Gb must not match");
        check(not id_ok(DEV_AS308G208, x"E6212C02"), "AS: wrong frequency code must not match");
        check(not id_ok(DEV_AS308G208, x"EF4018FF"), "AS: W25Q ID must not match");

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        wait;
    end process;
end architecture sim;
