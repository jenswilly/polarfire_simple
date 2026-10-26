----------------------------------------------------------------------
-- Created by SmartDesign Mon Oct 26 10:30:17 2026
-- Version: 2026.1 2026.1.0.17
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Libraries
----------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library polarfire;
use polarfire.all;
----------------------------------------------------------------------
-- TOP entity declaration
----------------------------------------------------------------------
entity TOP is
    -- Port list
    port(
        -- Inputs
        REFCLK        : in    std_logic;
        REFCLK_N      : in    std_logic;
        REF_CLK_50MHz : in    std_logic;
        SWITCH2       : in    std_logic;
        UART0_RX      : in    std_logic;
        -- Outputs
        A             : out   std_logic_vector(13 downto 0);
        ACT_N         : out   std_logic;
        BA            : out   std_logic_vector(1 downto 0);
        BG0           : out   std_logic;
        CAS_N         : out   std_logic;
        CK0           : out   std_logic;
        CK0_N         : out   std_logic;
        CKE0          : out   std_logic;
        CS0_N         : out   std_logic;
        DEBUG         : out   std_logic;
        DM            : out   std_logic_vector(1 downto 0);
        LED1          : out   std_logic;
        LED2          : out   std_logic;
        LED3          : out   std_logic;
        LED4          : out   std_logic;
        LED5          : out   std_logic;
        LED6          : out   std_logic;
        LED7          : out   std_logic;
        ODT0          : out   std_logic;
        QSPI_CS_N     : out   std_logic;
        QSPI_SCLK     : out   std_logic;
        RAS_N         : out   std_logic;
        RESET_N       : out   std_logic;
        RPi_GPIO16    : out   std_logic;
        RPi_GPIO19    : out   std_logic;
        RPi_GPIO20    : out   std_logic;
        RPi_GPIO26    : out   std_logic;
        UART0_TX      : out   std_logic;
        WE_N          : out   std_logic;
        -- Inouts
        DQ            : inout std_logic_vector(15 downto 0);
        DQS           : inout std_logic_vector(1 downto 0);
        DQS_N         : inout std_logic_vector(1 downto 0);
        QSPI_IO       : inout std_logic_vector(3 downto 0)
        );
end TOP;
----------------------------------------------------------------------
-- TOP architecture body
----------------------------------------------------------------------
architecture RTL of TOP is
----------------------------------------------------------------------
-- Component declarations
----------------------------------------------------------------------
-- AND2
component AND2
    -- Port list
    port(
        -- Inputs
        A : in  std_logic;
        B : in  std_logic;
        -- Outputs
        Y : out std_logic
        );
end component;
-- AXI_IC
component AXI_IC
    -- Port list
    port(
        -- Inputs
        ACLK                : in  std_logic;
        ARESETN             : in  std_logic;
        INITIATOR0_ARADDR   : in  std_logic_vector(37 downto 0);
        INITIATOR0_ARBURST  : in  std_logic_vector(1 downto 0);
        INITIATOR0_ARCACHE  : in  std_logic_vector(3 downto 0);
        INITIATOR0_ARID     : in  std_logic_vector(7 downto 0);
        INITIATOR0_ARLEN    : in  std_logic_vector(7 downto 0);
        INITIATOR0_ARLOCK   : in  std_logic_vector(0 to 0);
        INITIATOR0_ARPROT   : in  std_logic_vector(2 downto 0);
        INITIATOR0_ARQOS    : in  std_logic_vector(3 downto 0);
        INITIATOR0_ARREGION : in  std_logic_vector(3 downto 0);
        INITIATOR0_ARSIZE   : in  std_logic_vector(2 downto 0);
        INITIATOR0_ARUSER   : in  std_logic_vector(0 to 0);
        INITIATOR0_ARVALID  : in  std_logic;
        INITIATOR0_AWADDR   : in  std_logic_vector(37 downto 0);
        INITIATOR0_AWBURST  : in  std_logic_vector(1 downto 0);
        INITIATOR0_AWCACHE  : in  std_logic_vector(3 downto 0);
        INITIATOR0_AWID     : in  std_logic_vector(7 downto 0);
        INITIATOR0_AWLEN    : in  std_logic_vector(7 downto 0);
        INITIATOR0_AWLOCK   : in  std_logic_vector(0 to 0);
        INITIATOR0_AWPROT   : in  std_logic_vector(2 downto 0);
        INITIATOR0_AWQOS    : in  std_logic_vector(3 downto 0);
        INITIATOR0_AWREGION : in  std_logic_vector(3 downto 0);
        INITIATOR0_AWSIZE   : in  std_logic_vector(2 downto 0);
        INITIATOR0_AWUSER   : in  std_logic_vector(0 to 0);
        INITIATOR0_AWVALID  : in  std_logic;
        INITIATOR0_BREADY   : in  std_logic;
        INITIATOR0_RREADY   : in  std_logic;
        INITIATOR0_WDATA    : in  std_logic_vector(63 downto 0);
        INITIATOR0_WLAST    : in  std_logic;
        INITIATOR0_WSTRB    : in  std_logic_vector(7 downto 0);
        INITIATOR0_WUSER    : in  std_logic_vector(0 to 0);
        INITIATOR0_WVALID   : in  std_logic;
        TARGET0_ARREADY     : in  std_logic;
        TARGET0_AWREADY     : in  std_logic;
        TARGET0_BRESP       : in  std_logic_vector(1 downto 0);
        TARGET0_BVALID      : in  std_logic;
        TARGET0_RDATA       : in  std_logic_vector(31 downto 0);
        TARGET0_RRESP       : in  std_logic_vector(1 downto 0);
        TARGET0_RVALID      : in  std_logic;
        TARGET0_WREADY      : in  std_logic;
        -- Outputs
        INITIATOR0_ARREADY  : out std_logic;
        INITIATOR0_AWREADY  : out std_logic;
        INITIATOR0_BID      : out std_logic_vector(7 downto 0);
        INITIATOR0_BRESP    : out std_logic_vector(1 downto 0);
        INITIATOR0_BUSER    : out std_logic_vector(0 to 0);
        INITIATOR0_BVALID   : out std_logic;
        INITIATOR0_RDATA    : out std_logic_vector(63 downto 0);
        INITIATOR0_RID      : out std_logic_vector(7 downto 0);
        INITIATOR0_RLAST    : out std_logic;
        INITIATOR0_RRESP    : out std_logic_vector(1 downto 0);
        INITIATOR0_RUSER    : out std_logic_vector(0 to 0);
        INITIATOR0_RVALID   : out std_logic;
        INITIATOR0_WREADY   : out std_logic;
        TARGET0_ARADDR      : out std_logic_vector(37 downto 0);
        TARGET0_ARPROT      : out std_logic_vector(2 downto 0);
        TARGET0_ARVALID     : out std_logic;
        TARGET0_AWADDR      : out std_logic_vector(37 downto 0);
        TARGET0_AWPROT      : out std_logic_vector(2 downto 0);
        TARGET0_AWVALID     : out std_logic;
        TARGET0_BREADY      : out std_logic;
        TARGET0_RREADY      : out std_logic;
        TARGET0_WDATA       : out std_logic_vector(31 downto 0);
        TARGET0_WSTRB       : out std_logic_vector(3 downto 0);
        TARGET0_WVALID      : out std_logic
        );
end component;
-- axi_sys_ctrl
-- using entity instantiation for component axi_sys_ctrl
-- block_arbiter
-- using entity instantiation for component block_arbiter
-- button_debounce
component button_debounce
    -- Port list
    port(
        -- Inputs
        btn_in      : in  std_logic;
        clk         : in  std_logic;
        reset_n     : in  std_logic;
        -- Outputs
        pressed_out : out std_logic;
        pulse_out   : out std_logic
        );
end component;
-- CLKINT
component CLKINT
    -- Port list
    port(
        -- Inputs
        A : in  std_logic;
        -- Outputs
        Y : out std_logic
        );
end component;
-- CORERESET
component CORERESET
    -- Port list
    port(
        -- Inputs
        BANK_x_VDDI_STATUS : in  std_logic;
        BANK_y_VDDI_STATUS : in  std_logic;
        CLK                : in  std_logic;
        EXT_RST_N          : in  std_logic;
        FF_US_RESTORE      : in  std_logic;
        FPGA_POR_N         : in  std_logic;
        INIT_DONE          : in  std_logic;
        PLL_LOCK           : in  std_logic;
        SS_BUSY            : in  std_logic;
        -- Outputs
        FABRIC_RESET_N     : out std_logic;
        PLL_POWERDOWN_B    : out std_logic
        );
end component;
-- CORERESET_1
component CORERESET_1
    -- Port list
    port(
        -- Inputs
        BANK_x_VDDI_STATUS : in  std_logic;
        BANK_y_VDDI_STATUS : in  std_logic;
        CLK                : in  std_logic;
        EXT_RST_N          : in  std_logic;
        FF_US_RESTORE      : in  std_logic;
        FPGA_POR_N         : in  std_logic;
        INIT_DONE          : in  std_logic;
        PLL_LOCK           : in  std_logic;
        SS_BUSY            : in  std_logic;
        -- Outputs
        FABRIC_RESET_N     : out std_logic;
        PLL_POWERDOWN_B    : out std_logic
        );
end component;
-- INIT_MONITOR
component INIT_MONITOR
    -- Port list
    port(
        -- Outputs
        AUTOCALIB_DONE             : out std_logic;
        BANK_0_CALIB_STATUS        : out std_logic;
        BANK_1_CALIB_STATUS        : out std_logic;
        DEVICE_INIT_DONE           : out std_logic;
        FABRIC_POR_N               : out std_logic;
        PCIE_INIT_DONE             : out std_logic;
        SRAM_INIT_DONE             : out std_logic;
        SRAM_INIT_FROM_SNVM_DONE   : out std_logic;
        SRAM_INIT_FROM_SPI_DONE    : out std_logic;
        SRAM_INIT_FROM_UPROM_DONE  : out std_logic;
        USRAM_INIT_DONE            : out std_logic;
        USRAM_INIT_FROM_SNVM_DONE  : out std_logic;
        USRAM_INIT_FROM_SPI_DONE   : out std_logic;
        USRAM_INIT_FROM_UPROM_DONE : out std_logic;
        XCVR_INIT_DONE             : out std_logic
        );
end component;
-- MSS_simple
component MSS_simple
    -- Port list
    port(
        -- Inputs
        FIC_0_ACLK           : in    std_logic;
        FIC_0_AXI4_M_ARREADY : in    std_logic;
        FIC_0_AXI4_M_AWREADY : in    std_logic;
        FIC_0_AXI4_M_BID     : in    std_logic_vector(7 downto 0);
        FIC_0_AXI4_M_BRESP   : in    std_logic_vector(1 downto 0);
        FIC_0_AXI4_M_BVALID  : in    std_logic;
        FIC_0_AXI4_M_RDATA   : in    std_logic_vector(63 downto 0);
        FIC_0_AXI4_M_RID     : in    std_logic_vector(7 downto 0);
        FIC_0_AXI4_M_RLAST   : in    std_logic;
        FIC_0_AXI4_M_RRESP   : in    std_logic_vector(1 downto 0);
        FIC_0_AXI4_M_RVALID  : in    std_logic;
        FIC_0_AXI4_M_WREADY  : in    std_logic;
        MMUART_0_RXD_F2M     : in    std_logic;
        MSS_RESET_N_F2M      : in    std_logic;
        REFCLK               : in    std_logic;
        REFCLK_N             : in    std_logic;
        -- Outputs
        A                    : out   std_logic_vector(13 downto 0);
        ACT_N                : out   std_logic;
        BA                   : out   std_logic_vector(1 downto 0);
        BG0                  : out   std_logic;
        CAS_N                : out   std_logic;
        CK0                  : out   std_logic;
        CK0_N                : out   std_logic;
        CKE0                 : out   std_logic;
        CS0_N                : out   std_logic;
        DM                   : out   std_logic_vector(1 downto 0);
        FIC_0_AXI4_M_ARADDR  : out   std_logic_vector(37 downto 0);
        FIC_0_AXI4_M_ARBURST : out   std_logic_vector(1 downto 0);
        FIC_0_AXI4_M_ARCACHE : out   std_logic_vector(3 downto 0);
        FIC_0_AXI4_M_ARID    : out   std_logic_vector(7 downto 0);
        FIC_0_AXI4_M_ARLEN   : out   std_logic_vector(7 downto 0);
        FIC_0_AXI4_M_ARLOCK  : out   std_logic;
        FIC_0_AXI4_M_ARPROT  : out   std_logic_vector(2 downto 0);
        FIC_0_AXI4_M_ARQOS   : out   std_logic_vector(3 downto 0);
        FIC_0_AXI4_M_ARSIZE  : out   std_logic_vector(2 downto 0);
        FIC_0_AXI4_M_ARVALID : out   std_logic;
        FIC_0_AXI4_M_AWADDR  : out   std_logic_vector(37 downto 0);
        FIC_0_AXI4_M_AWBURST : out   std_logic_vector(1 downto 0);
        FIC_0_AXI4_M_AWCACHE : out   std_logic_vector(3 downto 0);
        FIC_0_AXI4_M_AWID    : out   std_logic_vector(7 downto 0);
        FIC_0_AXI4_M_AWLEN   : out   std_logic_vector(7 downto 0);
        FIC_0_AXI4_M_AWLOCK  : out   std_logic;
        FIC_0_AXI4_M_AWPROT  : out   std_logic_vector(2 downto 0);
        FIC_0_AXI4_M_AWQOS   : out   std_logic_vector(3 downto 0);
        FIC_0_AXI4_M_AWSIZE  : out   std_logic_vector(2 downto 0);
        FIC_0_AXI4_M_AWVALID : out   std_logic;
        FIC_0_AXI4_M_BREADY  : out   std_logic;
        FIC_0_AXI4_M_RREADY  : out   std_logic;
        FIC_0_AXI4_M_WDATA   : out   std_logic_vector(63 downto 0);
        FIC_0_AXI4_M_WLAST   : out   std_logic;
        FIC_0_AXI4_M_WSTRB   : out   std_logic_vector(7 downto 0);
        FIC_0_AXI4_M_WVALID  : out   std_logic;
        FIC_0_DLL_LOCK_M2F   : out   std_logic;
        MMUART_0_TXD_M2F     : out   std_logic;
        MMUART_0_TXD_OE_M2F  : out   std_logic;
        MSS_RESET_N_M2F      : out   std_logic;
        ODT0                 : out   std_logic;
        PLL_CPU_LOCK_M2F     : out   std_logic;
        PLL_DDR_LOCK_M2F     : out   std_logic;
        RAS_N                : out   std_logic;
        RESET_N              : out   std_logic;
        WE_N                 : out   std_logic;
        -- Inouts
        DQ                   : inout std_logic_vector(15 downto 0);
        DQS                  : inout std_logic_vector(1 downto 0);
        DQS_N                : inout std_logic_vector(1 downto 0)
        );
end component;
-- OR2
component OR2
    -- Port list
    port(
        -- Inputs
        A : in  std_logic;
        B : in  std_logic;
        -- Outputs
        Y : out std_logic
        );
end component;
-- PF_CCC_C0
component PF_CCC_C0
    -- Port list
    port(
        -- Inputs
        PLL_POWERDOWN_N_0 : in  std_logic;
        REF_CLK_0         : in  std_logic;
        -- Outputs
        OUT0_FABCLK_0     : out std_logic;
        OUT1_FABCLK_0     : out std_logic;
        PLL_LOCK_0        : out std_logic
        );
end component;
-- pulse_stretch
-- using entity instantiation for component pulse_stretch
-- qspi_board
-- using entity instantiation for component qspi_board
-- spi_tx_path
component spi_tx_path
    -- Port list
    port(
        -- Inputs
        clk           : in  std_logic;
        reset_n       : in  std_logic;
        s_data        : in  std_logic_vector(79 downto 0);
        s_valid       : in  std_logic;
        -- Outputs
        busy_out      : out std_logic;
        frame_err_out : out std_logic;
        s_ready       : out std_logic;
        spi_cs_n      : out std_logic;
        spi_mosi      : out std_logic;
        spi_sclk      : out std_logic
        );
end component;
-- test_block_producer
-- using entity instantiation for component test_block_producer
----------------------------------------------------------------------
-- Signal declarations
----------------------------------------------------------------------
signal A_net_0                                   : std_logic_vector(13 downto 0);
signal ACT_N_net_0                               : std_logic;
signal AND2_0_Y                                  : std_logic;
signal AXI_IC_0_AXI4Lmtarget0_ARADDR             : std_logic_vector(37 downto 0);
signal AXI_IC_0_AXI4Lmtarget0_ARPROT             : std_logic_vector(2 downto 0);
signal AXI_IC_0_AXI4Lmtarget0_ARREADY            : std_logic;
signal AXI_IC_0_AXI4Lmtarget0_ARVALID            : std_logic;
signal AXI_IC_0_AXI4Lmtarget0_AWADDR             : std_logic_vector(37 downto 0);
signal AXI_IC_0_AXI4Lmtarget0_AWPROT             : std_logic_vector(2 downto 0);
signal AXI_IC_0_AXI4Lmtarget0_AWREADY            : std_logic;
signal AXI_IC_0_AXI4Lmtarget0_AWVALID            : std_logic;
signal AXI_IC_0_AXI4Lmtarget0_BREADY             : std_logic;
signal AXI_IC_0_AXI4Lmtarget0_BRESP              : std_logic_vector(1 downto 0);
signal AXI_IC_0_AXI4Lmtarget0_BVALID             : std_logic;
signal AXI_IC_0_AXI4Lmtarget0_RDATA              : std_logic_vector(31 downto 0);
signal AXI_IC_0_AXI4Lmtarget0_RREADY             : std_logic;
signal AXI_IC_0_AXI4Lmtarget0_RRESP              : std_logic_vector(1 downto 0);
signal AXI_IC_0_AXI4Lmtarget0_RVALID             : std_logic;
signal AXI_IC_0_AXI4Lmtarget0_WDATA              : std_logic_vector(31 downto 0);
signal AXI_IC_0_AXI4Lmtarget0_WREADY             : std_logic;
signal AXI_IC_0_AXI4Lmtarget0_WSTRB              : std_logic_vector(3 downto 0);
signal AXI_IC_0_AXI4Lmtarget0_WVALID             : std_logic;
signal axi_sys_ctrl_0_DEBUG_PULSE                : std_logic;
signal BA_net_0                                  : std_logic_vector(1 downto 0);
signal BG0_net_0                                 : std_logic;
signal block_arbiter_0_m_data                    : std_logic_vector(79 downto 0);
signal block_arbiter_0_m_valid                   : std_logic;
signal block_arbiter_0_s_ready0to0               : std_logic_vector(0 to 0);
signal block_arbiter_0_s_ready1to1               : std_logic_vector(1 to 1);
signal button_debounce_0_pulse_out               : std_logic;
signal CAS_N_net_0                               : std_logic;
signal CK0_net_0                                 : std_logic;
signal CK0_N_net_0                               : std_logic;
signal CKE0_net_0                                : std_logic;
signal CLKINT_0_Y                                : std_logic;
signal CORERESET_0_FABRIC_RESET_N                : std_logic;
signal CORERESET_0_PLL_POWERDOWN_B               : std_logic;
signal CORERESET_1_0_FABRIC_RESET_N              : std_logic;
signal CS0_N_net_0                               : std_logic;
signal DEBUG_net_0                               : std_logic;
signal DM_net_0                                  : std_logic_vector(1 downto 0);
signal INIT_MONITOR_0_DEVICE_INIT_DONE           : std_logic;
signal INIT_MONITOR_0_FABRIC_POR_N               : std_logic;
signal LED2_net_0                                : std_logic;
signal LED3_net_0                                : std_logic;
signal LED4_net_0                                : std_logic;
signal LED5_net_0                                : std_logic;
signal LED6_net_0                                : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARADDR  : std_logic_vector(37 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARBURST : std_logic_vector(1 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARCACHE : std_logic_vector(3 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARID    : std_logic_vector(7 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARLEN   : std_logic_vector(7 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARLOCK  : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARPROT  : std_logic_vector(2 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARQOS   : std_logic_vector(3 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARREADY : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARSIZE  : std_logic_vector(2 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_ARVALID : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWADDR  : std_logic_vector(37 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWBURST : std_logic_vector(1 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWCACHE : std_logic_vector(3 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWID    : std_logic_vector(7 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWLEN   : std_logic_vector(7 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWLOCK  : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWPROT  : std_logic_vector(2 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWQOS   : std_logic_vector(3 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWREADY : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWSIZE  : std_logic_vector(2 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_AWVALID : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_BID     : std_logic_vector(7 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_BREADY  : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_BRESP   : std_logic_vector(1 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_BUSER   : std_logic_vector(0 to 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_BVALID  : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_RDATA   : std_logic_vector(63 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_RID     : std_logic_vector(7 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_RLAST   : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_RREADY  : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_RRESP   : std_logic_vector(1 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_RUSER   : std_logic_vector(0 to 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_RVALID  : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_WDATA   : std_logic_vector(63 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_WLAST   : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_WREADY  : std_logic;
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_WSTRB   : std_logic_vector(7 downto 0);
signal MSS_simple_0_FIC_0_AXI4_INITIATOR_WVALID  : std_logic;
signal MSS_simple_0_FIC_0_DLL_LOCK_M2F           : std_logic;
signal MSS_simple_0_MSS_RESET_N_M2F              : std_logic;
signal ODT0_net_0                                : std_logic;
signal OR2_1_Y                                   : std_logic;
signal PF_CCC_C0_0_OUT0_FABCLK_0                 : std_logic;
signal PF_CCC_C0_0_OUT1_FABCLK_0                 : std_logic;
signal PF_CCC_C0_0_PLL_LOCK_0                    : std_logic;
signal QSPI_CS_N_net_0                           : std_logic;
signal QSPI_SCLK_net_0                           : std_logic;
signal RAS_N_net_0                               : std_logic;
signal RESET_N_net_0                             : std_logic;
signal RPi_GPIO16_net_0                          : std_logic;
signal RPi_GPIO19_net_0                          : std_logic;
signal RPi_GPIO26_net_0                          : std_logic;
signal spi_tx_path_0_s_ready                     : std_logic;
signal test_block_producer_0_m_data              : std_logic_vector(79 downto 0);
signal test_block_producer_0_m_valid             : std_logic;
signal test_block_producer_1_m_data              : std_logic_vector(79 downto 0);
signal test_block_producer_1_m_valid             : std_logic;
signal UART0_TX_net_0                            : std_logic;
signal WE_N_net_0                                : std_logic;
signal RESET_N_net_1                             : std_logic;
signal CKE0_net_1                                : std_logic;
signal CS0_N_net_1                               : std_logic;
signal ODT0_net_1                                : std_logic;
signal CK0_net_1                                 : std_logic;
signal CK0_N_net_1                               : std_logic;
signal RAS_N_net_1                               : std_logic;
signal WE_N_net_1                                : std_logic;
signal CAS_N_net_1                               : std_logic;
signal ACT_N_net_1                               : std_logic;
signal BG0_net_1                                 : std_logic;
signal UART0_TX_net_1                            : std_logic;
signal LED2_net_1                                : std_logic;
signal LED3_net_1                                : std_logic;
signal LED4_net_1                                : std_logic;
signal LED5_net_1                                : std_logic;
signal LED6_net_1                                : std_logic;
signal DEBUG_net_1                               : std_logic;
signal RPi_GPIO16_net_1                          : std_logic;
signal RPi_GPIO19_net_1                          : std_logic;
signal RPi_GPIO26_net_1                          : std_logic;
signal QSPI_SCLK_net_1                           : std_logic;
signal QSPI_CS_N_net_1                           : std_logic;
signal BA_net_1                                  : std_logic_vector(1 downto 0);
signal DM_net_1                                  : std_logic_vector(1 downto 0);
signal A_net_1                                   : std_logic_vector(13 downto 0);
signal s_data_net_0                              : std_logic_vector(159 downto 0);
signal s_valid_net_0                             : std_logic_vector(1 downto 0);
signal s_ready_net_0                             : std_logic_vector(1 downto 0);
----------------------------------------------------------------------
-- TiedOff Signals
----------------------------------------------------------------------
signal GND_net                                   : std_logic;
signal VCC_net                                   : std_logic;
signal INITIATOR0_AWREGION_const_net_0           : std_logic_vector(3 downto 0);
signal INITIATOR0_ARREGION_const_net_0           : std_logic_vector(3 downto 0);

begin
----------------------------------------------------------------------
-- Constant assignments
----------------------------------------------------------------------
 GND_net                         <= '0';
 VCC_net                         <= '1';
 INITIATOR0_AWREGION_const_net_0 <= B"0000";
 INITIATOR0_ARREGION_const_net_0 <= B"0000";
----------------------------------------------------------------------
-- TieOff assignments
----------------------------------------------------------------------
 LED1             <= '0';
 LED7             <= '0';
 RPi_GPIO20       <= '0';
----------------------------------------------------------------------
-- Top level output port assignments
----------------------------------------------------------------------
 RESET_N_net_1    <= RESET_N_net_0;
 RESET_N          <= RESET_N_net_1;
 CKE0_net_1       <= CKE0_net_0;
 CKE0             <= CKE0_net_1;
 CS0_N_net_1      <= CS0_N_net_0;
 CS0_N            <= CS0_N_net_1;
 ODT0_net_1       <= ODT0_net_0;
 ODT0             <= ODT0_net_1;
 CK0_net_1        <= CK0_net_0;
 CK0              <= CK0_net_1;
 CK0_N_net_1      <= CK0_N_net_0;
 CK0_N            <= CK0_N_net_1;
 RAS_N_net_1      <= RAS_N_net_0;
 RAS_N            <= RAS_N_net_1;
 WE_N_net_1       <= WE_N_net_0;
 WE_N             <= WE_N_net_1;
 CAS_N_net_1      <= CAS_N_net_0;
 CAS_N            <= CAS_N_net_1;
 ACT_N_net_1      <= ACT_N_net_0;
 ACT_N            <= ACT_N_net_1;
 BG0_net_1        <= BG0_net_0;
 BG0              <= BG0_net_1;
 UART0_TX_net_1   <= UART0_TX_net_0;
 UART0_TX         <= UART0_TX_net_1;
 LED2_net_1       <= LED2_net_0;
 LED2             <= LED2_net_1;
 LED3_net_1       <= LED3_net_0;
 LED3             <= LED3_net_1;
 LED4_net_1       <= LED4_net_0;
 LED4             <= LED4_net_1;
 LED5_net_1       <= LED5_net_0;
 LED5             <= LED5_net_1;
 LED6_net_1       <= LED6_net_0;
 LED6             <= LED6_net_1;
 DEBUG_net_1      <= DEBUG_net_0;
 DEBUG            <= DEBUG_net_1;
 RPi_GPIO16_net_1 <= RPi_GPIO16_net_0;
 RPi_GPIO16       <= RPi_GPIO16_net_1;
 RPi_GPIO19_net_1 <= RPi_GPIO19_net_0;
 RPi_GPIO19       <= RPi_GPIO19_net_1;
 RPi_GPIO26_net_1 <= RPi_GPIO26_net_0;
 RPi_GPIO26       <= RPi_GPIO26_net_1;
 QSPI_SCLK_net_1  <= QSPI_SCLK_net_0;
 QSPI_SCLK        <= QSPI_SCLK_net_1;
 QSPI_CS_N_net_1  <= QSPI_CS_N_net_0;
 QSPI_CS_N        <= QSPI_CS_N_net_1;
 BA_net_1         <= BA_net_0;
 BA(1 downto 0)   <= BA_net_1;
 DM_net_1         <= DM_net_0;
 DM(1 downto 0)   <= DM_net_1;
 A_net_1          <= A_net_0;
 A(13 downto 0)   <= A_net_1;
----------------------------------------------------------------------
-- Slices assignments
----------------------------------------------------------------------
 block_arbiter_0_s_ready0to0(0) <= s_ready_net_0(0);
 block_arbiter_0_s_ready1to1(1) <= s_ready_net_0(1);
----------------------------------------------------------------------
-- Concatenation assignments
----------------------------------------------------------------------
 s_data_net_0  <= ( test_block_producer_1_m_data & test_block_producer_0_m_data );
 s_valid_net_0 <= ( test_block_producer_1_m_valid & test_block_producer_0_m_valid );
----------------------------------------------------------------------
-- Component instances
----------------------------------------------------------------------
-- AND2_0
AND2_0 : AND2
    port map( 
        -- Inputs
        A => MSS_simple_0_MSS_RESET_N_M2F,
        B => MSS_simple_0_FIC_0_DLL_LOCK_M2F,
        -- Outputs
        Y => AND2_0_Y 
        );
-- AXI_IC_0
AXI_IC_0 : AXI_IC
    port map( 
        -- Inputs
        ACLK                 => PF_CCC_C0_0_OUT0_FABCLK_0,
        ARESETN              => CORERESET_0_FABRIC_RESET_N,
        INITIATOR0_AWVALID   => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWVALID,
        INITIATOR0_WLAST     => MSS_simple_0_FIC_0_AXI4_INITIATOR_WLAST,
        INITIATOR0_WVALID    => MSS_simple_0_FIC_0_AXI4_INITIATOR_WVALID,
        INITIATOR0_BREADY    => MSS_simple_0_FIC_0_AXI4_INITIATOR_BREADY,
        INITIATOR0_ARVALID   => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARVALID,
        INITIATOR0_RREADY    => MSS_simple_0_FIC_0_AXI4_INITIATOR_RREADY,
        TARGET0_AWREADY      => AXI_IC_0_AXI4Lmtarget0_AWREADY,
        TARGET0_WREADY       => AXI_IC_0_AXI4Lmtarget0_WREADY,
        TARGET0_BVALID       => AXI_IC_0_AXI4Lmtarget0_BVALID,
        TARGET0_ARREADY      => AXI_IC_0_AXI4Lmtarget0_ARREADY,
        TARGET0_RVALID       => AXI_IC_0_AXI4Lmtarget0_RVALID,
        INITIATOR0_AWID      => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWID,
        INITIATOR0_AWADDR    => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWADDR,
        INITIATOR0_AWLEN     => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWLEN,
        INITIATOR0_AWSIZE    => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWSIZE,
        INITIATOR0_AWBURST   => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWBURST,
        INITIATOR0_AWLOCK(0) => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWLOCK,
        INITIATOR0_AWCACHE   => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWCACHE,
        INITIATOR0_AWPROT    => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWPROT,
        INITIATOR0_AWQOS     => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWQOS,
        INITIATOR0_AWREGION  => INITIATOR0_AWREGION_const_net_0, -- tied to X"0" from definition
        INITIATOR0_WDATA     => MSS_simple_0_FIC_0_AXI4_INITIATOR_WDATA,
        INITIATOR0_WSTRB     => MSS_simple_0_FIC_0_AXI4_INITIATOR_WSTRB,
        INITIATOR0_ARID      => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARID,
        INITIATOR0_ARADDR    => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARADDR,
        INITIATOR0_ARLEN     => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARLEN,
        INITIATOR0_ARSIZE    => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARSIZE,
        INITIATOR0_ARBURST   => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARBURST,
        INITIATOR0_ARLOCK(0) => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARLOCK,
        INITIATOR0_ARCACHE   => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARCACHE,
        INITIATOR0_ARPROT    => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARPROT,
        INITIATOR0_ARQOS     => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARQOS,
        INITIATOR0_ARREGION  => INITIATOR0_ARREGION_const_net_0, -- tied to X"0" from definition
        INITIATOR0_AWUSER(0) => GND_net, -- tied to '0' from definition
        INITIATOR0_WUSER(0)  => GND_net, -- tied to '0' from definition
        INITIATOR0_ARUSER(0) => GND_net, -- tied to '0' from definition
        TARGET0_BRESP        => AXI_IC_0_AXI4Lmtarget0_BRESP,
        TARGET0_RDATA        => AXI_IC_0_AXI4Lmtarget0_RDATA,
        TARGET0_RRESP        => AXI_IC_0_AXI4Lmtarget0_RRESP,
        -- Outputs
        INITIATOR0_AWREADY   => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWREADY,
        INITIATOR0_WREADY    => MSS_simple_0_FIC_0_AXI4_INITIATOR_WREADY,
        INITIATOR0_BVALID    => MSS_simple_0_FIC_0_AXI4_INITIATOR_BVALID,
        INITIATOR0_ARREADY   => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARREADY,
        INITIATOR0_RLAST     => MSS_simple_0_FIC_0_AXI4_INITIATOR_RLAST,
        INITIATOR0_RVALID    => MSS_simple_0_FIC_0_AXI4_INITIATOR_RVALID,
        TARGET0_AWVALID      => AXI_IC_0_AXI4Lmtarget0_AWVALID,
        TARGET0_WVALID       => AXI_IC_0_AXI4Lmtarget0_WVALID,
        TARGET0_BREADY       => AXI_IC_0_AXI4Lmtarget0_BREADY,
        TARGET0_ARVALID      => AXI_IC_0_AXI4Lmtarget0_ARVALID,
        TARGET0_RREADY       => AXI_IC_0_AXI4Lmtarget0_RREADY,
        INITIATOR0_BID       => MSS_simple_0_FIC_0_AXI4_INITIATOR_BID,
        INITIATOR0_BRESP     => MSS_simple_0_FIC_0_AXI4_INITIATOR_BRESP,
        INITIATOR0_RID       => MSS_simple_0_FIC_0_AXI4_INITIATOR_RID,
        INITIATOR0_RDATA     => MSS_simple_0_FIC_0_AXI4_INITIATOR_RDATA,
        INITIATOR0_RRESP     => MSS_simple_0_FIC_0_AXI4_INITIATOR_RRESP,
        INITIATOR0_BUSER     => MSS_simple_0_FIC_0_AXI4_INITIATOR_BUSER,
        INITIATOR0_RUSER     => MSS_simple_0_FIC_0_AXI4_INITIATOR_RUSER,
        TARGET0_AWADDR       => AXI_IC_0_AXI4Lmtarget0_AWADDR,
        TARGET0_AWPROT       => AXI_IC_0_AXI4Lmtarget0_AWPROT,
        TARGET0_WDATA        => AXI_IC_0_AXI4Lmtarget0_WDATA,
        TARGET0_WSTRB        => AXI_IC_0_AXI4Lmtarget0_WSTRB,
        TARGET0_ARADDR       => AXI_IC_0_AXI4Lmtarget0_ARADDR,
        TARGET0_ARPROT       => AXI_IC_0_AXI4Lmtarget0_ARPROT 
        );
-- axi_sys_ctrl_0
axi_sys_ctrl_0 : entity work.axi_sys_ctrl
    generic map( 
        ADDR_WIDTH => ( 38 )
        )
    port map( 
        -- Inputs
        ACLK        => PF_CCC_C0_0_OUT0_FABCLK_0,
        ARESETN     => CORERESET_0_FABRIC_RESET_N,
        AWADDR      => AXI_IC_0_AXI4Lmtarget0_AWADDR,
        AWPROT      => AXI_IC_0_AXI4Lmtarget0_AWPROT,
        AWVALID     => AXI_IC_0_AXI4Lmtarget0_AWVALID,
        WDATA       => AXI_IC_0_AXI4Lmtarget0_WDATA,
        WSTRB       => AXI_IC_0_AXI4Lmtarget0_WSTRB,
        WVALID      => AXI_IC_0_AXI4Lmtarget0_WVALID,
        BREADY      => AXI_IC_0_AXI4Lmtarget0_BREADY,
        ARADDR      => AXI_IC_0_AXI4Lmtarget0_ARADDR,
        ARPROT      => AXI_IC_0_AXI4Lmtarget0_ARPROT,
        ARVALID     => AXI_IC_0_AXI4Lmtarget0_ARVALID,
        RREADY      => AXI_IC_0_AXI4Lmtarget0_RREADY,
        -- Outputs
        AWREADY     => AXI_IC_0_AXI4Lmtarget0_AWREADY,
        WREADY      => AXI_IC_0_AXI4Lmtarget0_WREADY,
        BRESP       => AXI_IC_0_AXI4Lmtarget0_BRESP,
        BVALID      => AXI_IC_0_AXI4Lmtarget0_BVALID,
        ARREADY     => AXI_IC_0_AXI4Lmtarget0_ARREADY,
        RDATA       => AXI_IC_0_AXI4Lmtarget0_RDATA,
        RRESP       => AXI_IC_0_AXI4Lmtarget0_RRESP,
        RVALID      => AXI_IC_0_AXI4Lmtarget0_RVALID,
        LED2        => LED2_net_0,
        LED3        => LED3_net_0,
        DEBUG_PULSE => axi_sys_ctrl_0_DEBUG_PULSE 
        );
-- block_arbiter_0
block_arbiter_0 : entity work.block_arbiter
    generic map( 
        BLOCK_BYTES => ( 10 ),
        NUM_PORTS   => ( 2 )
        )
    port map( 
        -- Inputs
        clk     => PF_CCC_C0_0_OUT0_FABCLK_0,
        reset_n => CORERESET_0_FABRIC_RESET_N,
        m_ready => spi_tx_path_0_s_ready,
        s_data  => s_data_net_0,
        s_valid => s_valid_net_0,
        -- Outputs
        m_valid => block_arbiter_0_m_valid,
        s_ready => s_ready_net_0,
        m_data  => block_arbiter_0_m_data 
        );
-- button_debounce_0
button_debounce_0 : button_debounce
    port map( 
        -- Inputs
        clk         => PF_CCC_C0_0_OUT0_FABCLK_0,
        reset_n     => CORERESET_0_FABRIC_RESET_N,
        btn_in      => SWITCH2,
        -- Outputs
        pressed_out => LED4_net_0,
        pulse_out   => button_debounce_0_pulse_out 
        );
-- CLKINT_0
CLKINT_0 : CLKINT
    port map( 
        -- Inputs
        A => REF_CLK_50MHz,
        -- Outputs
        Y => CLKINT_0_Y 
        );
-- CORERESET_0
CORERESET_0 : CORERESET
    port map( 
        -- Inputs
        CLK                => PF_CCC_C0_0_OUT0_FABCLK_0,
        EXT_RST_N          => AND2_0_Y,
        BANK_x_VDDI_STATUS => VCC_net,
        BANK_y_VDDI_STATUS => VCC_net,
        PLL_LOCK           => PF_CCC_C0_0_PLL_LOCK_0,
        SS_BUSY            => GND_net,
        INIT_DONE          => INIT_MONITOR_0_DEVICE_INIT_DONE,
        FF_US_RESTORE      => GND_net,
        FPGA_POR_N         => INIT_MONITOR_0_FABRIC_POR_N,
        -- Outputs
        PLL_POWERDOWN_B    => CORERESET_0_PLL_POWERDOWN_B,
        FABRIC_RESET_N     => CORERESET_0_FABRIC_RESET_N 
        );
-- CORERESET_1_0
CORERESET_1_0 : CORERESET_1
    port map( 
        -- Inputs
        CLK                => PF_CCC_C0_0_OUT1_FABCLK_0,
        EXT_RST_N          => AND2_0_Y,
        BANK_x_VDDI_STATUS => VCC_net,
        BANK_y_VDDI_STATUS => VCC_net,
        PLL_LOCK           => PF_CCC_C0_0_PLL_LOCK_0,
        SS_BUSY            => GND_net,
        INIT_DONE          => INIT_MONITOR_0_DEVICE_INIT_DONE,
        FF_US_RESTORE      => GND_net,
        FPGA_POR_N         => INIT_MONITOR_0_FABRIC_POR_N,
        -- Outputs
        PLL_POWERDOWN_B    => OPEN,
        FABRIC_RESET_N     => CORERESET_1_0_FABRIC_RESET_N 
        );
-- INIT_MONITOR_0
INIT_MONITOR_0 : INIT_MONITOR
    port map( 
        -- Outputs
        FABRIC_POR_N               => INIT_MONITOR_0_FABRIC_POR_N,
        PCIE_INIT_DONE             => OPEN,
        USRAM_INIT_DONE            => OPEN,
        SRAM_INIT_DONE             => OPEN,
        DEVICE_INIT_DONE           => INIT_MONITOR_0_DEVICE_INIT_DONE,
        BANK_0_CALIB_STATUS        => OPEN,
        BANK_1_CALIB_STATUS        => OPEN,
        XCVR_INIT_DONE             => OPEN,
        USRAM_INIT_FROM_SNVM_DONE  => OPEN,
        USRAM_INIT_FROM_UPROM_DONE => OPEN,
        USRAM_INIT_FROM_SPI_DONE   => OPEN,
        SRAM_INIT_FROM_SNVM_DONE   => OPEN,
        SRAM_INIT_FROM_UPROM_DONE  => OPEN,
        SRAM_INIT_FROM_SPI_DONE    => OPEN,
        AUTOCALIB_DONE             => OPEN 
        );
-- MSS_simple_0
MSS_simple_0 : MSS_simple
    port map( 
        -- Inputs
        FIC_0_ACLK           => PF_CCC_C0_0_OUT0_FABCLK_0,
        FIC_0_AXI4_M_AWREADY => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWREADY,
        FIC_0_AXI4_M_WREADY  => MSS_simple_0_FIC_0_AXI4_INITIATOR_WREADY,
        FIC_0_AXI4_M_BVALID  => MSS_simple_0_FIC_0_AXI4_INITIATOR_BVALID,
        FIC_0_AXI4_M_ARREADY => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARREADY,
        FIC_0_AXI4_M_RLAST   => MSS_simple_0_FIC_0_AXI4_INITIATOR_RLAST,
        FIC_0_AXI4_M_RVALID  => MSS_simple_0_FIC_0_AXI4_INITIATOR_RVALID,
        MMUART_0_RXD_F2M     => UART0_RX,
        MSS_RESET_N_F2M      => VCC_net,
        REFCLK               => REFCLK,
        REFCLK_N             => REFCLK_N,
        FIC_0_AXI4_M_BID     => MSS_simple_0_FIC_0_AXI4_INITIATOR_BID,
        FIC_0_AXI4_M_BRESP   => MSS_simple_0_FIC_0_AXI4_INITIATOR_BRESP,
        FIC_0_AXI4_M_RID     => MSS_simple_0_FIC_0_AXI4_INITIATOR_RID,
        FIC_0_AXI4_M_RDATA   => MSS_simple_0_FIC_0_AXI4_INITIATOR_RDATA,
        FIC_0_AXI4_M_RRESP   => MSS_simple_0_FIC_0_AXI4_INITIATOR_RRESP,
        -- Outputs
        FIC_0_DLL_LOCK_M2F   => MSS_simple_0_FIC_0_DLL_LOCK_M2F,
        FIC_0_AXI4_M_AWLOCK  => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWLOCK,
        FIC_0_AXI4_M_AWVALID => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWVALID,
        FIC_0_AXI4_M_WLAST   => MSS_simple_0_FIC_0_AXI4_INITIATOR_WLAST,
        FIC_0_AXI4_M_WVALID  => MSS_simple_0_FIC_0_AXI4_INITIATOR_WVALID,
        FIC_0_AXI4_M_BREADY  => MSS_simple_0_FIC_0_AXI4_INITIATOR_BREADY,
        FIC_0_AXI4_M_ARLOCK  => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARLOCK,
        FIC_0_AXI4_M_ARVALID => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARVALID,
        FIC_0_AXI4_M_RREADY  => MSS_simple_0_FIC_0_AXI4_INITIATOR_RREADY,
        MMUART_0_TXD_M2F     => UART0_TX_net_0,
        MMUART_0_TXD_OE_M2F  => OPEN,
        PLL_CPU_LOCK_M2F     => OPEN,
        PLL_DDR_LOCK_M2F     => OPEN,
        MSS_RESET_N_M2F      => MSS_simple_0_MSS_RESET_N_M2F,
        RESET_N              => RESET_N_net_0,
        CKE0                 => CKE0_net_0,
        CS0_N                => CS0_N_net_0,
        ODT0                 => ODT0_net_0,
        CK0                  => CK0_net_0,
        CK0_N                => CK0_N_net_0,
        RAS_N                => RAS_N_net_0,
        WE_N                 => WE_N_net_0,
        CAS_N                => CAS_N_net_0,
        ACT_N                => ACT_N_net_0,
        BG0                  => BG0_net_0,
        FIC_0_AXI4_M_AWID    => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWID,
        FIC_0_AXI4_M_AWADDR  => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWADDR,
        FIC_0_AXI4_M_AWLEN   => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWLEN,
        FIC_0_AXI4_M_AWSIZE  => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWSIZE,
        FIC_0_AXI4_M_AWBURST => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWBURST,
        FIC_0_AXI4_M_AWQOS   => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWQOS,
        FIC_0_AXI4_M_AWCACHE => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWCACHE,
        FIC_0_AXI4_M_AWPROT  => MSS_simple_0_FIC_0_AXI4_INITIATOR_AWPROT,
        FIC_0_AXI4_M_WDATA   => MSS_simple_0_FIC_0_AXI4_INITIATOR_WDATA,
        FIC_0_AXI4_M_WSTRB   => MSS_simple_0_FIC_0_AXI4_INITIATOR_WSTRB,
        FIC_0_AXI4_M_ARID    => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARID,
        FIC_0_AXI4_M_ARADDR  => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARADDR,
        FIC_0_AXI4_M_ARLEN   => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARLEN,
        FIC_0_AXI4_M_ARSIZE  => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARSIZE,
        FIC_0_AXI4_M_ARBURST => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARBURST,
        FIC_0_AXI4_M_ARQOS   => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARQOS,
        FIC_0_AXI4_M_ARCACHE => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARCACHE,
        FIC_0_AXI4_M_ARPROT  => MSS_simple_0_FIC_0_AXI4_INITIATOR_ARPROT,
        BA                   => BA_net_0,
        DM                   => DM_net_0,
        A                    => A_net_0,
        -- Inouts
        DQ                   => DQ,
        DQS                  => DQS,
        DQS_N                => DQS_N 
        );
-- OR2_1
OR2_1 : OR2
    port map( 
        -- Inputs
        A => button_debounce_0_pulse_out,
        B => axi_sys_ctrl_0_DEBUG_PULSE,
        -- Outputs
        Y => OR2_1_Y 
        );
-- PF_CCC_C0_0
PF_CCC_C0_0 : PF_CCC_C0
    port map( 
        -- Inputs
        REF_CLK_0         => CLKINT_0_Y,
        PLL_POWERDOWN_N_0 => CORERESET_0_PLL_POWERDOWN_B,
        -- Outputs
        OUT0_FABCLK_0     => PF_CCC_C0_0_OUT0_FABCLK_0,
        OUT1_FABCLK_0     => PF_CCC_C0_0_OUT1_FABCLK_0,
        PLL_LOCK_0        => PF_CCC_C0_0_PLL_LOCK_0 
        );
-- pulse_stretch_0
pulse_stretch_0 : entity work.pulse_stretch
    generic map( 
        STRETCH_CYCLES => ( 125000 )
        )
    port map( 
        -- Inputs
        clk       => PF_CCC_C0_0_OUT0_FABCLK_0,
        reset_n   => CORERESET_0_FABRIC_RESET_N,
        pulse_in  => OR2_1_Y,
        -- Outputs
        pulse_out => DEBUG_net_0 
        );
-- qspi_board_0
qspi_board_0 : entity work.qspi_board
    generic map( 
        BLK_LEN    => ( 880 ),
        CALIBRATE  => ( 1 ),
        CLK_HZ     => ( 100000000 ),
        DEVICE_SEL => ( 0 ),
        NBLK       => ( 8 ),
        SAMPLE_DLY => ( 2 ),
        SCLK_DIV   => ( 1 )
        )
    port map( 
        -- Inputs
        clk       => PF_CCC_C0_0_OUT1_FABCLK_0,
        reset_n   => CORERESET_1_0_FABRIC_RESET_N,
        -- Outputs
        qspi_sclk => QSPI_SCLK_net_0,
        qspi_cs_n => QSPI_CS_N_net_0,
        bist_pass => LED5_net_0,
        bist_fail => LED6_net_0,
        -- Inouts
        qspi_io   => QSPI_IO 
        );
-- spi_tx_path_0
spi_tx_path_0 : spi_tx_path
    port map( 
        -- Inputs
        clk           => PF_CCC_C0_0_OUT0_FABCLK_0,
        reset_n       => CORERESET_0_FABRIC_RESET_N,
        s_valid       => block_arbiter_0_m_valid,
        s_data        => block_arbiter_0_m_data,
        -- Outputs
        s_ready       => spi_tx_path_0_s_ready,
        spi_sclk      => RPi_GPIO19_net_0,
        spi_mosi      => RPi_GPIO16_net_0,
        spi_cs_n      => RPi_GPIO26_net_0,
        busy_out      => OPEN,
        frame_err_out => OPEN 
        );
-- test_block_producer_0
test_block_producer_0 : entity work.test_block_producer
    generic map( 
        BLOCKS_PER_PRESS => ( 1 ),
        FIRST_BYTE       => ( 240 )
        )
    port map( 
        -- Inputs
        clk      => PF_CCC_C0_0_OUT0_FABCLK_0,
        reset_n  => CORERESET_0_FABRIC_RESET_N,
        start_in => OR2_1_Y,
        m_ready  => block_arbiter_0_s_ready0to0(0),
        -- Outputs
        m_valid  => test_block_producer_0_m_valid,
        m_data   => test_block_producer_0_m_data 
        );
-- test_block_producer_1
test_block_producer_1 : entity work.test_block_producer
    generic map( 
        BLOCKS_PER_PRESS => ( 1 ),
        FIRST_BYTE       => ( 170 )
        )
    port map( 
        -- Inputs
        clk      => PF_CCC_C0_0_OUT0_FABCLK_0,
        reset_n  => CORERESET_0_FABRIC_RESET_N,
        start_in => OR2_1_Y,
        m_ready  => block_arbiter_0_s_ready1to1(1),
        -- Outputs
        m_valid  => test_block_producer_1_m_valid,
        m_data   => test_block_producer_1_m_data 
        );

end RTL;
