-- Self-checking testbench for mss_qspi_pads
--   Checks that every pin follows its MSS output enable (driven value or 'Z'), that the pins
--   read back on mss_qspi_data_i, and that a value driven by the "flash" (external driver on
--   qspi_io while the MSS releases the pins) reaches mss_qspi_data_i. Weak pull-ups ('H') on
--   CS# and IO2/IO3 model io.pdc and the click board.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;

entity tb_mss_qspi_pads is
end entity tb_mss_qspi_pads;

architecture sim of tb_mss_qspi_pads is
    signal clk_o, clk_oe   : std_logic := '0';
    signal sel_o, sel_oe   : std_logic := '0';
    signal data_o, data_oe : std_logic_vector(3 downto 0) := (others => '0');
    signal data_i          : std_logic_vector(3 downto 0);

    signal qspi_sclk, qspi_cs_n : std_logic;
    signal qspi_io              : std_logic_vector(3 downto 0);
    signal flash_io             : std_logic_vector(3 downto 0) := (others => 'Z');  -- External driver
begin
    dut : entity work.mss_qspi_pads
        port map (
            mss_qspi_clk => clk_o, mss_qspi_clk_oe => clk_oe,
            mss_qspi_sel => sel_o, mss_qspi_sel_oe => sel_oe,
            mss_qspi_data_o => data_o, mss_qspi_data_oe => data_oe, mss_qspi_data_i => data_i,
            qspi_sclk => qspi_sclk, qspi_cs_n => qspi_cs_n, qspi_io => qspi_io);

    -- Board: pull-up on CS# (io.pdc), 4.7 k pull-ups on IO2/IO3 (click board), flash drivers
    qspi_cs_n  <= 'H';
    qspi_io(3) <= 'H';
    qspi_io(2) <= 'H';
    qspi_io    <= flash_io;

    stim : process
        variable errors : natural := 0;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errors := errors + 1;
                report "CHECK FAILED: " & msg severity error;
            end if;
        end procedure;
    begin
        -- All enables low: pins released, pull-ups win
        wait for 10 ns;
        check(qspi_sclk = 'Z', "SCLK released when CLK_OE = 0");
        check(to_x01(qspi_cs_n) = '1', "CS# pulled high when SEL_OE = 0");
        check(qspi_io(0) = 'Z' and qspi_io(1) = 'Z', "IO1:0 released when DATA_OE = 0");
        check(to_x01(qspi_io(3 downto 2)) = "11", "IO3:2 pulled high when DATA_OE = 0");

        -- Clock and select follow their values when enabled
        clk_oe <= '1'; sel_oe <= '1';
        for v in std_logic range '0' to '1' loop
            clk_o <= v; sel_o <= v;
            wait for 10 ns;
            check(qspi_sclk = v, "SCLK = QSPI_CLK_M2F when enabled");
            check(to_x01(qspi_cs_n) = v, "CS# = QSPI_SEL_M2F when enabled");
        end loop;

        -- Each data pin separately: driven, read back; the others stay released
        for i in 0 to 3 loop
            data_oe <= (others => '0');
            data_oe(i) <= '1';
            for v in std_logic range '0' to '1' loop
                data_o <= (others => not v);
                data_o(i) <= v;
                wait for 10 ns;
                check(qspi_io(i) = v, "IO" & integer'image(i) & " = DATA_M2F when enabled");
                check(to_x01(data_i(i)) = v, "DATA_F2M reads back IO" & integer'image(i));
                for j in 0 to 3 loop
                    if j /= i then
                        check(qspi_io(j) = 'Z' or qspi_io(j) = 'H',
                              "IO" & integer'image(j) & " released while only IO" & integer'image(i) & " enabled");
                    end if;
                end loop;
            end loop;
        end loop;

        -- Read direction: MSS releases all, flash drives patterns
        data_oe <= (others => '0');
        for p in 0 to 15 loop
            case p mod 4 is
                when 0 => flash_io <= "1010";
                when 1 => flash_io <= "0101";
                when 2 => flash_io <= "0000";
                when others => flash_io <= "1111";
            end case;
            wait for 10 ns;
            check(data_i = flash_io, "DATA_F2M = value driven by the flash");
        end loop;
        flash_io <= (others => 'Z');

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        wait;
    end process;
end architecture sim;
