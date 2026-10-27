# qspi_xact

QSPI transaction engine: one command (opcode, address, mode byte, latency, data) becomes one CS# assertion on the pins, with AXI4-Stream TX and RX data. Both dies run in lockstep.
Source: `hdl/qspi_xact.vhd`. Used inside [qspi_mram_ctrl](qspi_mram_ctrl.md).

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `DEVICE` | `device_t` | `DEV_W25Q128JV` | Sets the CS# high times. |
| `DIE2_PRESENT` | boolean | false | Second die on IO7:4. |
| `CLK_HZ` | positive | 200 000 000 | `clk` frequency (CS# high times). |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `cmd_valid` | in | 1 | Command valid. |
| `cmd_ready` | out | 1 | High when idle; command accepted. |
| `cmd_op` | in | 8 | Opcode (always on IO0). |
| `cmd_lanes` | in | `cmd_lanes_t` | `L111`, `L114` or `L144` (address/data lines). |
| `cmd_addr` | in | 32 | Die byte address, sent MSB first. |
| `cmd_addr_bytes` | in | 0–4 | Address bytes to send; 0 = no address. |
| `cmd_mode_en` | in | 1 | Send `cmd_mode` after the address. |
| `cmd_mode` | in | 8 | Mode byte. |
| `cmd_latency` | in | 0–15 | Dummy/latency clocks. |
| `cmd_dir` | in | `dir_t` | `DIR_NONE`, `DIR_TX` or `DIR_RX`. |
| `cmd_len` | in | 16 | 4-line: host bytes (= data clocks); 1-line: bytes per die. ≥ 1 unless `DIR_NONE`. |
| `cmd_sclk_div` | in | 1–8 | SCLK = `CLK_HZ` / (2·div) for this command. |
| `cmd_write` | in | 1 | Use the device's write CS# high time afterwards. |
| `s_axis_tdata` | in | 8 | TX byte. |
| `s_axis_tvalid` | in | 1 | TX byte valid. |
| `s_axis_tready` | out | 1 | TX byte accepted. |
| `m_axis_tdata` | out | 8 | RX byte. |
| `m_axis_tvalid` | out | 1 | RX byte valid. |
| `m_axis_tready` | in | 1 | Consumer ready; must keep up (4-entry FIFO only). |
| `m_axis_tlast` | out | 1 | Last byte of a command. |
| `rx_overflow` | out | 1 | One-cycle pulse: an RX byte was dropped. |
| `sample_dly` | in | 1–8 | RX sample delay; change only while `busy` = 0. |
| `busy` | out | 1 | Command, PHY or RX output active. |
| `sclk` | out | 2 | SCLK; index 0 = die 1, 1 = die 2. |
| `cs_n` | out | 2 | CS#; index 0 = die 1, 1 = die 2. |
| `io_o` | out | 8 | IO7:0 output data. |
| `io_oe` | out | 8 | IO7:0 output enable. |
| `io_i` | in | 8 | IO7:0 input. |

## Usage notes

- Stream bytes: 4-line data = one `{die2_nibble, die1_nibble}` byte per SCLK cycle. 1-line data = two stream bytes per byte (die 1, then die 2; die 1 only without die 2).
- RX has only a 4-entry FIFO (8 slots, so incoming words can be written before the overflow check; SCLK can't stop); the consumer must keep up or `rx_overflow` pulses. If TX data is late, SCLK pauses with CS# low.
- The next command's opcode follows directly; the PHY enforces the CS# high time.

## Sub-components

| Component | Purpose |
|---|---|
| [qspi_phy](qspi_phy.md) | Drives SCLK/CS#/IO from phase descriptors and samples RX data. |

## Testbench

`sim/tb_qspi_xact.vhd` — `sim/run_tb.sh tb_qspi_xact`. Three configurations side by side (W25Q, AS 1 die, AS 2 dies) at 200 MHz `clk`, 50 MHz SCLK, sample delay 4, 3 ns board delay.

| Test | Checks |
|---|---|
| ID / registers | Device ID per die, status reads, RDAR/WRAR. |
| EBh reads | Latency 8 and 10, across the end of the die. |
| W25Q writes | Sector erase with BUSY polling, quad and 1-1-1 page programs (page wrap, ignored upper nibble with one die). |
| AS writes | D2h/02h writes over several TX chunks. |
| Queued reads | Two reads (880 + 20 host bytes) back to back. |
| Data | Every byte, nibble order `{die2, die1}`, 1-line die order and `tlast`. |
| Protocol | No model protocol errors, `rx_overflow` never pulses. |
