# qspi_read_ctrl

QSPI read front end: read requests `{len, addr}` in host bytes become EBh (1-4-4) commands for [qspi_xact](qspi_xact.md), with credit-based flow control; read data is passed through to `m_axis`.
Source: `hdl/qspi_read_ctrl.vhd`. Used inside [qspi_mram_ctrl](qspi_mram_ctrl.md).

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `DEVICE` | `device_t` | `DEV_W25Q128JV` | Sets address bytes and latency (W25Q: 3 bytes + 4 dummy clocks; AS: 4 bytes + latency 8). |
| `SCLK_DIV` | positive | 1 | SCLK = `clk` / (2·`SCLK_DIV`). |
| `SPACE_W` | positive | 16 | Width of `rx_space`. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `init_done` | in | 1 | Requests are rejected while low. |
| `s_axis_req_tdata` | in | 48 | Request `{len[15:0], addr[31:0]}` in host bytes. |
| `s_axis_req_tvalid` | in | 1 | Request valid. |
| `s_axis_req_tready` | out | 1 | Request accepted. |
| `req_err` | out | 1 | One-cycle pulse: request dropped. |
| `rx_space` | in | `SPACE_W` | Free bytes downstream. |
| `busy` | out | 1 | Request pending or data in flight. |
| `cmd_*` | out/in | | Command port to `qspi_xact`. |
| `rx_t*` | in/out | | RX stream from `qspi_xact`. |
| `m_axis_tdata` | out | 8 | Read data byte. |
| `m_axis_tvalid` | out | 1 | Byte valid. |
| `m_axis_tready` | in | 1 | Consumer ready; must stay high as promised by `rx_space`. |
| `m_axis_tlast` | out | 1 | Last byte of a request. |

## Usage notes

- Valid request: even address, even non-zero length, `addr + len` ≤ 2 × die size, `init_done` = 1.
- A request starts only when `rx_space` ≥ bytes in flight + `len`. `m_axis_tready` must then stay high as promised (SCLK can't stall).
- One request is buffered while the previous one runs, so back-to-back reads have no gap beyond the EBh overhead.

## Testbench

`sim/tb_qspi_read_ctrl.vhd` — `sim/run_tb.sh tb_qspi_read_ctrl`. Runs with `qspi_xact` against preloaded models (W25Q, AS 1 and 2 dies).

| Test | Checks |
|---|---|
| Rejected requests | Before `init_done`, odd address/length, length 0, past the end: `req_err`, no data. |
| Read time | 8 non-contiguous blocks of 880 host bytes in 140.8–150 µs (144.5 W25Q / 145.5 AS). |
| Credit flow control | 1000-byte buffer drained at ¼ rate: requests wait for space, the buffer never overflows. |
| Data | Every byte and `tlast` compared with the preload. |
