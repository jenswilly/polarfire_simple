# qspi_init

QSPI memory initialisation: reset, ID check, configuration and a quad-path check. Runs after reset and on `init_restart`, driving [qspi_xact](qspi_xact.md) through its command port.
Source: `hdl/qspi_init.vhd`. Used inside [qspi_mram_ctrl](qspi_mram_ctrl.md). Sequence details: `documentation/device_facts.md` §4.3.

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `DEVICE` | `device_t` | `DEV_W25Q128JV` | Memory type. |
| `DIE2_PRESENT` | boolean | false | Check both dies. |
| `CLK_HZ` | positive | 100 000 000 | `clk` frequency (for wait times and the slow SCLK). |
| `SCLK_DIV` | positive | 1 | Normal SCLK divider. |
| `T_POWERUP_NS` | natural | 0 | W25Q tPUW / AS tPU; 0 = datasheet value. |
| `T_RESET_NS` | natural | 0 | W25Q tRST / AS RESET# low time; 0 = datasheet value. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `init_restart` | in | 1 | Pulse: run again (only when done or failed). |
| `init_done` | out | 1 | Sequence finished without error. |
| `init_err` | out | 1 | A check failed. |
| `err_code` | out | 2 | `01` = wrong ID on a die, `10` = register check. |
| `step` | out | 5 | Current step number (debug). |
| `mem_reset_n` | out | 1 | AS308G208 RESET# (always '1' for the W25Q). |
| `cmd_*` | | | Command port to `qspi_xact`. |
| `xact_busy` | in | 1 | `busy` from `qspi_xact`. |
| `tx_t*` | | | TX stream to `qspi_xact`. |
| `rx_t*` | | | RX stream from `qspi_xact`. |

## Usage notes

- W25Q128JV: software reset (66h/99h), ID `EF 40 18`, status registers checked (never written).
- AS308G208: RESET# pulse, ID, CR2 latency = 8 and SR = 00h written and read back.
- 9Fh and 05h run at the device's slow SCLK limit (40 MHz on the AS308G208). The final EBh read only checks that the quad path completes.

## Testbench

`sim/tb_qspi_init.vhd` — `sim/run_tb.sh tb_qspi_init`. Runs `qspi_init` + `qspi_xact` against the models in eight configurations side by side.

| Test | Checks |
|---|---|
| W25Q normal / QE = 0 / wrong ID | `init_done`, `ERR_CFG`, `ERR_ID`. |
| AS, 1 die, non-default CR2/SR | Init writes fix them, `init_done`. |
| AS, 2 dies | Normal: `init_done`; die 2 ignores writes or has a wrong ID: the matching error. |
| AS, 1 die ignores writes | `ERR_CFG`. |
| Restart | Same results after `init_restart`. |
| Protocol | Power-up/reset recovery times, CS# high times, 9Fh/05h ≤ 40 MHz on the AS. |
| RESET# | Stays high for the W25Q; pulsed once per run for the AS. |
