# Plan: Client access to the QSPI memory (CPU over AXI4-Lite, fabric over AXI4-Stream)

## Instructions for Claude Code

Work through the steps **in order**, one step per session/PR. At the end of every step:

1. All testbenches must pass with `sim/run_tb.sh` (see CLAUDE.md), and `tools/syn_check.sh` must be clean for every new or changed RTL entity.
2. Update README.md (design overview, register map, repository layout, one Simulation paragraph per new testbench), `documentation/qspi_controller.drawio` and, when TOP changes, `documentation/top_level.drawio`.
3. Update the **Status** table at the bottom of this file.
4. Stop and report. The user commits to Git. Do not start the next step without being asked.

The ground rules in CLAUDE.md apply (VHDL subset Synplify supports, `hdl/` conventions, the user does all Libero GUI work, Claude verifies by reading the generated files). The open questions below must be answered before the step that needs them.

## Goal

After the BIST has passed, two clients can read and write the QSPI memory through `qspi_board`, **never at the same time**:

- **CPU** (E51 over FIC0): an AXI4-Lite register block. The CPU writes the memory to update lookup data and reads it back to verify. Throughput is not critical.
- **Fabric**: AXI4-Stream request, write data, read data and response streams, for the high-throughput readers of the lookup data (e.g. 8 × 880 bytes within 200 µs).

Who may access the memory follows from a **high-level system state** that the CPU controls:
- `operational`: the fabric owns the QSPI.
- Any other state: the CPU owns it, and the fabric blocks that produce data can be held in reset.

The CPU only updates the lookup data while the system is not operational. The hardware enforces the ownership anyway: requests from the client that doesn't own the QSPI are held, not executed.

Until the BIST has passed, all client requests are held (`tready` low). After a BIST fail they stay held, and `bist_fail` tells the client why.

## Starting point (existing, unchanged by this plan unless noted)

- `qspi_mram_ctrl` has a read request stream and a write request stream (`{len[15:0], addr[31:0]}`, host bytes), a read data stream (`m_axis`, `tlast` per request), a write data stream, `rd_req_err` / `wr_req_err` (one-cycle pulses in the cycle after the request handshake), `wr_done`, and `busy`.
- **Reads are credit-based:** `qspi_read_ctrl` starts a read only when `rd_space ≥ in_flight + len`, and after that the consumer must keep up (the PHY can't stop SCLK). One read request is buffered while the previous one runs.
- **Late write data pauses SCLK** (CS# stays low, `qspi_xact`). Functionally harmless, but a client that never delivers its data would keep the controller busy forever, and an ownership change would then never happen.
- `qspi_bist` stops in `B_DONE` / `B_FAIL` (with `LOOP_ROUNDS = false`) and keeps driving `sample_dly_ovr_valid = '1'` with the calibrated delay until reset.
- The BIST writes 8 blocks of 880 host bytes at stride `0x4000` from `BASE_ADDR = 0`, i.e. within host addresses `0x0000_0000 – 0x0001_FFFF`. On the W25Q128JV it erases the sectors it touches. It does this **at every power-up**.
- `qspi_board` runs on `clk_ctrl` (100 MHz, `CORERESET_1`). FIC0 and the rest of the fabric run on 125 MHz. The two clocks are asynchronous (`constraints/timing.sdc`).

## Architecture

```
 125 MHz                                                      | 100 MHz (clk_ctrl)
                                                              |
 FIC0 -+-> axi_sys_ctrl (LED, ID, DEBUG, STATE)                |
       |      | operational                                   |
       |      v                                               |
       +-> qspi_axil_regs --(port 0)--+                       |
                                      +--> qspi_client_mux --> qspi_port_cdc --> qspi_board
 fabric client(s) -------(port 1)----+     (owner = fabric    |   (CoreFIFOs)     qspi_host_mux
   (reset while not operational)           when operational)  |                   + qspi_bist
                                                              |                   + qspi_mram_ctrl
```

## Design decisions

| Item | Decision |
|---|---|
| Structure | `qspi_board` stays **single-clock** (`clk_ctrl`) with **one** client port. There is **one CDC block** (`qspi_port_cdc`) outside `qspi_board`. CPU and fabric meet in `qspi_client_mux` on the 125 MHz side. No arbitration, no per-client credit or read routing, because only one client owns the port at a time. |
| Handover from the BIST | `qspi_host_mux` inside `qspi_board` connects `qspi_bist` to the controller until the BIST has passed **and** `busy = '0'`. Then it switches to the client port once (registered `ready`, cleared only by reset). `sample_dly_ovr*` stay driven by the BIST. `init_restart` is held at `'0'` after the switch. `LOOP_ROUNDS` must be false (`qspi_board` already uses the default false). |
| Client request format | One request stream, 49 bit: `{wr, len[15:0], addr[31:0]}`. `qspi_host_mux` splits it into the controller's read and write request streams. |
| Read flow control | `rd_space` of the controller comes from the CDC read data FIFO's write-side count (`clk_ctrl` domain, conservative). A read longer than that FIFO (`RD_DEPTH` generic) could never start, so it is rejected. |
| Write flow control | **Store and forward.** `qspi_host_mux` forwards a write only when the CDC write data FIFO holds all `len` bytes (`wr_avail`, from its read-side count). The controller then never waits for data while CS# is low. A half-written request (e.g. the CPU program stops) therefore can't leave the controller busy and block the next ownership change. A write longer than `WR_DEPTH` is rejected. |
| Responses | **Every request gets exactly one response** on a response stream, `{wr, err}`. Read OK: after its `tlast` has been forwarded. Write OK: `wr_done`. Error: the controller's `req_err` (one cycle after the accept), or `qspi_host_mux`'s own checks. `qspi_client_mux` counts requests without a response, to know when the port is idle. |
| BIST area protection | `qspi_host_mux` rejects **writes** that overlap the BIST area (`BASE_ADDR … BASE_ADDR + (NBLK − 1) · BLK_STRIDE + BLK_LEN`). Reads there are allowed. The area is documented in README as reserved. Open question Q1. |
| Ownership | `qspi_client_mux` (125 MHz) has two client ports with the same signals as the CDC client side: port 0 = CPU (`qspi_axil_regs`), port 1 = fabric. Its input is `operational`. Owner = fabric when `operational = '1'`, else CPU. The non-owner's `tready` signals are low and it sees no read data or responses. |
| Ownership change | The owner changes only when the port is idle: no outstanding requests, and the CDC request and write data FIFOs are empty. Until then the old owner stays connected and the new one is held. **Leaving `operational`:** the fabric readers may be put into reset immediately, so from then on `qspi_client_mux` takes over the fabric's side. It drops further fabric requests, accepts and discards the remaining read data and responses of its outstanding requests, and only then hands the port to the CPU. `owner` (0 = CPU, 1 = fabric) is an output, readable by the CPU and visible to the fabric. |
| System state | The high-level state register is `STATE` in **`axi_sys_ctrl`**, the renamed and extended `axi_led_reg` (register map below). It already has the general registers (LEDs, ID, debug pulse) and runs on the same 125 MHz FIC0 clock. Its output `operational` (125 MHz, no CDC needed) drives `qspi_client_mux` and, in TOP, the reset of the fabric blocks that produce data (`reset_n = FABRIC_RESET_N and operational`). `qspi_axil_regs` contains only QSPI registers. Open question Q3. |
| Status | `qspi_board` outputs `ready` and `bist_fail` (quasi-static; `qspi_port_cdc` synchronises them with 2 flip-flops). `bist_pass` / `bist_fail` keep driving LED5 / LED6. |
| CDC block | `qspi_port_cdc`, dual-clock CoreFIFOs: request (client → QSPI), write data (client → QSPI), read data + `tlast` (QSPI → client), response (QSPI → client), plus the `ready` / `bist_fail` synchronisers. It also gives `rd_space` and `wr_avail` to `qspi_board`, in the `clk_ctrl` domain. |
| CoreFIFO configs | Two new configurations: `QSPI_CTL_FIFO` (dual clock, 49 bit × 16, for requests and responses; responses use the low bits) and `QSPI_DATA_FIFO` (dual clock, 9 bit × 2048 = one LSRAM, with write-side and read-side counts, for read data `{tlast, byte}` and write data). FWFT, active-high WE/RE, sync reset per side, like `BLOCK_FIFO_CORE`. Verify the exact count port names and latency in the configurator before writing the wrapper. |
| CPU port | `qspi_axil_regs` on the 125 MHz FIC0 clock is a second target of CoreAXI4Interconnect, at `0x6000_1000 – 0x6000_1FFF`. Data moves 4 bytes per 32-bit register access. |
| Fabric port | Port 1 of `qspi_client_mux`, exposed in TOP on the 125 MHz clock. First user: a small test client (Step 8). Open question Q2. |

### System register map (`axi_sys_ctrl`, base `0x6000_0000`, proposal)

The existing `axi_led_reg` offsets stay unchanged, so the current software keeps working.

| Offset | Name | Access | Description |
|---|---|---|---|
| 0x0 | LED | R/W | bit 0 = LED2, bit 1 = LED3 (unchanged) |
| 0x4 | ID | RO | `0x1ED50002` (was `0x1ED50001`, so software can tell the new bitstream from the old one) |
| 0x8 | DEBUG | WO | Writing bit 0 = 1 gives one `DEBUG_PULSE` (unchanged) |
| 0xC | STATE | R/W | High-level system state, bits 3:0. The encoding is set by Q3; one value means `operational`. Reset value: a non-operational state (CPU owns the QSPI) |

### CPU register map (`qspi_axil_regs`, base `0x6000_1000`, proposal)

| Offset | Name | Access | Description |
|---|---|---|---|
| 0x00 | ID | RO | Fixed value, e.g. `0x95F1_0001` |
| 0x04 | STATUS | RO | bit 0 `ready`, bit 1 `bist_fail`, bit 2 `owner` (1 = fabric), bit 3 request FIFO full, bit 4 response available |
| 0x08 | ADDR | R/W | Host byte address |
| 0x0C | LEN | R/W | Length in host bytes (even, > 0) |
| 0x10 | CMD | WO | Write pushes `{wr = bit 0, LEN, ADDR}` as one request. 0 = read, 1 = write. Held (not lost) while the CPU isn't the owner; check `owner` first |
| 0x14 | RSP | RO | Reading pops one response: bit 31 valid, bit 1 `wr`, bit 0 `err`. Reads `0` when there is none |
| 0x18 | WDATA | WO | Pushes 4 bytes, byte 0 = bits 7:0 (sent first) |
| 0x1C | WDATA16 | WO | Pushes 2 bytes (bits 15:0), for lengths that are 2 mod 4 |
| 0x20 | RDATA | RO | Pops up to 4 bytes, byte 0 = bits 7:0. Fewer at the end of a request (`tlast`) |
| 0x24 | LEVELS | RO | bits 15:0 read bytes available, bits 31:16 free write bytes |

Pop-on-read registers (RSP, RDATA) are safe because the FIC0 region is I/O memory (no speculative or cached reads).

Software sequences:
- **Update the lookup data:** set `axi_sys_ctrl` STATE to a non-operational state, then poll until `qspi_axil_regs` STATUS `owner` = 0. Write the data (below), read it back to verify, then set STATE to operational.
- **Write:** push the data to WDATA, write ADDR, LEN and then CMD = 1, and poll RSP.
- **Read:** write ADDR, LEN and then CMD = 0, pop RDATA until LEN bytes have arrived, then read RSP.

## Open questions (answer before the step that needs them)

- **Q1 (Step 1):** Keep the BIST area at host `0x0000_0000 – 0x0001_FFFF`, or move it, e.g. to the end of the memory (the `BASE_ADDR` generic, exposed on `qspi_board`)? On the MRAM, lookup data in that area would be overwritten at every power-up.
- **Q2 (Step 8):** What is the real fabric client? Its clock domain and how it consumes the data decide the TOP wiring after the test client. If it runs on `clk_ctrl`, it would need its own path; this plan assumes 125 MHz.
- **Q3 (Step 6):** Which system states are there besides `operational`, and what is their encoding in STATE? If this isn't decided by Step 6, use 0 = idle (reset value) and 1 = operational, and leave the rest reserved.

## Steps

### Step 1 — BIST area and `qspi_board` generics
- Expose `BASE_ADDR` (and `BLK_STRIDE` if useful) as integer generics on `qspi_board` (HDL+ configurator handles integers only). Set it according to Q1.
- Add a function in `qspi_pkg` that returns the BIST area for given `NBLK`, `BLK_LEN`, `BLK_STRIDE` and `BASE_ADDR`, for use by `qspi_host_mux`. `tb_qspi_pkg` checks it.
- README: document the reserved area.
- **Done when:** tests pass, and the user has updated the HDL+ core and checked the `generic map` in `TOP.vhd`.

### Step 2 — `qspi_host_mux` (`clk_ctrl`, pure RTL)
- Ports:
  - BIST side, as today
  - controller side
  - one client port: `req_*` 49 bit, `wr_*` 8 bit, `rd_*` 8 bit + `tlast`, `rsp_*` 2 bit, `rd_space`, `wr_avail`
  - `ready`
- Behaviour: handover from the BIST, splitting requests into read and write, store and forward, the length and BIST-area checks, and the responses, as in Design decisions.
- `sim/tb_qspi_host_mux.vhd` against `qspi_mram_ctrl` + the W25Q128JV / AS308G208 models (BIST included, short `NBLK` / `BLK_LEN`):
  - client requests before the BIST pass are held and run after it
  - nothing is accepted after a BIST fail
  - mixed reads and writes with all data checked, one response per request in order
  - a slow reader (`rd_space` model) never overflows
  - a write is not forwarded before all its data is there
  - errors (odd address, too long, BIST area) give an `err` response and no data
  - `sample_dly_ovr` keeps the calibrated value after the handover
- **Done when:** the testbench passes and `syn_check` is clean.

### Step 3 — `qspi_board` with the client port
- Put `qspi_host_mux` between `qspi_bist` and `qspi_mram_ctrl`. Bring the client port and `ready` out. Add generics `RD_DEPTH` / `WR_DEPTH`.
- Extend `tb_qspi_board`: after `bist_pass`, the client writes and reads a block outside the BIST area at pin level, and the model sees no protocol errors.
- The user updates the HDL+ core and the instance in SmartDesign (new ports tied off for now) and does Generate Component.
- **Done when:** tests pass, the generated `TOP.vhd` shows the new ports, and synthesis, place and route and timing still pass in Libero.

### Step 4 — `qspi_port_cdc` with CoreFIFOs
- The user creates `QSPI_CTL_FIFO` and `QSPI_DATA_FIFO` in the CoreFIFO configurator (instructions from Claude). Claude checks the `.cxf` values and the `_manifest.txt`.
- `hdl/qspi_port_cdc.vhd`: four FIFOs, `rd_space` / `wr_avail` from the counts, 2-FF synchronisers for `ready` / `bist_fail`, and a client-side `idle` output (request and write data FIFOs empty) for `qspi_client_mux`.
- `sim/tb_qspi_port_cdc.vhd` (`-- run_tb cores: QSPI_CTL_FIFO QSPI_DATA_FIFO`), with 100 MHz and 125 MHz clocks:
  - streams pass through intact in both directions
  - `rd_space` never overstates the real free space
  - `wr_avail` never overstates the bytes present
  - resets on both sides
- CLAUDE.md: add the two CoreFIFO configs (like the `BLOCK_FIFO_CORE` note).
- **Done when:** the testbench passes and `syn_check` is clean (with the core sources).

### Step 5 — `qspi_client_mux` (125 MHz, pure RTL)
- Two client ports (CPU, fabric), one port to `qspi_port_cdc`, inputs `operational` and `idle`, output `owner`.
- Ownership as in Design decisions: change only when the port is idle, the non-owner is held, and on leaving `operational` the remaining fabric data and responses are drained.
- `sim/tb_qspi_client_mux.vhd` with a behavioural stand-in for the CDC + `qspi_board` (responds to requests with data and responses after a delay):
  - each client only gets through while it is the owner
  - `operational` toggled with requests outstanding: `owner` changes only after the last response
  - fabric put in reset mid-read: its remaining data is drained, and the CPU's first read afterwards gets only its own data
  - a CPU request written while the fabric owns the port runs after the switch, not before
- **Done when:** the testbench passes and `syn_check` is clean.

### Step 6 — `axi_sys_ctrl`: add STATE
The rename `axi_led_reg` → `axi_sys_ctrl` (HDL, testbench, docs, `e51.c` comments; register map and ID unchanged) was done separately, ahead of this plan.

- Add `STATE` (0xC) and the `operational` output, and bump the ID to `0x1ED50002`, as in the system register map.
- Extend `tb_axi_sys_ctrl`:
  - STATE write and readback, and its reset value
  - `operational` follows STATE
  - the existing LED, ID and DEBUG checks still pass
- Update README, `documentation/components/axi_sys_ctrl.md`, `top_level.drawio`, and the expected ID in `e51.c`.
- The user updates the core in Libero (new `operational` port, unconnected for now) and does Generate Component.

**Done when:** the tests pass, Libero passes synthesis, place and route and timing, and on the board the software reads the new ID.

### Step 7 — CPU port: `qspi_axil_regs` and TOP
- `hdl/qspi_axil_regs.vhd` (structure like `axi_sys_ctrl`), register map as above.
- `sim/tb_qspi_axil_regs.vhd`:
  - AXI-Lite master BFM through `qspi_client_mux` → `qspi_port_cdc` → `qspi_board` → model
  - write/read of a block via the registers, lengths of 4n and 4n + 2
  - RSP and LEVELS behaviour, ID, STATUS before and after `ready`
  - `owner` following an `operational` input driven by the testbench
  - slow `BREADY` / `RREADY`
- TOP (user, with instructions):
  - a second interconnect target at `0x6000_1000`
  - `qspi_axil_regs` + `qspi_client_mux` + `qspi_port_cdc` wiring, `axi_sys_ctrl` `operational` → `qspi_client_mux`, fabric port tied off
  - Derive Constraints if needed, then check that the existing asynchronous clock groups cover the FIFO crossings
- **Done when:** the tests pass, Libero passes synthesis, place and route and timing, and the user has programmed the board.

### Step 8 — Fabric port in TOP and a test client
- `hdl/qspi_fabric_test.vhd` on port 1 of `qspi_client_mux`, reset by `FABRIC_RESET_N and operational`:
  - after reset it waits for `owner` = fabric
  - reads N blocks from an address range the CPU wrote
  - checks them against a known pattern
  - reports pass, fail and the measured read time, in a read-only status register added to `axi_sys_ctrl` or on an LED
- Test with `sim/tb_qspi_fabric_test.vhd`. Then decide on the real client (Q2).
- **Done when:** tests pass, timing passes, and on the board the fabric test passes after a CPU update.

### Step 9 — Bare-metal driver and on-board test
- `softconsole/led_test/src/application/hart0/qspi.c` / `qspi.h`: `qspi_wait_ready()`, `qspi_write(addr, buf, len)`, `qspi_read(addr, buf, len)`, response and error handling, timeouts.
- `sys_set_state()` for `axi_sys_ctrl` STATE (in `sys_ctrl.c` / `.h`). Switching to non-operational waits until `qspi_axil_regs` `owner` = CPU.
- `e51.c`:
  - wait for `ready`
  - in the non-operational state: write a pattern outside the BIST area, read it back, compare
  - try a write into the BIST area, which must give an error
  - switch to operational and let the fabric test from Step 8 read the data
  - switch back, and check that the CPU owns the port again
  - print the results on the UART
- README: CPU usage section, register map.
- **Done when:** the UART log shows all checks passing on the board (W25Q128JV breakout), recorded in `documentation/bringup.md`.

## Status

| Step | Status |
|---|---|
| 1 — BIST area and `qspi_board` generics | open |
| 2 — `qspi_host_mux` | open |
| 3 — `qspi_board` with the client port | open |
| 4 — `qspi_port_cdc` with CoreFIFOs | open |
| 5 — `qspi_client_mux` | open |
| 6 — `axi_sys_ctrl`: add STATE | open (rename done) |
| 7 — CPU port: `qspi_axil_regs` and TOP | open |
| 8 — Fabric port in TOP and a test client | open |
| 9 — Bare-metal driver and on-board test | open |
