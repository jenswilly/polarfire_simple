-- Self-checking testbench for button_debounce
--   Uses a short DEBOUNCE_CYCLES so the bounces stay short in simulation. The button changes
--   at times that aren't aligned to the clock, like a real asynchronous input.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;

entity tb_button_debounce is
end entity tb_button_debounce;

architecture sim of tb_button_debounce is
    constant CLK_PERIOD : time     := 5 ns;   -- 200 MHz
    constant DB_CYCLES  : positive := 20;
    constant DB_TIME    : time     := DB_CYCLES * CLK_PERIOD;

    signal clk     : std_logic := '0';
    signal rstn    : std_logic := '0';
    signal btn     : std_logic := '1';   -- Active low, released
    signal pressed : std_logic;
    signal pulse   : std_logic;

    signal pulse_count  : natural := 0;   -- Number of pulses
    signal pulse_cycles : natural := 0;   -- Total cycles with pulse_out high
    signal done         : boolean := false;
begin
    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.button_debounce
        generic map (DEBOUNCE_CYCLES => DB_CYCLES, ACTIVE_LOW => true)
        port map (clk => clk, reset_n => rstn, btn_in => btn, pressed_out => pressed, pulse_out => pulse);

    monitor : process (clk)
        variable prev : std_logic := '0';
    begin
        if rising_edge(clk) then
            if pulse = '1' then
                pulse_cycles <= pulse_cycles + 1;
                if prev = '0' then
                    pulse_count <= pulse_count + 1;
                end if;
            end if;
            prev := pulse;
        end if;
    end process;

    stim : process
        variable errors : natural := 0;
        variable t0      : time;
        variable latency : natural;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errors := errors + 1;
                report "CHECK FAILED: " & msg severity error;
            end if;
        end procedure;

        -- Bounce the button n times (each level held for 'width'), ending at 'final_level'
        procedure bounce(n : positive; width : time; final_level : std_logic) is
        begin
            for i in 1 to n loop
                btn <= final_level;
                wait for width;
                btn <= not final_level;
                wait for width;
            end loop;
            btn <= final_level;
        end procedure;
    begin
        wait for 3 * CLK_PERIOD + 1 ns;
        rstn <= '1';

        -- 1. Released and idle: nothing happens
        wait for 2 * DB_TIME;
        check(pulse_count = 0 and pressed = '0', "idle: no pulse, not pressed");

        -- 2. Short glitch while released (shorter than the debounce time): ignored
        btn <= '0';
        wait for DB_TIME / 2;
        btn <= '1';
        wait for 2 * DB_TIME;
        check(pulse_count = 0 and pressed = '0', "short glitch must be ignored");

        -- 3. Bouncy press, then held: exactly one single-cycle pulse, DB_CYCLES + 2 edges after
        --    the last bounce. The first edge comes less than a period after t0, so the
        --    measured time is DB_CYCLES + 1 whole periods.
        bounce(5, 37 ns, '0');
        t0 := now;
        wait until pulse = '1' for 3 * DB_TIME;
        latency := (now - t0) / CLK_PERIOD;
        check(latency = DB_CYCLES + 1, "press: expected pulse " & integer'image(DB_CYCLES + 1)
              & " whole periods after the last bounce, got " & integer'image(latency));
        wait for 3 * DB_TIME;
        check(pressed = '1', "press: PRESSED should be '1'");
        check(pulse_count = 1, "press: expected 1 pulse, got " & integer'image(pulse_count));
        check(pulse_cycles = 1, "press: pulse should be 1 cycle wide, got " & integer'image(pulse_cycles));

        -- 4. Holding the button gives no more pulses
        wait for 10 * DB_TIME;
        check(pulse_count = 1, "holding must not give more pulses");

        -- 5. Short glitch while pressed: ignored
        btn <= '1';
        wait for DB_TIME / 2;
        btn <= '0';
        wait for 2 * DB_TIME;
        check(pressed = '1' and pulse_count = 1, "glitch while pressed must be ignored");

        -- 6. Bouncy release: no pulse, PRESSED goes back to '0'
        bounce(4, 53 ns, '1');
        wait for 3 * DB_TIME;
        check(pressed = '0', "release: PRESSED should be '0'");
        check(pulse_count = 1, "release must not give a pulse");

        -- 7. Second press: second pulse
        bounce(3, 29 ns, '0');
        wait for 3 * DB_TIME;
        check(pulse_count = 2 and pulse_cycles = 2, "second press: expected 2 single-cycle pulses in total");
        btn <= '1';
        wait for 3 * DB_TIME;

        -- 8. Reset while pressed clears the state; holding through reset counts as a new press
        btn <= '0';
        wait for 3 * DB_TIME;
        check(pulse_count = 3, "third press: expected 3 pulses");
        rstn <= '0';
        wait for 2 * CLK_PERIOD;
        check(pressed = '0', "reset should clear PRESSED");
        rstn <= '1';
        wait for 3 * DB_TIME;
        check(pressed = '1' and pulse_count = 4, "button held through reset gives one pulse after reset");

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;
end architecture sim;
