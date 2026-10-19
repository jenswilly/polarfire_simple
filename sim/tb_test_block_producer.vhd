-- Self-checking testbench for test_block_producer
--   A consumer with random m_ready accepts blocks and checks their content (A5, sequence
--   number, 02..09) and that m_data/m_valid stay stable while m_ready is low. Checks:
--     - each start pulse gives exactly BLOCKS_PER_PRESS blocks, then m_valid goes low;
--     - a start pulse during a burst is ignored;
--     - the sequence number continues across bursts and wraps from FF to 00;
--     - reset during a burst stops it and restarts the sequence at 00.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_test_block_producer is
    generic (
        BLOCKS_PER_PRESS : positive := 3
    );
end entity tb_test_block_producer;

architecture sim of tb_test_block_producer is

    constant CLK_PERIOD : time := 8 ns;    -- 125 MHz, same as the fabric clock

    function blk(seq : natural) return std_logic_vector is
    begin
        return x"A5" & std_logic_vector(to_unsigned(seq mod 256, 8)) & x"0203040506070809";
    end function;

    signal clk     : std_logic := '0';
    signal rstn    : std_logic := '0';
    signal start   : std_logic := '0';
    signal m_data  : std_logic_vector(79 downto 0);
    signal m_valid : std_logic;
    signal m_ready : std_logic := '0';

    signal done    : boolean := false;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.test_block_producer
        generic map (BLOCKS_PER_PRESS => BLOCKS_PER_PRESS)
        port map (clk => clk, reset_n => rstn, start_in => start,
                  m_data => m_data, m_valid => m_valid, m_ready => m_ready);

    p_main : process
        variable errors       : natural := 0;
        variable got          : natural := 0;     -- Blocks accepted since the last reset
        variable seed1, seed2 : positive := 21;
        variable r            : real;
        variable stalled      : boolean := false;
        variable prev_data    : std_logic_vector(79 downto 0);

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errors := errors + 1;
                report "CHECK FAILED: " & msg severity error;
            end if;
        end procedure;

        -- One clock as consumer: sample the handshake, then drive a random m_ready
        procedure step(p_rd : real) is
        begin
            wait until rising_edge(clk);
            if stalled and rstn = '1' then         -- A reset may drop m_valid
                check(m_valid = '1' and m_data = prev_data, "m_* changed while stalled at "
                      & time'image(now));
            end if;
            if m_valid = '1' and m_ready = '1' then
                check(m_data = blk(got), "block " & integer'image(got) & " wrong content");
                got := got + 1;
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

        -- One start pulse, driven during the next clock
        procedure press is
        begin
            start <= '1';
            step(0.5);
            start <= '0';
        end procedure;

        -- Press and consume until the burst is over
        procedure burst(name : string) is
            constant first : natural := got;
        begin
            press;
            for i in 1 to 100 * BLOCKS_PER_PRESS loop
                step(0.5);
                exit when m_valid = '0';
            end loop;
            steps(5, 0.5);
            check(m_valid = '0', name & ": m_valid still high");
            check(got - first = BLOCKS_PER_PRESS, name & ": " & integer'image(got - first)
                  & " blocks, expected " & integer'image(BLOCKS_PER_PRESS));
        end procedure;
    begin
        steps(10, 0.5);
        rstn <= '1';
        steps(5, 0.5);
        check(m_valid = '0', "m_valid high without a start pulse");

        burst("first burst");
        burst("second burst");

        -- Start pulse during a burst: ignored
        if BLOCKS_PER_PRESS > 1 then
            press;
            m_ready <= '0';
            steps(3, 0.0);
            check(m_valid = '1', "extra press: burst did not start");
            press;                                  -- Ignored
            for i in 1 to 100 * BLOCKS_PER_PRESS loop
                step(0.5);
                exit when m_valid = '0';
            end loop;
            steps(5, 0.5);
            check(got = 3 * BLOCKS_PER_PRESS, "extra press: " & integer'image(got)
                  & " blocks in total, expected " & integer'image(3 * BLOCKS_PER_PRESS));
        end if;

        -- Sequence wrap: run past 256 blocks
        while got < 260 loop
            burst("wrap burst");
        end loop;

        -- Reset during a burst
        press;
        m_ready <= '0';
        steps(3, 0.0);
        rstn <= '0';
        steps(2, 0.0);
        rstn <= '1';
        steps(5, 0.5);
        check(m_valid = '0', "reset: m_valid still high after the reset");
        got := 0;
        burst("after reset");

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture sim;
