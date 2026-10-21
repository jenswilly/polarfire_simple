-- Block arbiter: NUM_PORTS block producers share one block consumer (e.g. spi_tx_path)
--
--   s_* (NUM_PORTS x block, valid/ready) --> round-robin --> m_* (block, valid/ready)
--
--   One handshake on m_* moves exactly one block from exactly one producer, so blocks from
--   different producers never interleave. Only the selected producer sees s_ready; the
--   others hold their block until they are selected.
--
--   The search for the next producer starts after the one that was served last, so every
--   waiting producer is served within NUM_PORTS blocks. Once a block is offered on m_* and
--   m_ready is low, the selection is held until the handshake, so m_data and m_valid stay
--   stable even if other producers become valid in the meantime.
--
--   The mux is combinational (no extra latency): s_ready depends on s_valid and m_ready
--   within the same cycle, which valid/ready allows as long as no producer makes its valid
--   depend on its ready.
--
--   SmartDesign has no array ports, so the inputs are flattened: producer i uses
--   s_data((i + 1) * BLOCK_BYTES * 8 - 1 downto i * BLOCK_BYTES * 8), s_valid(i) and s_ready(i).
--   With 10-byte blocks: producer 0 = s_data(79 downto 0), producer 1 = s_data(159 downto 80).

library ieee;
use ieee.std_logic_1164.all;

entity block_arbiter is
    generic (
        NUM_PORTS   : positive := 2;
        BLOCK_BYTES : positive := 10
    );
    port (
        clk     : in  std_logic;
        reset_n : in  std_logic;            -- Synchronous, active low

        -- Blocks in, one slice per producer
        s_data  : in  std_logic_vector(NUM_PORTS * BLOCK_BYTES * 8 - 1 downto 0);
        s_valid : in  std_logic_vector(NUM_PORTS - 1 downto 0);
        s_ready : out std_logic_vector(NUM_PORTS - 1 downto 0);

        -- Blocks out
        m_data  : out std_logic_vector(BLOCK_BYTES * 8 - 1 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic
    );
end entity block_arbiter;

architecture rtl of block_arbiter is

    constant W : positive := BLOCK_BYTES * 8;

    subtype port_t is natural range 0 to NUM_PORTS - 1;

    signal last   : port_t    := NUM_PORTS - 1;   -- Served last; port 0 goes first after reset
    signal locked : std_logic := '0';             -- A block is offered and not yet taken
    signal held   : port_t    := 0;               -- The offered producer while locked

    signal sel    : port_t;                       -- Selected producer this cycle
    signal found  : std_logic;                    -- sel has a valid block

begin

    -- Round-robin search, starting after the producer that was served last
    sel_proc : process (all)
        variable p : port_t;
    begin
        sel   <= held;
        found <= '0';
        if locked = '1' then
            found <= s_valid(held);               -- Stays high until the handshake
        else
            p := last;
            for i in 1 to NUM_PORTS loop
                p := (p + 1) mod NUM_PORTS;
                if s_valid(p) = '1' then
                    sel   <= p;
                    found <= '1';
                    exit;
                end if;
            end loop;
        end if;
    end process;

    reg_proc : process (clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                last   <= NUM_PORTS - 1;
                locked <= '0';
                held   <= 0;
            elsif found = '1' then
                if m_ready = '1' then
                    last   <= sel;
                    locked <= '0';
                else
                    held   <= sel;
                    locked <= '1';
                end if;
            else
                locked <= '0';                    -- Only if a producer broke the rules and dropped valid
            end if;
        end if;
    end process;

    m_data  <= s_data((sel + 1) * W - 1 downto sel * W);
    m_valid <= found;

    ready_gen : for i in 0 to NUM_PORTS - 1 generate
        s_ready(i) <= m_ready when found = '1' and sel = i else '0';
    end generate;

end architecture rtl;
