# qspi_mram_ctrl

QSPI memory controller top for the W25Q128JV (prototype) and one port/die of the AS308G208 MRAM (the other die is on the MSS): memory init, credit-based read requests with an AXI4-Stream output, and write requests (tests/calibration). No tristates inside.
Source: `hdl/qspi_mram_ctrl.vhd`. Diagram: `documentation/qspi_controller.drawio`. Device facts: `documentation/device_facts.md`.

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `DEVICE` | `device_t` | `DEV_W25Q128JV` | `DEV_W25Q128JV` or `DEV_AS308G208` (`qspi_pkg`). |
| `CLK_CTRL_HZ` | positive | 200 000 000 | `clk` frequency. |
| `SCLK_DIV` | positive | 2 | SCLK = `CLK_CTRL_HZ` / (2·`SCLK_DIV`), max 8. |
| `SAMPLE_DLY` | positive | 4 | Default RX sample delay in clocks after the SCLK falling edge (1–8). |
| `SPACE_W` | positive | 16 | Width of `rd_space`. |
| `T_POWERUP_NS` | natural | 0 | Power-up wait; 0 = datasheet value. |
| `T_RESET_NS` | natural | 0 | Reset time; 0 = datasheet value. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. Init runs after reset. |
| **Init / status** | | | |
| `init_restart` | in | 1 | Pulse: run init again (accepted when done or failed). |
| `init_done` | out | 1 | Init finished OK. Held until the next run. |
| `init_err` | out | 1 | Init failed. Held until the next run. |
| `init_err_code` | out | 2 | `01` = wrong ID, `10` = register check failed. |
| `init_step` | out | 5 | Current init step (debug). |
| `busy` | out | 1 | Any request or command in progress. |
| **Read** | | | |
| `rd_req_tdata` | in | 48 | Read request `{len[15:0], addr[31:0]}` in bytes. |
| `rd_req_tvalid` | in | 1 | Request valid. |
| `rd_req_tready` | out | 1 | Request accepted. |
| `rd_req_err` | out | 1 | One-cycle pulse: request dropped. |
| `rd_space` | in | `SPACE_W` | Free bytes in the downstream buffer (credit). |
| `m_axis_tdata` | out | 8 | Read data byte. |
| `m_axis_tvalid` | out | 1 | Byte valid. |
| `m_axis_tready` | in | 1 | Consumer ready; must stay high as promised by `rd_space`. |
| `m_axis_tlast` | out | 1 | Last byte of a request. |
| **Write** | | | |
| `wr_req_tdata` | in | 48 | Write request `{len[15:0], addr[31:0]}` in bytes. |
| `wr_req_tvalid` | in | 1 | Request valid. |
| `wr_req_tready` | out | 1 | Request accepted. |
| `wr_req_err` | out | 1 | One-cycle pulse: request dropped (its data not consumed). |
| `wr_done` | out | 1 | One-cycle pulse: request written. |
| `s_axis_wr_tdata` | in | 8 | Write data byte; `len` bytes per request. |
| `s_axis_wr_tvalid` | in | 1 | Byte valid. |
| `s_axis_wr_tready` | out | 1 | Byte accepted. |
| **Calibration** | | | |
| `sample_dly_ovr_valid` | in | 1 | Use `sample_dly_ovr` instead of `SAMPLE_DLY`. Change only while `busy` = 0. |
| `sample_dly_ovr` | in | 1–8 | Sample delay override (clocks); registered, takes effect one clock later. |
| **Pins** | | | |
| `sclk` | out | 1 | SCLK. |
| `cs_n` | out | 1 | CS#. |
| `io_o` | out | 4 | IO3:0 output data. |
| `io_oe` | out | 4 | IO3:0 output enable. Add tristate buffers outside. |
| `io_i` | in | 4 | IO3:0 input. |
| `mem_reset_n` | out | 1 | AS308G208 RESET# (always '1' for the W25Q128JV). |

## Usage notes

- **Bytes:** addresses and lengths are device bytes. Each byte takes two quad SCLK cycles on IO3:0, high nibble first (8 × 880 bytes ≈ 286 µs at 50 MHz).
- **Request rules:** length ≠ 0, `addr + len` ≤ die size, and `init_done` = 1. Any address and length otherwise. Otherwise `*_req_err` pulses.
- **Read flow control:** a read starts only when `rd_space` covers it plus bytes still in flight, because SCLK can't stall. `m_axis_tready` must then stay high as promised. Reads are EBh 1-4-4.
- **Writes:** W25Q128JV erases every touched 4 KB sector, then page-programs (other data in those sectors is lost). AS308G208 uses one D2h per request.
- Reads and writes share the engine; a write keeps it for a whole request, a read that is delivering data is not cut short.
- The PHY's pad registers should be packed into the I/O cells (see `constraints/qspi_ioreg.ndc`).
- Size (Synplify, standalone): 1.5k LUTs / 750 flip-flops (W25Q), 1.2k LUTs / 710 flip-flops (AS).

## Sub-components

| Component | Purpose |
|---|---|
| [qspi_init](qspi_init.md) | Resets, identifies and configures the memory after reset / `init_restart`. |
| [qspi_read_ctrl](qspi_read_ctrl.md) | Turns read requests into EBh commands with credit-based flow control. |
| [qspi_write](qspi_write.md) | Turns write requests into erase/program (W25Q) or D2h (AS) commands. |
| [qspi_xact](qspi_xact.md) | Runs one command per CS# assertion and drives the pins through `qspi_phy`. |

## Testbench

`sim/tb_qspi_mram_ctrl.vhd` — `sim/run_tb.sh tb_qspi_mram_ctrl`. Uses the memory models; W25Q128JV and AS308G208 (one port/die).

| Test | Checks |
|---|---|
| Init | Init completes on all configurations. |
| Write | 8 blocks of 880 bytes; a read requested during the first write waits for it. |
| Write during read | A write requested while a read is delivering data does not cut the read short. |
| Read back | 8 blocks back to back (285.1 µs W25Q, 286.0 µs AS), then an odd-length read at an odd address; all data compared. |
| Sample delay override | `SAMPLE_DLY` = 6 fails with a 3 ns board delay; `sample_dly_ovr` = 4 works. |
| `init_restart` | Requests during the rerun give `rd_req_err` / `wr_req_err`; a read afterwards works. |
| Protocol | Models report no protocol errors. |
