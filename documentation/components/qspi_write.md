# qspi_write

QSPI write front end (test patterns and calibration): write requests plus their data become erase/program commands for [qspi_xact](qspi_xact.md).
Source: `hdl/qspi_write.vhd`. Used inside [qspi_mram_ctrl](qspi_mram_ctrl.md).

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `DEVICE` | `device_t` | `DEV_W25Q128JV` | Memory type. |
| `DIE2_PRESENT` | boolean | false | false: the upper nibble of each data byte is ignored. |
| `SCLK_DIV` | positive | 1 | SCLK = `clk` / (2·`SCLK_DIV`). |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `init_done` | in | 1 | Requests are rejected while low. |
| `s_axis_req_tdata` | in | 48 | Request `{len[15:0], addr[31:0]}` in host bytes. |
| `s_axis_req_tvalid` | in | 1 | Request valid. |
| `s_axis_req_tready` | out | 1 | Request accepted. |
| `s_axis_data_tdata` | in | 8 | Write data byte; `len` bytes per request. |
| `s_axis_data_tvalid` | in | 1 | Byte valid. |
| `s_axis_data_tready` | out | 1 | Byte accepted. |
| `req_err` | out | 1 | One-cycle pulse: request dropped (data not consumed). |
| `wr_done` | out | 1 | One-cycle pulse: request completely written. |
| `busy` | out | 1 | Request in progress. |
| `cmd_*` | | | Command port to `qspi_xact`. |
| `xact_busy` | in | 1 | `busy` from `qspi_xact`. |
| `tx_t*` | | | TX stream to `qspi_xact`. |
| `rx_t*` | | | RX stream from `qspi_xact`. |

## Usage notes

- Same request rules as [qspi_read_ctrl](qspi_read_ctrl.md).
- W25Q128JV: every touched 4 KB sector is erased first (other data there is lost), then programmed page by page with 32h, polling BUSY.
- AS308G208: WREN + one D2h for the whole request; `wr_done` after the write CS# high time.

## Testbench

`sim/tb_qspi_write.vhd` — `sim/run_tb.sh tb_qspi_write`. Runs `qspi_write` and `qspi_read_ctrl` on one `qspi_xact` against preloaded models (W25Q, AS 1 and 2 dies).

| Test | Checks |
|---|---|
| Rejected requests | Before `init_done` or bad requests: `req_err`, nothing written. |
| Write / read back | 880 host bytes (W25Q: across a sector boundary and three pages). |
| Erase side effects | W25Q: rest of both erased sectors reads FFh. |
| Overlapping write | 64-byte block over the first one, whole area read back. |
| Neighbours | AS: bytes around the block keep the preload. |
| One die | Upper nibble ignored. |
| Protocol | WEL/WREN, BUSY, CS# high times, byte boundaries. |
