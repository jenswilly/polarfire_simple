-- Single BFIC data producer module
--
--   inputs --> 10-byte register write block for the current beam on m_* (valid/ready)
--
--   The block for beam_index is registered from the inputs and offered on m_data with m_valid
--   high. m_data/m_valid stay stable until m_ready is high; on that handshake m_valid drops for
--   one cycle while the block for the next beam (0, 1, 2, 3, 0, ...) is registered. So each
--   accepted block advances the beam by one, at most one block every 2 clocks. The upper level
--   decides when a block is taken by driving m_ready. The inputs are sampled when a block is
--   registered (the cycle after reset or after a handshake).
--
--   Block layout (byte 0 = bits 79:72, sent first):
--     79:78  "00"             write operation
--     77:74  BFIC_ADDRESS     hardware address (A13:A10)
--     73:64  start register   0x100 + 8 * beam_index
--     63:0   8 bytes          delay(e), gain(e) for elements e = 0..3, each "00" & 6-bit value
--   with (channel c = 4 * beam_index + e, all sums wrap at 6 bits)
--     delay(e) = tau_y(beam) + calib_tau(c) + (BFIC_ELEMENT_OFFSET + e) * delta_tau_x(beam)
--     gain(e)  = calib_attenuation(c) + tapering_attenuation(e)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.custom_types_pkg.all;

entity bfic_producer is
    generic (
        BFIC_ADDRESS : std_logic_vector(3 downto 0);    -- Hardware address for the BFIC. These will be bits A13:A10 in the output data
        BFIC_ELEMENT_OFFSET : integer := 0              -- BFIC's first element index
    );
    port (
        tau_y : in beam_values_t;                    -- Calculated Y delay for entire slice
        delta_tau_x : in beam_values_t;              -- Calculated delta-X delay
        calib_tau : in channel_values_t;             -- Delay calibration values from LUT
        calib_attenuation : in channel_values_t;     -- Attenuation calibration values from LUT
        tapering_attenuation : in element_values_t;  -- Tapering attenuation values for each element

        clk : in std_logic;                          -- Clock
        reset_n : in std_logic;                      -- Synchronous reset signal for the module; active low

        -- Blocks out
        m_data   : out std_logic_vector(79 downto 0); -- 10 byte output data
        m_valid  : out std_logic;                     -- Indicates when the output data is valid
        m_ready  : in  std_logic                      -- Downstream accepts the block; advances to the next beam
    );
end entity bfic_producer;

architecture rtl of bfic_producer is

    signal beam_index : beam_index_t := 0; -- Beam of the offered (or next registered) block
    signal data_reg : std_logic_vector(73 downto 0);
    signal valid_r : std_logic := '0';

    -- Constant multiplies (BFIC_ELEMENT_OFFSET + e) * delta_tau_x: only 6 result bits, so build them
    -- from LUT/carry logic. Synplify otherwise maps them to MACC blocks, which limits fmax.
    attribute syn_multstyle : string;
    attribute syn_multstyle of rtl : architecture is "logic";

begin

    reg_proc : process (clk)
        variable delay : element_values_t;
        variable gain : element_values_t;
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                beam_index <= 0;
                valid_r <= '0';
            elsif valid_r = '1' then
                -- Block offered: wait for downstream to accept it, then move on to the next beam
                if m_ready = '1' then
                    valid_r <= '0';
                    if beam_index = 3 then
                        beam_index <= 0;
                    else
                        beam_index <= beam_index + 1;
                    end if;
                end if;
            else
                -- Register the block for beam_index
                -- Select starting register (bits 73 downto 64) based on beam_index
                case beam_index is
                    when 0 =>
                        data_reg(73 downto 64) <= 10x"100";
                    when 1 =>
                        data_reg(73 downto 64) <= 10x"108";
                    when 2 =>
                        data_reg(73 downto 64) <= 10x"110";
                    when 3 =>
                        data_reg(73 downto 64) <= 10x"118";
                end case;

                -- Set delay and attenuation values for the current beam
                for elem in 0 to 3 loop
                    delay(elem) := tau_y(beam_index) + calib_tau(beam_index * 4 + elem) + resize((BFIC_ELEMENT_OFFSET + elem) * delta_tau_x(beam_index), 6);
                    gain(elem)  := calib_attenuation(beam_index * 4 + elem) + tapering_attenuation(elem);
                end loop;
         
                -- Concatenate delay and attenuation values into the data register. Prefix each value with two 0 bits to expand to full bytes
                data_reg(63 downto 0) <= "00" & std_logic_vector(delay(0)) &
                                         "00" & std_logic_vector(gain(0)) &
                                         "00" & std_logic_vector(delay(1)) &
                                         "00" & std_logic_vector(gain(1)) &
                                         "00" & std_logic_vector(delay(2)) &
                                         "00" & std_logic_vector(gain(2)) &
                                         "00" & std_logic_vector(delay(3)) &
                                         "00" & std_logic_vector(gain(3));

                valid_r <= '1';
            end if;
        end if;
    end process reg_proc;

    m_valid <= valid_r;
    m_data <= "00" &            -- Fixed header bits for write operation
              BFIC_ADDRESS &    -- Hardware address for the BFIC
              data_reg;         -- Start register and register values

end architecture rtl;
