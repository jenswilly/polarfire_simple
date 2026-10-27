-- Self-checking testbench for axi_sys_ctrl
--   Drives AXI4-Lite reads/writes and checks LED bits, the ID register and DEBUG_PULSE.
--   The bus is 64 bits wide. axi_write/axi_read model a 32-bit access from FIC_0 through the
--   interconnect: data and strobes in the lane selected by address bit 2, the other lane filled with
--   junk and its strobes off. Reads check that both lanes carry the same value.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_axi_sys_ctrl is
end entity tb_axi_sys_ctrl;

architecture sim of tb_axi_sys_ctrl is
    constant CLK_PERIOD : time := 5 ns;   -- 200 MHz, same as the fabric clock

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
    signal wdata   : std_logic_vector(63 downto 0) := (others => '0');
    signal rdata   : std_logic_vector(63 downto 0);
    signal wstrb   : std_logic_vector(7 downto 0) := (others => '0');
    signal bresp   : std_logic_vector(1 downto 0);
    signal rresp   : std_logic_vector(1 downto 0);
    signal led2    : std_logic;
    signal led3    : std_logic;
    signal pulse   : std_logic;

    signal pulse_cycles : natural := 0;   -- Total ACLK cycles with DEBUG_PULSE high
    signal done         : boolean := false;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.axi_sys_ctrl
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

        -- 32-bit AXI4-Lite write on the 64-bit bus; bready_delay holds off BREADY to model a slow
        -- initiator. strb is the 4-bit strobe of the addressed lane; the other lane gets
        -- junk = not value with strobes off.
        procedure axi_write(addr : natural; value : std_logic_vector(31 downto 0);
                            bready_delay : natural := 0;
                            strb : std_logic_vector(3 downto 0) := "1111") is
        begin
            awaddr  <= std_logic_vector(to_unsigned(addr, awaddr'length));
            if (addr / 4) mod 2 = 1 then
                wdata <= value & not value;
                wstrb <= strb & "0000";
            else
                wdata <= not value & value;
                wstrb <= "0000" & strb;
            end if;
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
            -- Let any pulse finish before the caller checks pulse_cycles
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
            -- The initiator takes the lane selected by address bit 2; both must match
            if (addr / 4) mod 2 = 1 then
                value := rdata(63 downto 32);
            else
                value := rdata(31 downto 0);
            end if;
            check(rdata(63 downto 32) = rdata(31 downto 0), "RDATA lanes differ at offset " & integer'image(addr));
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

        -- The other lane must be ignored: lower-lane write of 1 with junk 0xFFFFFFFE in the upper lane
        axi_write(16#0#, x"00000001");
        check(led2 = '1' and led3 = '0', "LED write must use the lower lane only");
        -- Byte 0 strobe off: no effect
        axi_write(16#0#, x"00000003", strb => "1110");
        check(led2 = '1' and led3 = '0', "LED write with WSTRB byte 0 off must be ignored");
        -- Upper-lane offsets (0x4 ID, 0xC unused) don't write: lower-lane junk 0xFFFFFFFC
        -- (bits 1:0 = 00) and the 0x4/0xC decode must leave the LEDs alone
        axi_write(16#4#, x"00000003");
        axi_write(16#C#, x"00000003");
        check(led2 = '1' and led3 = '0', "writes to 0x4/0xC must not change the LEDs");
        axi_read(16#0#, data);
        check(data = x"00000001", "LED register should read back 1");
        -- Alias at 0x10 (only bits 3:2 decoded), lower lane
        axi_write(16#10#, x"00000003");
        check(led2 = '1' and led3 = '1', "LED write at alias 0x10 should set both LEDs");

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
