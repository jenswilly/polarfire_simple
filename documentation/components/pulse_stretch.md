# pulse_stretch

Stretches a short synchronous pulse to `STRETCH_CYCLES` clocks; a retrigger restarts the count. Output comes straight from a flip-flop (glitch-free on a pin).
Source: `hdl/pulse_stretch.vhd`.

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `STRETCH_CYCLES` | positive | 125 000 | Output length in clocks (1 ms at 125 MHz). |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset (clears the output). |
| `pulse_in` | in | 1 | Pulse of any length, synchronous to `clk`. |
| `pulse_out` | out | 1 | High for `STRETCH_CYCLES` clocks after the last `pulse_in` cycle, starting on the next clock edge. |

## Testbench

`sim/tb_pulse_stretch.vhd` — `sim/run_tb.sh tb_pulse_stretch`. Uses `STRETCH_CYCLES = 125` (1 µs).

| Test | Checks |
|---|---|
| Single pulse | A 1-cycle input gives exactly 125 cycles high, starting one clock later. |
| Retrigger | A retrigger 50 cycles in merges into one pulse of 50 + 125 cycles. |
| Long input | A 3-cycle input stays high until 125 cycles after its last cycle. |
| Reset | Reset clears the output. |
