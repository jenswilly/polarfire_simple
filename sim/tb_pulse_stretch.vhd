-- Self-checking testbench for pulse_stretch
--   Sets STRETCH_CYCLES = 125 (1 us at 125 MHz) instead of the design default (125_000, 1 ms),
--   which keeps the simulation short. The checks scale with STRETCH.
--   pulse_in is driven right after a clock edge, like the output of a flip-flop.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;

entity tb_pulse_stretch is
end entity tb_pulse_stretch;

architecture sim of tb_pulse_stretch is
    constant CLK_PERIOD : time     := 8 ns;   -- 125 MHz
    constant STRETCH    : positive := 125;    -- STRETCH_CYCLES for the DUT

    signal clk       : std_logic := '0';
    signal rstn      : std_logic := '0';
    signal pulse_in  : std_logic := '0';
    signal pulse_out : std_logic;

    signal rise_time  : time    := 0 ns;   -- Time of the last rising edge of pulse_out
    signal high_time  : time    := 0 ns;   -- Length of the last completed high period
    signal high_count : natural := 0;      -- Number of completed high periods
    signal done       : boolean := false;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.pulse_stretch
        generic map (STRETCH_CYCLES => STRETCH)
        port map (clk => clk, reset_n => rstn, pulse_in => pulse_in, pulse_out => pulse_out);

    monitor : process (pulse_out)
    begin
        if rising_edge(pulse_out) then
            rise_time <= now;
        elsif falling_edge(pulse_out) then
            high_time  <= now - rise_time;
            high_count <= high_count + 1;
        end if;
    end process;

    stim : process
        variable errors : natural := 0;
        variable t_in   : time;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errors := errors + 1;
                report "CHECK FAILED: " & msg severity error;
            end if;
        end procedure;

        procedure clocks(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- Drive pulse_in high for n clock cycles
        procedure pulse(n : positive) is
        begin
            pulse_in <= '1';
            clocks(n);
            pulse_in <= '0';
        end procedure;
    begin
        clocks(3);
        rstn <= '1';

        -- 1. Idle after reset: output low
        clocks(10);
        check(pulse_out = '0' and high_count = 0, "idle: pulse_out should be low");

        -- 2. Single-cycle input: output goes high on the next edge and stays high exactly 1 us
        t_in := now;
        pulse(1);
        wait for 1 ns;   -- Let the output update after the edge
        check(pulse_out = '1', "pulse_out should be high one clock after pulse_in");
        check(rise_time - t_in = CLK_PERIOD, "pulse_out should rise 1 clock after pulse_in");
        clocks(STRETCH + 5);
        check(high_count = 1, "single pulse: expected 1 output pulse, got " & integer'image(high_count));
        check(high_time = STRETCH * CLK_PERIOD, "single pulse: expected high for " & time'image(STRETCH * CLK_PERIOD)
              & ", got " & time'image(high_time));

        -- 3. Retrigger 50 cycles into the stretch: one merged pulse of 50 + STRETCH cycles
        pulse(1);
        clocks(49);
        pulse(1);
        clocks(STRETCH + 5);
        check(high_count = 2, "retrigger: expected one merged pulse (2 in total), got " & integer'image(high_count));
        check(high_time = (50 + STRETCH) * CLK_PERIOD, "retrigger: expected high for "
              & time'image((50 + STRETCH) * CLK_PERIOD) & ", got " & time'image(high_time));

        -- 4. Multi-cycle input (3 cycles): high until STRETCH cycles after the last input cycle
        pulse(3);
        clocks(STRETCH + 5);
        check(high_count = 3, "long input: expected 3 pulses in total");
        check(high_time = (2 + STRETCH) * CLK_PERIOD, "long input: expected high for "
              & time'image((2 + STRETCH) * CLK_PERIOD) & ", got " & time'image(high_time));

        -- 5. Reset during a stretch: output goes low on the next edge
        pulse(1);
        clocks(20);
        rstn <= '0';
        clocks(1);
        wait for 1 ns;
        check(pulse_out = '0', "reset should clear pulse_out");
        rstn <= '1';
        clocks(STRETCH + 5);
        check(pulse_out = '0' and high_count = 4, "after reset: no further pulse");

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;
end architecture sim;
