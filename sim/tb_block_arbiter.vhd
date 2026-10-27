-- Self-checking testbench for block_arbiter
--   NUM_PORTS producers offer numbered blocks (port number, sequence number, filler) with
--   random gaps and hold each block until s_ready; a consumer with random m_ready checks
--   every block it takes. Checks:
--     - at most one s_ready is high, and only for a valid producer;
--     - a handshake on m_* is exactly one handshake on s_*, with that producer's block;
--     - every block of every producer arrives exactly once and in order;
--     - m_data/m_valid stay stable while m_ready is low;
--     - with all producers valid and m_ready high, they are served in turn 0, 1, ..., N-1;
--     - reset leaves m_valid low and port 0 is served first afterwards.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).
--
-- Other sizes, e.g.: sim/run_tb.sh tb_block_arbiter -gNUM_PORTS=1

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_block_arbiter is
    generic (
        NUM_PORTS : positive := 3;
        NBLOCKS   : positive := 300     -- Blocks per producer in the random phase
    );
end entity tb_block_arbiter;

architecture sim of tb_block_arbiter is

    constant BLOCK_BYTES : positive := 10;
    constant W           : positive := BLOCK_BYTES * 8;
    constant CLK_PERIOD  : time     := 5 ns;    -- 200 MHz, same as the fabric clock

    -- Block = port (8 b), sequence number (16 b), filler that depends on both
    function blk(p, seq : natural) return std_logic_vector is
        variable pv : unsigned(7 downto 0)  := to_unsigned(p, 8);
        variable sv : unsigned(15 downto 0) := to_unsigned(seq mod 65536, 16);
    begin
        return std_logic_vector(pv) & std_logic_vector(sv) & std_logic_vector(not sv)
             & std_logic_vector(sv xor x"A5A5") & x"5AC3" & std_logic_vector(pv);
    end function;

    type nat_array is array (0 to NUM_PORTS - 1) of natural;

    signal clk     : std_logic := '0';
    signal rstn    : std_logic := '0';
    signal s_data  : std_logic_vector(NUM_PORTS * W - 1 downto 0) := (others => '0');
    signal s_valid : std_logic_vector(NUM_PORTS - 1 downto 0)     := (others => '0');
    signal s_ready : std_logic_vector(NUM_PORTS - 1 downto 0);
    signal m_data  : std_logic_vector(W - 1 downto 0);
    signal m_valid : std_logic;
    signal m_ready : std_logic := '0';

    -- Set by the main process
    signal p_offer : real    := 0.0;      -- Chance per clock that an idle producer offers a block
    signal limit   : natural := 0;        -- Blocks per producer to offer (total since reset)
    signal sent    : nat_array;           -- Blocks taken from each producer (from the producers)
    signal done    : boolean := false;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.block_arbiter
        generic map (NUM_PORTS => NUM_PORTS, BLOCK_BYTES => BLOCK_BYTES)
        port map (clk => clk, reset_n => rstn,
                  s_data => s_data, s_valid => s_valid, s_ready => s_ready,
                  m_data => m_data, m_valid => m_valid, m_ready => m_ready);

    -- Producers: offer blocks blk(p, 0), blk(p, 1), ... and hold each one until s_ready
    prod_gen : for p in 0 to NUM_PORTS - 1 generate
        p_prod : process
            variable seed1 : positive := 7 + p;
            variable seed2 : positive := 31 * (p + 1);
            variable r     : real;
            variable seq   : natural := 0;
        begin
            wait until rising_edge(clk);
            if rstn = '0' then
                seq        := 0;
                s_valid(p) <= '0';
            else
                if s_valid(p) = '1' and s_ready(p) = '1' then
                    seq := seq + 1;
                    s_valid(p) <= '0';
                end if;
                uniform(seed1, seed2, r);
                if (s_valid(p) = '0' or s_ready(p) = '1') and seq < limit and r < p_offer then
                    s_data((p + 1) * W - 1 downto p * W) <= blk(p, seq);
                    s_valid(p) <= '1';
                end if;
            end if;
            sent(p) <= seq;
        end process;
    end generate;

    p_main : process
        variable errors       : natural := 0;
        variable got          : nat_array := (others => 0);   -- Blocks received per producer
        variable seed1, seed2 : positive := 5;
        variable r            : real;
        variable stalled      : boolean := false;
        variable prev_data    : std_logic_vector(W - 1 downto 0);
        variable nready, hs   : natural;
        variable hs_port      : natural;
        variable p            : natural;
        variable order        : natural;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errors := errors + 1;
                report "CHECK FAILED: " & msg & " at " & time'image(now) severity error;
            end if;
        end procedure;

        -- One clock as consumer: check the handshakes, then drive a random m_ready
        procedure step(p_rd : real) is
        begin
            wait until rising_edge(clk);
            if stalled and rstn = '1' then
                check(m_valid = '1' and m_data = prev_data, "m_* changed while stalled");
            end if;
            nready := 0;
            hs     := 0;
            for i in 0 to NUM_PORTS - 1 loop
                if s_ready(i) = '1' then
                    nready := nready + 1;
                    check(s_valid(i) = '1', "s_ready(" & integer'image(i) & ") without s_valid");
                    if s_valid(i) = '1' then
                        hs      := hs + 1;
                        hs_port := i;
                    end if;
                end if;
            end loop;
            check(nready <= 1, integer'image(nready) & " s_ready high");
            if m_valid = '1' and m_ready = '1' then
                check(hs = 1, "m_* handshake without exactly one s_* handshake");
                p := to_integer(unsigned(m_data(W - 1 downto W - 8)));
                if hs = 1 then
                    check(p = hs_port, "block from port " & integer'image(p)
                          & " but handshake on port " & integer'image(hs_port));
                end if;
                if p < NUM_PORTS then
                    check(m_data = blk(p, got(p)), "port " & integer'image(p) & ": expected block "
                          & integer'image(got(p)));
                    got(p) := got(p) + 1;
                else
                    check(false, "block with port number " & integer'image(p));
                end if;
            else
                check(hs = 0, "s_* handshake without m_* handshake");
            end if;
            stalled   := m_valid = '1' and m_ready = '0';
            prev_data := m_data;
            uniform(seed1, seed2, r);
            m_ready <= '1' when r < p_rd else '0';
        end procedure;

        procedure steps(n : natural; p_rd : real) is
        begin
            for i in 1 to n loop
                step(p_rd);
            end loop;
        end procedure;

        -- Run until every producer has sent `limit` blocks and the arbiter is empty
        procedure drain(name : string; p_rd : real) is
        begin
            for i in 1 to 200 * (NBLOCKS + 100) * NUM_PORTS loop
                step(p_rd);
                exit when sent = (0 to NUM_PORTS - 1 => limit) and s_valid = (s_valid'range => '0');
            end loop;
            steps(5, p_rd);
            check(m_valid = '0', name & ": m_valid still high");
            for i in 0 to NUM_PORTS - 1 loop
                check(got(i) = limit, name & ": port " & integer'image(i) & " got "
                      & integer'image(got(i)) & " blocks, expected " & integer'image(limit));
            end loop;
        end procedure;
    begin
        steps(10, 0.5);
        rstn <= '1';
        steps(5, 0.5);
        check(m_valid = '0', "m_valid high without a producer");

        -- 1. Random offers and random m_ready, light and heavy load
        p_offer <= 0.05;
        limit   <= NBLOCKS / 3;
        drain("light load", 0.7);
        p_offer <= 0.8;
        limit   <= NBLOCKS;
        drain("heavy load", 0.3);

        -- 2. Fairness: all producers keep a block ready, consumer always ready
        m_ready <= '0';
        p_offer <= 1.0;
        limit   <= NBLOCKS + 4 * NUM_PORTS;
        steps(3, 0.0);                             -- All producers are now valid
        check(s_valid = (s_valid'range => '1'), "fairness: not all producers valid");
        order   := to_integer(unsigned(m_data(W - 1 downto W - 8)));   -- Whoever is first
        m_ready <= '1';
        for i in 0 to 4 * NUM_PORTS - 1 loop
            wait for CLK_PERIOD / 4;               -- Let the arbiter settle after the edge
            check(to_integer(unsigned(m_data(W - 1 downto W - 8))) = (order + i) mod NUM_PORTS,
                  "fairness: block " & integer'image(i) & " from port "
                  & integer'image(to_integer(unsigned(m_data(W - 1 downto W - 8)))));
            step(1.0);
        end loop;
        drain("fairness", 1.0);

        -- 3. Reset while blocks are waiting; port 0 goes first afterwards
        p_offer <= 1.0;
        limit   <= limit + 10;
        steps(3, 0.0);
        rstn <= '0';
        steps(2, 0.0);
        rstn <= '1';
        p_offer <= 0.0;
        wait until rising_edge(clk);
        check(m_valid = '0', "reset: m_valid high after the reset");
        got     := (others => 0);
        limit   <= 5;
        p_offer <= 1.0;
        m_ready <= '0';
        steps(3, 0.0);
        wait for CLK_PERIOD / 4;
        check(m_valid = '1' and to_integer(unsigned(m_data(W - 1 downto W - 8))) = 0,
              "reset: port 0 not first");
        drain("after reset", 0.5);

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture sim;
