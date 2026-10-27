-- Self-checking testbench for block_serializer
--   One process drives both sides cycle by cycle. Every byte on m_axis is checked against
--   the expected block (most significant byte first) and tlast must be set exactly on the
--   last byte of each block. While m_axis_tvalid is high and m_axis_tready low, tdata, tlast
--   and tvalid must stay stable (AXI4-Stream rule). Phases:
--     1. Random valid/ready stalls on both sides.
--     2. Throughput with valid and ready always high: BLOCK_BYTES + 1 clocks per block.
--     3. Reset in the middle of a block: m_axis_tvalid must drop and the next block must
--        start from its first byte.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).
--
-- Generics can be overridden from the command line, e.g.
--   sim/run_tb.sh tb_block_serializer -gBLOCK_BYTES=1

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_block_serializer is
    generic (
        BLOCK_BYTES : positive := 10;
        NBLOCKS     : positive := 500    -- Blocks in the random phase
    );
end entity tb_block_serializer;

architecture sim of tb_block_serializer is

    constant W          : positive := BLOCK_BYTES * 8;
    constant CLK_PERIOD : time     := 5 ns;    -- 200 MHz, same as the fabric clock

    -- Byte j (0 = sent first) of block i
    function byte_of(i, j : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(((i * BLOCK_BYTES + j) * 7 + 3) mod 256, 8));
    end function;

    -- Block i with byte 0 in the most significant position
    function blk(i : natural) return std_logic_vector is
        variable v : std_logic_vector(W - 1 downto 0);
    begin
        for j in 0 to BLOCK_BYTES - 1 loop
            v(W - 1 - 8 * j downto W - 8 - 8 * j) := byte_of(i, j);
        end loop;
        return v;
    end function;

    signal clk      : std_logic := '0';
    signal rstn     : std_logic := '0';

    signal s_data   : std_logic_vector(W - 1 downto 0) := (others => '0');
    signal s_valid  : std_logic := '0';
    signal s_ready  : std_logic;
    signal m_tdata  : std_logic_vector(7 downto 0);
    signal m_tvalid : std_logic;
    signal m_tready : std_logic := '0';
    signal m_tlast  : std_logic;

    signal done     : boolean := false;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.block_serializer
        generic map (BLOCK_BYTES => BLOCK_BYTES)
        port map (
            clk => clk, reset_n => rstn,
            s_data => s_data, s_valid => s_valid, s_ready => s_ready,
            m_axis_tdata => m_tdata, m_axis_tvalid => m_tvalid,
            m_axis_tready => m_tready, m_axis_tlast => m_tlast);

    p_main : process
        variable errors       : natural := 0;
        variable wr_i         : natural := 0;     -- Blocks accepted so far
        variable rd_i, rd_j   : natural := 0;     -- Block and byte expected next on m_axis
        variable seed1, seed2 : positive := 9;
        variable r            : real;
        variable cycles       : natural;
        -- Previous cycle, for the stability check
        variable stalled      : boolean := false;
        variable prev_data    : std_logic_vector(7 downto 0);
        variable prev_last    : std_logic;

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
        -- Blocks stop at wr_target. p_wr / p_rd: probability of offering a block / of tready.
        procedure step(wr_target : natural; p_wr, p_rd : real) is
            variable wr_ok : boolean;
        begin
            wait until rising_edge(clk);
            if stalled then
                check(m_tvalid = '1' and m_tdata = prev_data and m_tlast = prev_last,
                      "m_axis changed while stalled (block " & integer'image(rd_i) & ")");
            end if;
            if m_tvalid = '1' then
                check(rd_i < wr_i, "m_axis_tvalid with no block accepted");
                if m_tready = '1' then
                    check(m_tdata = byte_of(rd_i, rd_j), "data mismatch at block "
                          & integer'image(rd_i) & " byte " & integer'image(rd_j));
                    check((m_tlast = '1') = (rd_j = BLOCK_BYTES - 1),
                          "tlast wrong at block " & integer'image(rd_i) & " byte " & integer'image(rd_j));
                    if rd_j = BLOCK_BYTES - 1 then
                        rd_i := rd_i + 1;
                        rd_j := 0;
                    else
                        rd_j := rd_j + 1;
                    end if;
                end if;
            end if;
            stalled   := m_tvalid = '1' and m_tready = '0';
            prev_data := m_tdata;
            prev_last := m_tlast;

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
            m_tready <= '1' when r < p_rd else '0';
        end procedure;

        -- Run step() until block rd_target has been read, with a timeout
        procedure run(n : natural; p_wr, p_rd : real; name : string) is
            constant target : natural := rd_i + n;
        begin
            cycles := 0;
            while rd_i < target loop
                step(wr_i + (target - rd_i), p_wr, p_rd);
                cycles := cycles + 1;
                if cycles > 100 * BLOCK_BYTES * (n + 10) then
                    check(false, name & ": timeout");
                    exit;
                end if;
            end loop;
            s_valid <= '0';
            m_tready <= '0';
        end procedure;
    begin
        clocks(10);
        rstn <= '1';
        clocks(5);
        check(m_tvalid = '0' and s_ready = '1', "not idle after reset");

        -- 1. Random stalls on both sides
        run(NBLOCKS, 0.5, 0.6, "random");
        clocks(5);
        check(m_tvalid = '0' and s_ready = '1', "random: not idle afterwards");

        -- 2. Throughput: valid and ready always high
        run(100, 1.0, 1.0, "throughput");
        report "Throughput: 100 blocks in " & integer'image(cycles) & " clocks";
        check(cycles <= 100 * (BLOCK_BYTES + 1) + 3, "throughput: " & integer'image(cycles)
              & " clocks for 100 blocks");

        -- 3. Reset in the middle of a block (not possible with 1-byte blocks: no "middle")
        if BLOCK_BYTES > 1 then
            step(wr_i + 1, 1.0, 0.0);              -- Offer one block
            step(wr_i, 0.0, 1.0);                  -- Accepted at this edge
            step(wr_i, 0.0, 1.0);                  -- Byte 0 out
            stalled := false;
            rstn <= '0';
            clocks(2);
            rstn <= '1';
            wait for 1 ns;
            check(m_tvalid = '0' and s_ready = '1', "reset test: not idle after the reset");
            rd_i := wr_i;                          -- The interrupted block is dropped
            rd_j := 0;
            run(5, 1.0, 1.0, "after reset");
        end if;

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture sim;
