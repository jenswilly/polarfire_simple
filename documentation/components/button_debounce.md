# button_debounce

Push-button debouncer with a 2-FF synchronizer, a debounced level output and a single-clock press pulse.
Source: `hdl/button_debounce.vhd`.

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `DEBOUNCE_CYCLES` | positive | 2 000 000 | Clocks the input must be stable before the state changes (10 ms at 200 MHz). |
| `ACTIVE_LOW` | boolean | true | true: `btn_in` = '0' means pressed. |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Clock. |
| `reset_n` | in | 1 | Synchronous, active-low reset. |
| `btn_in` | in | 1 | Raw button input (asynchronous). |
| `pressed_out` | out | 1 | Debounced level, '1' = pressed (independent of `ACTIVE_LOW`). |
| `pulse_out` | out | 1 | One clock high per accepted press; releases give no pulse. |

## Usage notes

- Latency: `pulse_out` rises on the `DEBOUNCE_CYCLES + 2`th clock edge after the last bounce (2 of those are the synchronizer).
- Set `DEBOUNCE_CYCLES` for the actual clock frequency.

## Testbench

`sim/tb_button_debounce.vhd` — `sim/run_tb.sh tb_button_debounce`. Uses `DEBOUNCE_CYCLES = 20` and asynchronous edges.

| Test | Checks |
|---|---|
| Glitches | Short glitches are ignored, both when released and when pressed. |
| Bouncy press | Exactly one single-cycle pulse, exactly `DEBOUNCE_CYCLES + 2` edges after the last bounce. |
| Hold / release | No extra pulse while held or on release. |
| Reset while held | Holding through a reset gives one pulse after the reset. |
