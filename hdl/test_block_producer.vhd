-- Test block producer for spi_tx_path
--
--   start_in (e.g. a debounced button pulse) --> BLOCKS_PER_PRESS blocks on m_* (valid/ready)
--
--   Every block is   <id>  <seq>  02 03 04 05 06 07 08 09   (byte 0 = bits 79:72, sent first),
--   where <id> is FIRST_BYTE (A5 by default; give each instance its own to tell them apart)
--   and <seq> counts blocks since reset and wraps at 255. The fixed bytes make the frames
--   easy to recognize on a logic analyser. A start pulse while blocks are still being sent
--   is ignored.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity test_block_producer is
    generic (
        BLOCKS_PER_PRESS : positive := 1;   -- Number of blocks to produce per start pulse
        FIRST_BYTE       : natural range 0 to 255 := 16#A5#   -- Byte 0 of every block (identifier)
    );
    port (
        clk      : in  std_logic;
        reset_n  : in  std_logic;            -- Synchronous, active low
        start_in : in  std_logic;            -- One-cycle pulse starts a burst

        -- Blocks out
        m_data   : out std_logic_vector(79 downto 0);
        m_valid  : out std_logic;
        m_ready  : in  std_logic
    );
end entity test_block_producer;

architecture rtl of test_block_producer is

    signal seq     : unsigned(7 downto 0) := (others => '0');
    signal left    : natural range 0 to BLOCKS_PER_PRESS := 0;   -- Blocks still to send
    signal valid_r : std_logic := '0';

begin

    prod_proc : process (clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                seq     <= (others => '0');
                left    <= 0;
                valid_r <= '0';
            elsif valid_r = '1' then
                -- Currently sending a block. Data is already on m_data
                if m_ready = '1' then
                    -- Downstream has accepted the block. If last, deassert valid_r
                    seq <= seq + 1;
                    if left = 1 then
                        valid_r <= '0';
                    end if;
                    left <= left - 1;
                end if;
            elsif start_in = '1' then
                -- Start of a new output burst
                left    <= BLOCKS_PER_PRESS;
                valid_r <= '1';
            end if;
        end if;
    end process;

    -- Only changes on a handshake, so it is stable while m_ready is low
    m_data  <= std_logic_vector(to_unsigned(FIRST_BYTE, 8)) & std_logic_vector(seq) & x"0203040506070809";
    m_valid <= valid_r;

end architecture rtl;
