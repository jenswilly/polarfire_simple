--------------------------------------------------------------------------------
-- Company: <Name>
--
-- File: corereset_pf.vhd
-- File history:
--      <Revision number>: <Date>: <Comments>
--      <Revision number>: <Date>: <Comments>
--      <Revision number>: <Date>: <Comments>
--
-- Description: 
--
-- <Description here>
--
-- Targeted device: <Family::PolarFire> <Die::MPF300T_ES> <Package::FCG1152>
-- Author: <Name>
--
--------------------------------------------------------------------------------

library IEEE;

use IEEE.std_logic_1164.all;

entity CORERESET_1_CORERESET_1_0_corereset_pf is
port (
	CLK                 : IN    std_logic;
    EXT_RST_N           : IN    std_logic;
    PLL_LOCK            : IN    std_logic;
    SS_BUSY             : IN    std_logic;
    FF_US_RESTORE          : IN    std_logic;
    BANK_x_VDDI_STATUS  : IN    std_logic;
    BANK_y_VDDI_STATUS  : IN    std_logic;
    INIT_DONE           : IN    std_logic;
    FPGA_POR_N          : IN    std_logic;
    PLL_POWERDOWN_B     : OUT   std_logic;
    FABRIC_RESET_N      : OUT   std_logic);
end CORERESET_1_CORERESET_1_0_corereset_pf;

architecture architecture_corereset_pf of CORERESET_1_CORERESET_1_0_corereset_pf is
	signal A : std_logic;
    signal B : std_logic;
    signal C : std_logic;
    signal D : std_logic;
    signal INTERNAL_RST : std_logic;
    signal dff_0  : std_logic:='1';
    signal dff_1  : std_logic:='1';
    signal dff_2  : std_logic:='1';
    signal dff_3  : std_logic:='1';
    signal dff_4  : std_logic:='1';
    signal dff_5  : std_logic:='1';
    signal dff_6  : std_logic:='1';
    signal dff_7  : std_logic:='1';
    signal dff_8  : std_logic:='1';
    signal dff_9  : std_logic:='1';
    signal dff_10 : std_logic:='1';
    signal dff_11 : std_logic:='1';
    signal dff_12 : std_logic:='1';
    signal dff_13 : std_logic:='1';
    signal dff_14 : std_logic:='1';
    signal dff_15 : std_logic:='1';

	
begin
    A<= NOT(NOT(EXT_RST_N)OR NOT(BANK_x_VDDI_STATUS));
    B<= NOT(NOT(A) OR NOT(PLL_LOCK));
    C<= NOT(NOT(B) AND NOT(SS_BUSY));
    D<= NOT(NOT(C) OR NOT(INIT_DONE));
    INTERNAL_RST <= NOT(NOT(D) AND NOT(FF_US_RESTORE));
    PLL_POWERDOWN_B <= NOT(NOT(BANK_y_VDDI_STATUS) OR NOT(FPGA_POR_N));


    dff0_proc: process(CLK, INTERNAL_RST)
    begin
       if (INTERNAL_RST = '0') then 
          
            dff_0 <= '0';
            dff_1 <= '0';
            dff_2 <= '0';
            dff_3 <= '0';
            dff_4 <= '0';
            dff_5 <= '0';
            dff_6 <= '0';
            dff_7 <= '0';
            dff_8 <= '0';
            dff_9 <= '0';
            dff_10 <= '0';
            dff_11 <= '0';
            dff_12 <= '0';
            dff_13 <= '0';
            dff_14 <= '0';
            dff_15 <= '0';

       elsif (CLK'event and CLK = '1') then 
              dff_0 <= '1';
              dff_1 <= dff_0;
              dff_2 <= dff_1;
              dff_3 <= dff_2;
              dff_4 <= dff_3;
              dff_5 <= dff_4;
              dff_6 <= dff_5;
              dff_7 <= dff_6;
              dff_8 <= dff_7;
              dff_9 <= dff_8;
              dff_10 <= dff_9;
              dff_11 <= dff_10;
              dff_12 <= dff_11;
              dff_13 <= dff_12;
              dff_14 <= dff_13;
              dff_15 <= dff_14; 
       end if;
    end process dff0_proc;



    FABRIC_RESET_N <= NOT(NOT(dff_15) AND NOT(FF_US_RESTORE)); 

   
end architecture_corereset_pf;
