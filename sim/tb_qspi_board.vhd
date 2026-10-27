-- run_tb models: qspi_model_pkg qspi_mem_model
-- Self-checking testbench for qspi_board: the board wrapper with a W25Q128JV model on its pins
--   qspi_board (DEVICE_SEL 0, CALIBRATE 1, 2 blocks of 64 host bytes) drives the model directly
--   through its inout qspi_io pins (3 ns board delay). Uses the datasheet power-up time (5 ms
--   tPUW), so the run is mostly waiting. Checks: bist_pass comes on, bist_fail stays off, and the
--   model reports no protocol errors. Covers the tristate wiring and the generic mapping that
--   tb_qspi_bist does not.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use work.qspi_pkg.all;

entity tb_qspi_board is
end entity tb_qspi_board;

architecture sim of tb_qspi_board is
    constant CLK_PERIOD : time := 5 ns;      -- clk_ctrl 200 MHz, as in TOP

    signal clk       : std_logic := '0';
    signal rstn      : std_logic := '0';
    signal done      : boolean := false;
    signal qspi_sclk : std_logic;
    signal qspi_cs_n : std_logic;
    signal qspi_io   : std_logic_vector(3 downto 0);
    signal pass      : std_logic;
    signal fail      : std_logic;
    signal err_count : natural;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.qspi_board
        generic map (DEVICE_SEL => 0, CLK_HZ => 200_000_000, SCLK_DIV => 2, SAMPLE_DLY => 4,
                     CALIBRATE => 1, NBLK => 2, BLK_LEN => 64)
        port map (clk => clk, reset_n => rstn, qspi_sclk => qspi_sclk, qspi_cs_n => qspi_cs_n,
                  qspi_io => qspi_io, bist_pass => pass, bist_fail => fail);

    flash : entity work.qspi_mem_model
        generic map (DEVICE => DEV_W25Q128JV, DIE => 1, PRELOAD_SEED => 5, T_BOARD => 3 ns,
                     T_PP => 3 us, T_SE => 5 us)
        port map (sclk => qspi_sclk, cs_n => qspi_cs_n, io => qspi_io, err_count => err_count);

    process
        variable errors : natural := 0;
    begin
        wait for 50 ns;
        wait until rising_edge(clk);
        rstn <= '1';
        wait until pass = '1' or fail = '1' for 10 ms;
        if pass /= '1' or fail /= '0' then
            report "CHECK FAILED: bist_pass expected, got pass=" & std_logic'image(pass)
                   & " fail=" & std_logic'image(fail) severity error;
            errors := errors + 1;
        end if;
        wait for 200 us;
        if pass /= '1' or fail /= '0' then
            report "CHECK FAILED: should keep passing" severity error;
            errors := errors + 1;
        end if;
        if err_count /= 0 then
            report "CHECK FAILED: model protocol errors: " & integer'image(err_count) severity error;
            errors := errors + 1;
        end if;
        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;
end architecture sim;
