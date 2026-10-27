-- Push-button debouncer with a single-clock press pulse
--   btn_in is asynchronous; it goes through a 2-FF synchronizer first.
--   The debounced state changes only after the synchronized input has differed from it
--   for DEBOUNCE_CYCLES consecutive clocks (default 2_000_000 = 10 ms at 200 MHz).
--   pulse_out is high for exactly one clk cycle when a press is accepted. Releases give no pulse.
--   pressed_out is the debounced level ('1' = pressed, regardless of ACTIVE_LOW).
--   Latency: pulse_out goes high on the (DEBOUNCE_CYCLES + 2)th clock edge after the last bounce
--   (2 of those edges are the synchronizer).

library ieee;
use ieee.std_logic_1164.all;

entity button_debounce is
    generic (
        DEBOUNCE_CYCLES : positive := 2_000_000; -- Number of clock cycles to debounce. Align with clock freq.
        ACTIVE_LOW      : boolean  := true       -- True: btn_in = '0' means pressed
    );
    port (
        clk         : in  std_logic;
        reset_n     : in  std_logic;   -- Synchronous, active low
        btn_in      : in  std_logic;   -- Raw button input (asynchronous)
        pressed_out : out std_logic;   -- Debounced level
        pulse_out   : out std_logic    -- One clk cycle per accepted press
    );
end entity button_debounce;

architecture rtl of button_debounce is
    signal sync_ff : std_logic_vector(1 downto 0);
    signal btn_s   : std_logic;   -- Synchronized, '1' = pressed
    signal stable  : std_logic;
    signal count   : natural range 0 to DEBOUNCE_CYCLES - 1;
    signal pulse_out_i : std_logic;
begin
    -- 2-FF synchronizer (no reset, so it just follows the pin)
    sync_proc : process (clk)
    begin
        if rising_edge(clk) then
            sync_ff <= sync_ff(0) & btn_in;
        end if;
    end process;

    btn_s <= not sync_ff(1) when ACTIVE_LOW else sync_ff(1);

    debounce_proc : process (clk)
    begin
        if rising_edge(clk) then
            -- Default: the pulse lasts only one cycle
            pulse_out_i <= '0';
            if reset_n = '0' then
                stable <= '0';
                count  <= 0;
            elsif btn_s = stable then
                count <= 0;
            elsif count = DEBOUNCE_CYCLES - 1 then
                stable <= btn_s;
                count  <= 0;
                pulse_out_i <= btn_s;   -- Pulse on press only
            else
                count <= count + 1;
            end if;
        end if;
    end process;

    pressed_out <= stable;
    pulse_out   <= pulse_out_i;
end architecture rtl;
