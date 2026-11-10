-- Self-checking testbench for bfic_block_producer
--   A consumer with random m_ready accepts blocks and compares each with a reference model of
--   bfic_producer using the fixed inputs of the five instances (BFIC addresses 1..5). Checks:
--     - each start pulse gives BLOCKS_PER_PRESS blocks per BFIC, BFIC 1 first and 5 last, with
--       the beams 0, 1, 2, 3, 0, ... per BFIC, then m_valid goes low;
--     - m_data/m_valid stay stable while m_ready is low;
--     - a start pulse during a burst is ignored;
--     - reset during a burst stops it and the next burst starts again at BFIC 1, beam 0.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_bfic_block_producer is
    generic (
        BLOCKS_PER_PRESS : positive := 4
    );
end entity tb_bfic_block_producer;

architecture sim of tb_bfic_block_producer is

    constant CLK_PERIOD : time := 5 ns;    -- 200 MHz, same as the fabric clock
    constant N_BFIC     : positive := 5;

    -- Fixed inputs of the five instances (all values are the same for every beam/channel,
    -- except tau_y = 1/3/5/7)
    type nat_array_t is array (0 to N_BFIC - 1) of natural;
    constant DTX   : nat_array_t := (3, 2, 5, 4, 2);    -- delta_tau_x
    constant CTAU  : nat_array_t := (1, 4, 3, 5, 2);    -- calib_tau
    constant CATT  : natural := 2;                       -- calib_attenuation
    constant TAPER : natural := 3;                       -- tapering_attenuation
    type tau_y_t is array (0 to 3) of natural;
    constant TAU_Y : tau_y_t := (1, 3, 5, 7);

    -- Expected block of BFIC index k (address k + 1) for beam b
    function blk(k : natural; b : natural) return std_logic_vector is
        variable v : std_logic_vector(79 downto 0);
        variable d, g : natural;
    begin
        v(79 downto 78) := "00";
        v(77 downto 74) := std_logic_vector(to_unsigned(k + 1, 4));
        v(73 downto 64) := std_logic_vector(to_unsigned(16#100# + 8 * b, 10));
        for e in 0 to 3 loop
            d := (TAU_Y(b) + CTAU(k) + e * DTX(k)) mod 64;
            g := (CATT + TAPER) mod 64;
            v(63 - 16 * e downto 56 - 16 * e) := "00" & std_logic_vector(to_unsigned(d, 6));
            v(55 - 16 * e downto 48 - 16 * e) := "00" & std_logic_vector(to_unsigned(g, 6));
        end loop;
        return v;
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

    dut : entity work.bfic_block_producer
        generic map (BLOCKS_PER_PRESS => BLOCKS_PER_PRESS)
        port map (clk => clk, reset_n => rstn, start_in => start,
                  m_data => m_data, m_valid => m_valid, m_ready => m_ready);

    p_main : process
        variable errors       : natural := 0;
        variable got          : natural := 0;     -- Blocks accepted in the current burst
        variable beam         : nat_array_t := (others => 0);   -- Next expected beam per BFIC
        variable seed1, seed2 : positive := 7;
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
            variable k : natural;
        begin
            wait until rising_edge(clk);
            if stalled and rstn = '1' then
                check(m_valid = '1' and m_data = prev_data, "m_* changed while stalled at "
                      & time'image(now));
            end if;
            if m_valid = '1' and m_ready = '1' then
                k := got / BLOCKS_PER_PRESS;
                if k < N_BFIC then
                    check(m_data = blk(k, beam(k)), "block " & integer'image(got) & " (BFIC "
                          & integer'image(k + 1) & ", beam " & integer'image(beam(k))
                          & ") wrong content at " & time'image(now));
                    beam(k) := (beam(k) + 1) mod 4;
                else
                    check(false, "extra block " & integer'image(got));
                end if;
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

        -- Consume until the burst is over and check the block count
        procedure finish(name : string; p_rd : real) is
        begin
            for i in 1 to 100 * N_BFIC * BLOCKS_PER_PRESS loop
                step(p_rd);
                exit when got >= N_BFIC * BLOCKS_PER_PRESS;   -- m_valid has 1-cycle gaps
            end loop;
            steps(10, p_rd);
            check(m_valid = '0', name & ": m_valid still high");
            check(got = N_BFIC * BLOCKS_PER_PRESS, name & ": " & integer'image(got)
                  & " blocks, expected " & integer'image(N_BFIC * BLOCKS_PER_PRESS));
            got := 0;
        end procedure;

        procedure burst(name : string; p_rd : real) is
        begin
            press;
            finish(name, p_rd);
        end procedure;
    begin
        steps(10, 0.5);
        rstn <= '1';
        steps(5, 0.5);
        check(m_valid = '0', "m_valid high without a start pulse");

        burst("first burst", 0.5);
        burst("second burst", 0.5);
        burst("m_ready always high", 1.0);
        burst("slow consumer", 0.1);

        -- Start pulse during a burst: ignored
        press;
        steps(N_BFIC * BLOCKS_PER_PRESS, 0.5);     -- Somewhere in the middle of the burst
        check(m_valid = '1' or got > 0, "extra press: burst did not start");
        press;                                      -- Ignored
        finish("extra press", 0.5);

        -- Reset during a burst (in BFIC 2, so bfic_no and the beams are not at their start)
        press;
        while got < BLOCKS_PER_PRESS + 1 loop
            step(0.5);
        end loop;
        m_ready <= '0';
        rstn <= '0';
        steps(2, 0.0);
        rstn <= '1';
        steps(5, 0.0);
        check(m_valid = '0', "reset: m_valid still high after the reset");
        got  := 0;
        beam := (others => 0);                      -- The producers restart at beam 0
        burst("after reset", 0.5);

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture sim;
