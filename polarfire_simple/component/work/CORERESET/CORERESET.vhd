----------------------------------------------------------------------
-- Created by SmartDesign Wed Oct  7 11:09:51 2026
-- Version: 2026.1 2026.1.0.17
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Component Description (Tcl) 
----------------------------------------------------------------------
--# Exporting Component Description of CORERESET to TCL
--# Family: PolarFireSoC
--# Part Number: MPFS095T-1FCSG325E
--# Create and Configure the core component CORERESET
--create_and_configure_core -core_vlnv {Actel:DirectCore:CORERESET_PF:2.3.100} -component_name {CORERESET} -params { }
--# Exporting Component Description of CORERESET to TCL done

----------------------------------------------------------------------
-- Libraries
----------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library polarfire;
use polarfire.all;
----------------------------------------------------------------------
-- CORERESET entity declaration
----------------------------------------------------------------------
entity CORERESET is
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
end CORERESET;
----------------------------------------------------------------------
-- CORERESET architecture body
----------------------------------------------------------------------
architecture RTL of CORERESET is
----------------------------------------------------------------------
-- Component declarations
----------------------------------------------------------------------
-- CORERESET_CORERESET_0_CORERESET_PF   -   Actel:DirectCore:CORERESET_PF:2.3.100
component CORERESET_CORERESET_0_CORERESET_PF
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
----------------------------------------------------------------------
-- Signal declarations
----------------------------------------------------------------------
signal FABRIC_RESET_N_net_0  : std_logic;
signal PLL_POWERDOWN_B_net_0 : std_logic;
signal PLL_POWERDOWN_B_net_1 : std_logic;
signal FABRIC_RESET_N_net_1  : std_logic;

begin
----------------------------------------------------------------------
-- Top level output port assignments
----------------------------------------------------------------------
 PLL_POWERDOWN_B_net_1 <= PLL_POWERDOWN_B_net_0;
 PLL_POWERDOWN_B       <= PLL_POWERDOWN_B_net_1;
 FABRIC_RESET_N_net_1  <= FABRIC_RESET_N_net_0;
 FABRIC_RESET_N        <= FABRIC_RESET_N_net_1;
----------------------------------------------------------------------
-- Component instances
----------------------------------------------------------------------
-- CORERESET_0   -   Actel:DirectCore:CORERESET_PF:2.3.100
CORERESET_0 : CORERESET_CORERESET_0_CORERESET_PF
    port map( 
        -- Inputs
        CLK                => CLK,
        EXT_RST_N          => EXT_RST_N,
        BANK_x_VDDI_STATUS => BANK_x_VDDI_STATUS,
        BANK_y_VDDI_STATUS => BANK_y_VDDI_STATUS,
        PLL_LOCK           => PLL_LOCK,
        SS_BUSY            => SS_BUSY,
        INIT_DONE          => INIT_DONE,
        FF_US_RESTORE      => FF_US_RESTORE,
        FPGA_POR_N         => FPGA_POR_N,
        -- Outputs
        PLL_POWERDOWN_B    => PLL_POWERDOWN_B_net_0,
        FABRIC_RESET_N     => FABRIC_RESET_N_net_0 
        );

end RTL;
