-- Test block producer for spi_tx_path using five bfic_producer instances with fixed inputs
--
--   start_in (e.g. a debounced button pulse) --> N_BFIC * BEAMS_PER_BFIC BFIC blocks on m_* (valid/ready)
--
--   A start pulse opens a gate (valid_r) and selects producer 0 (current_bfic). Each producer in turn
--   sends BEAMS_PER_BFIC blocks: m_data/m_valid come from the selected producer (m_valid =
--   valid_r and its valid), and only that producer sees m_ready. Every handshake moves that
--   producer to its next beam (0, 1, 2, 3, 0, ...) and counts down left; after its last block
--   current_bfic moves to the next producer, and after the last block of the last producer the gate
--   closes. With the default of 4, each burst sends beams 0..3 of BFIC 1, then of BFIC 2, ... 5
--   (use a multiple of 4 to keep bursts aligned to beam 0). A start pulse during a burst is ignored.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.custom_types_pkg.all;

entity bfic_block_producer is
    generic (
        BEAMS_PER_BFIC : positive := 4;         -- Blocks per start pulse; 4 = all beams. Use a multiple of 4
        BFIC_AD3 : integer range 0 to 1 := 0    -- BFIC address bit 3
    );
    port (
        clk      : in  std_logic;
        reset_n  : in  std_logic;       -- Synchronous, active low
        start_in : in  std_logic;       -- One-cycle pulse sends a burst of BEAMS_PER_BFIC blocks

        -- Blocks out
        m_data   : out std_logic_vector(79 downto 0);
        m_valid  : out std_logic;
        m_ready  : in  std_logic
    );
end entity bfic_block_producer;

architecture rtl of bfic_block_producer is

    constant N_BFIC : positive := 5;                                        -- Number of bfic_producer instances
    constant BFIC_AD3_BIT : std_logic_vector(0 downto 0) := std_logic_vector(to_unsigned(BFIC_AD3, 1));

    signal left         : natural range 0 to BEAMS_PER_BFIC := 0; -- Blocks still to send
    signal current_bfic : natural range 0 to N_BFIC - 1 := 0;     -- Current BFIC producer
    signal prod_valid   : std_logic_vector(0 to N_BFIC - 1);
    signal prod_ready   : std_logic_vector(0 to N_BFIC - 1);
    signal valid_r      : std_logic := '0';                       -- Gate open: a burst is in progress

    type data_array_t is array (0 to N_BFIC - 1) of std_logic_vector(79 downto 0);
    signal data_r     : data_array_t;

begin

    bfic_producer_inst_0: entity work.bfic_producer
    generic map(
        BFIC_ADDRESS => BFIC_AD3_BIT & "001",
        BFIC_ELEMENT_OFFSET => 0
    )
    port map(
        tau_y => (6x"1", 6x"3", 6x"5", 6x"7"),
        delta_tau_x => (others => 6x"3"),
        calib_tau => (others => 6x"1"),
        calib_attenuation => (others => 6x"2"),
        tapering_attenuation => (others => 6x"3"),

        clk => clk,
        reset_n => reset_n,
        m_data => data_r(0),
        m_valid => prod_valid(0),
        m_ready => prod_ready(0)
    );

    bfic_producer_inst_1: entity work.bfic_producer
    generic map(
        BFIC_ADDRESS => BFIC_AD3_BIT & "010",
        BFIC_ELEMENT_OFFSET => 4
    )
    port map(
        tau_y => (6x"1", 6x"3", 6x"5", 6x"7"),
        delta_tau_x => (others => 6x"2"),
        calib_tau => (others => 6x"4"),
        calib_attenuation => (others => 6x"2"),
        tapering_attenuation => (others => 6x"3"),

        clk => clk,
        reset_n => reset_n,
        m_data => data_r(1),
        m_valid => prod_valid(1),
        m_ready => prod_ready(1)
    );
    
    bfic_producer_inst_2: entity work.bfic_producer
    generic map(
        BFIC_ADDRESS => BFIC_AD3_BIT & "011",
        BFIC_ELEMENT_OFFSET => 8
    )
    port map(
        tau_y => (6x"1", 6x"3", 6x"5", 6x"7"),
        delta_tau_x => (others => 6x"5"),
        calib_tau => (others => 6x"3"),
        calib_attenuation => (others => 6x"2"),
        tapering_attenuation => (others => 6x"3"),

        clk => clk,
        reset_n => reset_n,
        m_data => data_r(2),
        m_valid => prod_valid(2),
        m_ready => prod_ready(2)
    );

    bfic_producer_inst_3: entity work.bfic_producer
    generic map(
        BFIC_ADDRESS => BFIC_AD3_BIT & "100",
        BFIC_ELEMENT_OFFSET => 12
    )
    port map(
        tau_y => (6x"1", 6x"3", 6x"5", 6x"7"),
        delta_tau_x => (others => 6x"4"),
        calib_tau => (others => 6x"5"),
        calib_attenuation => (others => 6x"2"),
        tapering_attenuation => (others => 6x"3"),

        clk => clk,
        reset_n => reset_n,
        m_data => data_r(3),
        m_valid => prod_valid(3),
        m_ready => prod_ready(3)
    );

    bfic_producer_inst_4: entity work.bfic_producer
    generic map(
        BFIC_ADDRESS => BFIC_AD3_BIT & "101",
        BFIC_ELEMENT_OFFSET => 16
    )
    port map(
        tau_y => (6x"1", 6x"3", 6x"5", 6x"7"),
        delta_tau_x => (others => 6x"2"),
        calib_tau => (others => 6x"2"),
        calib_attenuation => (others => 6x"2"),
        tapering_attenuation => (others => 6x"3"),

        clk => clk,
        reset_n => reset_n,
        m_data => data_r(4),
        m_valid => prod_valid(4),
        m_ready => prod_ready(4)
    );

    gate_proc : process (clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                left    <= 0;
                current_bfic <= 0;
                valid_r <= '0';
            elsif valid_r = '1' then
                if prod_valid(current_bfic) = '1' and m_ready = '1' then   -- a block was accepted
                    left <= left - 1;

                    -- If this was the last block for the last BFIC, stop the valid signal
                    if left = 1 and current_bfic = N_BFIC - 1 then
                        valid_r <= '0';
                    end if;

                    -- Move to the next BFIC if this was the last block for the current one
                    if left = 1 and current_bfic < N_BFIC - 1 then
                        current_bfic <= current_bfic + 1;
                        left <= BEAMS_PER_BFIC;
                    end if;
                end if;  -- prod_valid and m_ready
            elsif start_in = '1' then
                -- Start of a new output burst
                left    <= BEAMS_PER_BFIC;
                current_bfic <= 0;
                valid_r <= '1';
            end if;
        end if;
    end process gate_proc;

    m_data     <= data_r(current_bfic);
    m_valid    <= valid_r and prod_valid(current_bfic);

    -- Only the current BFIC sees m_ready
    prod_ready_gen : for i in prod_ready'range generate
        prod_ready(i) <= valid_r and m_ready when i = current_bfic else '0';
    end generate prod_ready_gen;

end architecture rtl;
