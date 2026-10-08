# Microchip Technology Inc.
# Date: 2026-Oct-07 12:00:51
# This file was generated based on the following SDC source files:
#   /home/jenswilly/Projs/polarfire_simple/polarfire_simple/component/work/AXI_IC/AXI_IC_0/AXI_IC.sdc
#   /home/jenswilly/Projs/polarfire_simple/polarfire_simple/component/work/MSS_simple/MSS_simple.sdc
#   /home/jenswilly/Projs/polarfire_simple/polarfire_simple/component/work/PF_CCC_C0/PF_CCC_C0_0/PF_CCC_C0_PF_CCC_C0_0_PF_CCC.sdc
# *** Any modifications to this file will be lost if derived constraints is re-run. ***
#

create_clock -name {REF_CLK_50MHz} -period 20 [ get_ports { REF_CLK_50MHz } ]
create_generated_clock -name {PF_CCC_C0_0/PF_CCC_C0_0/pll_inst_0/OUT0} -multiply_by 5 -divide_by 2 -source [ get_pins { PF_CCC_C0_0/PF_CCC_C0_0/pll_inst_0/REF_CLK_0 } ] -phase 0 [ get_pins { PF_CCC_C0_0/PF_CCC_C0_0/pll_inst_0/OUT0 } ]
set_false_path -through [ get_nets { AXI_IC_0/ARESETN* } ]
