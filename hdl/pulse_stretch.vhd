-- Pulse stretcher
--   A high pulse_in (any length, synchronous to clk) makes pulse_out high for STRETCH_CYCLES
--   clk cycles, starting on the next clock edge (default 200_000 = 1 ms at 200 MHz).
--   A new pulse_in while pulse_out is high restarts the count, so close pulses merge.
--   pulse_out comes straight from a flip-flop, so it is glitch-free on a pin.

library ieee;
use ieee.std_logic_1164.all;

entity pulse_stretch is
    generic (
        STRETCH_CYCLES : positive := 200_000   -- Output length in clk cycles. Align with clock freq.
    );
    port (
        clk       : in  std_logic;
        reset_n   : in  std_logic;   -- Synchronous, active low
        pulse_in  : in  std_logic;   -- Short pulse (synchronous to clk)
        pulse_out : out std_logic    -- Stretched pulse
    );
end entity pulse_stretch;

architecture rtl of pulse_stretch is
    signal count       : natural range 0 to STRETCH_CYCLES - 1;
    signal pulse_out_i : std_logic;
begin
    stretch_proc : process (clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                count       <= 0;
                pulse_out_i <= '0';
            elsif pulse_in = '1' then
                -- (Re)start: high for STRETCH_CYCLES cycles from this edge
                count       <= STRETCH_CYCLES - 1;
                pulse_out_i <= '1';
            elsif count /= 0 then
                count <= count - 1;
            else
                pulse_out_i <= '0';
            end if;
        end if;
    end process;

    pulse_out <= pulse_out_i;
end architecture rtl;
