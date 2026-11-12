-- Latency testbench: start_in pulse --> SPI frames at the pins
--   Instantiates the block path as it is wired in TOP (same generics, same 200 MHz clock):
--
--     start_in --> bfic_block_producer x2 (BFIC_AD3 = 0, 1) --> block_arbiter --> spi_tx_path --> SPI
--
--   One start pulse makes each producer send 5 BFICs x BEAMS_PER_BFIC blocks, so
--   2 * 5 * BEAMS_PER_BFIC SPI frames (40 with the default of 4). The testbench measures and reports:
--     - start_in -> first cs_n falling edge
--     - start_in -> first sclk leading edge (the first data bit on MOSI is sampled here)
--     - start_in -> cs_n rising edge after the first frame
--     - start_in -> cs_n rising edge after the last frame (whole burst)
--   Checks: exactly the expected number of frames, 80 sclk leading edges per frame, and the
--   first sclk edge within MAX_FIRST_EDGE_CYC clock cycles of the start pulse.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).
--
-- run_tb cores: BLOCK_FIFO_CORE

library ieee;
use ieee.std_logic_1164.all;

entity tb_start_to_spi is
    generic (
        BEAMS_PER_BFIC     : positive := 4;     -- As in TOP
        MAX_FIRST_EDGE_CYC : positive := 20     -- Limit for start_in -> first sclk edge, in clk cycles
    );
end entity tb_start_to_spi;

architecture sim of tb_start_to_spi is

    constant CLK_PERIOD  : time     := 5 ns;    -- 200 MHz, same as the fabric clock
    constant N_PROD      : positive := 2;
    constant N_BFIC      : positive := 5;
    constant N_FRAMES    : positive := N_PROD * N_BFIC * BEAMS_PER_BFIC;
    constant FRAME_BITS  : positive := 80;
    constant CPOL        : std_logic := '0';    -- spi_tx_path default, as in TOP

    signal clk      : std_logic := '0';
    signal reset_n  : std_logic := '0';
    signal start_in : std_logic := '0';
    signal done     : boolean   := false;

    -- Producers -> arbiter (flattened, as in TOP)
    signal prod_data  : std_logic_vector(N_PROD * 80 - 1 downto 0);
    signal prod_valid : std_logic_vector(N_PROD - 1 downto 0);
    signal prod_ready : std_logic_vector(N_PROD - 1 downto 0);

    -- Arbiter -> spi_tx_path
    signal arb_data  : std_logic_vector(79 downto 0);
    signal arb_valid : std_logic;
    signal arb_ready : std_logic;

    -- SPI pins
    signal spi_sclk : std_logic;
    signal spi_mosi : std_logic;
    signal spi_cs_n : std_logic;
    signal busy     : std_logic;

    -- Measurement (also handy in the wave window)
    signal t_start     : time    := 0 ns;     -- Rising clk edge that samples start_in = '1'
    signal frame_count : natural := 0;        -- Completed frames (cs_n rising edges)
    signal bit_count   : natural := 0;        -- Sclk leading edges in the current frame

begin

    clk <= not clk after CLK_PERIOD / 2 when not done;

    -- DUT: the same blocks and generics as in TOP.vhd
    gen_prod : for i in 0 to N_PROD - 1 generate
        u_prod : entity work.bfic_block_producer
            generic map (
                BEAMS_PER_BFIC => BEAMS_PER_BFIC,
                BFIC_AD3       => i
            )
            port map (
                clk      => clk,
                reset_n  => reset_n,
                start_in => start_in,
                m_data   => prod_data((i + 1) * 80 - 1 downto i * 80),
                m_valid  => prod_valid(i),
                m_ready  => prod_ready(i)
            );
    end generate gen_prod;

    u_arb : entity work.block_arbiter
        generic map (
            NUM_PORTS   => N_PROD,
            BLOCK_BYTES => 10
        )
        port map (
            clk     => clk,
            reset_n => reset_n,
            s_data  => prod_data,
            s_valid => prod_valid,
            s_ready => prod_ready,
            m_data  => arb_data,
            m_valid => arb_valid,
            m_ready => arb_ready
        );

    u_spi : entity work.spi_tx_path      -- No generic map in TOP, so the defaults apply here too
        port map (
            clk      => clk,
            reset_n  => reset_n,
            s_data   => arb_data,
            s_valid  => arb_valid,
            s_ready  => arb_ready,
            spi_sclk => spi_sclk,
            spi_mosi => spi_mosi,
            spi_cs_n => spi_cs_n,
            busy_out => busy
        );

    -- Count sclk leading edges per frame and frames (cs_n rising edges)
    count_proc : process (spi_sclk, spi_cs_n)
    begin
        if spi_cs_n'event and spi_cs_n = '0' then
            bit_count <= 0;
        elsif spi_sclk'event and spi_sclk = not CPOL and spi_cs_n = '0' then
            bit_count <= bit_count + 1;
        end if;
        if spi_cs_n'event and spi_cs_n = '1' and spi_cs_n'last_value = '0' then
            frame_count <= frame_count + 1;
        end if;
    end process count_proc;

    stim_proc : process
        variable errors : natural := 0;
        variable t0     : time;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                report msg severity error;
                errors := errors + 1;
            end if;
        end procedure;

        procedure show(what : string; t : time) is
        begin
            report what & ": " & time'image(t - t0) & " = "
                 & integer'image((t - t0) / CLK_PERIOD) & " clk cycles";
        end procedure;

    begin
        -- Reset
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;
        reset_n <= '1';
        for i in 1 to 5 loop
            wait until rising_edge(clk);
        end loop;
        check(spi_cs_n = '1', "cs_n not high after reset");

        -- One-cycle start pulse (like button_debounce / DEBUG_PULSE). t0 is the clock edge that
        -- samples it, so a latency of N cycles means N clock edges after that one.
        start_in <= '1';
        wait until rising_edge(clk);
        t0 := now;
        t_start <= now;
        start_in <= '0';

        -- First frame
        wait until falling_edge(spi_cs_n);
        show("start_in -> first cs_n falling edge", now);

        wait until spi_sclk = not CPOL;
        show("start_in -> first sclk leading edge", now);
        check((now - t0) / CLK_PERIOD <= MAX_FIRST_EDGE_CYC,
              "first sclk edge later than MAX_FIRST_EDGE_CYC = " & integer'image(MAX_FIRST_EDGE_CYC) & " cycles");

        wait until rising_edge(spi_cs_n);
        show("start_in -> end of first frame (cs_n high)", now);
        check(bit_count = FRAME_BITS, "frame 1: " & integer'image(bit_count) & " sclk edges, expected 80");

        -- Remaining frames
        for f in 2 to N_FRAMES loop
            wait until rising_edge(spi_cs_n) for 10 us;
            if spi_cs_n /= '1' or not spi_cs_n'event then
                check(false, "timeout waiting for frame " & integer'image(f));
                exit;
            end if;
            check(bit_count = FRAME_BITS,
                  "frame " & integer'image(f) & ": " & integer'image(bit_count) & " sclk edges, expected 80");
        end loop;
        show("start_in -> end of last frame (" & integer'image(N_FRAMES) & " frames)", now);

        -- No extra frames, path idle
        wait for 5 us;
        check(frame_count = N_FRAMES,
              integer'image(frame_count) & " frames, expected " & integer'image(N_FRAMES));
        check(spi_cs_n = '1' and arb_valid = '0', "path not idle after the burst");

        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process stim_proc;

end architecture sim;
