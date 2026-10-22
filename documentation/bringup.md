# QSPI bring-up: W25Q128JV breakout (PLAN.md Step 13)

## Setup
- Adafruit QSPI DIP breakout (product 5634, W25Q128JVSSIQ). The board only routes the chip pins to two 1×4 headers: no pull-ups, no decoupling capacitor ([schematic](https://github.com/adafruit/Adafruit-QSPI-DIP-Breakout-PCB)).
- Wired to the RPi header with about 10 cm jumper wires (pins in README.md), one GND wire (pin 9), 3.3 V from pin 17.
- `qspi_board_0`: DEVICE_SEL 0, CLK_HZ 100 MHz, SAMPLE_DLY 2, CALIBRATE 1, NBLK 8, BLK_LEN 880.
- Logic analyzer: Saleae Logic Pro 8 on CS#, SCLK and IO0–3 at the breakout, exported as CSV and decoded with a script (opcodes, addresses, status bytes, data nibbles against the BIST pattern).
- SmartDebug Active Probe for the BIST and init registers (`qspi_board_0/bist/…`, `qspi_board_0/ctrl/init/…`).

## Results
| SCLK | SCLK_DIV | Result | Calibration window | Notes |
|---|---|---|---|---|
| 50 MHz | 1 | Fail (LED6) | 0000 | Init passed; before the fixes below |
| 12.5 MHz | 4 | Fail (LED6) | 0000 | Same; analyzer showed fixes 1 and 2 |
| 12.5 MHz | 4 | **Pass (LED5)** | {2, 3, 4} → 3 | After fixes 1–4. Delay 1 (10 ns) is too early (timing budget: misses by ~6 ns) |
| 25 MHz | 2 | **Pass (LED5)** | not read | BIST runs one round by default now (`LOOP_ROUNDS`) |
| 50 MHz | 1 | TBD | TBD | |

## Problems found and fixes
1. **Erase/program ignored: CS# high too short after WREN** (HDL).
   - Analyzer: WREN, then only 10 ns CS# high, then 20h. The next 05h returned `02h`: WEL set, not busy. The erase never started, and the whole sequence took 3 ms.
   - The W25Q needs tSHSL2 ≥ 50 ns after "Erase or Program or Write" commands. WREN counts as one.
   - Fix: `qspi_write` issues WREN with `cmd_write = '1'`. The memory model now checks the write CS# time after WREN too.
2. **IO1 bad when driven by the FPGA** (wiring).
   - During quad write data, 30–45 % of the IO1 bits were wrong, with edges chattering for up to 120 ns. IO0/2/3 were clean, and IO1 was clean when the chip drove it (9Fh).
   - A high-resistance contact between RPi pin 16 and the breakout. Fix: new jumper.
3. **CS# high a few ns short at the pin** (HDL).
   - Measured 6–8 ns for the 10 ns minimum and 46–48 ns for 50 ns: CS# rises slower than it falls.
   - Fix: `qspi_xact` adds one clk_ctrl cycle to both (20 / 60 ns at 100 MHz).
4. **32h page program accepted but not executed** (signal integrity).
   - The command was correct at the breakout: byte-aligned, right data. But the status afterwards was `00h`: WEL cleared, BUSY never set. The erase (IO0 only) worked.
   - Most likely ground bounce from IO0–3 switching together over one GND wire, so the chip counts an extra SCLK edge.
   - Fix: `-OUT_DRIVE 4` (default 8 mA) on SCLK and IO0–3 in `constraints/io.pdc`. A 100 nF capacitor at the breakout and more GND wires are still recommended.

## Next steps
1. Fit 100 nF between 3V and GND directly on the breakout (and preferably a second GND wire, RPi pin 14, 20 or 25).
2. 50 MHz: `SCLK_DIV` = 1 → Generate, synthesis, P&R, **Verify Timing** (the I/O drive is now 4 mA, so recheck the output slack in `timing_budget.md`), program.
3. Check LED5, and read `bist/window[4:1]` and `bist/ovr_d[2:0]` with Active Probe.
4. Optional: read the 25 MHz window too for the table.
5. Then Step 13 is done; commit. Step 14 (AS308G208 dual die) needs the target PCB.
- Expected at 50 MHz: {2}, maybe {1, 2} (`documentation/timing_budget.md`).
- `constraints/timing.sdc` assumes SCLK_DIV = 1 (`-divide_by 2`). The timing report is only meaningful for that build.
