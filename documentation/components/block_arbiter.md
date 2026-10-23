# block_arbiter

Round-robin arbiter: `NUM_PORTS` block producers share one block consumer (e.g. [spi_tx_path](spi_tx_path.md)). One handshake moves one whole block, so blocks from different producers never interleave.
Source: `hdl/block_arbiter.vhd`.

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `NUM_PORTS` | positive | 2 | Number of producers. |
| `BLOCK_BYTES` | positive | 10 | Block size in bytes (block width = `BLOCK_BYTES·8`). |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `s_data` | in | `NUM_PORTS·BLOCK_BYTES·8` | Flattened producer blocks; producer *i* = `s_data((i+1)·BLOCK_BYTES·8-1 downto i·BLOCK_BYTES·8)`. |
| `s_valid` | in | `NUM_PORTS` | Bit *i* = producer *i* valid. |
| `s_ready` | out | `NUM_PORTS` | Bit *i* = producer *i* ready; at most one bit is high. |
| `m_data` | out | `BLOCK_BYTES·8` | Selected block. |
| `m_valid` | out | 1 | Block valid. |
| `m_ready` | in | 1 | Consumer ready. |

## Usage notes

- Combinational mux, no added latency: `s_ready` depends on `s_valid` and `m_ready` in the same cycle. Producers must not make `valid` depend on `ready`.
- Every waiting producer is served within `NUM_PORTS` blocks. Once offered, `m_data` / `m_valid` stay stable until taken.
- After reset, port 0 has priority.
- In SmartDesign, use **Edit Slices** on the flattened `s_*` ports. 10-byte blocks: producer 0 = `s_data(79:0)`, producer 1 = `s_data(159:80)`.

## Testbench

`sim/tb_block_arbiter.vhd` — `sim/run_tb.sh tb_block_arbiter [-gNUM_PORTS=<n>]`. Generics: `NUM_PORTS` (3), `NBLOCKS` (300).

| Test | Checks |
|---|---|
| Ready exclusivity | At most one `s_ready` high, and only for a valid producer. |
| Handshake mapping | Each `m_*` handshake is exactly one `s_*` handshake with that producer's block. |
| Completeness / order | Every block of every producer arrives once and in order (random gaps and random `m_ready`). |
| Stability | `m_*` stable while stalled. |
| Fairness | With all producers valid, they are served in turn. |
| Reset | After reset, port 0 goes first. |
