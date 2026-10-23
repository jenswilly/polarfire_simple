# block_fifo

Valid/ready wrapper around the Libero CoreFIFO configuration `BLOCK_FIFO_CORE`: one FIFO word is one complete block (80 bit × 512, single clock, FWFT).
Source: `hdl/block_fifo.vhd`. Used inside [spi_tx_path](spi_tx_path.md).

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `BLOCK_BYTES` | positive | 10 | Must equal the CoreFIFO width / 8. Only checked (assertion), it does not change the core. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset (empties the FIFO). |
| `s_data` | in | `BLOCK_BYTES·8` | Block in. |
| `s_valid` | in | 1 | `s_data` valid. |
| `s_ready` | out | 1 | Ready for a block (= not FULL). |
| `m_data` | out | `BLOCK_BYTES·8` | Head of the FIFO; valid together with `m_valid` (FWFT, no read needed first). |
| `m_valid` | out | 1 | Block available (= not EMPTY). |
| `m_ready` | in | 1 | Consumer takes the block. |

## Usage notes

- `BLOCK_FIFO_CORE` must be configured as: Single Clock, Sync Reset, FWFT, 80 bit on both ports, depth 512, active-high WE/RE, "Disable Reads when Empty" and "Disable Writes when Full". Change the core and this wrapper together.
- A written block appears on `m_*` 5 clocks after the write.
- Simulation needs the generated core: `-- run_tb cores: BLOCK_FIFO_CORE`.

## Sub-components

| Component | Purpose |
|---|---|
| `BLOCK_FIFO_CORE` (CoreFIFO 4.0.139) | Libero-generated FIFO storage and flags. |

## Testbench

`sim/tb_block_fifo.vhd` — `sim/run_tb.sh tb_block_fifo`. Generics: `DEPTH` (512), `NRANDOM` (3000).

| Test | Checks |
|---|---|
| Capacity | Exactly 512 blocks fit before `s_ready` goes low. |
| FWFT | A block appears on `m_data` with `m_valid` without a read and is held while `m_ready` is low. |
| Random traffic | 3000 blocks with random stalls on both sides arrive in order with all 80 bits. |
| Throughput | One block per clock with both sides always ready. |
| Reset | Reset with blocks in the FIFO empties it. |
