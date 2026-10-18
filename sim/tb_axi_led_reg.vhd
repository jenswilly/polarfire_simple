-- Self-checking testbench for axi_led_reg
--   Drives AXI4-Lite reads/writes and checks LED bits, the ID register and DEBUG_PULSE.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_axi_led_reg is
end entity tb_axi_led_reg;

architecture sim of tb_axi_led_reg is
    constant CLK_PERIOD : time := 8 ns;   -- 125 MHz, same as the fabric clock

    signal clk     : std_logic := '0';
    signal rstn    : std_logic := '0';
    signal awaddr  : std_logic_vector(37 downto 0) := (others => '0');
    signal araddr  : std_logic_vector(37 downto 0) := (others => '0');
    signal awvalid : std_logic := '0';
    signal wvalid  : std_logic := '0';
    signal bready  : std_logic := '0';
    signal arvalid : std_logic := '0';
    signal rready  : std_logic := '0';
    signal awready : std_logic;
    signal wready  : std_logic;
    signal bvalid  : std_logic;
    signal arready : std_logic;
    signal rvalid  : std_logic;
    signal wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal rdata   : std_logic_vector(31 downto 0);
    signal wstrb   : std_logic_vector(3 downto 0) := "1111";
    signal bresp   : std_logic_vector(1 downto 0);
    signal rresp   : std_logic_vector(1 downto 0);
    signal led2    : std_logic;
    signal led3    : std_logic;
    signal pulse   : std_logic;

    signal pulse_cycles : natural := 0;   -- total ACLK cycles with DEBUG_PULSE high
    signal done         : boolean := false;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.axi_led_reg
        port map (
            ACLK    => clk,     ARESETN => rstn,
            AWADDR  => awaddr,  AWPROT  => "000", AWVALID => awvalid, AWREADY => awready,
            WDATA   => wdata,   WSTRB   => wstrb, WVALID  => wvalid,  WREADY  => wready,
            BRESP   => bresp,   BVALID  => bvalid, BREADY => bready,
            ARADDR  => araddr,  ARPROT  => "000", ARVALID => arvalid, ARREADY => arready,
            RDATA   => rdata,   RRESP   => rresp, RVALID  => rvalid,  RREADY  => rready,
            LED2    => led2,    LED3    => led3,
            DEBUG_PULSE => pulse
        );

    count_pulse : process (clk)
    begin
        if rising_edge(clk) and pulse = '1' then
            pulse_cycles <= pulse_cycles + 1;
        end if;
    end process;

    stim : process
        variable errors : natural := 0;
        variable data   : std_logic_vector(31 downto 0);

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errors := errors + 1;
                report "CHECK FAILED: " & msg severity error;
            end if;
        end procedure;

        -- AXI4-Lite write; bready_delay holds off BREADY to model a slow initiator
        procedure axi_write(addr : natural; value : std_logic_vector(31 downto 0);
                            bready_delay : natural := 0) is
        begin
            awaddr  <= std_logic_vector(to_unsigned(addr, awaddr'length));
            wdata   <= value;
            awvalid <= '1';
            wvalid  <= '1';
            loop
                wait until rising_edge(clk);
                exit when awready = '1';
            end loop;
            awvalid <= '0';
            wvalid  <= '0';
            for i in 1 to bready_delay loop
                wait until rising_edge(clk);
            end loop;
            bready <= '1';
            loop
                wait until rising_edge(clk);
                exit when bvalid = '1';
            end loop;
            bready <= '0';
            check(bresp = "00", "BRESP not OKAY");
            -- let any pulse finish before the caller checks pulse_cycles
            for i in 1 to 3 loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        procedure axi_read(addr : natural; value : out std_logic_vector(31 downto 0)) is
        begin
            araddr  <= std_logic_vector(to_unsigned(addr, araddr'length));
            arvalid <= '1';
            loop
                wait until rising_edge(clk);
                exit when arready = '1';
            end loop;
            arvalid <= '0';
            rready  <= '1';
            loop
                wait until rising_edge(clk);
                exit when rvalid = '1';
            end loop;
            value  := rdata;
            rready <= '0';
            check(rresp = "00", "RRESP not OKAY");
        end procedure;
    begin
        wait for 4 * CLK_PERIOD;
        rstn <= '1';
        wait until rising_edge(clk);

        -- ID register
        axi_read(16#4#, data);
        check(data = x"1ED50001", "ID register should read 0x1ED50001");

        -- LED register write and readback
        axi_write(16#0#, x"00000003");
        check(led2 = '1' and led3 = '1', "LED2/LED3 should be on after writing 3");
        axi_read(16#0#, data);
        check(data = x"00000003", "LED register should read back 3");
        check(pulse_cycles = 0, "LED write must not pulse DEBUG_PULSE");

        -- DEBUG: writing 1 gives exactly one pulse cycle
        axi_write(16#8#, x"00000001");
        check(pulse_cycles = 1, "write 1 to DEBUG should give 1 pulse cycle, got " & integer'image(pulse_cycles));

        -- A slow BREADY must not stretch the pulse
        axi_write(16#8#, x"00000001", bready_delay => 5);
        check(pulse_cycles = 2, "slow BREADY: expected 2 pulse cycles in total, got " & integer'image(pulse_cycles));

        -- Writing 0 does nothing
        axi_write(16#8#, x"00000000");
        check(pulse_cycles = 2, "write 0 to DEBUG must not pulse");

        -- DEBUG write leaves the LEDs alone, and DEBUG reads as 0
        check(led2 = '1' and led3 = '1', "DEBUG write must not change the LEDs");
        axi_read(16#8#, data);
        check(data = x"00000000", "DEBUG register should read 0");

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;
end architecture sim;
