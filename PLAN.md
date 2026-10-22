# Plan: Dual-QSPI MRAM read controller (VHDL, PolarFire SoC Discovery Kit)

## Instructions for Claude Code

Work through the steps **in order**, one step per session/PR. At the end of every step:

1. All testbenches written so far must pass with `sim/run_tb.sh` (see CLAUDE.md).
2. Update README.md (repository layout, Simulation section with one paragraph per new testbench) `documentation/qspi_controller.drawio` (block diagram of this plan; mark blocks as existing once built), and, when TOP changes, `documentation/top_level.drawio`.
3. Update the **Status** table at the bottom of this file.
4. Stop and report. The user commits to Git. Do not start the next step without being asked.

Ground rules:

- **Do not guess device facts.** Opcodes, register addresses, bit fields, latency tables and timing values come from the datasheets in `documentation/` (`Avalanche_AS308G208_Dual_QSPI.pdf`, rev J.1, and `W25Q128JV_QSPI_Flash.pdf`) and are recorded in `documentation/device_facts.md` (Step 1), each with a page/table reference. If a value is missing or ambiguous, write `TBD` with a note and ask. Never fill in a value from memory.
- RTL is synthesizable **VHDL-2008, restricted to constructs Synplify Pro (Libero SoC) supports**: no `process(all)`, no unconstrained record elements, no generics on packages. Testbenches may use full VHDL-2008.
- Follow the existing `hdl/` conventions: one entity per file, file name = entity name, header comment describing the block, `clk` + **synchronous active-low `reset_n`**, valid/ready and AXI4-Stream port naming as in `spi_tx_path` / `block_serializer`. Single clock domain inside the controller.
- RTL goes in `hdl/`, testbenches in `sim/tb_<entity>.vhd` (self-checking, `TB PASSED` / `TB FAILED`), the behavioural device model in `sim/models/`, documentation in `documentation/`, constraints in `constraints/`.
- The user does all Libero GUI work (SmartDesign, IP configurators, linking files, constraints manager). Claude gives step-by-step instructions and verifies by reading the generated files (`TOP.vhd`, `.cxf`, `.prjx`, generated core netlists).

## Target and design decisions

| Item | Decision |
|---|---|
| Final device | Avalanche AS308G208 (Dual-Quad SPI MRAM). Device 1 on IO[3:0], device 2 on IO[7:4], separate CS1#/CS2#, CLK1/CLK2 |
| Prototype device | **Winbond W25Q128JV** (single Quad-SPI NOR flash, 128 Mb, 3.3 V) on a breakout wired to the Discovery Kit. Only IO[3:0] is used; IO[7:4] input is forced to `"0000"` |
| Device selection | Generic `DEVICE : device_t` (`DEV_W25Q128JV`, `DEV_AS308G208`, enum in `qspi_pkg`). Opcodes, address width, latency, init sequence and write method are chosen from it |
| Die support | Generic `DIE2_PRESENT : boolean`. With `false`, IO[7:4] input is forced to `"0000"` in RTL and all die-2 checks are skipped. Always `false` with the W25Q128JV |
| Operating mode | **SDR only**, SPI mode 0 (CLK idle low) |
| Read command | **Fast Read Quad I/O (EBh), 1-4-4** for both devices: opcode on IO0, address/mode/latency and data on IO[3:0]. The W25Q128JV has **no QPI (4-4-4) mode** (no 38h command), so this is the only common quad read. The AS308G208 lists EBh (1-4-4) SDR at 54 MHz. Cost vs. QPI: 6 extra SCLKs per request (≈ 1 µs for 8 requests at 50 MHz). QPI (0Bh 4-4-4) on the AS308G208 is an optional later step (Step 15) |
| SCLK | **50 MHz** (max. 54 MHz for every AS308G208 SDR read in rev J.1, Tables 31–33 and the command table; the W25Q128JV allows 133 MHz). Reduced speed via generic `SCLK_DIV`. See Clocking |
| Lockstep | Both dies receive identical command/address/latency. Each quad SCLK cycle moves one host byte: `{die2_nibble, die1_nibble}` |
| Addressing | Host address/length in host bytes, both **must be even**. Die byte address = host_addr / 2. Odd values raise `req_err`. Address width per device (W25Q128JV 24 bit, AS308G208 per Step 1) |
| Init | Controller performs power-up wait, reset, ID check, configuration and verification by itself and asserts `init_done` |
| Flow control | No SCLK stalling. A read starts only when downstream space ≥ request length (credit input) |
| Data out | AXI4-Stream, 8-bit, `tlast` on the last byte of each request |

### Clocking

Current design (from `PF_CCC_C0.cxf` and the generated `PF_CCC_C0_0/*.v`): the board's **50 MHz** oscillator (`REF_CLK_50MHz`, pin R18) → `CLKINT` → `PF_CCC_C0`, VCO 5000 MHz, `OUT0` divider 10 → **125 MHz** (the PLL outputs are VCO / (4 × DIV)). Everything in the fabric, including FIC0 `ACLK`, runs on that 125 MHz with `CORERESET_0_FABRIC_RESET_N`. (The MSS's own 125 MHz reference is separate and not involved.)

The controller needs its own clock:

- `clk_ctrl` = **2 × SCLK**. The PHY toggles SCLK every `SCLK_DIV` `clk_ctrl` cycles (default `SCLK_DIV = 1`), so SCLK has an exact 50 % duty cycle and SCLK, data and sampling are all in one clock domain. 125 MHz would give SCLK 62.5 MHz, which is above the AS308G208's 54 MHz.
- **Add a second output `OUT1` = 100 MHz to the existing `PF_CCC_C0`**, rather than adding another CCC. 100 MHz cannot share the current VCO with 125 MHz (5000 / 4 / 100 = 12.5), so the configurator has to move the VCO to **4000 MHz**: `OUT0` divider 8 → 125 MHz, `OUT1` divider 10 → 100 MHz → SCLK 50 MHz. After the change, check in the generated netlist that `VCOFREQUENCY` is 4000, `DIV0_VAL` 8, `DIV1_VAL` 10, and that the GUI shows both outputs as exact.
- Reduced speed for bring-up: `SCLK_DIV = 2` → SCLK 25 MHz from the same 100 MHz. No CCC change needed.
- Reset: a second `CORERESET_PF` instance clocked by `clk_ctrl` (same `PLL_LOCK`/`INIT_DONE` connections as `CORERESET_0`) gives `reset_n` for the `clk_ctrl` domain.
- **Clock domain crossing:** `clk_ctrl` (100 MHz) and the 125 MHz fabric clock are different domains. In this plan the controller and the BIST both run entirely on `clk_ctrl`, and only LEDs (quasi-static) leave it, so no CDC logic is needed yet. Connecting the read stream to the 125 MHz side or the MSS later needs a dual-clock FIFO (CoreFIFO) and synchronisers; that's outside this plan. Declare the two clocks asynchronous in the SDC (Step 12).

### Sampling

- The device drives data after the SCLK falling edge. Because of round-trip delay, the controller samples IO **a configurable number of `clk_ctrl` cycles after the launching edge**. This is generic `SAMPLE_DLY` (range 1–4) plus a runtime override input used for calibration.
- All pad-facing flops (SCLK, CS#, IO out, IO OE, IO in) are single registers intended for packing into I/O cells. Step 11 determines how Libero 2026.1 does this for PolarFire (Synplify `syn_useioff` and/or a PDC I/O-register setting) and records it.

---

## Steps

### Step 1 — Extract device facts (no RTL)
Create `documentation/device_facts.md` with one section per device (W25Q128JV, AS308G208) and a page/table reference for every entry:
- Opcodes needed: reset enable/reset, Read JEDEC ID, Read Status, Write Enable, register read/write (W25Q: status registers 1–3; AS308G208: status/config registers or "any register" commands), 4-byte address mode (AS308G208, if needed), Fast Read Quad I/O EBh, write command(s) for test patterns, and for the W25Q128JV sector erase.
- Command format of each command in 1-1-1 and, for EBh and the write command, the quad form: opcode clocks, address bytes, mode bits (value to send so the device does **not** enter continuous-read/XIP mode), latency/dummy cycles, data direction.
- Read latency for EBh vs SCLK: the W25Q128JV's fixed dummy cycles; the AS308G208's latency setting (register and field) and the value for 50 MHz (Table 31 gives 8–15 at ≤ 54 MHz with XIP; resolve which table applies without XIP).
- AS308G208 QPI recovery: whether the device can be in QPI mode after an FPGA reload without a power cycle (only relevant if it can enter QPI at all in our flow), and the reset form that works in both modes.
- Quad enable: W25Q128JV QE bit (SR2, non-volatile, default depends on part number). AS308G208 equivalent, if any. What IO2/IO3 must be (WP#/HOLD# function) during 1-1-1 commands before quad is enabled.
- Expected JEDEC ID bytes for both devices.
- Power-up time (tVSL/tPU), reset recovery (tRST), CS# high time (tSHSL/tCSH, read and write), and tCLQV, tCLQX, tSU, tH for SDR.
- Writes: W25Q128JV needs erase before program, 256-byte page limit (wrap behaviour), busy polling (BUSY/WIP), program/erase times. AS308G208: confirm no busy polling and no erase, write latency, WREN requirement.
- AS308G208 8 Gb addressing: how the die-select bits map into the address. Flag open questions for the vendor.
- **Done when:** the user has reviewed the file and all values needed for Steps 2–8 are filled in or explicitly accepted as TBD.

### Step 2 — Package `qspi_pkg` and simulation script support
- `hdl/qspi_pkg.vhd`: `device_t`, per-device constants or functions (opcodes, address bytes, mode byte, latency, timing in ns, write method). Generic helpers (ns → `clk_ctrl` cycles, clog2) are in `hdl/util_pkg.vhd`, shared with the rest of `hdl/`.
- Types: `lane_mode_t` (SPI1, QUAD4), `dir_t` (DIR_NONE, DIR_TX, DIR_RX; prefixed so they don't clash with signal names).
- **Extend `sim/run_tb.sh`:** it compiles `hdl/*.vhd` in one alphabetical `vcom` call, which breaks once `qspi_*` files depend on `qspi_pkg` (and e.g. `qspi_mram_ctrl` sorts before `qspi_phy`). Compile `hdl/*_pkg.vhd` first and make the rest order-independent (e.g. retry loop or an explicit order list). Also add a header line `-- run_tb models: <file> ...` that compiles files from `sim/models/` before the testbench, like `-- run_tb cores:`. Update the script header, CLAUDE.md and README.
- **Done when:** the package compiles, `tb_util_pkg` checks the ns→cycles conversions at 100 MHz and 50 MHz, `tb_qspi_pkg` the device parameters, and all existing testbenches still pass.

### Step 3 — PHY / bit engine `qspi_phy`
Low level only: no knowledge of commands.
- Inputs: a phase descriptor stream (valid/ready) `{lanes, dir, nclk, tx1, tx2 (32 bits per die), last, sclk_div, cs_high}`. A transaction starts with the first descriptor after idle; `last` ends it (CS# high).
- Generates SCLK (toggles every `sclk_div` `clk_ctrl` cycles while a phase is active, idle low). `sclk_div` is a **per-transaction input** (1 or 2), defaulting to the `SCLK_DIV` generic: the AS308G208's 05h and 9Fh are limited to 40 MHz (device_facts.md §3.2), so init runs those at 25 MHz, CS# (both dies identical), IO out per die, IO OE.
- In SPI1 phases, IO2/IO3 (and IO6/IO7) are driven to the level Step 1 requires for WP#/HOLD#.
- RX: samples IO `SAMPLE_DLY` cycles after the launch edge and produces per-clock 8-bit words `{die2_nib, die1_nib}`. In SPI1 mode it extracts IO1 (die 1) and IO5 (die 2). Holds CS# low until the last delayed sample is taken.
- Releases OE for the turnaround at the start of latency cycles. With `DIE2_PRESENT=false`, IO[7:4] are never driven and read as `0000`.
- Enforces minimum CS# high time between transactions.
- **Done when:** `tb_qspi_phy` checks waveforms with a pin-level checker: CS/SCLK relationship, bit order in SPI1 and QUAD4, OE turnaround, `SAMPLE_DLY` 1–4, `SCLK_DIV` 1 and 2, CS# high time.

### Step 4 — Behavioural device model `qspi_mem_model`
- `sim/models/qspi_mem_model.vhd`: one die, generic `DEVICE`. Supports the Step 1 command subset: reset, Read JEDEC ID, status/config register R/W, Write Enable, EBh with the device's latency and mode-byte handling, the write command, and for the W25Q128JV sector erase with BUSY for a (generic, shortened) time and page-wrap on program. Sparse memory (associative array or hashed) so the full address space works in simulation.
- W25Q128JV model: QE reads as 1 (W25Q128JVSSIQ, fixed). A generic `QE_INIT` (default 1) lets a test start with QE = 0 to check the init error path; quad commands are rejected while QE = 0.
- Output timing: drives data `tCLQV` after the falling SCLK edge and keeps it until `tCLQX` after the next falling edge (generics, defaulting to the datasheet values).
- Asserts on protocol violations: wrong latency, illegal address, write without WEL, command while busy, SCLK above the max frequency, wrong mode bits (continuous-read entered unintentionally).
- Optional generic for board delay (SCLK out + IO back) to exercise `SAMPLE_DLY`.
- **Done when:** `tb_qspi_mem_model` drives the model with hand-written stimulus for both devices and checks Read ID, register write/readback, erase/program/busy (W25Q) and EBh reads (both latency settings for the AS308G208).

### Step 5 — Transaction engine `qspi_xact`
- Turns a high-level command (`opcode`, `addr`, `addr_bytes`, `mode_byte`, `latency`, `dir`, `nbytes`, `lanes` 1-1-1 / 1-4-4 / 1-1-4) into PHY phase descriptors.
- RX data out as an AXI4-Stream (8-bit host bytes). TX data in as an AXI4-Stream.
- **Done when:** `tb_qspi_xact` runs Read ID, register read/write and EBh reads against the W25Q128JV model and against one and two AS308G208 models (`DIE2_PRESENT=false/true`), checking data and nibble ordering.

### Step 6 — Init/configuration FSM `qspi_init`
Sequence, adjusted to the Step 1 facts:
1. Wait the power-up time after reset release (cycles from ns).
2. Reset. W25Q128JV: 66h + 99h, wait tRST. AS308G208: it has **no software reset**, so pulse the `mem_reset_n` output (RESET# pin), then wait tPU (25 ms). No QPI recovery is needed because we never enter QPI.
3. Read JEDEC ID in 1-1-1. Compare die 1 (and die 2 if present) against the expected ID for `DEVICE`. Mismatch → `init_err` with code `ERR_ID`.
4. Configure: W25Q128JV — nothing to write: check that nothing is protected and that QE = 1 (fixed on the W25Q128JVSSIQ; QE = 0 → `ERR_CFG`). AS308G208 — always write CR2 = 08h (latency 8) with WRAR and SR = 00h (no protection) with WRSR: register volatility is unknown (Q‑A3) and RDAR itself depends on CR2, so reading first isn't safe. Addresses are always 4 bytes, so there is no address mode to set.
5. Read back the configuration registers and verify (AS: CR2 = 08h, CR1 WRENS = 00, SR not protected). Mismatch → `ERR_CFG`.
6. Do one EBh read of a few bytes as a quad-path check (data not compared) and assert `init_done`.
- An `init_restart` input reruns the sequence. A status output gives the state and the error code.
- **Done when:** `tb_qspi_init` passes for the W25Q128JV (including QE = 0 → `ERR_CFG`) and for 1 and 2 AS308G208 models, including injected faults: wrong ID, a model ignoring a config write.

### Step 7 — Read front end `qspi_read_ctrl`
- Request input: AXI4-Stream, `tdata = {len[15:0], addr[31:0]}` (host bytes, even values only).
- Credit input `rx_space` (free bytes downstream). A request starts only when `rx_space ≥ in_flight + len` (`in_flight` = bytes of started requests not yet delivered) and `init_done = '1'`.
- Issues EBh via `qspi_xact`, with die address = addr/2 and data clock count = len.
- Output: `m_axis` 8-bit, `tlast` on the final byte. `req_err` for odd addr/len, an address beyond the device size, or a request before init.
- Handles back-to-back requests (e.g. 8 × 880 bytes) with minimal gaps.
- **Done when:** `tb_qspi_read_ctrl` reads 8 non-contiguous blocks of 880 host bytes from pre-loaded models (W25Q128JV; AS308G208 with 1 and 2 dies), checks the data and reports the total time in µs. At 50 MHz SCLK that is 7040 data clocks (140.8 µs) plus per-request overhead, so about 145 µs. Also checks that credit starvation delays the start without corrupting data.

### Step 8 — Write path (test and calibration support)
- Minimal write request (AXI4-Stream, same header format), Write Enable before each command.
- W25Q128JV: sector erase + BUSY polling, then page program split at 256-byte page boundaries with BUSY polling after each page. The quad page program (1-1-4) is used if Step 1 confirms it; otherwise 1-1-1 (only used for test patterns, so speed doesn't matter).
- AS308G208: the write command from Step 1, any length, busy polling only if Step 1 says it's needed.
- **Done when:** `tb_qspi_write` writes a pattern, reads it back with Step 7 and compares (W25Q128JV; AS308G208 with 1 and 2 dies).

### Step 9 — Controller top `qspi_mram_ctrl`
- Wraps init, read, write and xact/phy, with an arbiter for the `qspi_xact` command port and its TX/RX streams: `qspi_init` owns it until `init_done`, then read and write requests take turns. The owner only changes while `qspi_xact` is idle, so RX bytes always reach the source that issued the command (`tb_qspi_write` uses a simple testbench switch for this). Generics: `DEVICE`, `DIE2_PRESENT`, `CLK_CTRL_HZ`, `SCLK_DIV`, `SAMPLE_DLY`, `SPACE_W` (and `T_POWERUP_NS`/`T_RESET_NS` for simulation). No `MAX_LEN`: lengths are limited by the 16-bit `len` and buffering by `rd_space`.
- Pin-level ports: `sclk(1 downto 0)`, `cs_n(1 downto 0)`, `io_o(7 downto 0)`, `io_oe(7 downto 0)`, `io_i(7 downto 0)`, `mem_reset_n` (AS308G208 RESET#, unused with the W25Q128JV). No tristates inside.
- Runtime `sample_dly_ovr` input (valid flag + value) for calibration.
- **Done when:** a full-system TB (init → write → 8 × 880 read) passes for the W25Q128JV and for the AS308G208 with 1 and 2 dies, and a Libero synthesis run (Synplify, with `qspi_mram_ctrl` temporarily as root or via Step 11's wrapper) shows no latches and no multi-driven nets.

### Step 10 — Built-in self-test `qspi_bist`
- Fabric-only test, no software needed: after `init_done`, write a counter pattern to N blocks once per reset (flash endurance), then read them back and compare, again and again. Two LEDs, no error codes: LED5 = pass (on after at least one complete pass and no failure since reset), LED6 = fail (init error or data mismatch; latched until reset). Both off while init and the first pass are running. LED5–7 are currently tied low; LED1–4 are in use, LED7 stays tied low.
- Optional calibration mode: if init fails, retry it with sample delays 1–4 (init reads ID/registers too). Then sweep `SAMPLE_DLY` 1–4 over the read rounds, record which values pass and select the centre of the passing window (lower middle for an even width).
- **Done when:** `tb_qspi_bist` passes with model board delays set so only some `SAMPLE_DLY` values work, and the calibration picks a passing value.

### Step 11 — Integration into `TOP`
The project's top level is the SmartDesign `TOP`, so there's no separate HDL board top.
- `hdl/qspi_board.vhd`: `qspi_mram_ctrl` + `qspi_bist` + the tristate IO buffers (inout `io(3 downto 0)` for the prototype; `io(7 downto 4)` and the second `cs_n`/`sclk` only when `DIE2_PRESENT = true`). Make it an **HDL+ core** so `DEVICE`, `SCLK_DIV`, etc. can be set per instance (plain HDL modules lose their generics in SmartDesign).
- **User actions (GUI):** add `OUT1` = 100 MHz to `PF_CCC_C0` (see Clocking); add a second `CORERESET_PF` instance for `clk_ctrl`; place `qspi_board` in `TOP`, connect clock/reset, LED5/LED6 (remove their tie-low) and promote the QSPI pins to top-level ports; Generate Component.
- **User action:** pick the pins for the breakout: CS#, SCLK, IO0–IO3 (6 pins), 3.3 V. Candidates are the RPi header (Bank1; full pin list in the reference design's `MPFS_DISCOVERY_RPi.pdc`) or the mikroBUS connector. On the RPi header avoid the pins already used: E13 (40), B19 (35), B15 (36), B17 (37), B14 (38). Confirm from the board schematic. Keep the wires short.
- I/O-register packing on PolarFire: `syn_useioff` is not supported (Synplify lists it for other vendors only). Libero uses `set_ioff` in an NDC file (`constraints/qspi_ioreg.ndc`, linked in Constraint Manager → Netlist Attributes). PolarFire syntax `set_ioff -port_name {P} -OUT_REG 1`. Only one register per I/O cell can be combined (fanout 1): SCLK/CS# output registers, IO3:0 input registers (the read sample is the tight path); IO out/OE stay in the fabric and are timed in Step 12. `syn_preserve` keeps every pad register separate.
- Verify `TOP.vhd`, the `PF_CCC_C0` netlist (VCO 4000, dividers 8/10) and the new core's `.cxf`.
- **Done when:** the design synthesises and places in Libero with no I/O-register packing warnings on the pad flops, and README + `top_level.drawio` show the new block.

### Step 12 — Constraints
- `constraints/io.pdc`: QSPI pin assignments with `-io_std LVCMOS33` (Bank1, see CLAUDE.md), drive strength/slew, and weak pull-ups on CS# (both datasheets recommend one) and IO2/IO3 (IO6/IO7): after a QUAD4 read the PHY leaves IO3:0 released while CS# is high, and the AS308G208's WP# has no internal pull-up.
- `constraints/timing.sdc` (new, linked into the project as a timing constraint): the CCC clocks come from Libero's derived constraints; add `set_clock_groups -asynchronous` between `OUT0` (125 MHz) and `OUT1` (100 MHz), `create_generated_clock` for SCLK at the output pin, `set_output_delay` (tSU/tH) and `set_input_delay` (tCLQV/tCLQX + estimated board delay) relative to SCLK, and multicycle settings matching `SAMPLE_DLY`.
- `documentation/timing_budget.md`: a short budget that justifies the default `SAMPLE_DLY` at 50 MHz SCLK for the breakout wiring.
- **Done when:** the Libero flow completes with timing met at 100 MHz `clk_ctrl`, no unconstrained I/O paths, and no timed paths between the two clock domains.

### Step 13 — Hardware bring-up, W25Q128JV breakout
Checklist in `documentation/bringup.md`, filled in with results:
1. Program, check the pass LED (LED5) or the fail LED (LED6).
2. If it fails: read the init status/error code with SmartDebug (Live Probe on `qspi_init`'s status output), or rebuild with `SCLK_DIV = 2` (SCLK 25 MHz) and scope CS#/SCLK/IO1 on the header pins.
3. Run BIST at 25 MHz, then 50 MHz. Run calibration and record the passing `SAMPLE_DLY` window.
4. Optional: SmartDebug/Identify probes on the PHY.
- Note: the BIST erases and programs the flash once per reset (write once, then read-only rounds), so flash endurance is not an issue.
- **Done when:** BIST passes repeatedly at 50 MHz SCLK on the breakout, and the passing window is documented.

### Step 14 — AS308G208 dual-die board (later)
- Set `DEVICE = DEV_AS308G208`, `DIE2_PRESENT = true`, update pins and constraints for the target PCB, rerun BIST and calibration, and confirm the measured read time for 8 × 880 bytes.
- Resolve the 8 Gb addressing question from Step 1 before using addresses beyond the first die group.

### Step 15 — Optional: QPI (4-4-4) reads on the AS308G208
- Only if the 1-4-4 overhead matters: Enable QPI (38h) in init, 0Bh 4-4-4 reads with the QPI latency (Table 31: 10–15 for 4-4-4 SDR), reset in both forms at init (the device may still be in QPI after an FPGA reload), and an `ERR_QPI` check by reading back a register in QPI form.

---

## Status

| Step | Title | Status | Notes |
|---|---|---|---|
| 1 | Device facts | done | `documentation/device_facts.md`. Part is W25Q128JVSSIQ; Q‑W2/Q‑A* assumptions accepted |
| 2 | Package + run_tb.sh | done | `hdl/qspi_pkg.vhd`, `hdl/util_pkg.vhd` (clog2/reverse/ns_to_cycles, also used by the SPI masters), `tb_qspi_pkg`, `tb_util_pkg`. `run_tb.sh`: packages first, dependency-order retry, fresh work library, `-- run_tb models:`. All 12 testbenches pass |
| 3 | PHY | done | `hdl/qspi_phy.vhd`, `tb_qspi_phy` (also with `-gDIE2_I=0`); 6 deliberate DUT faults all caught. `SCLK_DIV_MAX`/`SAMPLE_DLY_MAX` = 4 in `qspi_pkg` |
| 4 | Device model | done | `sim/models/qspi_mem_model.vhd` + `qspi_model_pkg.vhd`, `tb_qspi_mem_model`. Found and fixed in `qspi_phy`: it re-drove IO0/2/3 at CS# high while the device was still driving after a quad read; pads now change only with CS# low |
| 5 | Transaction engine | done | `hdl/qspi_xact.vhd` (contains `qspi_phy`), `tb_qspi_xact` (W25Q, AS 1 die, AS 2 dies in one run); 6 deliberate DUT faults all caught. Stream format: 4-line data = host bytes `{die2_nib, die1_nib}`, 1-line data = die 1 byte then die 2 byte |
| 6 | Init FSM | done | `hdl/qspi_init.vhd`, `tb_qspi_init` (8 configurations incl. faults, each run twice); 6 deliberate DUT faults all caught. Model got fault-injection generics (`W25_ID`, `AS_SR_INIT`, `AS_CR2_INIT`, `REG_WRITE_IGNORE`) |
| 7 | Read front end | done | `hdl/qspi_read_ctrl.vhd`, `tb_qspi_read_ctrl`. 8 × 880 host bytes: 144.5 µs (W25Q), 145.5 µs (AS, 1 and 2 dies). 5 deliberate DUT faults all caught (after making the starvation test stricter) |
| 8 | Write path | done | `hdl/qspi_write.vhd`, `tb_qspi_write`. W25Q erases every 4 KB sector the request touches; `wr_done` pulse when written. 5 deliberate DUT faults all caught. 880 host bytes: 18.8 µs (AS), 42.9 µs (W25Q with the model's shortened erase/program times; real tSE is 45 ms typ.) |
| 9 | Controller top | done | `hdl/qspi_mram_ctrl.vhd`, `tb_qspi_mram_ctrl`. Fixed in `qspi_init`: `init_done` now drops in the same cycle as `init_restart`. Synplify (`tools/syn_check.sh`, W25Q and AS 2 dies): no errors/latches/multi-drivers, ~1.5k LUTs, 700/815 FFs; pad flops kept separate with `syn_preserve` |
| 10 | BIST | done | `hdl/qspi_bist.vhd`, `tb_qspi_bist` (5 configurations incl. calibration windows {1,2} and {2}, init retry, data and ID faults); 4 deliberate DUT faults all caught. Synplify clean, ~190 LUTs. Model got `MEM_WRITE_IGNORE` |
| 11 | Integration into TOP | done | `hdl/qspi_board.vhd` (single die, integer generics for HDL+), `tb_qspi_board`, `constraints/qspi_ioreg.ndc`. PolarFire combines only one register per I/O: SCLK/CS# output, IO3:0 input registers. Pins on the RPi header: SCLK G18 (11), CS# F21 (13), IO0–3 F20/E21/F19/A19 (15/16/18/22), pull-ups on CS#/IO2/IO3. `PF_CCC_C0` OUT1 = 100 MHz (VCO 4000), `CORERESET_1`. P&R + timing met: OUT1 worst setup slack 5.5 ns, hold 0.066 ns; QSPI I/O still unconstrained (Step 12) |
| 12 | Constraints | done | `constraints/timing.sdc` (async clock groups, `qspi_sclk` generated clock on the pin, I/O delays relative to SCLK for the worst of both devices, 2-cycle input setup, LED5/6 false paths), `documentation/timing_budget.md`. Pins and pull-ups were done in Step 11. Timing met in all corners; worst QSPI slacks: input setup 2.15 ns, output setup 3.14 ns (CS#), hold ≥ 3.45 ns. OUT1/`qspi_sclk` fully constrained. `SAMPLE_DLY` = 2 is the only valid setting at 50 MHz |
| 13 | Bring-up, W25Q128JV | todo | |
| 14 | AS308G208 dual die | todo | |
| 15 | QPI reads (optional) | todo | |

