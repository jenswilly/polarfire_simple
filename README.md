# polarfire_simple

A minimal PolarFire SoC test project for the **PolarFire SoC Discovery Kit** (MPFS095T-1FCSG325E). It uses Libero SoC 2026.1 for the FPGA design and SoftConsole for the bare-metal software.

Outputs:

| Output | Source | Pin |
|--------|--------|-----|
| LED1 | Push-button SWITCH1 (inverted), pure fabric | T18 |
| LED2 | MSS register write via FIC0 AXI → bit 0 | V17 |
| LED3 | MSS register write via FIC0 AXI → bit 1 | U20 |
| LED4 | SWITCH2, debounced (on while pressed) | U21 |
| LED5–7 | Tied low (off) | AA18, V16, U15 |
| DEBUG | 1 ms pulse per SWITCH2 press or write to DEBUG (`0x6000_0008`) | E13, RPi header pin 40 (GPIO21) |
| SPI SCLK | `spi_tx_path` | B19, RPi header pin 35 (GPIO19) |
| SPI MOSI | `spi_tx_path` | B15, RPi header pin 36 (GPIO16) |
| SPI CS_N | `spi_tx_path` | B17, RPi header pin 37 (GPIO26) |
| (unused) | Tied low | B14, RPi header pin 38 (GPIO20) |

The RPi header pins are in Bank1 (3.3 V). GPIO numbers are BCM numbers; the pin numbers are the physical header pins.

## Design overview

Block diagram of `TOP`: `documentation/top_level.drawio` (open it with draw.io or the VS Code Draw.io extension). Everything in the fabric runs on the 125 MHz `PF_CCC_C0` clock with `FABRIC_RESET_N` from `CORERESET_PF`. The MSS FIC_0 AXI4 initiator reaches `axi_led_reg` through CoreAXI4Interconnect (AXI4 64 b → AXI4-Lite 32 b). SWITCH2 is debounced to LED4, and its press pulse is OR'd with `axi_led_reg`'s `DEBUG_PULSE`; that pulse drives both the 1 ms `pulse_stretch` → DEBUG and two `test_block_producer`s → `block_arbiter` → `spi_tx_path` → SPI.

### SPI TX path
`spi_tx_path` takes 80-bit blocks (valid/ready) and sends each one as one SPI frame: one CS_N assertion, 10 bytes, most significant byte and bit first (bit 79 is the first bit on MOSI). Mode 0 (CPOL 0, CPHA 0), `CLK_DIV = 7` so SCLK = 125 MHz / 14 ≈ 8.93 MHz. Inside, `block_fifo` (CoreFIFO `BLOCK_FIFO_CORE`, 80 bit × 512, FWFT) buffers up to 512 blocks, `block_serializer` turns a block into 10 AXI4-Stream bytes, and `axis_spi_wo_master` shifts them out. The serializer holds a whole block, so a frame never pauses mid-way. Block diagram: `documentation/spi_tx_path.drawio`.

Several producers share `spi_tx_path` through `block_arbiter` (in TOP, in front of `spi_tx_path`). It is round-robin and moves one whole block per handshake, so blocks from different producers never interleave. Only the selected producer sees `s_ready`; the others hold their block. The mux is combinational (no extra latency), and once a block is offered the selection is held until it is taken. SmartDesign has no array ports, so the inputs are flattened: producer *i* is `s_data((i+1)*80-1 downto i*80)`, `s_valid(i)`, `s_ready(i)`.

For now the blocks come from two `test_block_producer` instances (HDL+ cores, so the generics are set per instance) on `block_arbiter`. Each pulse from SWITCH2 or a write to DEBUG makes each of them send one block `<id> <seq> 02 03 04 05 06 07 08 09`, where `<id>` is the `FIRST_BYTE` generic (`F0` for `test_block_producer_0`, `AA` for `test_block_producer_1`) and `<seq>` counts that producer's blocks since reset. So every pulse gives two SPI frames, `F0 <seq> …` first, then `AA <seq> …`.

### Register map (`axi_led_reg`, base `0x6000_0000`)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x0 | LED  | R/W | bit 0 = LED2, bit 1 = LED3 |
| 0x4 | ID   | RO  | `0x1ED50001` (sanity check for AXI reads) |
| 0x8 | DEBUG | WO | Writing bit 0 = 1 drives `DEBUG_PULSE` high for exactly one ACLK cycle. In TOP that gives a 1 ms pulse on DEBUG and sends one test block over SPI, the same as a SWITCH2 press. Writing 0 does nothing. Reads return 0. |

The interconnect decodes `0x6000_0000 – 0x6000_0FFF`, which is in the FIC0 low (32-bit) window.

### MSS configuration (`mss/MSS_simple.cfg`)
- Reference clock 125 MHz, CPU clock 600 MHz, AXI clock 300 MHz, AHB/APB clock 150 MHz.
- DDR4, x16, 1 GB, 800 MHz (DDR4-1600), CL12. Timings are copied from Microchip's Discovery Kit reference design.
- L2 cache split: LIM 4 ways, scratchpad 4 ways. The scratchpad is needed by the HSS.
- MMUART_0 is routed to the fabric. FIC_0 AXI4 initiator is enabled. All other peripherals and FICs are off.

## Repository layout

```
mss/                MSS Configurator source (.cfg) and generated .cxz/.xml
hdl/                Hand-written VHDL, linked into Libero:
                      axi_led_reg.vhd      AXI4-Lite LED register + debug pulse
                      button_debounce.vhd  Push-button debouncer with single-clock press pulse
                      pulse_stretch.vhd    Stretches a short pulse (1 ms in TOP, for the DEBUG pin)
                      axis_spi_master.vhd  AXI4-Stream SPI master, full duplex, fixed 10-byte frames (not used; kept for later)
                      axis_spi_wo_master.vhd  Write-only version of axis_spi_master (no MISO/RX path)
                      block_fifo.vhd       valid/ready wrapper around the CoreFIFO BLOCK_FIFO_CORE (80 bit x 512)
                      block_serializer.vhd 80-bit block -> 10 AXI4-Stream bytes, MSB byte first, tlast on the last
                      spi_tx_path.vhd      block_fifo + block_serializer + axis_spi_wo_master: 80-bit blocks in, SPI frames out
                      block_arbiter.vhd    Round-robin arbiter: NUM_PORTS block producers -> one block consumer
                      test_block_producer.vhd  Test source for spi_tx_path: N blocks (<id> <seq> 02..09) per start pulse
                      util_pkg.vhd         Shared helpers: clog2, reverse (byte bit order), ns_to_cycles
                      qspi_pkg.vhd         QSPI controller (PLAN.md): device_t, opcodes, per-device parameters
                      qspi_phy.vhd         QSPI PHY: phase descriptors -> SCLK/CS#/IO pins, delayed RX sampling
                      qspi_xact.vhd        QSPI transaction engine: command + AXI4-Stream TX/RX -> qspi_phy
                      qspi_init.vhd        QSPI memory init: reset, ID check, configuration, quad-path check
                      qspi_read_ctrl.vhd   QSPI read requests {len, addr} -> EBh commands, credit-based flow control
                      qspi_write.vhd       QSPI write requests (test/calibration): W25Q erase + page program, AS D2h
                      qspi_mram_ctrl.vhd   QSPI controller top: init + read + write + arbiter + qspi_xact/qspi_phy
                      qspi_bist.vhd        Built-in self-test for qspi_mram_ctrl: write once, read/compare forever, pass/fail
                      qspi_board.vhd       qspi_mram_ctrl + qspi_bist + tristate pads, single die (HDL+ core in TOP)
documentation/      Board and memory datasheet PDFs (Git LFS) and draw.io diagrams: top_level.drawio (TOP), spi_tx_path.drawio (SPI TX path),
                      qspi_controller.drawio (planned QSPI controller, see PLAN.md); device_facts.md (QSPI memory facts with datasheet references)
constraints/io.pdc  Pin and bank constraints (linked into Libero)
constraints/qspi_ioreg.ndc  I/O register combining (set_ioff) for the QSPI pins (linked into Libero)
sim/                Testbenches (tb_*.vhd) and run_tb.sh to run them in QuestaSim
  models/           Simulation-only models: qspi_mem_model.vhd (one W25Q128JV / AS308G208 die),
                    qspi_model_pkg.vhd (sparse memory, preload pattern)
polarfire_simple/   Libero project (.prjx + component configs + designer/TOP/ENVM.cfg); build output is git-ignored
softconsole/        SoftConsole workspace
  led_test/         Bare-metal app (based on Microchip's mpfs-blank-baremetal template)
tools/              Libero license-server start/stop scripts (see tools/README.md), syn_check.sh (batch Synplify check),
                    and the udev rule for the board's UARTs
```

## Building

1. Start Libero with `tools/start_libero.sh`, which starts the FlexLM license server first if it isn't running (one-time setup in `tools/README.md`). Open `polarfire_simple/polarfire_simple.prjx`.
2. If the MSS config changed, regenerate it with the MSS Configurator (`pfsoc_mss`) into `mss/`, then re-import it with **File → Import → MSS**.
3. In Design Flow, run Synthesize → Place and Route → Verify Timing → Generate Bitstream → Run PROGRAM Action. The board's embedded FlashPro5 is used for programming.

**Fresh clone:** the bitstream includes the eNVM boot image (see [Standalone boot](#standalone-boot-from-envm-boot-mode-1)), and that hex is build output, so it isn't in git. Build the `Discovery-Kit-eNVM-Scratchpad-Release` configuration in SoftConsole first. Otherwise Generate Design Initialization Data / Generate Bitstream fails on the missing file.

The project uses **absolute paths** (`/home/jenswilly/Projs/polarfire_simple/...`) in two places. If you clone the repository somewhere else, fix both:
- `polarfire_simple.prjx` links all files in the `hdl/` folder, the testbenches in `sim/` and `constraints/io.pdc`. Re-link them, or search and replace the path in the `.prjx` while Libero is closed.
- `designer/TOP/ENVM.cfg` points the eNVM client at `led_test-bm1-p0.hex`. Select the hex again in the eNVM client.

## Simulation

Testbenches live in `sim/` and are self-checking. Run one from the command line with Libero's QuestaSim:

```bash
sim/run_tb.sh tb_axi_led_reg
```

The script rebuilds the work library in `sim/out/` (git-ignored) and compiles (VHDL-2008) `hdl/*_pkg.vhd` first, then the other `hdl/*.vhd` files, any models named in a `-- run_tb models: <name>` header line (from `sim/models/<name>.vhd`) and the testbench. Files are compiled in dependency order: a file that fails because a unit it uses isn't compiled yet is retried after the others. The testbench prints `TB PASSED` or `TB FAILED: <n> error(s)`, and the script exits with 0 or 1 accordingly. Any further arguments go to `vsim`, so generics can be overridden, e.g. `sim/run_tb.sh tb_axis_spi_master -gCPOL_I=1 -gCPHA_I=1`. QuestaSim needs the license server, which `tools/start_libero.sh` starts. To look at the waveforms afterwards:

```bash
/usr/local/microchip/Libero_SoC_2026.1/Libero_SoC/QuestaSim_Pro/linux_x86_64/vsim -view sim/out/tb_axi_led_reg.wlf
```

`tb_axi_led_reg` also runs from Libero. The testbenches `tb_axi_led_reg`, `tb_axis_spi_master`, `tb_button_debounce` and `tb_pulse_stretch` are linked into the project as stimulus files; the others run from the command line only. To link a testbench, use Files → stimulus → **Link Files**. A linked file does *not* show up under Files → stimulus, but it is listed in the Stimulus Hierarchy under Work and under User HDL Stimulus Files. `tb_axi_led_reg` is the one associated with `TOP` (Design Flow → **Create Design → Verify Pre-Synthesized Design → Simulate**, right-click → **Organize Input Files → Organize Stimulus Files**). Project Settings → Simulation Options has testbench module `tb_axi_led_reg` and top-level instance `dut`. Right-click that Simulate → **Open Interactively** to get the QuestaSim GUI with waveforms. The log is `polarfire_simple/simulation/tb_axi_led_reg_presynth_simulation.log`. Use only the pre-synthesis Simulate: the post-synthesis and post-layout netlists flatten `axi_led_reg` into `TOP`, so this testbench can't run there.

`tb_axi_led_reg` checks the ID register, the LED register (write and readback) and `DEBUG_PULSE`: exactly one cycle per write of 1, even with a slow `BREADY`, no pulse when writing 0 or writing to the LED register, and DEBUG reads as 0.

`tb_button_debounce` uses `DEBOUNCE_CYCLES = 20` and asynchronous button edges. It checks: short glitches are ignored, both when released and when pressed; a bouncy press gives exactly one single-cycle pulse, exactly `DEBOUNCE_CYCLES + 2` clock edges after the last bounce; holding and releasing give no pulse; and holding the button through a reset gives one pulse after the reset.

`tb_pulse_stretch` sets `STRETCH_CYCLES = 125` (1 µs) instead of the design default of 125 000 (1 ms), to keep the simulation short. It checks: a single-cycle input gives exactly 1 µs high, starting one clock later; a retrigger 50 cycles in merges into one pulse of 50 + 125 cycles; a 3-cycle input stays high until 125 cycles after its last cycle; and reset clears the output.

`tb_axis_spi_master` defaults to the design settings (10-byte frames, `CLK_DIV = 7`, 125 MHz); integer generics (`CPOL_I`, `CPHA_I`, `MSB_I`, `RX_I`, `FRAME_BYTES`, `CLK_DIV`, `MISO_SYNC_I`, `STALLS`) select other modes. A behavioural SPI slave checks every MOSI byte, drives a known MISO sequence and checks that every CS_N assertion has exactly `FRAME_BYTES * 8` bits with SCLK idle at both CS_N edges. A timing monitor checks the SCLK half-periods and the CS_N setup/hold/idle times. The RX side is checked for data and `tlast` under random stalls plus long `m_axis_tready` stalls (overrun check). The last frame has a wrong `s_axis_tlast` and must give `frame_err_out` pulses, and a reset mid-byte must return the DUT to idle.

`tb_axis_spi_wo_master` is `tb_axis_spi_master` without the RX parts: the same SPI slave (MOSI only), timing monitor, bad-`tlast` frame and mid-byte reset, with the same `CPOL_I`/`CPHA_I`/`MSB_I`/`FRAME_BYTES`/`CLK_DIV`/`STALLS` generics.

`tb_block_fifo` runs against the generated CoreFIFO RTL (`-- run_tb cores: BLOCK_FIFO_CORE`). It checks: the capacity is 512 blocks; FWFT shows a block on `m_data` with `m_valid` (5 clocks after the write) without a read and holds it while `m_ready` is low; 3000 blocks with random stalls on both sides arrive in order with all 80 bits; one block per clock with both sides always ready; a reset with blocks in the FIFO empties it.

`tb_block_serializer` checks every byte (most significant first) and `tlast` under random stalls on both sides, that `m_axis` stays stable while stalled, a throughput of `BLOCK_BYTES + 1` clocks per block, and a reset mid-block. `-gBLOCK_BYTES=<n>` selects other block sizes.

`tb_spi_tx_path` tests the whole path at the SPI pins (`-- run_tb cores: BLOCK_FIFO_CORE`). A behavioural SPI slave turns every CS_N assertion into an 80-bit word (first bit = bit 79) and checks it against the written blocks, so order, content, bit order and framing are checked together. 40 blocks with random gaps let the FIFO run empty; 600 back-to-back blocks overfill it, so `s_ready` must go low and every block must still arrive. `frame_err_out` must never pulse, and a reset with blocks in the FIFO and a frame in progress must leave the path idle. `CPOL_I`, `CPHA_I`, `CLK_DIV`, `NSPARSE` and `NBURST` can be overridden.

`tb_block_arbiter` uses `NUM_PORTS = 3` (override with `-gNUM_PORTS=<n>`). Producers with random gaps offer numbered blocks and a consumer with random `m_ready` takes them. It checks: at most one `s_ready` is high, and only for a valid producer; every handshake on `m_*` is exactly one handshake on `s_*` with that producer's block; every block of every producer arrives once and in order; `m_*` stays stable while stalled; with all producers valid they are served in turn; after a reset port 0 goes first.

`tb_qspi_phy` feeds a table of transactions (Read ID, an EBh read with mode byte and dummy cycles, a quad write, odd lengths, SPI1 latency, 1-cycle phases) to the PHY in 10 runs: SCLK divider 1 and 2 × sample delay 1–4, one run with gaps between descriptors, and one run whose device delay doesn't match the sample delay and must return wrong data. A pin-level device stub checks at every SCLK edge: the CS#/SCLK timing (first edge, exact high/low times, number of cycles per CS#, CS# high only after the last delayed sample, CS# high time), the TX bit order in SPI1 and QUAD4, and the OE pattern (IO2/IO3 high in SPI1, released in QUAD4 RX/dummy). It drives RX data a round-trip delay after each launching falling edge, and every RX word and `rx_last` is compared. A monitor checks that SCLK toggles only while CS# is low, that CS# and OE change only while SCLK is low, that OE doesn't change while CS# is high (after a quad read the device may still be driving), and that `sclk(1)`/`cs_n(1)` follow `sclk(0)`/`cs_n(0)`. `-gDIE2_I=0` runs it with `DIE2_PRESENT = false` (IO7:4 undriven, their RX nibble 0). A 1 ms watchdog ends a hung run with `TB FAILED`.

`tb_qspi_board` runs `qspi_board` with a W25Q128JV model directly on its `qspi_io` pins (datasheet power-up time, calibration on, 2 blocks of 64 host bytes) and checks that `bist_pass` comes on and stays on and that the model sees no protocol errors. It covers the tristate wiring and the generic mapping.

`tb_qspi_bist` runs `qspi_bist` + `qspi_mram_ctrl` against the models in five configurations (4 blocks of 880 host bytes): W25Q128JV without calibration (pass); W25Q128JV with calibration and a board delay where sample delays 1 and 2 work (window `0011`, picks 1, pass); AS308G208 with 2 dies, calibration, `SAMPLE_DLY` = 1 and a board delay where only 2 works (init fails with 1 and is retried, window `0010`, pass); AS308G208 with a model that ignores array writes (fail); AS308G208 with a wrong ID (all init retries fail, fail). It checks that `pass` only comes on after a complete round, that `pass` and `fail` are never on together, that passing configurations keep passing (`pass_count` ≥ 3) and that `fail` stays latched.

`tb_qspi_mram_ctrl` is the full-system test of `qspi_mram_ctrl` for the W25Q128JV and the AS308G208 with 1 and 2 dies: init, then 8 blocks of 880 host bytes written (with a read requested during the first write, which must wait for it, and a write requested while a read is still delivering data, which must not cut the read short), then the 8 blocks read back to back (144.5 µs on the W25Q128JV, 145.5 µs on the AS308G208). The `SAMPLE_DLY` generic is set to 3, which doesn't fit the 3 ns board delay: the test runs with `sample_dly_ovr = 2`, and one read without the override must return wrong data. Finally `init_restart`: requests during the rerun give `rd_req_err`/`wr_req_err`, and a read after it works. All data is checked against the written data, erased flash or the preload, and the models must report no protocol errors.

`tb_qspi_write` runs `qspi_write` and `qspi_read_ctrl` on one shared `qspi_xact` (the testbench switches the command port between them) against preloaded models for the W25Q128JV and the AS308G208 with 1 and 2 dies. Requests before `init_done` and bad requests give `req_err` and write nothing. It writes 880 host bytes (on the W25Q128JV across a sector boundary and three pages), reads them back, checks on the W25Q128JV that the rest of both erased sectors reads FFh, writes an overlapping 64-byte block and reads the whole area back, and on the AS308G208 checks that the bytes around the block still hold the preload. With one die, the upper nibble of each written byte must be ignored. The models must report no protocol errors (WEL/WREN, BUSY, CS# high times, byte boundaries).

`tb_qspi_read_ctrl` runs `qspi_read_ctrl` + `qspi_xact` against preloaded models for the W25Q128JV and the AS308G208 with 1 and 2 dies (`init_done` driven by the testbench). It checks that requests before `init_done` and bad requests (odd address or length, length 0, past the end of the device) give `req_err` and no data; reads 8 non-contiguous blocks of 880 host bytes and reports the time (144.5 µs on the W25Q128JV, 145.5 µs on the AS308G208; the check allows 140.8–150 µs); and repeats reads into a 1000-byte downstream buffer drained at a quarter of the read rate, where requests must wait for space (including bytes of earlier requests still in flight) and the buffer must never overflow. Every byte and `tlast` is compared with the preload pattern.

`tb_qspi_init` runs `qspi_init` + `qspi_xact` against the models in eight configurations side by side: W25Q128JV normal / QE = 0 / wrong ID, AS308G208 with one die (CR2 and SR at non-default values after reset, so init's writes must fix them), two dies normal, two dies where die 2 ignores register writes or has a wrong ID, and one die that ignores writes. Each must end in `init_done`, `ERR_ID` or `ERR_CFG` as expected, both after reset and after `init_restart`. The models must report no protocol errors (power-up and reset recovery times, CS# high times, 9Fh/05h at ≤ 40 MHz on the AS308G208); RESET# must stay high for the W25Q128JV and be pulsed once per run for the AS308G208.

`tb_qspi_xact` runs `qspi_xact` (with `qspi_phy`) against the device models in three configurations side by side: W25Q128JV, one AS308G208 die, two AS308G208 dies (die 2 with its own preload and ID), at SCLK 50 MHz, sample delay 2 and 3 ns board delay. It covers device ID (per die), status/register reads, RDAR/WRAR, EBh reads with latency 8 and 10 and across the end of the die, W25Q sector erase with BUSY polling, quad and 1-1-1 page programs (including the page wrap and ignored upper nibbles with one die), AS D2h/02h writes spanning several TX chunks, and two queued reads (880 + 20 host bytes). Every stream byte, the nibble order `{die2, die1}`, the die order of 1-line bytes and `tlast` are checked; the models must report no protocol errors and `rx_overflow` must never pulse.

`tb_qspi_mem_model` tests the device model (`-- run_tb models: qspi_model_pkg qspi_mem_model`) with one model per device, each driven by a bit-banged SPI host. W25Q128JV: reset, JEDEC ID, the three status registers, EBh reads of erased flash, WREN/WEL, sector erase with BUSY polling, a quad page program that wraps inside the page, and a 1-1-1 program that ANDs into the array. AS308G208: RESET#, ID and status at 25 MHz, register reads with RDAR, EBh reads of the preloaded pattern with latency 8 and 10 (CR2 set with WRAR), the wrap at the end of the die, D2h and 02h writes, WREN cleared after writes. It then injects protocol violations (program/write without WREN, command while BUSY, continuous-read mode byte, XIP byte, CS# high too short, partial-byte program, 9Fh at 50 MHz, address outside the die, command during tPU, bus contention) and checks that the model's `err_count` goes up by exactly one for each. The model reports those as `** Error` lines, so the transcript shows errors even when the testbench passes.

`tb_util_pkg` has no DUT; it calls the `util_pkg` functions. It checks `clog2` (including 0 and 1), `reverse` for all 256 byte values, and `ns_to_cycles` at 100 MHz and 50 MHz (exact values and rounding up).

`tb_qspi_pkg` has no DUT either. It checks the `qspi_pkg` device parameters (the timings the controller converts with `ns_to_cycles` at 100 MHz, address widths), the EBh overhead per device (20 and 26 clocks), and `id_ok` (W25Q128JV `EF 40 18`; AS308G208 with 4 Gb and 8 Gb density codes; wrong IDs rejected).

`tb_test_block_producer` uses `BLOCKS_PER_PRESS = 3` and `FIRST_BYTE = C3` (override with `-gBLOCKS_PER_PRESS=<n>` / `-gFIRST_BYTE=<n>`) and a consumer with random `m_ready`. It checks: each start pulse gives exactly `BLOCKS_PER_PRESS` blocks with the right content; `m_data`/`m_valid` stay stable while stalled; a start pulse during a burst is ignored; the sequence number continues across bursts and wraps from FF to 00; and a reset during a burst stops it and restarts the sequence.

### Synthesis check (Synplify batch)

`tools/syn_check.sh <top> <config> [GENERIC=value ...]` runs Synplify Pro in batch on hand-written HDL in `sim/out/syn/<config>/`, outside the Libero project (target MPFS095T FCSG325 -1, VHDL-2008, no I/O insertion). By default it takes `hdl/util_pkg.vhd`, `hdl/qspi_pkg.vhd` and `hdl/qspi_*.vhd`. It prints errors, latches, multiple drivers and combinational loops, plus the resource summary, and exits with 1 if it found any. Example:

```bash
tools/syn_check.sh qspi_mram_ctrl w25
tools/syn_check.sh qspi_mram_ctrl as2 DEVICE=DEV_AS308G208 DIE2_PRESENT=true
```

`qspi_mram_ctrl` is about 1.5k LUTs and 700 (W25Q128JV) / 815 (AS308G208, 2 dies) flip-flops.

## Software (SoftConsole)

1. **Fresh clone only:** `softconsole/.metadata/` is git-ignored. Without it, SoftConsole refuses the folder ("is not an empty folder or a SoftConsole workspace"), because it accepts only an empty folder or one with `.metadata/softconsole.xml`. Create it from SoftConsole's own empty-workspace template:
   ```bash
   SC=~/Microchip/SoftConsole-v2022.2-RISC-V-747
   unzip -q $SC/extras/workspace.empty.zip 'workspace.empty/.metadata/*' -d /tmp/sc-ws
   cp -r /tmp/sc-ws/workspace.empty/.metadata softconsole/ && rm -r /tmp/sc-ws
   ```
2. Start SoftConsole with the workspace `softconsole/`. Import `softconsole/led_test` with **File → Import → Existing Projects into Workspace**, leaving "copy" unticked.
3. Set the active build configuration to **`Discovery-Kit-LIM-Debug`** and build. The pre-build step generates `fpga_design_config/` from the MSS XML in `src/boards/mpfs-discovery-kit/fpga_design/design_description/`. Copy `mss/MSS_simple_mss_cfg.xml` there again after any MSS change.
4. Debug with **`led_test hw all-harts debug`** (GDB OpenOCD Debugging). It loads the program into L2 LIM over JTAG and stops in `e51()`. Then resume.

The E51 prints a banner and the ID register on MMUART0, then counts 0–3 on LED2/LED3.

### Serial console (Linux)
The console is MMUART0, routed through the fabric to FT4232H channel D (interface 3), at 115200 8N1.

By default Linux binds only interface 2 of the board's USB device (`1514:2008`), so only `/dev/ttyUSB0` appears, and that isn't our UART. To enable the other channels:
```bash
echo 1514 2008 | sudo tee /sys/bus/usb-serial/drivers/ftdi_sio/new_id
screen /dev/serial/by-id/usb-Microsemi_Embedded_FlashPro5_*-if03-port0 115200
```
To make this permanent, install the udev rule in `tools/`. It binds all interfaces, leaves interface 0 (JTAG) free, and creates `/dev/pfsoc-uart0`:
```bash
sudo cp tools/99-pfsoc-discovery-uart.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules   # then replug the board
screen /dev/pfsoc-uart0 115200
```
`/dev/pfsoc-uart0` belongs to group `dialout`, so your user needs to be in that group.

### Standalone boot from eNVM (boot mode 1)
The board runs `led_test` on its own at power-up. The program is stored in eNVM, copied to the L2 scratchpad and run from there.

1. In SoftConsole, build the **`Discovery-Kit-eNVM-Scratchpad-Release`** configuration. A post-build step runs Microchip's `mpfsBootmodeProgrammer.jar --bootmode 1 --dryrun`, which creates `Discovery-Kit-eNVM-Scratchpad-Release/bootmode1/led_test-bm1-p0.hex`: a dummy SBIC page at `0x2022_0000` followed by the program at `0x2022_0100`.
2. In Libero, open **Configure Design Initialization Data and Memories → eNVM**. The Boot Mode 1 client (`BOOT_MODE_1_ENVM_CLIENT`) points at that hex, with base address `0x20220000`. Its settings are saved in `polarfire_simple/designer/TOP/ENVM.cfg`.
3. Run Generate Design Initialization Data → Generate Bitstream → Run PROGRAM Action, then power-cycle the board.

Use the `-bm1-p0.hex`, not the plain `led_test.hex`. Libero rejects the plain file because its data starts at `0x2022_0100`.

After a software change, rebuild, then edit the eNVM client and select the hex again. The client stores a fixed byte count (`-number_of_bytes`), so a larger program isn't picked up automatically. Then regenerate and program.

For development, keep using `Discovery-Kit-LIM-Debug` with `led_test hw all-harts debug`. The JTAG reset and halt overrides the eNVM program until the next power cycle.

## Status / next steps
- [x] FPGA design built and programmed. SWITCH1 → LED1 works.
- [x] Bare-metal app (LIM debug): AXI reads and writes to `0x6000_0000` work, LED2/LED3 count, UART output works.
- [x] Standalone boot from eNVM (boot mode 1): everything works after a power cycle, without a PC.
- [x] SWITCH2 debounce → LED4 works.
- [ ] DEBUG pulse (1 ms) on RPi header pin 40: check on the scope.
- [x] SPI TX path: simulated (`tb_spi_tx_path`, `tb_block_arbiter`), and checked on header pins 35–37 with a logic analyser: each press gives two frames (`F0 <seq> …`, `AA <seq> …`) with the counter incrementing.
- [ ] Software: write blocks to the SPI TX path from the MSS instead of the `test_block_producer`s (as a `block_arbiter` port).
