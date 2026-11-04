-- Pad buffers for the MSS QSPI controller routed through the fabric (MSS QSPI = FABRIC)
--
--   MSS QSPI_*_M2F / *_OE_M2F --> tristate buffers --> qspi_sclk, qspi_cs_n, qspi_io(3:0)
--   MSS QSPI_DATA_F2M         <-- qspi_io(3:0)
--
--   Connects the MSS QSPI fabric ports to the mikroBUS pins of the Flash 6 Click (W25Q128JV,
--   documentation/device_facts.md section 2.7). The HSS uses this path to boot from QSPI.
--   Every output follows its MSS output enable, so the pins are released (high-Z) while the MSS
--   doesn't drive them. io.pdc puts a weak pull-up on CS# (the click board has none); IO2/IO3
--   have 4.7 k pull-ups on the click board.
--   Purely combinational, so no clk / reset_n: the MSS QSPI controller registers its own I/O
--   timing (SCLK is a divided MSS AHB clock), and the fabric only adds pad and routing delay.
--   Synplify infers BIBUF / TRIBUFF from the 'Z' assignments, as in qspi_board.

library ieee;
use ieee.std_logic_1164.all;

entity mss_qspi_pads is
    port (
        -- From / to the MSS (QSPI fabric ports)
        mss_qspi_clk      : in    std_logic;                     -- QSPI_CLK_M2F
        mss_qspi_clk_oe   : in    std_logic;                     -- QSPI_CLK_OE_M2F
        mss_qspi_sel      : in    std_logic;                     -- QSPI_SEL_M2F (active low CS)
        mss_qspi_sel_oe   : in    std_logic;                     -- QSPI_SEL_OE_M2F
        mss_qspi_data_o   : in    std_logic_vector(3 downto 0);  -- QSPI_DATA_M2F
        mss_qspi_data_oe  : in    std_logic_vector(3 downto 0);  -- QSPI_DATA_OE_M2F
        mss_qspi_data_i   : out   std_logic_vector(3 downto 0);  -- QSPI_DATA_F2M

        -- Board pins (mikroBUS)
        qspi_sclk         : out   std_logic;
        qspi_cs_n         : out   std_logic;
        qspi_io           : inout std_logic_vector(3 downto 0)
    );
end entity mss_qspi_pads;

architecture rtl of mss_qspi_pads is
begin
    qspi_sclk <= mss_qspi_clk when mss_qspi_clk_oe = '1' else 'Z';
    qspi_cs_n <= mss_qspi_sel when mss_qspi_sel_oe = '1' else 'Z';

    gen_io : for i in 0 to 3 generate
        qspi_io(i) <= mss_qspi_data_o(i) when mss_qspi_data_oe(i) = '1' else 'Z';
    end generate gen_io;

    mss_qspi_data_i <= qspi_io;
end architecture rtl;
