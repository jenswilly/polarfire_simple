# test_block_producer

Test source for [spi_tx_path](spi_tx_path.md): each start pulse sends `BLOCKS_PER_PRESS` blocks `<id> <seq> 02 03 04 05 06 07 08 09` (byte 0 = bits 79:72, sent first).
Source: `hdl/test_block_producer.vhd`. Use as an HDL+ core to set the generics per instance.

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `BLOCKS_PER_PRESS` | positive | 1 | Blocks per start pulse. |
| `FIRST_BYTE` | natural 0–255 | 16#A5# | `<id>` byte; give each instance its own value. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset (also restarts `<seq>`). |
| `start_in` | in | 1 | One-cycle pulse starts a burst; ignored while a burst is running. |
| `m_data` | out | 80 | Block out. |
| `m_valid` | out | 1 | Block valid. |
| `m_ready` | in | 1 | Consumer takes the block. |

## Usage notes

- `<seq>` counts this instance's blocks since reset and wraps from FF to 00.

## Testbench

`sim/tb_test_block_producer.vhd` — `sim/run_tb.sh tb_test_block_producer`. Generics: `BLOCKS_PER_PRESS` (3), `FIRST_BYTE` (C3).

| Test | Checks |
|---|---|
| Burst | Each start pulse gives exactly `BLOCKS_PER_PRESS` blocks with the right content. |
| Stability | `m_data` / `m_valid` stable while `m_ready` is low (random stalls). |
| Busy start | A start pulse during a burst is ignored. |
| Sequence | `<seq>` continues across bursts and wraps FF → 00. |
| Reset | Reset during a burst stops it and restarts the sequence. |
