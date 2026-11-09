-- Test block producer for spi_tx_path using one bfic_producer with fixed inputs
--
--   start_in (e.g. a debounced button pulse) --> BLOCKS_PER_PRESS BFIC blocks on m_* (valid/ready)
--
--   A start pulse opens a gate (valid_r) that passes BLOCKS_PER_PRESS blocks from bfic_producer
--   to m_*: m_valid = valid_r and producer valid, and the producer only sees m_ready while the
--   gate is open. Every handshake moves bfic_producer to the next beam (0, 1, 2, 3, 0, ...) and
--   counts down left; after the last block the gate closes. With the default of 4, each burst
--   sends beams 0..3 in order (use a multiple of 4 to keep bursts aligned to beam 0).
--   A start pulse during a burst is ignored.
--   BFIC address 1, inputs: tau_y = 1/3/5/7, delta_tau_x = 3, calib_tau = 1,
--   calib_attenuation = 2, tapering_attenuation = 3.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.custom_types_pkg.all;

entity bfic_block_producer is
    generic (
        BLOCKS_PER_PRESS : positive := 4   -- Blocks per start pulse; 4 = all beams. Use a multiple of 4
    );
    port (
        clk      : in  std_logic;
        reset_n  : in  std_logic;            -- Synchronous, active low
        start_in : in  std_logic;            -- One-cycle pulse sends a burst of BLOCKS_PER_PRESS blocks

        -- Blocks out
        m_data   : out std_logic_vector(79 downto 0);
        m_valid  : out std_logic;
        m_ready  : in  std_logic
    );
end entity bfic_block_producer;

architecture rtl of bfic_block_producer is

    signal left       : natural range 0 to BLOCKS_PER_PRESS := 0;   -- Blocks still to send
    signal prod_valid : std_logic;
    signal prod_ready : std_logic;
    signal valid_r    : std_logic := '0';                           -- Gate open: a burst is in progress

begin

    bfic_producer_inst_0: entity work.bfic_producer
     generic map(
        BFIC_ADDRESS => "0001"
    )
     port map(
        tau_y => (6x"1", 6x"3", 6x"5", 6x"7"),
        delta_tau_x => (others => 6x"3"),
        calib_tau => (others => 6x"1"),
        calib_attenuation => (others => 6x"2"),
        tapering_attenuation => (others => 6x"3"),

        clk => clk,
        reset_n => reset_n,
        m_data => m_data,
        m_valid => prod_valid,
        m_ready => prod_ready
    );

    gate_proc : process (clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                left    <= 0;
                valid_r <= '0';
            elsif valid_r = '1' then
                if prod_valid = '1' and m_ready = '1' then   -- a block was accepted
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
    end process gate_proc;

    m_valid    <= valid_r and prod_valid;
    prod_ready <= valid_r and m_ready;

end architecture rtl;
