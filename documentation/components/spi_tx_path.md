# spi_tx_path

80-bit blocks in, SPI frames out: each block becomes one CS_N assertion of 10 bytes, MSB first (bit 79 is the first bit on MOSI). Buffers up to 512 blocks.
Source: `hdl/spi_tx_path.vhd`. Diagram: `documentation/spi_tx_path.drawio`.

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `BLOCK_BYTES` | positive | 10 | Must match the CoreFIFO width / 8 (checked in `block_fifo`). |
| `CLK_DIV` | positive | 3 | `clk` cycles per SCLK half-period (20.83 MHz at 125 MHz). |
| `CPOL` | std_logic | '0' | SCLK idle level. |
| `CPHA` | std_logic | '0' | 0: slave samples on leading edge, 1: on trailing edge. |
| `CS_SETUP` | natural | 1 | Extra half-periods CS_N low before the first edge. |
| `CS_HOLD` | natural | 1 | Half-periods after the last edge before CS_N goes high. |
| `CS_IDLE` | natural | 2 | Minimum half-periods CS_N high between frames. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `s_data` | in | `BLOCK_BYTES·8` | Block in; bit 79 (for 10 bytes) is sent first. |
| `s_valid` | in | 1 | `s_data` valid. |
| `s_ready` | out | 1 | Block accepted; low while the FIFO is full. |
| `spi_sclk` | out | 1 | SPI clock. |
| `spi_mosi` | out | 1 | SPI data out. |
| `spi_cs_n` | out | 1 | SPI chip select, active low; one assertion per block. |
| `busy_out` | out | 1 | Frame in progress or CS_N idle time running. |
| `frame_err_out` | out | 1 | Internal `tlast` mismatch pulse; should never happen. |

## Usage notes

- Frames never pause mid-way (the serializer holds the whole block).
- Several producers can share the path through [block_arbiter](block_arbiter.md).
- Simulation needs the generated CoreFIFO: `-- run_tb cores: BLOCK_FIFO_CORE`.

## Sub-components

| Component | Purpose |
|---|---|
| [block_fifo](block_fifo.md) | Buffers up to 512 blocks (CoreFIFO, FWFT). |
| [block_serializer](block_serializer.md) | Splits a block into 10 AXI4-Stream bytes with `tlast`. |
| [axis_spi_wo_master](axis_spi_wo_master.md) | Shifts the bytes out as one SPI frame per block. |

## Testbench

`sim/tb_spi_tx_path.vhd` — `sim/run_tb.sh tb_spi_tx_path`. Generics: `CPOL_I`, `CPHA_I`, `CLK_DIV` (7), `NSPARSE` (40), `NBURST` (600), `DEPTH` (512).

| Test | Checks |
|---|---|
| End-to-end | A behavioural SPI slave turns each CS_N assertion into an 80-bit word and compares it with the written blocks (order, content, bit order, framing). |
| Sparse traffic | 40 blocks with random gaps; the FIFO runs empty. |
| Backpressure | 600 back-to-back blocks overfill the FIFO; `s_ready` goes low and every block still arrives. |
| No frame errors | `frame_err_out` never pulses. |
| Reset | Reset with blocks in the FIFO and a frame in progress leaves the path idle. |
