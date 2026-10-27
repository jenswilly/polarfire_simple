# axis_spi_wo_master

Write-only SPI master: AXI4-Stream bytes in, fixed-length SPI frames out (`FRAME_BYTES` bytes per CS_N assertion). Same as [axis_spi_master](axis_spi_master.md) without MISO and the RX path.
Source: `hdl/axis_spi_wo_master.vhd`. Used inside [spi_tx_path](spi_tx_path.md).

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `FRAME_BYTES` | positive | 10 | Bytes per CS_N assertion. |
| `CLK_DIV` | positive | 5 | `clk` cycles per SCLK half-period (f_sclk = f_clk / (2·CLK_DIV); 20 MHz at 200 MHz). |
| `CPOL` | std_logic | '0' | SCLK idle level. |
| `CPHA` | std_logic | '0' | 0: slave samples on leading edge, 1: on trailing edge. |
| `MSB_FIRST` | boolean | true | Bit order on MOSI. |
| `CS_SETUP` | natural | 0 | Extra half-periods CS_N low before the first edge. |
| `CS_HOLD` | natural | 0 | Half-periods after the last edge before CS_N goes high. |
| `CS_IDLE` | natural | 2 | Minimum half-periods CS_N high between frames. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `s_axis_tdata` | in | 8 | TX byte (AXI4-Stream target). |
| `s_axis_tvalid` | in | 1 | TX byte valid. |
| `s_axis_tready` | out | 1 | TX byte accepted. |
| `s_axis_tlast` | in | 1 | Optional; only used for the `frame_err_out` check (default '0'). |
| `spi_sclk` | out | 1 | SPI clock. |
| `spi_mosi` | out | 1 | SPI data out. |
| `spi_cs_n` | out | 1 | SPI chip select, active low. |
| `busy_out` | out | 1 | High from frame start until the CS_N idle time is over. |
| `frame_err_out` | out | 1 | One-cycle pulse when `s_axis_tlast` does not match the frame end. |

## Usage notes

- If `s_axis` runs dry mid-frame, SCLK pauses with CS_N held low. Feed whole frames to avoid this.
- Leave `frame_err_out` open if `s_axis_tlast` is not driven (it then pulses every frame).
- Timing in `clk` cycles: byte gap = `CLK_DIV + 1`; CS_N low → first edge = `CS_SETUP·CLK_DIV + CLK_DIV + 2`; last edge → CS_N high = `CS_HOLD·CLK_DIV + 1`; CS_N high min = `CS_IDLE·CLK_DIV + 1`.

## Testbench

`sim/tb_axis_spi_wo_master.vhd` — `sim/run_tb.sh tb_axis_spi_wo_master [-gCLK_DIV=3 ...]`.
Generics: `CPOL_I`, `CPHA_I`, `MSB_I`, `FRAME_BYTES`, `CLK_DIV`, `NFRAMES`, `STALLS`.

| Test | Checks |
|---|---|
| MOSI data | A behavioural SPI slave checks every byte in the selected mode and bit order. |
| Framing | Each CS_N assertion has exactly `FRAME_BYTES·8` bits; SCLK idle at both CS_N edges. |
| Timing | SCLK half-periods and CS_N setup/hold/idle times. |
| Stalls | Random `s_axis_tvalid` gaps. |
| Bad `tlast` | Last frame with a wrong `s_axis_tlast` gives `frame_err_out` pulses. |
| Reset | Reset mid-byte returns the master to idle. |
