# qspi_bist

Built-in self-test for [qspi_mram_ctrl](qspi_mram_ctrl.md): waits for init, writes a test pattern once, optionally calibrates the RX sample delay, then reads and compares. Fabric only, no software.
Source: `hdl/qspi_bist.vhd`. Used inside [qspi_board](qspi_board.md).

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `DIE2_PRESENT` | boolean | false | false: only the low nibble of each host byte is written and compared. |
| `NBLK` | positive | 8 | Number of blocks. |
| `BLK_LEN` | positive | 880 | Host bytes per block (even). |
| `BLK_STRIDE` | positive | 16#4000# | Host bytes between block starts (W25Q: 2 sectors). |
| `BASE_ADDR` | natural | 0 | Host address of block 0 (even). |
| `CALIBRATE` | boolean | false | Retry init with sample delays 1–8 and pick the delay from a read sweep. |
| `LOOP_ROUNDS` | boolean | false | Keep reading and comparing until reset; false = one round, then stop. |
| `SPACE_W` | positive | 16 | Width of `rd_space`. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `init_restart` | out | 1 | Restarts init (calibration retries). |
| `init_done` | in | 1 | From the controller. |
| `init_err` | in | 1 | From the controller. |
| `ctrl_busy` | in | 1 | Controller `busy`. Registered inside the BIST (timing at 200 MHz). |
| `rd_req_tdata` | out | 48 | Read request `{len[15:0], addr[31:0]}`. |
| `rd_req_tvalid` | out | 1 | Read request valid. |
| `rd_req_tready` | in | 1 | Read request accepted. |
| `rd_req_err` | in | 1 | Read request rejected. |
| `rd_space` | out | `SPACE_W` | Free read buffer space; always the maximum. |
| `rd_tdata` | in | 8 | Read data byte. |
| `rd_tvalid` | in | 1 | Read byte valid. |
| `rd_tready` | out | 1 | Always ready. |
| `rd_tlast` | in | 1 | Last byte of a read request. |
| `wr_req_tdata` | out | 48 | Write request `{len[15:0], addr[31:0]}`. |
| `wr_req_tvalid` | out | 1 | Write request valid. |
| `wr_req_tready` | in | 1 | Write request accepted. |
| `wr_req_err` | in | 1 | Write request rejected. |
| `wr_done` | in | 1 | Write request completed. |
| `wr_tdata` | out | 8 | Write data byte (pattern). |
| `wr_tvalid` | out | 1 | Write byte valid. |
| `wr_tready` | in | 1 | Write byte accepted. |
| `sample_dly_ovr_valid` | out | 1 | Use `sample_dly_ovr` instead of the controller's `SAMPLE_DLY`. |
| `sample_dly_ovr` | out | 1–8 | Sample delay for the controller. |
| `pass` | out | 1 | On after the first complete correct read round, while no failure. |
| `fail` | out | 1 | Init error (after retries), request error, no passing delay or data mismatch. Latched. |
| `cal_window` | out | 8 | Bit *d* = sample delay *d* passed (`CALIBRATE`). |
| `cal_dly` | out | 1–8 | Sample delay in use (`CALIBRATE`). |
| `pass_count` | out | 16 | Number of correct rounds. |
| `state_dbg` | out | 4 | Internal state number (debug). |

## Usage notes

- Pattern: host byte *i* of block *k* = (k·7 + i) mod 256 at `BASE_ADDR + k·BLK_STRIDE`. On the W25Q128JV the sectors are erased first; the pattern is written once per reset only (flash endurance).
- Calibration picks the middle of the first passing run of delays (lower middle for an even width).
- `pass` and `fail` are both off while init and the first round run.
- The sample delay override is changed only while the controller is idle. After a failed init the BIST waits for `busy` = 0 and then sets the next delay and restarts init in the same cycle. Before 2026-10-27 it set the delay as soon as `init_err` rose, while the failed init's last transaction could still be running in the PHY.
- `ctrl_busy` is used one cycle late (registered). That is safe: only the BIST makes the controller busy, and it sends nothing in the states that wait for idle.

## Testbench

`sim/tb_qspi_bist.vhd` — `sim/run_tb.sh tb_qspi_bist`. Runs `qspi_bist` + `qspi_mram_ctrl` against the memory models, 4 blocks of 880 host bytes, `clk_ctrl` 200 MHz, SCLK 50 MHz.

| Test | Checks |
|---|---|
| W25Q, no calibration | Pass. |
| W25Q, calibration | Board delay where delays 2–4 work: window `00001110`, picks 3, pass, one round only. |
| AS308G208, 2 dies, calibration | `SAMPLE_DLY` = 1 with a board delay where 4 and 5 work: init retried up to 4, window `00011000`, picks 4, pass. |
| AS308G208, writes ignored | Fail. |
| AS308G208, wrong ID | All init retries fail, fail. |
| Status rules | `pass` only after a complete round; never `pass` and `fail` together; `fail` stays latched. |
| Override only while idle | Every change of `sample_dly_ovr_valid` / `sample_dly_ovr` happens while the controller's `busy` = 0, and the PHY (`phy_busy`, read through a VHDL-2008 external name) is still idle one cycle later, when the controller's registered copy reaches it. |
| Loop / stop | With `LOOP_ROUNDS` passing configs keep passing (`pass_count` ≥ 3); without, no read requests after one round. |
