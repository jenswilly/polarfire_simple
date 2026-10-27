# qspi_board

QSPI memory controller + BIST with board-level tristate pins, single die. Runs the BIST on its own after reset and reports pass/fail (LEDs in TOP).
Source: `hdl/qspi_board.vhd`. Used as an HDL+ core in TOP; the generics are integers because the HDL+ configurator only handles integers.

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `DEVICE_SEL` | natural 0–1 | 0 | 0: W25Q128JV, 1: AS308G208 (one die). |
| `CLK_HZ` | positive | 200 000 000 | `clk` frequency. |
| `SCLK_DIV` | positive 1–8 | 2 | SCLK = `CLK_HZ` / (2·`SCLK_DIV`). |
| `SAMPLE_DLY` | positive 1–8 | 4 | RX sample delay (clocks) before calibration. |
| `CALIBRATE` | natural 0–1 | 1 | 1: BIST calibrates the sample delay. |
| `NBLK` | positive | 8 | BIST blocks. |
| `BLK_LEN` | positive | 880 | BIST host bytes per block (even). |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | `clk_ctrl`, the 200 MHz fabric clock (4 × SCLK for `SCLK_DIV` = 2). |
| `reset_n` | in | 1 | Synchronous to `clk`, active low. |
| `qspi_sclk` | out | 1 | SCLK pin. |
| `qspi_cs_n` | out | 1 | CS# pin. |
| `qspi_io` | inout | 4 | IO3:0 pins (tristate inside). |
| `bist_pass` | out | 1 | On after the first correct read round, while no failure. |
| `bist_fail` | out | 1 | Latched on any failure until reset. |

## Usage notes

- The BIST reads once and stops (`LOOP_ROUNDS` = false); block stride 0x4000, base address 0.
- With `DEVICE_SEL` = 1, the AS308G208 RESET# must be tied high on the board (not a port here). A dual-die board needs a different wrapper.
- The pad registers are in `qspi_phy`; `constraints/qspi_ioreg.ndc` packs them into the I/O cells. Timing: `constraints/timing.sdc`.

## Sub-components

| Component | Purpose |
|---|---|
| [qspi_mram_ctrl](qspi_mram_ctrl.md) | QSPI controller: init, read and write requests to the memory pins. |
| [qspi_bist](qspi_bist.md) | Writes a pattern, calibrates the sample delay and reads/compares it. |

## Testbench

`sim/tb_qspi_board.vhd` — `sim/run_tb.sh tb_qspi_board`. Uses the W25Q128JV model (`-- run_tb models: qspi_model_pkg qspi_mem_model`).

| Test | Checks |
|---|---|
| BIST on the pins | With the model on `qspi_io` (datasheet power-up time, calibration on, 2 blocks of 64 host bytes), `bist_pass` comes on and stays on. |
| Protocol | The model reports no protocol errors. |
| Wiring | Covers the tristate wiring and the generic mapping. |
