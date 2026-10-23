# block_serializer

Turns one `BLOCK_BYTES`-byte block into `BLOCK_BYTES` AXI4-Stream bytes, most significant byte first, with `tlast` on the last byte.
Source: `hdl/block_serializer.vhd`. Used inside [spi_tx_path](spi_tx_path.md).

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `BLOCK_BYTES` | positive | 10 | Bytes per block. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `s_data` | in | `BLOCK_BYTES·8` | Block in. |
| `s_valid` | in | 1 | `s_data` valid. |
| `s_ready` | out | 1 | Block accepted; high only while no block is being sent. |
| `m_axis_tdata` | out | 8 | Byte out (AXI4-Stream initiator). First byte = `s_data(BLOCK_BYTES·8-1 downto BLOCK_BYTES·8-8)`. |
| `m_axis_tvalid` | out | 1 | Byte valid. |
| `m_axis_tready` | in | 1 | Consumer ready. |
| `m_axis_tlast` | out | 1 | Last byte of the block. |

## Usage notes

- A block is only accepted while no block is being sent, so throughput is one block per `BLOCK_BYTES + 1` clocks. `s_ready` has no combinational path from `m_axis_tready`.
- The whole block is held internally, so a downstream SPI master never runs dry mid-frame.

## Testbench

`sim/tb_block_serializer.vhd` — `sim/run_tb.sh tb_block_serializer [-gBLOCK_BYTES=<n>]`. Generics: `BLOCK_BYTES` (10), `NBLOCKS` (500).

| Test | Checks |
|---|---|
| Byte order / `tlast` | Every byte (MSB first) and `tlast` under random stalls on both sides. |
| Stability | `m_axis` stable while stalled. |
| Throughput | `BLOCK_BYTES + 1` clocks per block. |
| Reset | Reset mid-block. |
