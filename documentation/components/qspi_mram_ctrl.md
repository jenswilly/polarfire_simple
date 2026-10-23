# qspi_mram_ctrl

QSPI memory controller top for the W25Q128JV (prototype) and the AS308G208 dual-die MRAM: memory init, credit-based read requests with an AXI4-Stream output, and write requests (tests/calibration). No tristates inside.
Source: `hdl/qspi_mram_ctrl.vhd`. Diagram: `documentation/qspi_controller.drawio`. Device facts: `documentation/device_facts.md`.

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `DEVICE` | `device_t` | `DEV_W25Q128JV` | `DEV_W25Q128JV` or `DEV_AS308G208` (`qspi_pkg`). |
| `DIE2_PRESENT` | boolean | false | Second die on IO7:4 / `sclk(1)` / `cs_n(1)`. |
| `CLK_CTRL_HZ` | positive | 100 000 000 | `clk` frequency. |
| `SCLK_DIV` | positive | 1 | SCLK = `CLK_CTRL_HZ` / (2·`SCLK_DIV`), max 4. |
| `SAMPLE_DLY` | positive | 2 | Default RX sample delay in clocks after the SCLK falling edge (1–4). |
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
| `rd_req_tdata` | in | 48 | Read request `{len[15:0], addr[31:0]}` in host bytes. |
| `rd_req_tvalid` | in | 1 | Request valid. |
| `rd_req_tready` | out | 1 | Request accepted. |
| `rd_req_err` | out | 1 | One-cycle pulse: request dropped. |
| `rd_space` | in | `SPACE_W` | Free bytes in the downstream buffer (credit). |
| `m_axis_tdata` | out | 8 | Read data byte. |
| `m_axis_tvalid` | out | 1 | Byte valid. |
| `m_axis_tready` | in | 1 | Consumer ready; must stay high as promised by `rd_space`. |
| `m_axis_tlast` | out | 1 | Last byte of a request. |
| **Write** | | | |
| `wr_req_tdata` | in | 48 | Write request `{len[15:0], addr[31:0]}` in host bytes. |
| `wr_req_tvalid` | in | 1 | Request valid. |
| `wr_req_tready` | out | 1 | Request accepted. |
| `wr_req_err` | out | 1 | One-cycle pulse: request dropped (its data not consumed). |
| `wr_done` | out | 1 | One-cycle pulse: request written. |
| `s_axis_wr_tdata` | in | 8 | Write data byte; `len` bytes per request. |
| `s_axis_wr_tvalid` | in | 1 | Byte valid. |
| `s_axis_wr_tready` | out | 1 | Byte accepted. |
| **Calibration** | | | |
| `sample_dly_ovr_valid` | in | 1 | Use `sample_dly_ovr` instead of `SAMPLE_DLY`. Change only while `busy` = 0. |
| `sample_dly_ovr` | in | 1–4 | Sample delay override (clocks). |
| **Pins** | | | |
| `sclk` | out | 2 | SCLK; index 0 = die 1, 1 = die 2. |
| `cs_n` | out | 2 | CS#; index 0 = die 1, 1 = die 2. |
| `io_o` | out | 8 | IO7:0 output data. |
| `io_oe` | out | 8 | IO7:0 output enable. Add tristate buffers outside. |
| `io_i` | in | 8 | IO7:0 input. |
| `mem_reset_n` | out | 1 | AS308G208 RESET# (always '1' for the W25Q128JV). |

## Usage notes

- **Host bytes:** one host byte per quad SCLK cycle = `{die2_nibble, die1_nibble}`; die address = host address / 2. With one die, the upper nibble is ignored on writes and 0 on reads.
- **Request rules:** address and length even, length ≠ 0, `addr + len` ≤ 2 × die size, and `init_done` = 1. Otherwise `*_req_err` pulses.
- **Read flow control:** a read starts only when `rd_space` covers it plus bytes still in flight, because SCLK can't stall. `m_axis_tready` must then stay high as promised. Reads are EBh 1-4-4.
- **Writes:** W25Q128JV erases every touched 4 KB sector, then page-programs (other data in those sectors is lost). AS308G208 uses one D2h per request.
- Reads and writes share the engine; a write keeps it for a whole request, a read that is delivering data is not cut short.
- With `DIE2_PRESENT` = false, `io_oe(7:4)` stays low; leave `sclk(1)` / `cs_n(1)` unconnected.
- The PHY's pad registers should be packed into the I/O cells (see `constraints/qspi_ioreg.ndc`).
- Size: ≈ 1.5k LUTs, 700 (W25Q) / 815 (AS, 2 dies) flip-flops.

## Sub-components

| Component | Purpose |
|---|---|
| [qspi_init](qspi_init.md) | Resets, identifies and configures the memory after reset / `init_restart`. |
| [qspi_read_ctrl](qspi_read_ctrl.md) | Turns read requests into EBh commands with credit-based flow control. |
| [qspi_write](qspi_write.md) | Turns write requests into erase/program (W25Q) or D2h (AS) commands. |
| [qspi_xact](qspi_xact.md) | Runs one command per CS# assertion and drives the pins through `qspi_phy`. |

## Testbench

`sim/tb_qspi_mram_ctrl.vhd` — `sim/run_tb.sh tb_qspi_mram_ctrl`. Uses the memory models; W25Q128JV and AS308G208 with 1 and 2 dies.

| Test | Checks |
|---|---|
| Init | Init completes on all configurations. |
| Write | 8 blocks of 880 host bytes; a read requested during the first write waits for it. |
| Write during read | A write requested while a read is delivering data does not cut the read short. |
| Read back | 8 blocks back to back (144.5 µs W25Q, 145.5 µs AS); all data compared. |
| Sample delay override | `SAMPLE_DLY` = 3 fails with a 3 ns board delay; `sample_dly_ovr` = 2 works. |
| `init_restart` | Requests during the rerun give `rd_req_err` / `wr_req_err`; a read afterwards works. |
| Protocol | Models report no protocol errors. |
