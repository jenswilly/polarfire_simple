# polarfire_simple

A minimal PolarFire SoC test project for the **PolarFire SoC Discovery Kit** (MPFS095T-1FCSG325E). It uses Libero SoC 2026.1 for the FPGA design and SoftConsole for the bare-metal software.

It drives three LEDs:

| LED  | Source                                   | Pin  |
|------|------------------------------------------|------|
| LED1 | Push-button SWITCH1 (inverted), pure fabric | T18 |
| LED2 | MSS register write via FIC0 AXI → bit 0     | V17 |
| LED3 | MSS register write via FIC0 AXI → bit 1     | U20 |
| LED4–7 | Tied low (off)                          | U21, AA18, V16, U15 |

## Design overview

```
REF_CLK_50MHz ─ CLKINT ─ PF_CCC (125 MHz) ─┬─ MSS FIC_0_ACLK
                                           ├─ CoreAXI4Interconnect ACLK
                                           └─ axi_led_reg ACLK
INIT_MONITOR + CORERESET_PF  (EXT_RST_N = MSS_RESET_N_M2F & FIC_0_DLL_LOCK_M2F)
        └─ FABRIC_RESET_N ─> interconnect / axi_led_reg ARESETN

MSS FIC_0 AXI4 initiator (64-bit) ─> CoreAXI4Interconnect v3 (I0 AXI4 64b → T0 AXI4-Lite 32b)
                                   ─> axi_led_reg (VHDL) ─> LED2, LED3
MSS MMUART_0 (via fabric) ─> UART0_TX (Y21) / UART0_RX (W21) ─> on-board FTDI
SWITCH1 (T19) ─ INV ─> LED1
```

### Register map (`axi_led_reg`, base `0x6000_0000`)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x0 | LED  | R/W | bit 0 = LED2, bit 1 = LED3 |
| 0x4 | ID   | RO  | `0x1ED50001` (sanity check for AXI reads) |
| 0x8 | DEBUG | WO | Writing bit 0 = 1 drives `DEBUG_PULSE` high for exactly one ACLK cycle. Writing 0 does nothing. Reads return 0. |

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
                      pulse_stretch.vhd    Stretches a short pulse to 1 us (for the DEBUG pin)
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
- `polarfire_simple.prjx` links `hdl/axi_led_reg.vhd` and `constraints/io.pdc`. Re-link those two files.
- `designer/TOP/ENVM.cfg` points the eNVM client at `led_test-bm1-p0.hex`. Select the hex again in the eNVM client.

## Simulation

Testbenches live in `sim/` and are self-checking. Run one from the command line with Libero's QuestaSim:

```bash
sim/run_tb.sh tb_axi_led_reg
```

The script compiles `hdl/*.vhd` and the testbench (VHDL-2008) into `sim/out/` (git-ignored). The testbench prints `TB PASSED` or `TB FAILED: <n> error(s)`, and the script exits with 0 or 1 accordingly. QuestaSim needs the license server, which `tools/start_libero.sh` starts. To look at the waveforms afterwards:

```bash
/usr/local/microchip/Libero_SoC_2026.1/Libero_SoC/QuestaSim_Pro/linux_x86_64/vsim -view sim/out/tb_axi_led_reg.wlf
```

The same testbench also runs from Libero. It is linked as a stimulus file and associated with `TOP` (Design Flow → **Create Design → Verify Pre-Synthesized Design → Simulate**, right-click → **Organize Input Files → Organize Stimulus Files**). Project Settings → Simulation Options has testbench module `tb_axi_led_reg` and top-level instance `dut`. Right-click that Simulate → **Open Interactively** to get the QuestaSim GUI with waveforms. The log is `polarfire_simple/simulation/tb_axi_led_reg_presynth_simulation.log`. Use only the pre-synthesis Simulate: the post-synthesis and post-layout netlists flatten `axi_led_reg` into `TOP`, so this testbench can't run there.

`tb_axi_led_reg` checks the ID register, the LED register (write and readback) and `DEBUG_PULSE`: exactly one cycle per write of 1, even with a slow `BREADY`, no pulse when writing 0 or writing to the LED register, and DEBUG reads as 0.

`tb_button_debounce` uses `DEBOUNCE_CYCLES = 20` and asynchronous button edges. It checks: short glitches are ignored, both when released and when pressed; a bouncy press gives exactly one single-cycle pulse, exactly `DEBOUNCE_CYCLES + 2` clock edges after the last bounce; holding and releasing give no pulse; and holding the button through a reset gives one pulse after the reset.

`tb_pulse_stretch` uses the default `STRETCH_CYCLES = 125`. It checks: a single-cycle input gives exactly 1 µs high, starting one clock later; a retrigger 50 cycles in merges into one pulse of 50 + 125 cycles; a 3-cycle input stays high until 125 cycles after its last cycle; and reset clears the output.

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
