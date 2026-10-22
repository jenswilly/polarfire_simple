# Timing constraints for TOP (in addition to Libero's derived constraints)
# Link in Constraint Manager -> Timing, AFTER constraint/TOP_derived_constraints.sdc (it uses the
# CCC clocks defined there), and tick it for Place and Route and Timing Verification.
# Budget and derivation of every number: documentation/timing_budget.md
#
# Values cover both devices (worst of W25Q128JV and AS308G208) and the breakout wiring
# (board delay 0.3 .. 1.5 ns per signal, SCLK and data independent).

# ---------------------------------------------------------------------------------------------
# Clock domains: OUT0 (125 MHz, MSS/AXI/SPI TX) and OUT1 (100 MHz, qspi_board, clk_ctrl) are
# asynchronous. Only LED5/LED6 leave the QSPI domain (see below), so no paths cross.
set_clock_groups -asynchronous \
    -group [ get_clocks { PF_CCC_C0_0/PF_CCC_C0_0/pll_inst_0/OUT0 } ] \
    -group [ get_clocks { PF_CCC_C0_0/PF_CCC_C0_0/pll_inst_0/OUT1 qspi_sclk } ]

# ---------------------------------------------------------------------------------------------
# QSPI SCLK at the pin: sclk_r toggles on every clk_ctrl edge while running (SCLK_DIV = 1), so it
# is clk_ctrl / 2. The generated clock includes the clock tree and the SCLK clock-to-out, so SCLK
# and data are compared in the same corner. STA puts the rising edges on even clk_ctrl edges; the
# real phase varies per transaction, but only the edge relationships matter:
#   - IO out, OE and CS# change on the clk_ctrl edge of the SCLK falling edge (or the edge before
#     the first rising edge), i.e. 1 clk_ctrl cycle before the rising edge that samples them.
#   - The device drives new data after each falling edge; io_i_r captures it SAMPLE_DLY = 2
#     clk_ctrl cycles later (one SCLK period).
create_generated_clock -name { qspi_sclk } -divide_by 2 \
    -source [ get_pins { PF_CCC_C0_0/PF_CCC_C0_0/pll_inst_0/OUT1 } ] \
    [ get_ports { QSPI_SCLK } ]

# ---------------------------------------------------------------------------------------------
# FPGA -> device: IO3:0 (data and output enable) and CS#, sampled by the device at SCLK rising.
#   -max = tSU + board_data_max - board_sclk_min
#   -min = 10 + board_data_min - board_sclk_max - tHD
#     STA checks hold against the change on the same clk_ctrl edge as the rising edge (relationship
#     0 ns). The PHY never changes them on that edge, only 10 ns later (next falling edge), so
#     the 10 ns go into -min.
# IO:  tSU 4 ns (AS; W25Q 1 ns), tHD 3 ns (AS; W25Q 2 ns)    -> max 5.2, min 5.8
# CS#: tCSS 5 ns (AS; W25Q tSLCH 3), tCSH 4 ns (AS; W25Q tCHSH 3) -> max 6.2, min 4.8
set_output_delay -max 5.2 -clock { qspi_sclk } [ get_ports { QSPI_IO[*] } ]
set_output_delay -min 5.8 -clock { qspi_sclk } [ get_ports { QSPI_IO[*] } ]
set_output_delay -max 6.2 -clock { qspi_sclk } [ get_ports { QSPI_CS_N } ]
set_output_delay -min 4.8 -clock { qspi_sclk } [ get_ports { QSPI_CS_N } ]

# ---------------------------------------------------------------------------------------------
# Device -> FPGA: IO3:0, launched by the device after SCLK falling.
#   -max = board_sclk_max + tCLQV/tCO + board_data_max = 1.5 + 9 (AS; W25Q 6) + 1.5 = 12.0
#   -min = board_sclk_min + tCLQX/tOH + board_data_min = 0.3 + 1 (AS; W25Q 1.5) + 0.3 = 1.6
# Captured SAMPLE_DLY = 2 clk_ctrl cycles after the launching edge: setup at 2 cycles; hold
# stays at 0 (the next word is launched exactly at the capture edge).
set_input_delay -max 12.0 -clock { qspi_sclk } -clock_fall [ get_ports { QSPI_IO[*] } ]
set_input_delay -min 1.6  -clock { qspi_sclk } -clock_fall [ get_ports { QSPI_IO[*] } ]
set_multicycle_path 2 -setup_only -from [ get_ports { QSPI_IO[*] } ]

# ---------------------------------------------------------------------------------------------
# Static outputs: BIST pass/fail LEDs
set_false_path -to [ get_ports { LED5 LED6 } ]
