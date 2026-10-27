# qspi_phy

QSPI PHY (SPI mode 0, SDR, both dies in lockstep): phase descriptors in, SCLK / CS# / IO pins out, with a configurable RX sample delay. Knows nothing about commands.
Source: `hdl/qspi_phy.vhd`. Used inside [qspi_xact](qspi_xact.md).

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `DIE2_PRESENT` | boolean | true | false: IO7:4 never driven, read as `0000`. |
| `NCLK_W` | positive | 16 | Width of `ph_nclk`. |
| `CS_HIGH_W` | positive | 8 | Width of `ph_cs_high`. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `ph_valid` | in | 1 | Descriptor valid. |
| `ph_ready` | out | 1 | Descriptor loaded (when idle, and at the end of the current phase's last SCLK cycle). |
| `ph_lanes` | in | `lane_mode_t` | `SPI1` (IO0 out / IO1 in) or `QUAD4` (IO3:0). |
| `ph_dir` | in | `dir_t` | `DIR_TX`, `DIR_RX` or `DIR_NONE` (dummy clocks). |
| `ph_nclk` | in | `NCLK_W` | SCLK cycles, ≥ 1. TX: ≤ 32 (SPI1) / ≤ 8 (QUAD4). |
| `ph_tx1` | in | 32 | Die 1 TX data, MSB first. |
| `ph_tx2` | in | 32 | Die 2 TX data, MSB first. |
| `ph_last` | in | 1 | Last phase: CS# goes high afterwards. |
| `ph_sclk_div` | in | 1–8 | SCLK half-period in clocks; taken from the first phase. |
| `ph_cs_high` | in | `CS_HIGH_W` | Minimum CS# high time in clocks (≥ 1); from the last phase. |
| `sample_dly` | in | 1–8 | RX sample point in clocks after the SCLK falling edge. Change only while `busy` = 0. |
| `rx_valid` | out | 1 | One RX word per RX SCLK cycle. No backpressure. |
| `rx_data` | out | 8 | `{die2_nibble, die1_nibble}`; in SPI1 each nibble is `000` & bit. |
| `rx_last` | out | 1 | Last word of an RX phase. |
| `busy` | out | 1 | Low when idle and the CS# high time is over. |
| `sclk` | out | 2 | SCLK; index 1 is a copy of index 0 with its own pad flop. |
| `cs_n` | out | 2 | CS#; index 1 is a copy of index 0 with its own pad flop. |
| `io_o` | out | 8 | IO7:0 output data. |
| `io_oe` | out | 8 | IO7:0 output enable. |
| `io_i` | in | 8 | IO7:0 input. |

## Usage notes

- SCLK idles low, 50 % duty cycle. IO and OE change on the SCLK falling edge.
- In SPI1 phases IO2/IO3 (and IO6/IO7) are driven high (WP#/HOLD# inactive). QUAD4 RX/NONE phases release all four lanes.
- Keep the next descriptor valid when `ph_ready` is high for a gap-free SCLK; otherwise SCLK waits low with CS# low.
- `sclk`, `cs_n` and the `io_i` capture are single registers meant to be packed into the I/O cells (`constraints/qspi_ioreg.ndc`).

## Testbench

`sim/tb_qspi_phy.vhd` — `sim/run_tb.sh tb_qspi_phy [-gDIE2_I=0]`. A transaction table (Read ID, EBh with mode and dummy, quad write, odd lengths, 1-cycle phases) in 10 runs. 1 ms watchdog.

| Test | Checks |
|---|---|
| Divider × delay | 200 MHz clock, SCLK dividers 1–8 × sample delays 1–8 (13 runs, including divider 2 / delay 4); every RX word and `rx_last` compared. |
| Gaps | A run with gaps between descriptors. |
| Wrong delay | Device delay not matching the sample delay returns wrong data. |
| CS#/SCLK timing | First edge, exact high/low times, cycles per CS#, CS# high exactly one clock after the last falling edge or the last sample (whichever is later), CS# high time. |
| TX / OE | Bit order in SPI1 and QUAD4; IO2/IO3 high in SPI1, released in QUAD4 RX/dummy. |
| Pin rules | SCLK toggles only with CS# low; CS#/OE change only with SCLK low; OE stable while CS# high; die-2 pins follow die 1. |
| One die | `DIE2_I=0`: IO7:4 undriven, RX nibble 0. |
