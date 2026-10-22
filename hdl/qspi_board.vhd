-- QSPI memory controller + BIST with board-level pins (single die), for SmartDesign TOP
--
--   clk / reset_n --> qspi_mram_ctrl <--> qspi_bist --> bist_pass / bist_fail (LEDs)
--                          |
--                     tristate buffers --> qspi_sclk, qspi_cs_n, qspi_io(3:0)
--
--   Runs qspi_bist on its own after reset: init, write the pattern once, (calibrate,) then read
--   and compare once (qspi_bist's LOOP_ROUNDS default). bist_pass / bist_fail drive LEDs (see qspi_bist).
--   Single die only (IO[3:0]); a dual-die AS308G208 board needs a wrapper with the die-2 pins
--   and RESET# (PLAN.md Step 14). With DEVICE_SEL = 1 (AS308G208 die), RESET# must be tied high
--   on the board.
--   Use as an HDL+ core so the generics can be set per instance. They are integers because the
--   HDL+ configurator only handles integer generics.
--   clk is clk_ctrl (2 x the SCLK frequency for SCLK_DIV = 1); reset_n must be synchronous to it.
--   The pad registers are inside qspi_phy; constraints/qspi_ioreg.ndc combines them into the I/O
--   cells.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_pkg.all;

entity qspi_board is
    generic (
        DEVICE_SEL : natural range 0 to 1 := 0;        -- 0: W25Q128JV, 1: AS308G208 (one die)
        CLK_HZ     : positive := 100_000_000;          -- Input clock frequency
        SCLK_DIV   : positive range 1 to 4 := 1;       -- SCLK = CLK_HZ / (2 * SCLK_DIV)
        SAMPLE_DLY : positive range 1 to 4 := 2;       -- RX sample delay before calibration
        CALIBRATE  : natural range 0 to 1 := 1;        -- 1: BIST calibrates the sample delay
        NBLK       : positive := 8;                    -- BIST blocks
        BLK_LEN    : positive := 880                   -- BIST host bytes per block (even)
    );
    port (
        clk       : in    std_logic;
        reset_n   : in    std_logic;                   -- Synchronous, active low

        qspi_sclk : out   std_logic;
        qspi_cs_n : out   std_logic;
        qspi_io   : inout std_logic_vector(3 downto 0);

        bist_pass : out   std_logic;
        bist_fail : out   std_logic
    );
end entity qspi_board;

architecture rtl of qspi_board is

    function sel_device(n : natural) return device_t is
    begin
        if n = 1 then
            return DEV_AS308G208;
        end if;
        return DEV_W25Q128JV;
    end function;

    constant DEV : device_t := sel_device(DEVICE_SEL);

    signal init_restart, init_done, init_err, busy : std_logic;
    signal rd_req_tdata, wr_req_tdata : std_logic_vector(47 downto 0);
    signal rd_req_tvalid, rd_req_tready, rd_req_err : std_logic;
    signal wr_req_tvalid, wr_req_tready, wr_req_err, wr_done : std_logic;
    signal rd_space    : unsigned(15 downto 0);
    signal rd_tdata, wr_tdata : std_logic_vector(7 downto 0);
    signal rd_tvalid, rd_tready, rd_tlast, wr_tvalid, wr_tready : std_logic;
    signal ovr_valid   : std_logic;
    signal ovr         : natural range 1 to SAMPLE_DLY_MAX;
    signal sclk, cs_n  : std_logic_vector(1 downto 0);
    signal io_o, io_oe : std_logic_vector(7 downto 0);
    signal io_i        : std_logic_vector(7 downto 0);
begin
    ctrl : entity work.qspi_mram_ctrl
        generic map (DEVICE => DEV, DIE2_PRESENT => false, CLK_CTRL_HZ => CLK_HZ,
                     SCLK_DIV => SCLK_DIV, SAMPLE_DLY => SAMPLE_DLY, SPACE_W => 16)
        port map (
            clk => clk, reset_n => reset_n,
            init_restart => init_restart, init_done => init_done, init_err => init_err,
            init_err_code => open, init_step => open, busy => busy,
            rd_req_tdata => rd_req_tdata, rd_req_tvalid => rd_req_tvalid,
            rd_req_tready => rd_req_tready, rd_req_err => rd_req_err, rd_space => rd_space,
            m_axis_tdata => rd_tdata, m_axis_tvalid => rd_tvalid, m_axis_tready => rd_tready,
            m_axis_tlast => rd_tlast,
            wr_req_tdata => wr_req_tdata, wr_req_tvalid => wr_req_tvalid,
            wr_req_tready => wr_req_tready, wr_req_err => wr_req_err, wr_done => wr_done,
            s_axis_wr_tdata => wr_tdata, s_axis_wr_tvalid => wr_tvalid, s_axis_wr_tready => wr_tready,
            sample_dly_ovr_valid => ovr_valid, sample_dly_ovr => ovr,
            sclk => sclk, cs_n => cs_n, io_o => io_o, io_oe => io_oe, io_i => io_i,
            mem_reset_n => open);

    bist : entity work.qspi_bist
        generic map (DIE2_PRESENT => false, NBLK => NBLK, BLK_LEN => BLK_LEN,
                     BLK_STRIDE => 16#4000#, BASE_ADDR => 0, CALIBRATE => CALIBRATE = 1,
                     SPACE_W => 16)
        port map (
            clk => clk, reset_n => reset_n,
            init_restart => init_restart, init_done => init_done, init_err => init_err,
            ctrl_busy => busy,
            rd_req_tdata => rd_req_tdata, rd_req_tvalid => rd_req_tvalid,
            rd_req_tready => rd_req_tready, rd_req_err => rd_req_err, rd_space => rd_space,
            rd_tdata => rd_tdata, rd_tvalid => rd_tvalid, rd_tready => rd_tready, rd_tlast => rd_tlast,
            wr_req_tdata => wr_req_tdata, wr_req_tvalid => wr_req_tvalid,
            wr_req_tready => wr_req_tready, wr_req_err => wr_req_err, wr_done => wr_done,
            wr_tdata => wr_tdata, wr_tvalid => wr_tvalid, wr_tready => wr_tready,
            sample_dly_ovr_valid => ovr_valid, sample_dly_ovr => ovr,
            pass => bist_pass, fail => bist_fail,
            cal_window => open, cal_dly => open, pass_count => open, state_dbg => open);

    -- Pads: tristate buffers (BIBUF), driven straight from the PHY's pad registers
    qspi_sclk <= sclk(0);
    qspi_cs_n <= cs_n(0);
    pads : for i in 0 to 3 generate
        qspi_io(i) <= io_o(i) when io_oe(i) = '1' else 'Z';
    end generate;
    io_i <= "0000" & qspi_io;
end architecture rtl;
