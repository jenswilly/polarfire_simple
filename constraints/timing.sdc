# Timing constraints for TOP (in addition to Libero's derived constraints)
# Link in Constraint Manager -> Timing, AFTER constraint/TOP_derived_constraints.sdc (it uses the
# CCC clock defined there), and tick it for Place and Route and Timing Verification.
# Budget and derivation of every number: documentation/timing_budget.md
#
# Values cover both devices (worst of W25Q128JV and AS308G208) and the breakout wiring
# (board delay 0.3 .. 1.5 ns per signal, SCLK and data independent).
#
# Single fabric clock: PF_CCC_C0 OUT0 = 200 MHz (clk_ctrl of qspi_board, MSS FIC_0, everything
# else). The QSPI numbers assume qspi_board's SCLK_DIV = 2 and SAMPLE_DLY = 4.

# ---------------------------------------------------------------------------------------------
# QSPI SCLK at the pin: sclk_r toggles every 2nd clk_ctrl edge while running (SCLK_DIV = 2), so it
# is clk_ctrl / 4 = 50 MHz. The generated clock includes the clock tree and the SCLK clock-to-out,
# so SCLK and data are compared in the same corner. STA puts the rising edges on every 4th
# clk_ctrl edge; the real phase varies per transaction, but only the edge relationships matter:
#   - IO out, OE and CS# change on the clk_ctrl edge of the SCLK falling edge (or 2 edges before
#     the first rising edge), i.e. 2 clk_ctrl cycles (10 ns) before the rising edge that samples
#     them, and 2 cycles after it.
#   - The device drives new data after each falling edge; io_i_r captures it SAMPLE_DLY = 4
#     clk_ctrl cycles later (one SCLK period).
create_generated_clock -name { qspi_sclk } -divide_by 4 \
    -source [ get_pins { PF_CCC_C0_0/PF_CCC_C0_0/pll_inst_0/OUT0 } ] \
    [ get_ports { QSPI_SCLK } ]

# ---------------------------------------------------------------------------------------------
# FPGA -> device: IO3:0 (data and output enable) and CS#, sampled by the device at SCLK rising.
#   -max = tSU + board_data_max - board_sclk_min - 5
#     STA checks setup from the clk_ctrl edge 5 ns before the rising edge (the closest one). The
#     PHY changes them 10 ns before it, so 5 ns come off -max.
#   -min = 10 + board_data_min - board_sclk_max - tHD
#     STA checks hold against the change on the same clk_ctrl edge as the rising edge (relationship
#     0 ns). The PHY never changes them on that edge, only 10 ns later (next falling edge), so
#     the 10 ns go into -min.
# IO:  tSU 4 ns (AS; W25Q 1 ns), tHD 3 ns (AS; W25Q 2 ns)    -> max 0.2, min 5.8
# CS#: tCSS 5 ns (AS; W25Q tSLCH 3), tCSH 4 ns (AS; W25Q tCHSH 3) -> max 1.2, min 4.8
set_output_delay -max 0.2 -clock { qspi_sclk } [ get_ports { QSPI_IO[*] } ]
set_output_delay -min 5.8 -clock { qspi_sclk } [ get_ports { QSPI_IO[*] } ]
set_output_delay -max 1.2 -clock { qspi_sclk } [ get_ports { QSPI_CS_N } ]
set_output_delay -min 4.8 -clock { qspi_sclk } [ get_ports { QSPI_CS_N } ]

# ---------------------------------------------------------------------------------------------
# Device -> FPGA: IO3:0, launched by the device after SCLK falling.
#   -max = board_sclk_max + tCLQV/tCO + board_data_max = 1.5 + 9 (AS; W25Q 6) + 1.5 = 12.0
#   -min = board_sclk_min + tCLQX/tOH + board_data_min = 0.3 + 1 (AS; W25Q 1.5) + 0.3 = 1.6
# Captured SAMPLE_DLY = 4 clk_ctrl cycles after the launching edge: setup at 4 cycles; hold
# stays at 0 (the next word is launched exactly at the capture edge).
set_input_delay -max 12.0 -clock { qspi_sclk } -clock_fall [ get_ports { QSPI_IO[*] } ]
set_input_delay -min 1.6  -clock { qspi_sclk } -clock_fall [ get_ports { QSPI_IO[*] } ]
set_multicycle_path 4 -setup_only -from [ get_ports { QSPI_IO[*] } ]

# ---------------------------------------------------------------------------------------------
# Pins without a timing relationship to the clock (intentionally not timed, so the coverage report
# only shows real gaps):
#   - SWITCH2: asynchronous button, into button_debounce's two-flop synchronizer
#   - LED2..LED6: static outputs (AXI LEDs, debounced SWITCH2, BIST pass/fail)
#   - DEBUG: 1 ms pulse
#   - RPi SPI (GPIO19 SCLK, GPIO16 MOSI, GPIO26 CS_N): 20 MHz; MOSI/CS_N change half an SCLK
#     period (25 ns) before the sampling edge and SCLK/data reach the pins within a few ns of each
#     other, so the receiver's setup/hold is met with a wide margin. Not checked by STA.
set_false_path -from [ get_ports { SWITCH2 } ]
set_false_path -to [ get_ports { LED2 LED3 LED4 LED5 LED6 DEBUG } ]
set_false_path -to [ get_ports { RPi_GPIO19 RPi_GPIO16 RPi_GPIO26 } ]
