-- Self-checking end-to-end testbench for spi_tx_path (block_fifo + block_serializer + axis_spi_wo_master)
--   A producer writes blocks; a behavioural SPI slave reassembles every cs_n assertion into
--   an 80-bit word (first bit = bit 79) and checks it against the block sequence, so order,
--   content, bit order and framing (exactly 80 bits per cs_n) are all checked at the pins.
--   Phases:
--     1. NSPARSE blocks with random gaps, some longer than a frame, so the FIFO often runs
--        empty and each block starts from an idle path.
--     2. NBURST blocks back to back, more than the FIFO holds: s_ready must go low
--        (backpressure) and every block must still arrive.
--   At the end the path must be idle. Then a reset with blocks in the FIFO and a frame in
--   progress must leave the path idle with cs_n high.
--   Prints "TB PASSED" or "TB FAILED: <n> error(s)" at the end (sim/run_tb.sh looks for these).
--
-- Other SPI modes, e.g.: sim/run_tb.sh tb_spi_tx_path -gCPOL_I=1 -gCPHA_I=1 -gCLK_DIV=2
--
-- run_tb cores: BLOCK_FIFO_CORE

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_spi_tx_path is
    generic (
        CPOL_I  : integer  := 0;
        CPHA_I  : integer  := 0;
        CLK_DIV : positive := 5;
        NSPARSE : natural  := 40;       -- Blocks with random gaps
        NBURST  : natural  := 600;      -- Back-to-back blocks (more than the 512-block FIFO)
        DEPTH   : positive := 512       -- FIFO depth, for the backpressure check
    );
end entity tb_spi_tx_path;

architecture sim of tb_spi_tx_path is

    function to_sl(b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function;

    constant CPOL        : std_logic := to_sl(CPOL_I /= 0);
    constant CPHA        : std_logic := to_sl(CPHA_I /= 0);
    constant BLOCK_BYTES : positive  := 10;
    constant W           : positive  := BLOCK_BYTES * 8;
    constant NBLOCKS     : natural   := NSPARSE + NBURST;
    constant CLK_PERIOD  : time      := 5 ns;    -- 200 MHz, same as the fabric clock

    -- Block number i -> 80 bits: five 16-bit fields that all depend on i
    function blk(i : natural) return std_logic_vector is
        variable u : unsigned(15 downto 0) := to_unsigned(i mod 65536, 16);
    begin
        return std_logic_vector(u) & std_logic_vector(u xor x"A5A5") & std_logic_vector(not u)
             & std_logic_vector(resize(u * 3, 16)) & std_logic_vector(u xor x"1234");
    end function;

    signal clk       : std_logic := '0';
    signal rstn      : std_logic := '0';

    signal s_data    : std_logic_vector(W - 1 downto 0) := (others => '0');
    signal s_valid   : std_logic := '0';
    signal s_ready   : std_logic;

    signal sclk, mosi, cs_n : std_logic;
    signal busy             : std_logic;

    signal tx_done, slv_done : boolean := false;
    signal reset_phase       : boolean := false;   -- Set by p_ctrl for the reset test
    signal done              : boolean := false;
    signal bp_seen           : boolean := false;   -- s_ready low while s_valid high
    signal err_slv           : natural := 0;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done;

    dut : entity work.spi_tx_path
        generic map (CLK_DIV => CLK_DIV, CPOL => CPOL, CPHA => CPHA)
        port map (
            clk => clk, reset_n => rstn,
            s_data => s_data, s_valid => s_valid, s_ready => s_ready,
            spi_sclk => sclk, spi_mosi => mosi, spi_cs_n => cs_n,
            busy_out => busy);

    -- Producer
    p_tx : process
        variable seed1, seed2 : positive := 3;
        variable r            : real;
    begin
        wait until rising_edge(clk) and rstn = '1';
        for i in 0 to NBLOCKS - 1 loop
            if i < NSPARSE then
                -- Random gap of up to about two frame times
                uniform(seed1, seed2, r);
                s_valid <= '0';
                for k in 1 to integer(r * real(2 * BLOCK_BYTES * 20 * CLK_DIV)) loop
                    wait until rising_edge(clk);
                end loop;
            end if;
            s_data  <= blk(i);
            s_valid <= '1';
            wait until rising_edge(clk) and s_ready = '1';
        end loop;
        s_valid <= '0';
        tx_done <= true;

        -- Reset test: keep the FIFO busy until p_ctrl resets the DUT
        wait until reset_phase;
        for i in 0 to 19 loop
            s_data  <= blk(NBLOCKS + i);
            s_valid <= '1';
            wait until rising_edge(clk) and s_ready = '1';
        end loop;
        s_valid <= '0';
        wait;
    end process;

    p_bp : process (clk)
    begin
        if rising_edge(clk) then
            if s_valid = '1' and s_ready = '0' then
                bp_seen <= true;
            end if;
        end if;
    end process;

    -- Behavioural SPI slave: one 80-bit word per cs_n assertion
    p_slave : process
        variable frame   : natural := 0;
        variable bits    : natural;
        variable word    : std_logic_vector(W - 1 downto 0);
        variable errs    : natural := 0;
        variable leading : boolean;
    begin
        wait until rstn = '1';
        while frame < NBLOCKS loop
            wait until cs_n = '0';
            bits := 0;
            loop
                wait on sclk, cs_n;
                exit when cs_n = '1';
                leading := sclk /= CPOL;
                if leading = (CPHA = '0') then
                    -- Sample edge: shift in from the right, so the first bit ends up as bit 79
                    word := word(W - 2 downto 0) & mosi;
                    bits := bits + 1;
                end if;
            end loop;
            if bits /= W then
                report "Frame " & integer'image(frame) & " had " & integer'image(bits)
                       & " bits, expected " & integer'image(W) severity error;
                errs := errs + 1;
            elsif word /= blk(frame) then
                report "Frame " & integer'image(frame) & " data mismatch" severity error;
                errs := errs + 1;
            end if;
            frame := frame + 1;
        end loop;
        err_slv  <= errs;
        slv_done <= true;
        wait;
    end process;

    -- Control, reset test and summary
    p_ctrl : process
        variable errors : natural := 0;

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
    begin
        clocks(10);
        rstn <= '1';

        wait until (tx_done and slv_done) for 100 ms;
        check(tx_done and slv_done, "timeout");
        clocks(20 * CLK_DIV);
        check(busy = '0' and cs_n = '1' and sclk = CPOL, "path not idle after the data phase");
        check(s_ready = '1', "s_ready low with an empty FIFO");
        check(NBURST <= DEPTH or bp_seen, "burst: no backpressure (s_ready never went low)");

        -- Reset with blocks in the FIFO and a frame in progress
        reset_phase <= true;
        wait until cs_n = '0' for 1 ms;
        check(cs_n = '0', "reset test: frame did not start");
        clocks(20 * CLK_DIV);                     -- Somewhere in the first bytes
        rstn <= '0';
        clocks(3);
        rstn <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        check(cs_n = '1' and sclk = CPOL, "reset test: SPI not idle after the reset");
        clocks(10 * CLK_DIV);
        check(cs_n = '1' and busy = '0', "reset test: a frame started from a block written before the reset");

        errors := errors + err_slv;
        if errors = 0 then
            report "TB PASSED";
        else
            report "TB FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture sim;
