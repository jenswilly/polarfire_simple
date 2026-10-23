# Plan: Client access to the QSPI memory (CPU over AXI4-Lite, fabric over AXI4-Stream)

## Instructions for Claude Code

Work through the steps **in order**, one step per session/PR. At the end of every step:

1. All testbenches must pass with `sim/run_tb.sh` (see CLAUDE.md), and `tools/syn_check.sh` must be clean for every new or changed RTL entity.
2. Update README.md (design overview, register map, repository layout, one Simulation paragraph per new testbench), `documentation/qspi_controller.drawio` and, when TOP changes, `documentation/top_level.drawio`.
3. Update the **Status** table at the bottom of this file.
4. Stop and report. The user commits to Git. Do not start the next step without being asked.

The ground rules in CLAUDE.md apply (VHDL subset Synplify supports, `hdl/` conventions, the user does all Libero GUI work, Claude verifies by reading the generated files). The open questions below must be answered before the step that needs them.

## Goal

After the BIST has passed, other blocks can read and write the QSPI memory through `qspi_board`:

- **CPU** (E51 over FIC0): an AXI4-Lite register block. Software writes address, length and command registers, pushes write data, pops read data and reads a response.
- **Fabric**: AXI4-Stream request, write data, read data and response streams, for high-throughput clients (e.g. 8 × 880 bytes within 200 µs).

Until the BIST has passed, client requests are held (`tready` low), not rejected. After a BIST fail they stay held, and `bist_fail` tells the client why.

## Starting point (existing, unchanged by this plan unless noted)

- `qspi_mram_ctrl` has a read request stream and a write request stream (`{len[15:0], addr[31:0]}`, host bytes), a read data stream (`m_axis`, `tlast` per request), a write data stream, `rd_req_err` / `wr_req_err` (one-cycle pulses in the cycle after the request handshake), `wr_done`, and `busy`.
- **Reads are credit-based:** `qspi_read_ctrl` starts a read only when `rd_space ≥ in_flight + len`, and after that the consumer must keep up (the PHY can't stop SCLK). One read request is buffered while the previous one runs.
- **Late write data pauses SCLK** (CS# stays low, `qspi_xact`). Functionally harmless, but a client that never delivers its data would block the controller forever.
- `qspi_bist` stops in `B_DONE` / `B_FAIL` (with `LOOP_ROUNDS = false`) and keeps driving `sample_dly_ovr_valid = '1'` with the calibrated delay until reset.
- The BIST writes 8 blocks of 880 host bytes at stride `0x4000` from `BASE_ADDR = 0`, i.e. within host addresses `0x0000_0000 – 0x0001_FFFF`. On the W25Q128JV it erases the sectors it touches. It does this **at every power-up**.
- `qspi_board` runs on `clk_ctrl` (100 MHz, `CORERESET_1`). FIC0 and the rest of the fabric run on 125 MHz. The two clocks are asynchronous (`constraints/timing.sdc`).

## Design decisions

| Item | Decision |
|---|---|
| Structure | `qspi_board` stays **single-clock** (`clk_ctrl`). It gets two client ports (port 0 = CPU, port 1 = fabric) in the `clk_ctrl` domain. **The CDC is outside `qspi_board`**, one `qspi_port_cdc` per port, as separate SmartDesign instances. A fabric client that runs on `clk_ctrl` can connect directly without a CDC block. `qspi_board` stays simulable without Libero cores. |
| Handover | New entity `qspi_host_mux` inside `qspi_board`. It connects `qspi_bist` to the controller until the BIST has passed **and** `busy = '0'`, then it switches to the client arbiter once (registered `ext_en`, cleared only by reset). `sample_dly_ovr*` stay driven by the BIST. `init_restart` is held at `'0'` after the switch. `LOOP_ROUNDS` must be false (`qspi_board` already uses the default false). |
| Port count | Fixed at 2 ports (`p0_*`, `p1_*`), no array ports (SmartDesign has none). |
| Port request format | One request stream per port, 49 bit: `{wr, len[15:0], addr[31:0]}`. Same checks as the controller (even address and length, length > 0, no wrap), plus the mux's own checks below. |
| Arbitration | Round robin between the two ports, one request at a time. Writes hold the grant for the whole request (the controller already serialises writes). Open question Q1. |
| Read routing | The mux pushes the port number of each accepted read into a small route FIFO (depth 4). Read data goes to the port at the head of that FIFO, and `tlast` pops it. The controller returns reads in order, so this is enough. |
| Read flow control | **Per-port credit.** Each port has an `rd_space` input (free bytes in its read data FIFO). The mux accepts a read from port k only when `rd_space_k ≥ in_flight_k + len`, so a slow CPU doesn't hold up fabric reads beyond its own request. The controller's own `rd_space` is then tied to a constant that is always large enough (sum of the ports' FIFO depths). A read longer than the port's FIFO depth (`P<k>_RD_DEPTH` generic) can never start, so it is rejected. |
| Write flow control | **Store and forward.** Each port has a `wr_avail` input (bytes waiting in its write data FIFO). The mux forwards a write only when `wr_avail_k ≥ len`, so the controller never waits for client data while holding CS# low. A write longer than the port's write FIFO depth (`P<k>_WR_DEPTH`) is rejected. A client on `clk_ctrl` without a FIFO can tie `wr_avail` high (all ones). It is then trusted to deliver the data in time. |
| Responses | **Every request gets exactly one response** on a per-port response stream: `{wr, err}`. Read OK → after its `tlast` has been forwarded. Write OK → `wr_done`. Error → the controller's `req_err` (attributed to the port whose request was accepted in the previous cycle), or the mux's own checks. |
| BIST area protection | The mux rejects client **writes** that overlap the BIST area (`BASE_ADDR … BASE_ADDR + (NBLK − 1) · BLK_STRIDE + BLK_LEN`). Reads there are allowed. The area is documented in README as reserved. Open question Q2. |
| Status | `qspi_board` outputs `ready` (= `ext_en`) and `bist_fail` (quasi-static; `qspi_port_cdc` synchronises them with 2 flip-flops). `bist_pass` / `bist_fail` keep driving LED5 / LED6. |
| CDC block | `qspi_port_cdc`: dual-clock CoreFIFOs for the request (client → QSPI), write data (client → QSPI), read data + `tlast` (QSPI → client) and response (QSPI → client) streams, plus `ready` / `bist_fail` synchronisers. `rd_space` comes from the read data FIFO's write-side count and `wr_avail` from the write data FIFO's read-side count. Both are in the `clk_ctrl` domain and conservative, because the other side's updates arrive late. |
| CoreFIFO configs | Two new configurations, each used for several FIFOs: `QSPI_CTL_FIFO` (dual clock, 49 bit × 16, for requests and responses; responses use the low bits) and `QSPI_DATA_FIFO` (dual clock, 9 bit × 2048 = one LSRAM, with write-side and read-side counts, for read data `{tlast, byte}` and write data). FWFT, active-high WE/RE, sync reset per side, like `BLOCK_FIFO_CORE`. Verify the exact count port names and latency in the configurator before writing the wrapper. |
| CPU port | `qspi_axil_regs` on the 125 MHz FIC0 clock, a second target of CoreAXI4Interconnect at `0x6000_1000 – 0x6000_1FFF`. Client side: the `qspi_port_cdc` client streams. Register map below. Data moves 4 bytes per 32-bit register access. This is for control and moderate amounts of data, not for the 200 µs read path. |
| Fabric port | Port 1's `qspi_port_cdc` client side, exposed in TOP on the 125 MHz clock. First user: a small test client (Step 6). Open question Q3. |

### CPU register map (`qspi_axil_regs`, base `0x6000_1000`, proposal)

| Offset | Name | Access | Description |
|---|---|---|---|
| 0x00 | ID | RO | Fixed value, e.g. `0x95F1_0001` |
| 0x04 | STATUS | RO | bit 0 `ready`, bit 1 `bist_fail`, bit 2 request FIFO full, bit 3 response available |
| 0x08 | ADDR | R/W | Host byte address |
| 0x0C | LEN | R/W | Length in host bytes (even, > 0) |
| 0x10 | CMD | WO | Write pushes `{wr = bit 0, LEN, ADDR}` as one request. 0 = read, 1 = write |
| 0x14 | RSP | RO | Reading pops one response: bit 31 valid, bit 1 `wr`, bit 0 `err`. Reads `0` when there is none |
| 0x18 | WDATA | WO | Pushes 4 bytes, byte 0 = bits 7:0 (sent first) |
| 0x1C | WDATA16 | WO | Pushes 2 bytes (bits 15:0), for lengths that are 2 mod 4 |
| 0x20 | RDATA | RO | Pops up to 4 bytes, byte 0 = bits 7:0. Fewer at the end of a request (`tlast`) |
| 0x24 | LEVELS | RO | bits 15:0 read bytes available, bits 31:16 free write bytes |

Pop-on-read registers (RSP, RDATA) are safe because the FIC0 region is I/O memory (no speculative or cached reads). Software sequence for a write: push data, then write ADDR, LEN, CMD = 1, then poll RSP. For a read: ADDR, LEN, CMD = 0, pop RDATA until LEN bytes, then RSP.

## Open questions (answer before the step that needs them)

- **Q1 (Step 2):** Round robin, or fixed priority for the fabric port? With round robin, a CPU read of up to 2 KB can delay a fabric read by ≈ 41 µs at 50 MHz SCLK, which matters for the 200 µs budget.
- **Q2 (Step 1):** Keep the BIST area at host `0x0000_0000 – 0x0001_FFFF`, or move it, e.g. to the end of the memory (the `BASE_ADDR` generic, exposed on `qspi_board`)? On the MRAM, any client data in that area is overwritten at every power-up.
- **Q3 (Step 6):** What is the real fabric client? Its clock domain and how it consumes the data (e.g. into `spi_tx_path` blocks) decide the TOP wiring after the test client.

## Steps

### Step 1 — BIST area and `qspi_board` generics
- Expose `BASE_ADDR` (and `BLK_STRIDE` if useful) as integer generics on `qspi_board` (HDL+ configurator handles integers only). Set it according to Q2.
- Add a function in `qspi_pkg` that returns the BIST area for given `NBLK`, `BLK_LEN`, `BLK_STRIDE` and `BASE_ADDR`, for use by the mux check. `tb_qspi_pkg` checks it.
- README: document the reserved area.
- **Done when:** tests pass, and the user has updated the HDL+ core and checked the `generic map` in `TOP.vhd`.

### Step 2 — `qspi_host_mux` (`clk_ctrl`, pure RTL)
- Ports: BIST side (as today), controller side, two client ports (`pN_req_*` 49 bit, `pN_wr_*` 8 bit, `pN_rd_*` 8 bit + `tlast`, `pN_rsp_*` 2 bit, `pN_rd_space`, `pN_wr_avail`), `ready`.
- Handover, round robin (or Q1), route FIFO, per-port credit, store and forward, response generation, BIST-area and length checks, as in Design decisions.
- `sim/tb_qspi_host_mux.vhd` against `qspi_mram_ctrl` + the W25Q128JV / AS308G208 models (BIST included, short `NBLK` / `BLK_LEN`):
  - client requests before the BIST pass are held and run after it
  - nothing is accepted after a BIST fail
  - concurrent reads and writes from both ports, with all data checked and each response matched to its request
  - a slow port 0 reader must not stall port 1 reads beyond its own request, and the read FIFOs must never overflow
  - a write is not forwarded before all its data is there
  - errors (odd address, too long, BIST area) give an `err` response and no data
  - `sample_dly_ovr` keeps the calibrated value after the handover
- **Done when:** the testbench passes and `syn_check` is clean.

### Step 3 — `qspi_board` with client ports
- Put `qspi_host_mux` between `qspi_bist` and `qspi_mram_ctrl`, and bring both client ports and `ready` out. Generics for the port FIFO depths.
- Extend `tb_qspi_board`: after `bist_pass`, port 1 writes and reads a block outside the BIST area at pin level, and the model sees no protocol errors.
- The user updates the HDL+ core and the instance in SmartDesign (new ports, client ports left unconnected / tied off for now) and does Generate Component.
- **Done when:** tests pass, the generated `TOP.vhd` shows the new ports, and synthesis, place and route and timing still pass in Libero.

### Step 4 — `qspi_port_cdc` with CoreFIFOs
- The user creates `QSPI_CTL_FIFO` and `QSPI_DATA_FIFO` in the CoreFIFO configurator (instructions from Claude). Claude checks the `.cxf` values and the `_manifest.txt`.
- `hdl/qspi_port_cdc.vhd`: four FIFOs, `rd_space` / `wr_avail` from the counts, and 2-FF synchronisers for `ready` / `bist_fail`. Client-side ports use the same names as the `qspi_board` ports, so a client can switch between direct and CDC connection.
- `sim/tb_qspi_port_cdc.vhd` (`-- run_tb cores: QSPI_CTL_FIFO QSPI_DATA_FIFO`), with 100 MHz and 125 MHz clocks:
  - streams pass through intact in both directions
  - `rd_space` never overstates the real free space
  - `wr_avail` never overstates the bytes present
  - resets on both sides
- CLAUDE.md: add the two CoreFIFO configs (like the `BLOCK_FIFO_CORE` note).
- **Done when:** the testbench passes and `syn_check` is clean (with the core sources).

### Step 5 — CPU port: `qspi_axil_regs` and TOP
- `hdl/qspi_axil_regs.vhd` (structure like `axi_led_reg`), register map as above.
- `sim/tb_qspi_axil_regs.vhd`:
  - AXI-Lite master BFM through `qspi_port_cdc` → `qspi_board` → model
  - write/read of a block via the registers, lengths of 4n and 4n + 2
  - RSP and LEVELS behaviour, ID, STATUS before and after `ready`
  - slow `BREADY` / `RREADY`
- TOP (user, with instructions):
  - a second interconnect target at `0x6000_1000`
  - `qspi_axil_regs` + `qspi_port_cdc` (port 0) wiring
  - Derive Constraints if needed, then check that the existing asynchronous clock groups cover the FIFO crossings
- **Done when:** the tests pass, Libero passes synthesis, place and route and timing, and the user has programmed the board.

### Step 6 — Fabric port in TOP and a test client
- `qspi_board` port 1 through a second `qspi_port_cdc` to the 125 MHz side.
- `hdl/qspi_fabric_test.vhd`, a simple fabric client:
  - on a trigger (an `axi_led_reg` bit or SWITCH2), it reads N blocks from an address range written by the CPU
  - it checks them against a known pattern
  - it reports pass, fail and the measured read time in `qspi_axil_regs`-readable status, or on an LED
- Test with `sim/tb_qspi_fabric_test.vhd`. Then decide on the real client (Q3).
- **Done when:** tests pass, timing passes, and on the board the fabric test passes after a CPU write.

### Step 7 — Bare-metal driver and on-board test
- `softconsole/led_test/src/application/hart0/qspi.c` / `qspi.h`: `qspi_wait_ready()`, `qspi_write(addr, buf, len)`, `qspi_read(addr, buf, len)`, response and error handling, timeouts.
- `e51.c`:
  - wait for `ready`
  - write a pattern outside the BIST area, read it back, compare
  - try a write into the BIST area, which must give an error
  - print the results on the UART
  - trigger the fabric test from Step 6 on the CPU-written data
- README: CPU usage section, register map. Copy the MSS XML again only if the MSS config changed (it shouldn't).
- **Done when:** the UART log shows all checks passing on the board (W25Q128JV breakout), recorded in `documentation/bringup.md`.

## Status

| Step | Status |
|---|---|
| 1 — BIST area and `qspi_board` generics | open |
| 2 — `qspi_host_mux` | open |
| 3 — `qspi_board` with client ports | open |
| 4 — `qspi_port_cdc` with CoreFIFOs | open |
| 5 — CPU port: `qspi_axil_regs` and TOP | open |
| 6 — Fabric port in TOP and a test client | open |
| 7 — Bare-metal driver and on-board test | open |
