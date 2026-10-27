set_component PF_CCC_C0_PF_CCC_C0_0_PF_CCC
# Microchip Technology Inc.
# Date: 2026-Oct-27 09:31:11
#

# Base clock for PLL #0
create_clock -period 20 [ get_pins { pll_inst_0/REF_CLK_0 } ]
create_generated_clock -multiply_by 4 -source [ get_pins { pll_inst_0/REF_CLK_0 } ] -phase 0 [ get_pins { pll_inst_0/OUT0 } ]
