-- Test block producer for spi_tx_path using one bfic_producer with fixed inputs
--
--   start_in (e.g. a debounced button pulse) --> one BFIC block on m_* (valid/ready)
--
--   A start pulse opens a gate (pending) that passes exactly one block from bfic_producer to
--   m_*: m_valid = pending and producer valid, and the producer only sees m_ready while pending.
--   After the handshake the gate closes and bfic_producer moves to the next beam
--   (0, 1, 2, 3, 0, ...). A start pulse while a block is pending is ignored.
--   BFIC address 1, inputs: tau_y = 1/3/5/7, delta_tau_x = 3, calib_tau = 1,
--   calib_attenuation = 2, tapering_attenuation = 3.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.custom_types_pkg.all;

entity bfic_block_producer is
    port (
        clk      : in  std_logic;
        reset_n  : in  std_logic;            -- Synchronous, active low
        start_in : in  std_logic;            -- One-cycle pulse sends one block

        -- Blocks out
        m_data   : out std_logic_vector(79 downto 0);
        m_valid  : out std_logic;
        m_ready  : in  std_logic
    );
end entity bfic_block_producer;

architecture rtl of bfic_block_producer is

    signal pending    : std_logic := '0';   -- A start pulse is waiting for its block to be accepted
    signal prod_valid : std_logic;
    signal prod_ready : std_logic;

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
                pending <= '0';
            elsif pending = '1' then
                if prod_valid = '1' and m_ready = '1' then
                    -- Downstream has accepted the block: close the gate
                    pending <= '0';
                end if;
            elsif start_in = '1' then
                pending <= '1';
            end if;
        end if;
    end process gate_proc;

    m_valid    <= pending and prod_valid;
    prod_ready <= pending and m_ready;

end architecture rtl;
