# polarfire_simple

A minimal PolarFire SoC test project for the **PolarFire SoC Discovery Kit** (MPFS095T-1FCSG325E). It uses Libero SoC 2026.1 for the FPGA design and SoftConsole for the bare-metal software.

Outputs:

| Output | Source | Pin |
|--------|--------|-----|
| LED1 | Tied low (off) | T18 |
| LED2 | MSS register write via FIC0 AXI → bit 0 | V17 |
| LED3 | MSS register write via FIC0 AXI → bit 1 | U20 |
| LED4 | SWITCH2, debounced (on while pressed) | U21 |
| LED5 | QSPI BIST pass (`qspi_board`) | AA18 |
| LED6 | QSPI BIST fail (`qspi_board`) | V16 |
| LED7 | Tied low (off) | U15 |
| DEBUG | 1 ms pulse per SWITCH2 press or write to DEBUG (`0x6000_0008`) | E13, RPi header pin 40 (GPIO21) |
| SPI SCLK | `spi_tx_path` | B19, RPi header pin 35 (GPIO19) |
| SPI MOSI | `spi_tx_path` | B15, RPi header pin 36 (GPIO16) |
| SPI CS_N | `spi_tx_path` | B17, RPi header pin 37 (GPIO26) |
| SPI busy | `spi_tx_path` | B14, RPi header pin 38 (GPIO20) |
| QSPI SCLK | `qspi_board` | G18, RPi header pin 11 (GPIO17), yellow wire |
| QSPI CS# | `qspi_board`, pull-up | F21, RPi header pin 13 (GPIO27), orange wire |
| QSPI IO0 | `qspi_board` | F20, RPi header pin 15 (GPIO22), green wire |
| QSPI IO1 | `qspi_board` | E21, RPi header pin 16 (GPIO23), gray wire |
| QSPI IO2 | `qspi_board`, pull-ups | F19, RPi header pin 18 (GPIO24), purple wire |
| QSPI IO3 | `qspi_board`, pull-ups | A19, RPi header pin 22 (GPIO25), blue wire |
| QSPI VCC | 3.3 V | RPi header pin 17, red wire |
| QSPI GND | GND | RPi header pin 9, brown wire |
| Boot flash SCLK | MSS QSPI via `mss_qspi_pads` | E17, mikroBUS SCK |
| Boot flash CS# | MSS QSPI via `mss_qspi_pads`, pull-up | C16, mikroBUS CS |
| Boot flash IO0/IO1 | MSS QSPI via `mss_qspi_pads` | E11 (MOSI), A18 (MISO) |
| Boot flash IO2/IO3 | MSS QSPI via `mss_qspi_pads` | D13 (PWM), G17 (INT) |


The RPi header pins are in Bank1 (3.3 V). The QSPI breakout (W25Q128JV) gets 3.3 V from header pin 17 and GND from pin 9. GPIO numbers are BCM numbers; the pin numbers are the physical header pins.

The boot flash is a MikroE Flash 6 Click (W25Q128JV) in the mikroBUS socket (also Bank1). It holds the RTEMS boot image for the HSS (see "Boot from QSPI flash"). It is separate from the RPi-header breakout, which `qspi_board` tests.

## Design overview

Block diagram of `TOP`: `documentation/top_level.drawio` (open it with draw.io or the VS Code Draw.io extension). Everything in the fabric, including `qspi_board` and the MSS FIC_0, runs on one clock: the 200 MHz `PF_CCC_C0` output OUT0, with `FABRIC_RESET_N` from `CORERESET_0`. The MSS FIC_0 AXI4 initiator reaches `axi_sys_ctrl` through CoreAXI4Interconnect (AXI4 64 b → AXI4-Lite 32 b). SWITCH2 is debounced to LED4, and its press pulse is OR'd with `axi_sys_ctrl`'s `DEBUG_PULSE`; that pulse drives both the 1 ms `pulse_stretch` → DEBUG and two `test_block_producer`s → `block_arbiter` → `spi_tx_path` → SPI. The MSS QSPI controller is routed through the fabric: `mss_qspi_pads` (tristate buffers that follow the MSS output enables, no clock) connects it to the mikroBUS pins of the boot flash.

### SPI TX path
`spi_tx_path` takes 80-bit blocks (valid/ready) and sends each one as one SPI frame: one CS_N assertion, 10 bytes, most significant byte and bit first (bit 79 is the first bit on MOSI). Mode 0 (CPOL 0, CPHA 0), `CLK_DIV = 5` so SCLK = 200 MHz / 10 = 20 MHz. Inside, `block_fifo` (CoreFIFO `BLOCK_FIFO_CORE`, 80 bit × 512, FWFT) buffers up to 512 blocks, `block_serializer` turns a block into 10 AXI4-Stream bytes, and `axis_spi_wo_master` shifts them out. The serializer holds a whole block, so a frame never pauses mid-way. Block diagram: `documentation/spi_tx_path.drawio`.

Several producers share `spi_tx_path` through `block_arbiter` (in TOP, in front of `spi_tx_path`). It is round-robin and moves one whole block per handshake, so blocks from different producers never interleave. Only the selected producer sees `s_ready`; the others hold their block. The mux is combinational (no extra latency), and once a block is offered the selection is held until it is taken. SmartDesign has no array ports, so the inputs are flattened: producer *i* is `s_data((i+1)*80-1 downto i*80)`, `s_valid(i)`, `s_ready(i)`.

For now the blocks come from two `test_block_producer` instances (HDL+ cores, so the generics are set per instance) on `block_arbiter`. Each pulse from SWITCH2 or a write to DEBUG makes each of them send one block `<id> <seq> 02 03 04 05 06 07 08 09`, where `<id>` is the `FIRST_BYTE` generic (`F0` for `test_block_producer_0`, `AA` for `test_block_producer_1`) and `<seq>` counts that producer's blocks since reset. So every pulse gives two SPI frames, `F0 <seq> …` first, then `AA <seq> …`.

### QSPI controller and BIST
`qspi_board` (HDL+ core) contains `qspi_mram_ctrl` (the QSPI controller for the W25Q128JV prototype and, later, a single port of the AS308G208 MRAM) and `qspi_bist`. After reset the BIST initialises the memory, writes a test pattern once, calibrates the RX sample delay and then reads and compares 8 × 880 bytes once and stops: LED5 = pass, LED6 = fail (the `LOOP_ROUNDS` generic of `qspi_bist` repeats the read rounds until reset). SCLK is 50 MHz, reads are 1-4-4 (EBh). The SCLK/CS# output registers and the IO3:0 input registers are packed into the I/O cells (`constraints/qspi_ioreg.ndc`). Block diagram: `documentation/qspi_controller.drawio`; device facts: `documentation/device_facts.md`; timing: `documentation/timing_budget.md`; bring-up on the breakout: `documentation/bringup.md`.

Design decisions:
- **Devices.** Final: one port (die: CS1#, CLK1, IO3:0) of the Avalanche AS308G208 MRAM; the other port is connected to the MSS. Prototype: Winbond W25Q128JVSSIQ. Selected with the `DEVICE` generic (`device_t` in `qspi_pkg`). The controller is single-die only: each quad SCLK cycle moves one nibble on IO3:0, so a byte takes two cycles, high nibble first.
- **Protocol.** SDR, SPI mode 0. Reads are EBh 1-4-4 on both devices (the W25Q has no QPI mode). Writes are only for tests and calibration: W25Q 20h sector erase + 32h page program with BUSY polling; AS D2h.
- **Clocking.** `clk_ctrl` is the 200 MHz fabric clock (`PF_CCC_C0` OUT0, `CORERESET_0`), the same as the rest of the fabric and FIC_0, so the read stream can go to the MSS without a clock crossing. SCLK = `clk_ctrl` / (2 × `SCLK_DIV`) = 50 MHz with `SCLK_DIV` = 2 (range 1–8). RX data is sampled `SAMPLE_DLY` `clk_ctrl` cycles (5 ns steps, range 1–8) after the SCLK falling edge, 4 by default; the BIST can calibrate it at run time.
- **Interface.** Read requests `{len, addr}` in device bytes (any address, `len` ≥ 1, no wrap past the end of the device). A read starts only when the credit `rd_space` covers it, so SCLK never stalls. Data out is AXI4-Stream, 8 bit, `tlast` per request.
- **Read time / LUT preload.** Each byte takes 2 SCLK cycles, so reads run at 25 MB/s at 50 MHz SCLK; 8 × 880 bytes take ≈ 286 µs (14240 / 14288 SCLK cycles for W25Q / AS; `tb_qspi_read_ctrl` measures 285.1 / 286.0 µs). There is no per-iteration read-time requirement: the calibration LUT is loaded once after init (and again after LUT updates) into RAM in each Slice Controller, 46,080 bits (5,760 bytes) per Slice Controller, 22 × 5,760 = 126,720 bytes in total. That takes ≈ 5.1 ms at 50 MHz (253,440 data clocks plus 26 per EBh request). Each read request must fit the downstream credit (`rd_space`) and is at most 65,535 bytes, so the load is split into several requests, e.g. one per Slice Controller.

Remaining work for the AS308G208 board (on hold until the target PCB exists):
1. RESET#: `qspi_board` has no RESET# port, so with the AS308G208 it must be tied high on the board (or `mem_reset_n` brought out; `PLAN_SC_FLASH.md` step 5 makes the pulse optional in `qspi_init`).

### Register map (`axi_sys_ctrl`, base `0x6000_0000`)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x0 | LED  | R/W | bit 0 = LED2, bit 1 = LED3 |
| 0x4 | ID   | RO  | `0x1ED50001` (sanity check for AXI reads) |
| 0x8 | DEBUG | WO | Writing bit 0 = 1 drives `DEBUG_PULSE` high for exactly one ACLK cycle. In TOP that gives a 1 ms pulse on DEBUG and sends one test block over SPI, the same as a SWITCH2 press. Writing 0 does nothing. Reads return 0. |

The interconnect decodes `0x6000_0000 – 0x6000_0FFF`, which is in the FIC0 low (32-bit) window. The registers are 32 bits wide, but the AXI4-Lite data bus is 64 bits, the width of FIC_0 and the crossbar, so the interconnect needs no data width converter. Its 64→32-bit DownConverter failed timing at 200 MHz. Software uses 32-bit accesses.

### MSS configuration (`mss/MSS_simple.cfg`)
- Reference clock 125 MHz, CPU clock 600 MHz, AXI clock 300 MHz, AHB/APB clock 150 MHz.
- DDR4, x16, 1 GB, 800 MHz (DDR4-1600), CL12. Timings are copied from Microchip's Discovery Kit reference design.
- L2 cache split: LIM 4 ways, scratchpad 4 ways. The scratchpad is needed by the HSS.
- MMUART_0 is routed to the fabric (FTDI channel D). FIC_0 AXI4 initiator is enabled.
- QSPI and QSPI clock are routed to the fabric (`QSPI = FABRIC`, `QSPI_CLK = FABRIC`), DATA 3:2 = Unused. The configurator requires Unused in fabric mode; all four data lines still reach the fabric (`QSPI_DATA_M2F/_OE_M2F/_F2M[3:0]`).
- For the HSS (as in Microchip's reference design): MMUART_1 and MMUART_4 on MSSIO_B2 (FTDI channels B and C), SD card on MSSIO_B4 (`SD_PORTS_DISABLE`, `SD_VOLT_SEL_IS_INVERTED` = true, SDR104). Their pads are top-level ports of TOP.
- All other peripherals and FICs are off.

### Timing Constants

Several components have generics that need to be adjusted when clock frequency change:

* button_debounce.vhd: `DEBOUNCE_CYCLES`
* spi_tx_path.vdh: `CLK_DIV`
* pulse_stretch_0 HDL+ component: `STRETCH_CYCLES`
* qspi_board_0 HDL+ component: `CLK_HZ` and `SCLK_DIV`

## Repository layout

```
mss/                MSS Configurator source (.cfg) and generated .cxz/.xml
hdl/                Hand-written VHDL, linked into Libero:
                      axi_sys_ctrl.vhd     AXI4-Lite system control registers: LEDs, ID, debug pulse
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
                      qspi_pkg.vhd         QSPI controller: device_t, opcodes, per-device parameters
                      qspi_phy.vhd         QSPI PHY: phase descriptors -> SCLK/CS#/IO pins, delayed RX sampling
                      qspi_xact.vhd        QSPI transaction engine: command + AXI4-Stream TX/RX -> qspi_phy
                      qspi_init.vhd        QSPI memory init: reset, ID check, configuration, quad-path check
                      qspi_read_ctrl.vhd   QSPI read requests {len, addr} -> EBh commands, credit-based flow control
                      qspi_write.vhd       QSPI write requests (test/calibration): W25Q erase + page program, AS D2h
                      qspi_mram_ctrl.vhd   QSPI controller top: init + read + write + arbiter + qspi_xact/qspi_phy
                      qspi_bist.vhd        Built-in self-test for qspi_mram_ctrl: write once, read/compare (once or looped), pass/fail
                      qspi_board.vhd       qspi_mram_ctrl + qspi_bist + tristate pads, single die (HDL+ core in TOP)
                      mss_qspi_pads.vhd    Tristate pads for the MSS QSPI (fabric mode) -> mikroBUS boot flash
documentation/      Board and memory datasheet PDFs (Git LFS; incl. the Flash 6 Click schematic) and draw.io diagrams: top_level.drawio (TOP), spi_tx_path.drawio (SPI TX path),
                      qspi_controller.drawio (QSPI controller); device_facts.md (QSPI memory facts with datasheet references); timing_budget.md (QSPI I/O timing budget behind timing.sdc); bringup.md (QSPI hardware bring-up log)
constraints/io.pdc  Pin and bank constraints (linked into Libero)
constraints/qspi_ioreg.ndc  I/O register combining (set_ioff) for the QSPI pins (linked into Libero)
constraints/timing.sdc      QSPI timing (SCLK generated clock, I/O delays), clock groups (linked, after the derived SDC)
sim/                Testbenches (tb_*.vhd) and run_tb.sh to run them in QuestaSim
  models/           Simulation-only models: qspi_mem_model.vhd (one W25Q128JV / AS308G208 die),
                    qspi_model_pkg.vhd (sparse memory, preload pattern)
polarfire_simple/   Libero project (.prjx + component configs + designer/TOP/ENVM.cfg); build output is git-ignored
softconsole/        SoftConsole workspace
  led_test/         Bare-metal app (based on Microchip's mpfs-blank-baremetal template)
hss/                HSS (Hart Software Services) build: build_hss.sh (devcontainer), make_envm_hex.sh, config_overrides,
                    drivers/ (W25Q128JV QSPI driver) and patches/ (applied to the HSS source by build_hss.sh)
rtems/              RTEMS 6.2: config.ini (BSP options), dts/ (Discovery Kit device tree), rtems-cmake (submodule),
                    led_test/ (RTEMS version of the LED test, CMake), write_sd.sh (boot image -> microSD),
                    write_qspi.sh (boot image -> QSPI flash via the HSS YMODEM utility)
.devcontainer/      RTEMS toolchain, BSP build, HSS source and xPack GCC
tools/              Libero license-server start/stop scripts (see tools/README.md), syn_check.sh (batch Synplify check),
                    the udev rule for the board's UARTs, openocd_mpfs.sh (GDB server), mss_reset.sh (MSS reset over JTAG)
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
sim/run_tb.sh tb_axi_sys_ctrl
```

The script rebuilds the work library in `sim/out/` (git-ignored) and compiles (VHDL-2008) `hdl/*_pkg.vhd` first, then the other `hdl/*.vhd` files, any models named in a `-- run_tb models: <name>` header line (from `sim/models/<name>.vhd`) and the testbench. Files are compiled in dependency order: a file that fails because a unit it uses isn't compiled yet is retried after the others. The testbench prints `TB PASSED` or `TB FAILED: <n> error(s)`, and the script exits with 0 or 1 accordingly. Any further arguments go to `vsim`, so generics can be overridden, e.g. `sim/run_tb.sh tb_axis_spi_master -gCPOL_I=1 -gCPHA_I=1`. QuestaSim needs the license server, which `tools/start_libero.sh` starts. To look at the waveforms afterwards:

```bash
/usr/local/microchip/Libero_SoC_2026.1/Libero_SoC/QuestaSim_Pro/linux_x86_64/vsim -view sim/out/tb_axi_sys_ctrl.wlf
```

`tb_axi_sys_ctrl` also runs from Libero. The testbenches `tb_axi_sys_ctrl`, `tb_axis_spi_master`, `tb_button_debounce` and `tb_pulse_stretch` are linked into the project as stimulus files; the others run from the command line only. To link a testbench, use Files → stimulus → **Link Files**. A linked file does *not* show up under Files → stimulus, but it is listed in the Stimulus Hierarchy under Work and under User HDL Stimulus Files. `tb_axi_sys_ctrl` is the one associated with `TOP` (Design Flow → **Create Design → Verify Pre-Synthesized Design → Simulate**, right-click → **Organize Input Files → Organize Stimulus Files**). Project Settings → Simulation Options has testbench module `tb_axi_sys_ctrl` and top-level instance `dut`. Right-click that Simulate → **Open Interactively** to get the QuestaSim GUI with waveforms. The log is `polarfire_simple/simulation/tb_axi_sys_ctrl_presynth_simulation.log`. Use only the pre-synthesis Simulate: the post-synthesis and post-layout netlists flatten `axi_sys_ctrl` into `TOP`, so this testbench can't run there.

`tb_axi_sys_ctrl` checks the ID register, the LED register (write and readback) and `DEBUG_PULSE`: exactly one cycle per write of 1, even with a slow `BREADY`, no pulse when writing 0 or writing to the LED register, and DEBUG reads as 0. Every access puts junk in the other half of the 64-bit bus, to check that only the addressed lane is used and that both read lanes match.

`tb_button_debounce` uses `DEBOUNCE_CYCLES = 20` and asynchronous button edges. It checks: short glitches are ignored, both when released and when pressed; a bouncy press gives exactly one single-cycle pulse, exactly `DEBOUNCE_CYCLES + 2` clock edges after the last bounce; holding and releasing give no pulse; and holding the button through a reset gives one pulse after the reset.

`tb_pulse_stretch` sets `STRETCH_CYCLES = 200` (1 µs at 200 MHz) instead of the design default of 200 000 (1 ms), to keep the simulation short. It checks: a single-cycle input gives exactly 1 µs high, starting one clock later; a retrigger 50 cycles in merges into one pulse of 50 + 200 cycles; a 3-cycle input stays high until 200 cycles after its last cycle; and reset clears the output.

`tb_axis_spi_master` defaults to 10-byte frames, `CLK_DIV = 7` and the 200 MHz fabric clock; integer generics (`CPOL_I`, `CPHA_I`, `MSB_I`, `RX_I`, `FRAME_BYTES`, `CLK_DIV`, `MISO_SYNC_I`, `STALLS`) select other modes. A behavioural SPI slave checks every MOSI byte, drives a known MISO sequence and checks that every CS_N assertion has exactly `FRAME_BYTES * 8` bits with SCLK idle at both CS_N edges. A timing monitor checks the SCLK half-periods and the CS_N setup/hold/idle times. The RX side is checked for data and `tlast` under random stalls plus long `m_axis_tready` stalls (overrun check). The last frame has a wrong `s_axis_tlast` and must give `frame_err_out` pulses, and a reset mid-byte must return the DUT to idle.

`tb_axis_spi_wo_master` is `tb_axis_spi_master` without the RX parts: the same SPI slave (MOSI only), timing monitor and mid-byte reset, with the same `CPOL_I`/`CPHA_I`/`MSB_I`/`FRAME_BYTES`/`CLK_DIV`/`STALLS` generics (`CLK_DIV` defaults to the design's 5).

`tb_block_fifo` runs against the generated CoreFIFO RTL (`-- run_tb cores: BLOCK_FIFO_CORE`). It checks: the capacity is 512 blocks; FWFT shows a block on `m_data` with `m_valid` (5 clocks after the write) without a read and holds it while `m_ready` is low; 3000 blocks with random stalls on both sides arrive in order with all 80 bits; one block per clock with both sides always ready; a reset with blocks in the FIFO empties it.

`tb_block_serializer` checks every byte (most significant first) and `tlast` under random stalls on both sides, that `m_axis` stays stable while stalled, a throughput of `BLOCK_BYTES + 1` clocks per block, and a reset mid-block. `-gBLOCK_BYTES=<n>` selects other block sizes.

`tb_spi_tx_path` tests the whole path at the SPI pins (`-- run_tb cores: BLOCK_FIFO_CORE`). A behavioural SPI slave turns every CS_N assertion into an 80-bit word (first bit = bit 79) and checks it against the written blocks, so order, content, bit order and framing are checked together. 40 blocks with random gaps let the FIFO run empty; 600 back-to-back blocks overfill it, so `s_ready` must go low and every block must still arrive. A reset with blocks in the FIFO and a frame in progress must leave the path idle. `CPOL_I`, `CPHA_I`, `CLK_DIV`, `NSPARSE` and `NBURST` can be overridden.

`tb_block_arbiter` uses `NUM_PORTS = 3` (override with `-gNUM_PORTS=<n>`). Producers with random gaps offer numbered blocks and a consumer with random `m_ready` takes them. It checks: at most one `s_ready` is high, and only for a valid producer; every handshake on `m_*` is exactly one handshake on `s_*` with that producer's block; every block of every producer arrives once and in order; `m_*` stays stable while stalled; with all producers valid they are served in turn; after a reset port 0 goes first.

`tb_qspi_phy` feeds a table of transactions (Read ID, an EBh read with mode byte and dummy cycles, a quad write, odd lengths, SPI1 latency, 1-cycle phases) to the PHY in 15 runs at 200 MHz: SCLK dividers 1–8 with sample delays 1–8 (including the design point, divider 2 with delay 4), one run with gaps between descriptors, and one run whose device delay doesn't match the sample delay and must return wrong data. A pin-level device stub checks at every SCLK edge: the CS#/SCLK timing (first edge, exact high/low times, number of cycles per CS#, CS# high exactly one clock after the last falling edge or the last delayed sample, whichever is later, CS# high time), the TX bit order in SPI1 and QUAD4, and the OE pattern (IO2/IO3 high in SPI1, released in QUAD4 RX/dummy). It drives RX data a round-trip delay after each launching falling edge, and every RX word and `rx_last` is compared. A monitor checks that SCLK toggles only while CS# is low, that CS# and OE change only while SCLK is low, and that OE doesn't change while CS# is high (after a quad read the device may still be driving). A 1 ms watchdog ends a hung run with `TB FAILED`.

`tb_qspi_board` runs `qspi_board` with a W25Q128JV model directly on its `qspi_io` pins (datasheet power-up time, calibration on, 2 blocks of 63 bytes) and checks that `bist_pass` comes on and stays on and that the model sees no protocol errors. It covers the tristate wiring and the generic mapping.

`tb_qspi_bist` runs `qspi_bist` + `qspi_mram_ctrl` against the models in five configurations (4 blocks of 880 bytes, `clk_ctrl` 200 MHz, SCLK 50 MHz): W25Q128JV without calibration (pass); W25Q128JV with calibration and a board delay where sample delays 2–4 work (window `00001110`, picks 3, pass, one round only); AS308G208 with calibration, `SAMPLE_DLY` = 1 and a board delay where 4 and 5 work (init fails with 1–3 and is retried up to 4, window `00011000`, picks 4, pass); AS308G208 with a model that ignores array writes (fail); AS308G208 with a wrong ID (all init retries fail, fail). It checks that `pass` only comes on after a complete round, that `pass` and `fail` are never on together, that passing configurations with `LOOP_ROUNDS` keep passing (`pass_count` ≥ 3), that without it the BIST stops after one round (no further read requests, `pass` stays on), that `fail` stays latched, and that the sample delay override only changes while the controller is idle (and the PHY is still idle one cycle later).

`tb_qspi_mram_ctrl` is the full-system test of `qspi_mram_ctrl` for the W25Q128JV and the AS308G208 (one port/die): init, then 8 blocks of 880 bytes written (with a read requested during the first write, which must wait for it, and a write requested while a read is still delivering data, which must not cut the read short), then the 8 blocks read back to back (285.1 µs on the W25Q128JV, 286.0 µs on the AS308G208) and an odd-length read at an odd address. The `SAMPLE_DLY` generic is set to 6 (30 ns), which doesn't fit the 3 ns board delay: the test runs with `sample_dly_ovr = 4`, and one read without the override must return wrong data. Finally `init_restart`: requests during the rerun give `rd_req_err`/`wr_req_err`, and a read after it works. All data is checked against the written data, erased flash or the preload, and the models must report no protocol errors.

`tb_qspi_write` runs `qspi_write` and `qspi_read_ctrl` on one shared `qspi_xact` (the testbench switches the command port between them) against preloaded models for the W25Q128JV and the AS308G208 (one port/die). Requests before `init_done` and bad requests give `req_err` and write nothing. It writes 880 bytes at an odd address (on the W25Q128JV across a sector boundary and four pages), reads them back, checks on the W25Q128JV that the rest of both erased sectors reads FFh, writes an overlapping 63-byte block and reads the whole area back, and on the AS308G208 checks that the bytes around the block still hold the preload. The models must report no protocol errors (WEL/WREN, BUSY, CS# high times, byte boundaries).

`tb_qspi_read_ctrl` runs `qspi_read_ctrl` + `qspi_xact` against preloaded models for the W25Q128JV and the AS308G208 (one port/die; `init_done` driven by the testbench). It checks that requests before `init_done` and bad requests (length 0, past the end of the device, starting at the end) give `req_err` and no data; reads 8 non-contiguous blocks of 880 bytes and reports the time (285.1 µs on the W25Q128JV, 286.0 µs on the AS308G208; the check allows 281.6–292 µs); and repeats reads (one with an odd address and length ending at the device end) into a 1000-byte downstream buffer drained at half the read rate, where requests must wait for space (including bytes of earlier requests still in flight) and the buffer must never overflow. Every byte and `tlast` is compared with the preload pattern.

`tb_qspi_init` runs `qspi_init` + `qspi_xact` against the models in eight configurations side by side: W25Q128JV normal / QE = 0 / wrong ID; AS308G208 (one port/die) with CR2 = 10 and SR protected after reset, and with CR2 = 12 (init's writes must fix them), with a 1 Gb ID, and ignoring register writes (with CR2 = 10, and with SR protected). Each must end in `init_done`, `ERR_ID` or `ERR_CFG` as expected, both after reset and after `init_restart`. The models must report no protocol errors (power-up and reset recovery times, CS# high times, 9Fh/05h at ≤ 40 MHz on the AS308G208); RESET# must stay high for the W25Q128JV and be pulsed once per run for the AS308G208.

`tb_qspi_xact` runs `qspi_xact` (with `qspi_phy`) against the device models in two configurations side by side: W25Q128JV and one AS308G208 port/die, at `clk_ctrl` 200 MHz, SCLK 50 MHz (33 MHz for the AS 9Fh), sample delay 4 and 3 ns board delay. It covers device ID, status/register reads, RDAR/WRAR, EBh reads with latency 8 and 10, of odd lengths and across the end of the die, W25Q sector erase with BUSY polling, quad and 1-1-1 page programs (including the page wrap), AS D2h (7 bytes) / 02h writes spanning several TX chunks, and two queued reads (880 + 21 bytes). Every stream byte (two nibbles, high nibble first) and `tlast` are checked; the models must report no protocol errors and `rx_overflow` must never pulse.

`tb_qspi_mem_model` tests the device model (`-- run_tb models: qspi_model_pkg qspi_mem_model`) with one model per device, each driven by a bit-banged SPI host. W25Q128JV: reset, JEDEC ID, the three status registers, EBh reads of erased flash, WREN/WEL, sector erase with BUSY polling, a quad page program that wraps inside the page, and a 1-1-1 program that ANDs into the array. AS308G208: RESET#, ID and status at 25 MHz, register reads with RDAR, EBh reads of the preloaded pattern with latency 8 and 10 (CR2 set with WRAR), the wrap at the end of the die, D2h and 02h writes, WREN cleared after writes. It then injects protocol violations (program/write without WREN, command while BUSY, continuous-read mode byte, XIP byte, CS# high too short, partial-byte program, 9Fh at 50 MHz, address outside the die, command during tPU, bus contention) and checks that the model's `err_count` goes up by exactly one for each. The model reports those as `** Error` lines, so the transcript shows errors even when the testbench passes.

`tb_util_pkg` has no DUT; it calls the `util_pkg` functions. It checks `clog2` (including 0 and 1), `reverse` for all 256 byte values, and `ns_to_cycles` at 100 MHz and 50 MHz (exact values and rounding up).

`tb_qspi_pkg` has no DUT either. It checks the `qspi_pkg` device parameters (the timings the controller converts with `ns_to_cycles` at 200 MHz and that they fit the `qspi_xact`/`qspi_init` counters, address widths), the EBh overhead per device (20 and 26 clocks), and `id_ok` (W25Q128JV `EF 40 18`; AS308G208 with 4 Gb and 8 Gb density codes; wrong IDs rejected).

`tb_test_block_producer` uses `BLOCKS_PER_PRESS = 3` and `FIRST_BYTE = C3` (override with `-gBLOCKS_PER_PRESS=<n>` / `-gFIRST_BYTE=<n>`) and a consumer with random `m_ready`. It checks: each start pulse gives exactly `BLOCKS_PER_PRESS` blocks with the right content; `m_data`/`m_valid` stay stable while stalled; a start pulse during a burst is ignored; the sequence number continues across bursts and wraps from FF to 00; and a reset during a burst stops it and restarts the sequence.

### Synthesis check (Synplify batch)

`tools/syn_check.sh <top> <config> [GENERIC=value ...]` runs Synplify Pro in batch on hand-written HDL in `sim/out/syn/<config>/`, outside the Libero project (target MPFS095T FCSG325 -1 at 200 MHz, `FREQ=<MHz>` to change, VHDL-2008, no I/O insertion). By default it takes `hdl/util_pkg.vhd`, `hdl/qspi_pkg.vhd` and `hdl/qspi_*.vhd`; after `--`, other `hdl/` files by name. It prints errors, latches, multiple drivers and combinational loops, plus the resource summary and Synplify's estimated clock frequency (a pre-P&R estimate), and exits with 1 if it found any. Example:

```bash
tools/syn_check.sh qspi_mram_ctrl w25
tools/syn_check.sh qspi_mram_ctrl as DEVICE=DEV_AS308G208
tools/syn_check.sh block_serializer bs -- util_pkg block_serializer
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

## RTEMS on U54_1 (HSS boot)
The HSS runs on the E51 from eNVM. It sets up clocks and DDR, loads the RTEMS image from the QSPI boot flash or the microSD card into DDR and starts it on U54_1 in machine mode (no OpenSBI). This replaces `led_test` in eNVM.

UARTs (udev rule in `tools/`): HSS console on `/dev/pfsoc-uart1` (MMUART1), RTEMS console on `/dev/pfsoc-uart0` (MMUART0), all 115200 8N1.

1. **Devcontainer:** the image builds the RTEMS 6.2 toolchain and contains the HSS source and xPack GCC. `postCreateCommand` builds and installs the BSP `riscv/mpfs64imafdc` with `rtems/config.ini` and the device tree `rtems/dts/mpfs-discovery-kit.dts` (console MMUART0, 896 MB DDR at `0x10_0000_0000`). Run `.devcontainer/scripts/post_configuration.sh` again after changing either. The host's SoftConsole and `/usr/local/microchip` (Libero) are mounted read-only at their host paths, with `SC_INSTALL_DIR` and `FPGENPROG` set, so OpenOCD and `mpfsBootmodeProgrammer`/`fpgenprog` also run in the container. These need no license. The Libero license server stays on the host.
2. **HSS** (after every MSS change): `hss/build_hss.sh` in the devcontainer. It also runs `hss/make_envm_hex.sh`, which can run on the host too. Use `hss/build/bootmode1/hss-envm-wrapper-bm1-p0.hex` as the Libero Boot Mode 1 eNVM client (see above) and program.
3. **Application** (devcontainer):
   ```bash
   cd rtems/led_test
   cmake --preset mpfs
   cmake --build --preset mpfs
   ```
   This builds `led_test.elf` and the HSS boot image `payload.bin` (`rtems/led_test/hss-payload.yaml`) in `rtems/led_test/build/`. The preset (`rtems/led_test/CMakePresets.json`) sets Ninja, the build directory, `RTEMS_PREFIX` and `RTEMS_BSP`. In VS Code, CMake Tools uses the same preset (`.vscode/settings.json`): select configure preset `mpfs`, then Build.
4. **SD card** (host): `sudo rtems/write_sd.sh /dev/sdX`. It erases the card, creates a GPT with one EF02 partition (the type the HSS looks for) and writes `payload.bin` into it. The image must be smaller than 4 MiB (the HSS staging area at `0x10_3FC0_0000`).

5. **Or QSPI flash** (host): see "Boot from QSPI flash" below.

The HSS zeroes all NOBITS sections of the ELF before it starts it, including the 256 MB RTEMS `.work` area. That costs a moment at every boot but is harmless.

### Boot from QSPI flash

The HSS tries the QSPI flash first and falls back to the SD card if it finds no flash or no valid image (an erased flash reads magic `ffffffff`).

- **Path:** MSS QSPI controller → fabric (`mss_qspi_pads`) → mikroBUS → Flash 6 Click (W25Q128JV, 16 MB). The HSS has no driver for this chip, so `hss/drivers/winbond_w25q128jv/` adds one (same `Flash_*` API as its Micron driver). `hss/patches/0001-qspi-winbond-w25q128jv.patch` selects it (Kconfig, Makefile, flash table) and fixes three bugs in the HSS YMODEM loader (see CLAUDE.md). `build_hss.sh` copies the driver and applies the patch. `config_overrides` turns on `CONFIG_SERVICE_QSPI`.
- **Driver:** commands, program and erase run at 5 MHz SCLK. Reads use Fast Read Quad Output (6Bh, 1-1-4) at 25 MHz. At the first init, the driver reads 1 KB at 5 MHz as a reference and compares it with the 25 MHz read for each MSS sample point (posedge/active/negedge). On the board all three match, so posedge is used. If none matches, or the flash is erased, reads stay at 5 MHz. The HSS only checks the image header CRC, so this check is the only protection against bad fast reads.
- **Writing the image** (host): `rtems/write_qspi.sh [payload.bin]`. Close any terminal on `/dev/pfsoc-uart1` first, and JTAG must be free. The script resets the MSS over JTAG (`tools/mss_reset.sh`) and catches the HSS's 1 s "Press a key to enter CLI" window. It then runs TinyCLI `YMODEM`: erase (about 40 s), receive (`sb -k`, about 11 KB/s at 115200 baud), write, quit. Finally it sends `BOOT` and shows the boot log. `RESET=0` makes it wait for a manual reset instead.
- **Timing (96 KB `led_test`):** the HSS's "Copying 95936 bytes" takes about 13 ms (44 ms with 5 MHz reads).
- **Reset without power cycle:** `tools/mss_reset.sh` writes `0xDEAD` to SYSREG `MSS_RESET_CR` (`0x2000_2018`) over JTAG. This is the same full MSS reset as the HSS reboot; the fabric is not reprogrammed and the FTDI UARTs stay up. The board has no reset button.

### Debugging RTEMS over JTAG

GDB in the devcontainer connects to U54_1 through SoftConsole's OpenOCD. It can attach to the running application, or load a new build into DDR and start it without writing the SD card.

1. **Host or devcontainer:** `tools/openocd_mpfs.sh` (default hart 1 = U54_1; GDB port 3333). It sets `COREID` so OpenOCD has a target for that hart only. The default (`COREID -1`) makes all five harts one SMP target, so a halt would also stop the E51 running the HSS. OpenOCD uses JTAG: stop it (Ctrl-C) before programming in Libero.
2. **Attach** (devcontainer, `--network=host`, so `localhost:3333` reaches OpenOCD wherever it runs). Nothing is loaded or reset: attaching halts U54_1 where it is, and detaching resumes it. The ELF must be the one the board runs.
   - command line, from `rtems/led_test`: `riscv-rtems6-gdb -x attach.gdb build/led_test.elf`
   - VS Code: Run and Debug → "RTEMS led_test: attach U54_1" (`.vscode/launch.json`)
3. **Load and run** a new build without writing the SD card:
   - command line, from `rtems/led_test`: `riscv-rtems6-gdb -x load.gdb build/led_test.elf` loads the ELF into DDR, starts it on U54_1 and stops at `Init` (`continue` runs it)
   - VS Code: "RTEMS led_test: load and run U54_1" builds (task "led_test: build"), loads and runs

   The HSS must have booted first, so DDR is trained. The SD card can hold an older payload: GDB stops it and starts the new build, which runs until the next reset; a reset boots the SD card image again. `_start` sets up `gp`, `mtvec` and `sp` and clears `.bss` itself. GDB only disables interrupts before the jump (`mstatus.MIE`, `mie`), so an interrupt from the old program can't fire before the new `mtvec` is set.

OpenOCD has no RTEMS thread support, so GDB sees only the thread that is running when it halts. The application is built with `-O2`, so stepping jumps around and some variables are `<optimized out>`.

## Status / next steps

- [ ] Convert use of AS308G208 to use one port for FPGA and one for MSS QSPI for storing MSS firmware instead of the current QSPI flash.
