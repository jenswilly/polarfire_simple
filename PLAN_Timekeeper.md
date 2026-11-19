# Plan: GNSS-disciplined timekeeper (PolarFire SoC fabric + RTEMS)

## Instructions for Claude Code

Work through the steps **in order**, one step per session/PR. At the end of every step:

1. All testbenches and unit tests written so far must pass, using the project's existing simulation and build flow.
2. Don't commit to Git; inform user when ready to make a commit.
3. Update the **Status** table at the bottom of this file.
4. Stop and report. Do not start the next step without being asked.

Ground rules:

- The project is already set up. Read its existing structure, build and simulation scripts, and coding conventions first, and put new files where they fit. Don't restructure the repository.
- **Do not guess receiver or board facts.** Message formats, which PPS a message refers to, PPS polarity and width, oscillator specs and pin assignments come from Step 1 (`docs/timing_facts.md`), each with a source reference. If something is missing, write `TBD` and ask.
- RTL: synthesizable VHDL-2008, restricted to constructs Synplify Pro (Libero SoC) supports. One entity per file. Synchronous active-high reset. No vendor primitives outside the top level and constraints.
- Testbenches: self-checking, print `PASS`/`FAIL`, exit non-zero on failure. GHDL (`--std=08`) unless the project uses something else.
- Software: C++17 for RTEMS on the U54s, following the project's MISRA C++ rules. No dynamic allocation after initialisation. The parser and time-conversion logic must built and be unit-tested on the host.

## Goal

Know GNSS time **at all times with ≤ 1 µs error** (target ≤ 100 ns while locked) in the FPGA fabric. Make it available to fabric logic (timestamps, scheduled triggers) and to RTEMS on the MSS, and keep running in holdover when PPS is lost.

## Design decisions (fixed)

| Item | Decision |
|---|---|
| Time master | FPGA fabric counter. RTEMS reads it; it never writes the running time directly |
| Time scale in fabric | **GNSS time (GPS) — no leap seconds.** UTC/Unix conversion only in software |
| Format | `sec` 32 bit (GPS seconds) + `ns` 30 bit (0…999 999 999). Internally `ns` carries 32 extra fractional bits (so 62 bits total) |
| Clock | Single domain `clk_time` = the FIC/AXI-Lite clock (e.g. 100 MHz). Generic `CLK_HZ` |
| Rate correction | Fixed-point accumulator: each clock adds `inc` (ns · 2³²). `inc` is recomputed every valid PPS |
| Discipline law | Each valid PPS: measure cycles `N` since the previous edge and phase error `e` (ns). `inc = (1e9 − K·e) · 2³² / N`, one sequential divide per second. Removes the frequency error and slews out the phase error over the next second while staying monotonic. `K` is a register (default 1.0, Q-format) |
| Large errors | If \|e\| > `STEP_THRESH_NS` (default 1 ms) or the time isn't set yet: **step** (load) instead of slewing, and set the `TIME_JUMP` flag |
| Setting the second | Software writes the **GPS second of the NEXT PPS edge** to `ARM_SEC` and sets `ARM_VALID`. At the edge, the FPGA compares it with its own rounded second. Equal: slew normally. Different (or the time isn't set): step to `ARM_SEC.0`. The arm is consumed at the edge |
| PPS validation | Accept an edge only if `N` is within `CLK_HZ ± PPS_TOL_PPM` (default 200 ppm) and the pulse is high for ≥ `PPS_MIN_HIGH` cycles. Otherwise reject and count |
| Holdover | No valid PPS within 1 s + tolerance → `HOLDOVER`: keep the last `inc` and count holdover seconds |
| States | `UNSET` → `ACQUIRING` → `LOCKED` (\|e\| < `LOCK_THRESH_NS` for `LOCK_COUNT` consecutive PPS) → `HOLDOVER` ↔ `LOCKED` |
| CPU interface | AXI4-Lite slave. 64-bit values are read low word first; reading the low word latches the high word |
| Interrupt | `pps_irq` (fabric → MSS) on each accepted PPS, plus optional capture/trigger IRQs |
| Extras | `N_CAPTURE` timestamp capture inputs and `N_TRIGGER` "fire at time T" outputs (generics) |

## Steps

### Step 1 — Gather receiver and board facts (no code)
Create `documentation/timekeeping_facts.md`, with a datasheet or manual reference for every entry:
- Format of incoming PVT message and whether it is received over UART or Ethernet or CAN.
- **Which PPS edge each time message refers to** (the preceding pulse or the next one), and the typical delay from PPS to message arrival.
- PPS polarity, pulse width, which time scale the pulse is aligned to (GPS or UTC, and whether it's configurable), and its quantisation error.
- How the receiver reports fix and time validity, and the current leap-second offset.
- Antenna cable and receiver delay compensation, if relevant.
- Fabric clock source: oscillator part, accuracy and stability in ppm. Expected holdover drift.
- PolarFire pin for the PPS input and the bank voltage.
- **Done when:** the user has reviewed the file and every TBD is resolved or accepted.

### Step 2 — Package and register map
- `timekeeper_pkg.vhd`: widths, fixed-point formats, state encoding, defaults, and helper functions (ppm → cycles, ns → fixed point).
- `docs/timekeeper_regs.md`: the AXI-Lite register map with offsets, access types, reset values and field descriptions. At minimum: `ID/VERSION`, `CTRL` (enable, force step, IRQ enables), `STATUS` (state, `TIME_SET`, `TIME_JUMP`, `PPS_REJECT`, sticky flags with write-1-to-clear), `TIME_NS`/`TIME_SEC` (latched pair), `ARM_SEC`, `ARM_CTRL`, `PPS_TS_NS`/`PPS_TS_SEC` (local time at the last edge, before correction), `PPS_COUNT`, `PPS_PERIOD` (N), `PHASE_ERR_NS` (signed), `INC`, `GAIN_K`, `HOLDOVER_SEC`, `REJECT_COUNT`, and capture/trigger registers.
- **Done when:** the package compiles, `tb_pkg` checks the helper functions, and the user has approved the register map.

### Step 3 — PPS conditioner `pps_cond`
- 2-FF synchroniser, configurable polarity, minimum-high-width glitch filter, one-cycle edge strobe.
- Period counter: outputs `N` (cycles between accepted edges), with the validity window check, `pps_valid` and `pps_reject` strobes, and a timeout strobe when no edge arrives within the window.
- **Done when:** `tb_pps_cond` passes with nominal pulses, ±200 ppm, out-of-window pulses, glitches, and missing pulses.

### Step 4 — Time counter `time_counter`
- Accumulator `{sec, ns, frac}`. It adds `inc` every clock, rolls `ns` over at 10⁹ and increments `sec`.
- Inputs: `load` (set to `{sec, 0}`) and `inc_update`.
- Outputs: the current time and a regenerated local PPS strobe at each local second rollover, usable in holdover.
- **Done when:** `tb_time_counter` checks rollover, monotonicity across `inc` changes, and `load`, and that the accumulated error over 10 s matches the fixed-point maths.

### Step 5 — Discipline engine `time_discipline`
- At each valid PPS:
  - Latch the local time.
  - Compute `e`, the signed nanosecond error to the nearest second, and the rounded local second.
  - Handle the arm compare and step.
  - Run the sequential divider (`(1e9 − K·e)·2³² / N`) and update `inc`.
  - Run the state machine (UNSET / ACQUIRING / LOCKED / HOLDOVER).
- Holdover entry and exit, and the jump/reject flags.
- **Done when:** `tb_time_discipline` with a behavioural `clk_time` that is off by +50, −50 and 0 ppm shows:
  - lock within ≤ 3 PPS after arming;
  - \|e\| < 100 ns while locked;
  - correct step on a wrong arm;
  - correct holdover entry and exit, with holdover drift matching the frozen `inc`;
  - no non-monotonic time steps while slewing.

### Step 6 — Capture and trigger units
- `time_capture`: on an input edge (synchronised), latch the time with an overflow flag.
- `time_trigger`: fire a one-cycle pulse when the time first reaches or passes the programmed `{sec, ns}`. Arm, disarm and missed-deadline flag.
- **Done when:** both testbenches pass, including a trigger programmed in the past (the missed flag is set and it doesn't fire) and a capture at a second rollover.

### Step 7 — AXI-Lite register block and top `gnss_timekeeper`
- AXI4-Lite slave implementing the Step 2 register map, latched 64-bit reads, W1C flags and IRQ generation.
- `gnss_timekeeper` wraps everything. Generics: `CLK_HZ`, `PPS_TOL_PPM`, `STEP_THRESH_NS`, `LOCK_THRESH_NS`, `LOCK_COUNT`, `N_CAPTURE`, `N_TRIGGER`. Time bus outputs for other fabric modules.
- **Done when:** `tb_gnss_timekeeper` drives it through an AXI-Lite BFM:
  - arm → lock → read time;
  - check that a read pair stays consistent across a second rollover;
  - check the IRQs.
  A synthesis-only run shows no latches.

### Step 8 — System testbench (scenarios)
- One long testbench with scripted scenarios:
  - cold start and arming;
  - an arm write late in the second (just before the edge) and early;
  - wrong arm (off by one second);
  - PPS dropout for 10 s and recovery;
  - glitch pulses;
  - an oscillator frequency step mid-run (temperature);
  - leap-second day (the fabric must not change).
- Report the maximum \|time error\| per scenario.
- **Done when:** every scenario meets the target, and the report is saved to `docs/timekeeper_sim_results.md`.

### Step 9 — Libero integration
- Instantiate on the FIC used for AXI-Lite. Connect `pps_irq` to an MSS fabric-to-MSS interrupt. Route the PPS pin (single-ended input, correct bank voltage, input-register packing).
- SDC: the PPS input is asynchronous, so add a `set_false_path` to the first synchroniser flop. No other new clocks.
- **Done when:** place and route completes with timing met, and the register map is reachable from a bare-metal or RTEMS test read of `ID/VERSION`.

### Step 10 — RTEMS low-level driver
- C++17 class over the register map: `read_time()` (correct latch order), `arm_next_second(sec)`, status/flags, capture/trigger access, PPS interrupt handler that posts an RTEMS event or semaphore with `PPS_COUNT`.
- Thread safety: one mutex for multi-register operations. ISR-safe status snapshot.
- **Done when:** host-side unit tests with a mocked register file pass, and on hardware a test task prints time and status every PPS.

### Step 11 — GNSS message parser
- Pure C++17 parser for the protocol from Step 1, with no RTEMS dependencies.
- Checksums, framing resync, extracting GPS week and time-of-week (or the equivalent), fix and time validity flags, and the leap-second count.
- **Done when:** host unit tests pass on recorded or hand-made messages, including corrupted, truncated and back-to-back frames.

### Step 12 — Time manager task
- RTEMS task that ties the parser, the PPS interrupt and the driver together:
  - On each valid time message, compute the GPS second of the **next** PPS (applying the Step 1 rule) and call `arm_next_second()` before that edge. Use `PPS_COUNT` to make sure the message is matched to the right pulse.
  - Compare the FPGA time against the message every second, and log or flag mismatches, steps and holdover.
  - Leap-second handling and conversion API: `gps_time()`, `utc_time()`, `unix_time_us()`.
  - Periodically set the RTEMS time-of-day clock from the FPGA time, for logging and timestamps in software.
- **Done when:** a host-side simulation of the arming logic (messages with realistic delays and jitter) passes, and on hardware the system reaches `LOCKED` and stays there.

### Step 13 — Hardware verification
`docs/timekeeper_bringup.md`, with measured results:
1. Generate a regenerated PPS (or a trigger at each `.000000000`) on a test pin. Scope it against the receiver PPS: report the offset and its jitter over 1 h.
2. Log `PHASE_ERR_NS` and `PPS_PERIOD` over at least 1 h.
3. Holdover test: disconnect the antenna for 1, 10 and 60 min, and log the error on reacquisition.
4. Cold-start and power-cycle behaviour, and the error caused by a wrong arm.
- **Done when:** locked error ≤ 100 ns and holdover behaviour are documented, and the limits are agreed with the user.

---

## Status

| Step | Title | Status | Notes |
|---|---|---|---|
| 1 | Receiver/board facts | todo | |
| 2 | Package + register map | todo | |
| 3 | PPS conditioner | todo | |
| 4 | Time counter | todo | |
| 5 | Discipline engine | todo | |
| 6 | Capture/trigger | todo | |
| 7 | AXI-Lite + top | todo | |
| 8 | System testbench | todo | |
| 9 | Libero integration | todo | |
| 10 | RTEMS driver | todo | |
| 11 | GNSS parser | todo | |
| 12 | Time manager | todo | |
| 13 | HW verification | todo | |