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
documentation/      Board PDFs (Git LFS) and draw.io diagrams: top_level.drawio (TOP), spi_tx_path.drawio (SPI TX path)
constraints/io.pdc  Pin and bank constraints (linked into Libero)
sim/                Testbenches (tb_*.vhd) and run_tb.sh to run them in QuestaSim
polarfire_simple/   Libero project (.prjx + component configs + designer/TOP/ENVM.cfg); build output is git-ignored
softconsole/        SoftConsole workspace
  led_test/         Bare-metal app (based on Microchip's mpfs-blank-baremetal template)
tools/              Libero license-server start/stop scripts (see tools/README.md) and the udev rule for the board's UARTs
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

The script compiles `hdl/*.vhd` and the testbench (VHDL-2008) into `sim/out/` (git-ignored). The testbench prints `TB PASSED` or `TB FAILED: <n> error(s)`, and the script exits with 0 or 1 accordingly. Any further arguments go to `vsim`, so generics can be overridden, e.g. `sim/run_tb.sh tb_axis_spi_master -gCPOL_I=1 -gCPHA_I=1`. QuestaSim needs the license server, which `tools/start_libero.sh` starts. To look at the waveforms afterwards:

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

`tb_test_block_producer` uses `BLOCKS_PER_PRESS = 3` and `FIRST_BYTE = C3` (override with `-gBLOCKS_PER_PRESS=<n>` / `-gFIRST_BYTE=<n>`) and a consumer with random `m_ready`. It checks: each start pulse gives exactly `BLOCKS_PER_PRESS` blocks with the right content; `m_data`/`m_valid` stay stable while stalled; a start pulse during a burst is ignored; the sequence number continues across bursts and wraps from FF to 00; and a reset during a burst stops it and restarts the sequence.

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
