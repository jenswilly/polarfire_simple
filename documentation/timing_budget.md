# QSPI timing budget (50 MHz SCLK, breakout wiring)

The budget behind `constraints/timing.sdc`. It covers the W25Q128JV prototype and the AS308G208 (device numbers from `device_facts.md`).

## Clocking in the PHY
- `clk_ctrl` = 100 MHz (10 ns), `SCLK_DIV` = 1, so SCLK = 50 MHz (20 ns). `sclk_r` toggles on every `clk_ctrl` edge while a transaction runs.
- **Outputs.** IO out, OE and CS# change on the `clk_ctrl` edge where SCLK falls. CS# low and the first data go out one edge before the first rising edge. Each value is therefore stable for 10 ns before and 10 ns after the rising edge that samples it.
- **Inputs.** The device drives new data after each falling edge. `io_i_r` samples it every `clk_ctrl` edge, and the PHY uses the sample taken `SAMPLE_DLY` edges after the falling edge. Sample points are therefore 10 ns apart.
- **Registers in the I/O cells** (`constraints/qspi_ioreg.ndc`): `sclk_r`, `cs_n_r` (output) and `io_i_r` (input). `io_o_r` and `io_oe_r` are fabric registers, because PolarFire combines only one register per I/O.
- **Clock insertion delay.** It is large: P&R reports about 4.8 ns (fast corner) to 7.6 ns (slow corner) from the CCC to the registers. It affects SCLK, the data outputs and the input capture equally. That is why the constraints are relative to SCLK at the pin (a generated clock): STA then compares SCLK and data in the same corner. Fixed clock-to-out limits relative to `clk_ctrl` would mix corners: clock-to-out is 6.7 ns at the fast corner and about 13 ns at the slow corner.

## Assumptions
| Item | Value | Note |
|---|---|---|
| Board delay per signal | 0.3 – 1.5 ns | ≤ 15 cm jumper wires + PCB trace to the header; SCLK and data independent |
| I/O standard | LVCMOS33, `-OUT_DRIVE 4` on SCLK and IO3:0 (CS# 8 mA default), pull-ups on CS#/IO2/IO3 | `constraints/io.pdc`; 4 mA since bring-up (`bringup.md`) |

## Device parameters used (worst of both)
| Parameter | W25Q128JV | AS308G208 | Used |
|---|---|---|---|
| Data in setup / hold (tDVCH/tCHDX, tSU/tHD) | 1 / 2 ns | 4 / 3 ns | 4 / 3 ns |
| CS# setup / hold (tSLCH/tCHSH, tCSS/tCSH) | 3 / 3 ns | 5 / 4 ns | 5 / 4 ns |
| Output valid (tCLQV, tCO) | ≤ 6 ns | ≤ 9 ns | 9 ns |
| Output hold (tCLQX, tOH) | ≥ 1.5 ns | ≥ 1 ns | 1 ns |

## FPGA → device (IO, CS#)
The device samples at the SCLK rising edge. The data was launched 10 ns earlier and changes again 10 ns later.

- Setup: `10 + t_sclk − t_data + b_sclk − b_data ≥ tSU`. In the SDC: `-max = tSU + b_data,max − b_sclk,min` = 4 + 1.5 − 0.3 = **5.2 ns**. For CS#: 5 + 1.2 = **6.2 ns**.
- Hold: `10 + t_data − t_sclk + b_data − b_sclk ≥ tHD`.
  - STA checks hold against a change on the same edge as the rising edge, so the 10 ns are folded into the min delay.
  - In the SDC: `-min = 10 + b_data,min − b_sclk,max − tHD` = 10 + 0.3 − 1.5 − 3 = **5.8 ns**. For CS#: 10 − 1.2 − 4 = **4.8 ns**.
- `t_sclk` and `t_data` are the FPGA clock-to-pin times, including the clock tree. STA gets them from the netlist.

## Device → FPGA (IO)
Data launched by SCLK falling at the pin arrives within `[b_sclk + tOH + b_data, b_sclk + tCO + b_data]` = **[1.6, 12.0] ns** after that edge. These are the `set_input_delay -clock_fall` min/max values.

`SAMPLE_DLY` = 2: the sample is taken 20 ns (one SCLK period) after the `clk_ctrl` edge that drove SCLK low.
- Setup: `20 + L_io − (L_sclk + 12.0) ≥ tSU,io`.
  - `L_sclk` is the FPGA delay from `clk_ctrl` to the SCLK pin; `L_io` is the clock delay to `io_i_r`.
  - The SDC sets a 2-cycle setup multicycle for this.
- Hold: the next word is launched exactly at the capture edge (relationship 0), so `L_sclk + 1.6 ≥ L_io + tH,io`. It holds because `L_sclk` includes the SCLK output delay and `L_io` doesn't.
- Rough numbers from the first P&R (slow corner): `L_sclk` ≈ 11–12 ns, `L_io` ≈ 7.6 ns.
  - Setup margin ≈ 20 + 7.6 − 24 ≈ 3.5 ns with the AS308G208.
  - With the W25Q128JV (tCLQV 6 ns) it is about 6.5 ns.
- `SAMPLE_DLY` = 1 (10 ns) misses setup by about 6 ns. `SAMPLE_DLY` = 3 (30 ns) breaks hold, because the next word arrives before it. So **2 is the only valid setting at 50 MHz**. The BIST calibration should find exactly {2}, maybe {1, 2} with short wires and a fast W25Q128JV.
- STA checks only the default `SAMPLE_DLY` = 2. Calibration picks the delay at run time.

## Slower SCLK
- With `SCLK_DIV` = 2 (25 MHz, used for 9Fh/05h on the AS308G208), data is valid for 40 ns. The 50 MHz case is the worst case.
- The sample point is still `SAMPLE_DLY` × 10 ns after the falling edge. That is well inside the window for both setup and hold.

## Results (Verify Timing, multi-corner, 2026-10-23, 4 mA drive on SCLK/IO)
All checks are met. The OUT1 and `qspi_sclk` domains have no unconstrained paths. The remaining unconstrained items are older pins outside the QSPI domain: SWITCH1/2, LED1–4, DEBUG and the RPi SPI pins.

| Check | 2026-10-23 (4 mA) | 2026-10-22 (8 mA) | Corner | Path |
|---|---|---|---|---|
| OUT1 register to register, setup / hold | 5.66 / 0.074 ns | 5.11 / 0.076 ns | slow_lv_ht / fast_hv_lt | inside `qspi_board`; hold: `CORERESET_1` |
| QSPI_IO input setup (`SAMPLE_DLY` = 2) | **1.91 ns** | 2.15 ns | slow_lv_ht | QSPI_IO[3] → `io_i_r[3]` |
| QSPI_IO input hold | 3.62 ns | 3.45 ns | fast_hv_lt | QSPI_IO[0] → `io_i_r[0]` |
| QSPI_IO output setup / hold | 3.48 / 4.24 ns | 3.48 / 4.58 ns | slow_lv_ht / slow_lv_lt | `io_o_r`, `io_oe_r` → QSPI_IO |
| QSPI_CS_N output setup / hold | 3.36 / 3.94 ns | 3.14 / 4.23 ns | slow_lv_ht / slow_lv_lt | `cs_n_r` → QSPI_CS_N |

Notes:
- SmartTime does propagate the generated clock through `sclk_r`. SCLK reaches the pin 9.9 / 11.3 ns (min / max, slow corner) and 6.7 ns (fast corner) after the CCC output edge. That is the clock tree, the IOREG and the output pad.
- The input setup slack uses the AS308G208's tCO = 9 ns. With the W25Q128JV (tCLQV = 6 ns) it is about 3 ns larger, i.e. about 4.9 ns.
- With 4 mA, SCLK reaches the pin later, which delays both the device's output data and the sampled SCLK edge relative to `io_i_r`: input setup drops by about 0.25 ns and CS# setup gains about 0.2 ns. The data outputs barely change.
- On hardware the BIST at 50 MHz found exactly this window: `SAMPLE_DLY` {2} (`bringup.md`).
- The I/O cell registers keep the input path at a fixed 0.55–1.2 ns (pad to `io_i_r`). The paths therefore don't change from one P&R run to the next.
