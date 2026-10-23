# axis_spi_master

Full-duplex SPI master with AXI4-Stream byte interfaces and fixed-length frames (`FRAME_BYTES` bytes per CS_N assertion).
Source: `hdl/axis_spi_master.vhd`. Not used in TOP (kept for later); the write-only variant is [axis_spi_wo_master](axis_spi_wo_master.md).

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `FRAME_BYTES` | positive | 10 | Bytes per CS_N assertion. |
| `CLK_DIV` | positive | 7 | `clk` cycles per SCLK half-period (f_sclk = f_clk / (2·CLK_DIV); 8.93 MHz at 125 MHz). |
| `CPOL` | std_logic | '0' | SCLK idle level. |
| `CPHA` | std_logic | '0' | 0: sample on leading edge, 1: on trailing edge. |
| `MSB_FIRST` | boolean | true | Bit order on MOSI/MISO. |
| `CS_SETUP` | natural | 1 | Extra half-periods CS_N low before the first edge. |
| `CS_HOLD` | natural | 1 | Half-periods after the last edge before CS_N goes high. |
| `CS_IDLE` | natural | 2 | Minimum half-periods CS_N high between frames. |
| `MISO_SYNC` | natural | 2 | MISO synchronizer stages (0 only if MISO is already synchronous to `clk`). |
| `RX_ENABLE` | boolean | true | false removes the RX path (`m_axis_tvalid` stays low). |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `s_axis_tdata` | in | 8 | TX byte (AXI4-Stream target). |
| `s_axis_tvalid` | in | 1 | TX byte valid. |
| `s_axis_tready` | out | 1 | TX byte accepted. |
| `s_axis_tlast` | in | 1 | Optional; only used for the `frame_err_out` check (default '0'). |
| `m_axis_tdata` | out | 8 | RX byte (AXI4-Stream initiator). |
| `m_axis_tvalid` | out | 1 | RX byte valid (stays low with `RX_ENABLE` = false). |
| `m_axis_tready` | in | 1 | Consumer ready; defaults to '1'. |
| `m_axis_tlast` | out | 1 | Last byte of a frame. |
| `spi_sclk` | out | 1 | SPI clock. |
| `spi_mosi` | out | 1 | SPI data out. |
| `spi_cs_n` | out | 1 | SPI chip select, active low. |
| `spi_miso` | in | 1 | SPI input (asynchronous, synchronized internally). |
| `busy_out` | out | 1 | High from frame start until the CS_N idle time is over. |
| `frame_err_out` | out | 1 | One-cycle pulse when `s_axis_tlast` does not match the frame end. |

## Usage notes

- One TX byte in gives one RX byte out. If `m_axis` stalls, the next byte waits; no data is dropped.
- If `s_axis` runs dry mid-frame, SCLK pauses with CS_N held low. Feed whole frames (e.g. from a FIFO) to avoid this.
- Leave `frame_err_out` open if `s_axis_tlast` is not driven (it then pulses every frame).
- Timing in `clk` cycles: byte gap = `CLK_DIV + 1`; CS_N low → first edge = `CS_SETUP·CLK_DIV + CLK_DIV + 2`; last edge → CS_N high = `CS_HOLD·CLK_DIV + 1`; CS_N high min = `CS_IDLE·CLK_DIV + 1`.
- MISO round trip must fit in one half-period: `CLK_DIV > MISO_SYNC + 1 + ceil((t_pad_out + t_slave + t_pad_in) / t_clk)`.

## Testbench

`sim/tb_axis_spi_master.vhd` — `sim/run_tb.sh tb_axis_spi_master [-gCPOL_I=1 -gCPHA_I=1 ...]`.
Generics: `CPOL_I`, `CPHA_I`, `MSB_I`, `RX_I`, `FRAME_BYTES`, `CLK_DIV`, `NFRAMES`, `STALLS`, `MISO_SYNC_I`.

| Test | Checks |
|---|---|
| MOSI data | A behavioural SPI slave checks every byte in the selected mode and bit order. |
| Framing | Each CS_N assertion has exactly `FRAME_BYTES·8` bits; SCLK idle at both CS_N edges. |
| Timing | SCLK half-periods and CS_N setup/hold/idle times. |
| RX path | Known MISO sequence arrives on `m_axis` with correct `tlast` under random stalls and long `tready` stalls (no overrun). |
| Bad `tlast` | Last frame with a wrong `s_axis_tlast` gives `frame_err_out` pulses. |
| Reset | Reset mid-byte returns the master to idle. |
