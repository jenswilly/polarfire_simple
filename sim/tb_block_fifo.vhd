-- Self-checking testbench for block_fifo (valid/ready wrapper around the CoreFIFO BLOCK_FIFO_CORE)
--   One process drives both sides cycle by cycle and checks every block read against the
--   write sequence (order and all 80 bits), and that m_valid never shows a block that was not
--   written. Phases:
--     1. Fill with m_ready low until s_ready drops; the capacity must be at least DEPTH.
--        Then drain completely.
--     2. FWFT: a block written into the empty FIFO appears on m_data with m_valid, without a
--        read, and stays stable while m_ready is low.
--     3. Random valid/ready stalls on both sides.
--     4. Throughput with valid and ready always high: one block per clock.
--     5. Reset with blocks in the FIFO: it must be empty afterwards and work again.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).
--
-- run_tb cores: BLOCK_FIFO_CORE

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_block_fifo is
    generic (
        DEPTH   : positive := 512;      -- Configured CoreFIFO depth
        NRANDOM : positive := 3000      -- Blocks in the random phase
    );
end entity tb_block_fifo;

architecture sim of tb_block_fifo is

    constant BLOCK_BYTES : positive := 10;
    constant W           : positive := BLOCK_BYTES * 8;
    constant CLK_PERIOD  : time     := 5 ns;    -- 200 MHz, same as the fabric clock

    -- Block number i -> 80 bits: five 16-bit fields that all depend on i
    function blk(i : natural) return std_logic_vector is
        variable u : unsigned(15 downto 0) := to_unsigned(i mod 65536, 16);
    begin
        return std_logic_vector(u) & std_logic_vector(u xor x"A5A5") & std_logic_vector(not u)
             & std_logic_vector(resize(u * 3, 16)) & std_logic_vector(u xor x"1234");
    end function;

    signal clk     : std_logic := '0';
    signal rstn    : std_logic := '0';

    signal s_data  : std_logic_vector(W - 1 downto 0) := (others => '0');
    signal s_valid : std_logic := '0';
    signal s_ready : std_logic;
    signal m_data  : std_logic_vector(W - 1 downto 0);
    signal m_valid : std_logic;
    signal m_ready : std_logic := '0';

    signal done    : boolean := false;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.block_fifo
        generic map (BLOCK_BYTES => BLOCK_BYTES)
        port map (
            clk => clk, reset_n => rstn,
            s_data => s_data, s_valid => s_valid, s_ready => s_ready,
            m_data => m_data, m_valid => m_valid, m_ready => m_ready);

    p_main : process
        variable errors       : natural := 0;
        variable wr_i, rd_i   : natural := 0;     -- Blocks written / read so far
        variable seed1, seed2 : positive := 5;
        variable r            : real;
        variable cycles       : natural;
        variable cap          : natural;
        variable full_cycles  : natural;
        variable held         : std_logic_vector(W - 1 downto 0);

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errors := errors + 1;
                report "CHECK FAILED: " & msg severity error;
            end if;
        end procedure;

        procedure clocks(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- One clock: sample both handshakes (values before the edge), then drive the next cycle.
        -- Writes stop at wr_target. p_wr / p_rd: probability of offering a block / of ready.
        procedure step(wr_target : natural; p_wr, p_rd : real) is
            variable wr_ok : boolean;
        begin
            wait until rising_edge(clk);
            -- Read side first, against the write count before this edge
            if m_valid = '1' then
                check(rd_i < wr_i, "m_valid with no block written (rd " & integer'image(rd_i) & ")");
                if m_ready = '1' then
                    check(m_data = blk(rd_i), "data mismatch at block " & integer'image(rd_i));
                    rd_i := rd_i + 1;
                end if;
            end if;
            wr_ok := s_valid = '1' and s_ready = '1';
            if wr_ok then
                wr_i := wr_i + 1;
            end if;

            -- A valid block is held until it is accepted
            if s_valid = '0' or wr_ok then
                uniform(seed1, seed2, r);
                if wr_i < wr_target and r < p_wr then
                    s_valid <= '1';
                    s_data  <= blk(wr_i);
                else
                    s_valid <= '0';
                end if;
            end if;
            uniform(seed1, seed2, r);
            m_ready <= '1' when r < p_rd else '0';
        end procedure;

        -- Run step() until rd_i reaches rd_target, with a timeout
        procedure run(wr_target, rd_target : natural; p_wr, p_rd : real; name : string) is
        begin
            cycles := 0;
            while rd_i < rd_target loop
                step(wr_target, p_wr, p_rd);
                cycles := cycles + 1;
                if cycles > 100 * (rd_target + 100) then
                    check(false, name & ": timeout");
                    exit;
                end if;
            end loop;
            s_valid <= '0';
            m_ready <= '0';
        end procedure;
    begin
        clocks(10);
        rstn <= '1';
        clocks(10);
        check(m_valid = '0' and s_ready = '1', "not empty after reset");

        -- 1. Fill until s_ready stays low, then drain
        full_cycles := 0;
        cycles      := 0;
        while full_cycles < 20 and cycles < 4 * DEPTH loop
            step(integer'high, 1.0, 0.0);
            cycles := cycles + 1;
            if s_valid = '1' and s_ready = '0' then
                full_cycles := full_cycles + 1;
            else
                full_cycles := 0;
            end if;
        end loop;
        s_valid <= '0';
        cap := wr_i - rd_i;
        report "Capacity: " & integer'image(cap) & " blocks";
        check(full_cycles = 20, "fill: s_ready never stayed low");
        check(cap >= DEPTH, "fill: capacity " & integer'image(cap) & " < " & integer'image(DEPTH));
        run(wr_i, wr_i, 0.0, 1.0, "drain");
        clocks(5);
        check(m_valid = '0', "drain: m_valid still high");

        -- 2. FWFT: one block into the empty FIFO, no read
        step(wr_i + 1, 1.0, 0.0);
        cycles := 0;
        while m_valid = '0' and cycles < 20 loop
            step(wr_i, 0.0, 0.0);
            cycles := cycles + 1;
        end loop;
        report "FWFT latency: " & integer'image(cycles) & " clocks after the write cycle";
        check(m_valid = '1', "FWFT: block did not appear");
        check(m_data = blk(rd_i), "FWFT: wrong data before the read");
        held := m_data;
        for i in 1 to 20 loop
            step(wr_i, 0.0, 0.0);
            check(m_valid = '1' and m_data = held, "FWFT: output not stable while m_ready is low");
        end loop;
        run(wr_i, wr_i, 0.0, 1.0, "FWFT read");
        clocks(5);
        check(m_valid = '0', "FWFT: m_valid still high after the read");

        -- 3. Random stalls on both sides
        run(wr_i + NRANDOM, rd_i + NRANDOM, 0.6, 0.5, "random");

        -- 4. Throughput: valid and ready always high
        run(wr_i + 1000, rd_i + 1000, 1.0, 1.0, "throughput");
        report "Throughput: 1000 blocks in " & integer'image(cycles) & " clocks";
        check(cycles <= 1000 + 10, "throughput: " & integer'image(cycles) & " clocks for 1000 blocks");

        -- 5. Reset with 10 blocks in the FIFO
        for i in 1 to 10 loop
            step(wr_i + 1, 1.0, 0.0);
        end loop;
        s_valid <= '0';
        clocks(5);
        check(m_valid = '1', "reset test: FIFO empty before the reset");
        rstn <= '0';
        clocks(3);
        rstn <= '1';
        clocks(10);
        check(m_valid = '0' and s_ready = '1', "reset test: FIFO not empty after the reset");
        wr_i := rd_i;                       -- Blocks lost in the reset are no longer expected
        run(wr_i + 50, rd_i + 50, 0.8, 0.8, "after reset");

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture sim;
