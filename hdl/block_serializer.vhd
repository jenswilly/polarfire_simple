-- Block serializer: one BLOCK_BYTES-byte block in, BLOCK_BYTES AXI4-Stream bytes out
--
--   s_* (block, valid/ready) --> m_axis (bytes + tlast)
--
--   The most significant byte goes first: bits 79:72 for a 10-byte block, so bit 79 is
--   the first bit on MOSI when the SPI master runs MSB first. m_axis_tlast is set on the
--   last byte of every block.
--
--   A block is only accepted while no block is being sent (s_ready = not active), so there
--   is one idle clock between blocks. That keeps s_ready free of a combinational path from
--   m_axis_tready and costs nothing at SPI speed.

library ieee;
use ieee.std_logic_1164.all;

entity block_serializer is
    generic (
        BLOCK_BYTES : positive := 10
    );
    port (
        clk           : in  std_logic;
        reset_n       : in  std_logic;           -- Synchronous, active low

        -- Blocks in
        s_data        : in  std_logic_vector(BLOCK_BYTES * 8 - 1 downto 0);
        s_valid       : in  std_logic;
        s_ready       : out std_logic;

        -- Bytes out (AXI4-Stream initiator)
        m_axis_tdata  : out std_logic_vector(7 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;
        m_axis_tlast  : out std_logic
    );
end entity block_serializer;

architecture rtl of block_serializer is

    constant W : positive := BLOCK_BYTES * 8;

    signal shift  : std_logic_vector(W - 1 downto 0) := (others => '0');
    signal count  : natural range 0 to BLOCK_BYTES - 1 := 0;   -- Byte now on m_axis_tdata
    signal active : std_logic := '0';                          -- A block is being sent

begin

    ser_proc : process (clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                active <= '0';
                count  <= 0;
            elsif active = '0' then
                -- Not currently active
                if s_valid = '1' then
                    -- Upstream has valid data: grab data block and set active
                    shift  <= s_data;
                    count  <= 0;
                    active <= '1';
                end if;
            elsif m_axis_tready = '1' then
                -- Currently active and downstream is ready
                if count = BLOCK_BYTES - 1 then
                    -- Last byte has been sent, deactivate
                    active <= '0';
                else
                    -- Not the last byte, shift out the next byte and increment count
                    shift <= shift(W - 9 downto 0) & x"00";
                    count <= count + 1;
                end if;
            end if;
        end if;
    end process;

    -- Ready to accept from upstream when not currently active
    s_ready       <=   not active;

    m_axis_tdata  <= shift(W - 1 downto W - 8);
    m_axis_tvalid <= active;
    m_axis_tlast  <= '1' when count = BLOCK_BYTES - 1 else '0';

end architecture rtl;
