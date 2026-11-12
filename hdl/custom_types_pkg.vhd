library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package custom_types_pkg is
    -- Define any types related to BFIC here
    type beam_values_t is array (0 to 3) of unsigned(5 downto 0);      -- Delay values. Index is beam index.
    type element_values_t is array (0 to 3) of unsigned(5 downto 0);   -- Element values. Index is element index.
    type channel_values_t is array (0 to 15) of unsigned(5 downto 0);  -- Channel values. Index is channel index. Can be either delay or gain.

    subtype beam_index_t is natural range 0 to 3; -- "Enum" for beam indices
end package custom_types_pkg;
