set_component PF_CCC_C0_PF_CCC_C0_0_PF_CCC
# Microchip Technology Inc.
# Date: 2026-Oct-07 11:06:51
#

# Base clock for PLL #0
create_clock -period 20 [ get_pins { pll_inst_0/REF_CLK_0 } ]
create_generated_clock -multiply_by 5 -divide_by 2 -source [ get_pins { pll_inst_0/REF_CLK_0 } ] -phase 0 [ get_pins { pll_inst_0/OUT0 } ]
