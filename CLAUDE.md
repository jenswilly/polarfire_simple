# CLAUDE.md

Learning project: PolarFire SoC Discovery Kit, Libero SoC 2026.1, and SoftConsole (bare-metal). See README.md for the design overview and register map.

## How we work
- **The user does all GUI work in Libero, the MSS Configurator and SoftConsole.** Claude gives step-by-step instructions and then **verifies by reading the generated files**. Claude does not drive the tools.
  - Project/device settings: `polarfire_simple/polarfire_simple.prjx`
  - MSS: `mss/MSS_simple.cfg`
  - SmartDesign result: `polarfire_simple/component/work/TOP/TOP.vhd`
  - IP configs: `polarfire_simple/component/work/<comp>/<comp>.cxf` (`configurableElement` values)
- HDL is **VHDL** (project is set to VHDL-2008). Do not write Verilog.
  - RTL must stay within what Synplify Pro supports: no `process(all)`, no unconstrained record elements, no generics on packages. Testbenches may use full VHDL-2008.
  - `hdl/` conventions: one entity per file, file name = entity name, header comment describing the block, `clk` + synchronous active-low `reset_n`, valid/ready and AXI4-Stream port naming as in `spi_tx_path` / `block_serializer`.
- **QSPI device facts are never guessed.** Opcodes, registers, latencies and timing come from the datasheets in `documentation/` and are recorded in `documentation/device_facts.md` with a page/table reference. Missing or ambiguous values are `TBD` with a question to the user. `hdl/qspi_pkg.vhd` and `sim/models/` take their values from that file.
- Hand-written sources live outside the Libero folder (`hdl/`, `constraints/`, `mss/`) and are *linked* into the project, not imported.
- Testbenches are in `sim/tb_<entity>.vhd`. They are self-checking and must print `TB PASSED` / `TB FAILED`. Run them with `sim/run_tb.sh tb_<entity> [vsim args, e.g. -gNAME=value]`, which rebuilds the work library, compiles `hdl/*_pkg.vhd` first and then the other `hdl/*.vhd` files in dependency order (failed files are retried), and uses Libero's QuestaSim (needs the license server). Claude can run these directly. Extend the testbench whenever HDL behaviour changes. A testbench that needs a Libero-generated core (e.g. CoreFIFO) names it in a header line `-- run_tb cores: <CORE> ...`; `run_tb.sh` then compiles the sources listed in `component/work/<CORE>/<CORE>_manifest.txt` (Verilog with `vlog -sv`, which COREFIFO.v needs). Simulation-only models live in `sim/models/` and are named in a header line `-- run_tb models: <name> ...` (file name without `.vhd`). vsim always runs with `-t 1ps -L polarfire` (Libero's precompiled PolarFire primitives, e.g. LSRAM/µSRAM).
- **Synthesis check:** `tools/syn_check.sh <top> <config> [GENERIC=value ...]` runs Synplify Pro in batch in `sim/out/syn/` (outside the Libero project; the user agreed). Claude can run it. It reports errors, latches, multiple drivers and combinational loops.
- **Libero simulation setup:** link the testbench as a stimulus file (type `tb_hdl` in the `.prjx`). Associate it via Design Flow → Verify Pre-Synthesized Design → Simulate → right-click → Organize Input Files → Organize Stimulus Files. That writes `LIST AssociatedStimulus` / `LIST TOP`. The Stimulus Hierarchy has **no** "Set as Active Stimulus" in 2026.1, and the Tcl `set_active_testbench "<tb>::work,<path>"` fails ("Cannot find module named …"). The testbench name and instance go in Project Settings → Simulation Options (`EntityName` / `TopInstanceName` in the `.prjx`). Only one testbench can be the Simulation Options testbench at a time, and running simulations can overwrite it: after running other associated testbenches, the `.prjx` had `EntityName=testbench`. Set it again after such runs and check the saved `.prjx`, not just the dialog. Changing only Simulation Options doesn't mark the project as modified, so Save stays disabled; Build Hierarchy (Design Hierarchy) enables it. Link files via Files → stimulus → Link Files; a linked testbench does **not** appear under Files → stimulus, only in the Stimulus Hierarchy (Work, User HDL Stimulus Files). Not every testbench is linked; the command line is the main way to run them.

## Tools / paths
- Libero: `/usr/local/microchip/Libero_SoC_2026.1`, started via `tools/start_libero.sh`, which starts the FlexLM license server if needed. The daemons are in `$LIBERO_INSTALL_DIR/LicenseDaemons/`, `lmutil` is in `Libero_SoC/Designer/bin64/`, and `License.dat` / `license.log` are in `~/Microchip/`. Stop the server with `tools/stop_licenser_server.sh`. Setup and troubleshooting are in `tools/README.md`.
- MSS Configurator: `/usr/local/microchip/Libero_SoC_2026.1/Libero_SoC/Designer/bin64/pfsoc_mss`
- IP vault: `/usr/local/microchip/common/vault/Components/` (core GUI labels are in `fs/p0f0/<CORE>.xml`)
- SoftConsole v2022.2 is in `~/Microchip` (the latest release). The workspace is `softconsole/`.
- The bare-metal project `softconsole/led_test` is a copy of `applications/mpfs-blank-baremetal` from Microchip's `polarfire-soc-bare-metal-examples` (local clone in `~/Projs/pfsoc-bare-metal-examples`).
  - Build configuration: `Discovery-Kit-LIM-Debug`. Debug with `led_test hw all-harts debug` (GDB OpenOCD).
  - The pre-build step runs `mpfs_configuration_generator.py`, which turns `src/boards/mpfs-discovery-kit/fpga_design/design_description/*.xml` (a copy of `mss/MSS_simple_mss_cfg.xml`) into `fpga_design_config/`. **Copy the XML again whenever the MSS config changes.**
  - `Discovery-Kit-eNVM-Scratchpad-Release` has a **post-build step** that runs `mpfsBootmodeProgrammer.jar --bootmode 1 --dryrun` to create `bootmode1/led_test-bm1-p0.hex` (a dummy SBIC page at `0x2022_0000` followed by the image at `0x2022_0100`). **Use this hex as the Libero "Boot Mode 1" eNVM client.** The plain `led_test.hex` is rejected because it starts at `0x2022_0100`. The step hard-codes `FPGENPROG=/usr/local/microchip/Libero_SoC_2026.1/...`, so update it if Libero is upgraded.
  - The Libero eNVM client config is saved in `polarfire_simple/designer/TOP/ENVM.cfg`. Apart from the `designer/impl1/simulation/.gitkeep` placeholder, this is the only file under `designer/` that is tracked in git. It stores **`-number_of_bytes`** and an absolute path to the hex, so after the program grows, select the hex again in the eNVM client.
  - The application code is in `src/application/hart0/e51.c`. Only the E51 runs our code; the U54s stay in WFI.
- Board reference: Microchip `polarfire-soc/polarfire-soc-discovery-kit-reference-design` on GitHub. Pins, MSS `.cfg` and DDR4 settings were taken from it (that design targets Libero 2025.2).

## Board facts
- Device MPFS095T, package FCSG325, speed -1, 1.0 V, range EXT. Default I/O standard LVCMOS18.
- Banks: Bank0 1.8 V, Bank1 3.3 V (J45 at 1-2). MSS banks: B2 3.3 V, B4 1.8 V, B5 3.3 V.
- Pins:
  - REF_CLK_50MHz R18
  - SWITCH1 T19, SWITCH2 U18 (both active low)
  - LED1–7: T18, V17, U20, U21, AA18, V16, U15 (active high)
  - FTDI UART: MSS TX → Y21, MSS RX ← W21
  - RPi header (Bank1, so `-io_std LVCMOS33`). GPIO = BCM number, pin = physical header pin. Source: the reference design's `script_support/constraints/MPFS_DISCOVERY_RPi.pdc`, which lists all RPi pins.
    - DEBUG: GPIO21, pin 40, E13 (`GPIO128NB1`)
    - SPI SCLK: GPIO19, pin 35, B19; MOSI: GPIO16, pin 36, B15; CS_N: GPIO26, pin 37, B17
    - GPIO20, pin 38, B14: tied low
    - QSPI breakout: SCLK GPIO17 pin 11 G18, CS# GPIO27 pin 13 F21, IO0–3 GPIO22/23/24/25 pins 15/16/18/22 F20/E21/F19/A19; 3.3 V pin 17, GND pin 9
- MSS reference clock is **125 MHz**. DDR4 is x16, 1 GB.

## Design notes
- Everything in the fabric runs on the 125 MHz `PF_CCC_C0` output (OUT0) with `CORERESET_0_FABRIC_RESET_N`, except `qspi_board` (QSPI controller + BIST, README.md), which runs on OUT1 = 100 MHz with `CORERESET_1`. After adding a CCC output, run Constraint Manager → Timing → **Derive Constraints** again, otherwise the new clock is not constrained.
- **CoreFIFO `BLOCK_FIFO_CORE`** (COREFIFO 4.0.139): 80 bit × 512, single clock, sync reset, FWFT, active-high WE/RE (`WE_POLARITY`/`RE_POLARITY` = 0 in the `.cxf`). Libero generates it as Verilog, which is why `run_tb.sh` uses `vlog`. `hdl/block_fifo.vhd` wraps it and assumes exactly this configuration, so update both together.
- Signal path and SPI TX path details are in README.md (Design overview, SPI TX path) and in `documentation/top_level.drawio` / `spi_tx_path.drawio`. Update the diagrams when TOP changes. Only `documentation/*.pdf` is in Git LFS; the `.drawio` files are plain git.

## Gotchas learned
- **CoreAXI4Interconnect is v3.0.130** here, not v2.9 like the reference design. It uses Initiator/Target naming, and its bus interfaces are `AXI4minitiator0` and `AXI4Lmtarget0`. The data width is set under "Crossbar Configuration" ("User Width" is the AXI USER sideband, not the data width).
- Libero has **no AXI4-Lite bus definition**. For a custom AXI4-Lite slave, use AMBA4 → AXI4 → slave in Create Core from HDL and map only the Lite signals; the others have defaults.
- An address-validation warning that the target can't be reached from FIC0 `0x20_0000_0000–0x2F_FFFF_FFFF` is expected. That is the FIC0 64-bit window; we use the low window `0x6000_0000`.
- "Open Component" on the MSS opens the MSS Configurator. Its ports are visible only on a SmartDesign canvas.
- MSS outputs that are not used must be marked unused: `PLL_CPU_LOCK_M2F`, `PLL_DDR_LOCK_M2F`, `MMUART_0_TXD_OE_M2F`.
- MSS cfg items that needed fixing compared with the defaults: `DDR4_READ_PREAMBLE 1`, `L2CACHE_LIM_SIZE 4` / `L2CACHE_SCRATCH_SIZE 4`. The scratchpad is needed by the HSS.
- The `.prjx` stores linked files as absolute paths.
- **Bank1 pins need `-io_std LVCMOS33` in `io.pdc`.** The project default is LVCMOS18, which only fits Bank0 (the HSIO pins: LEDs, switches, clock). A Bank1 pin without it fails with "macro <port>_obuf is incompatible with this IoBank Bank1". The bank is in the last column of `$LIBERO_INSTALL_DIR/Libero_SoC/Designer/data/aPA5SOC/PA5SOC095/fcsg325.ddf` (`…B1` = Bank1, `HSIO…B0` = Bank0).
- **Libero's working directory matters.** When an HDL+ core is updated, Libero writes `component/User/Private/<core>/…xml` relative to its working directory. Started from the repo root, that creates a stray `component/` there. `tools/start_libero.sh` therefore `cd`s into `polarfire_simple/` first.
- **Libero needs `designer/impl1/` to exist.** Each revision (`Impl1` in the `.prjx` `LIST REVISIONS` / `CURREV`) has a folder `designer/impl<N>/`. If that folder is missing (e.g. on a fresh clone, because `designer/` is git-ignored), Libero quietly creates a new revision `Impl2` on open. `designer/impl1/simulation/.gitkeep` is tracked to prevent this. `designer/TOP/` is per root module, not per revision.
- **Generics per instance need an HDL+ core.** For a plain HDL module, SmartDesign drops the generics (no `generic map` in `TOP.vhd`), so the entity defaults always apply. An HDL+ core shows them in its configuration dialog and gets a `generic map`. Neither can be expanded on the canvas. SmartDesign has no array ports, so multi-port blocks use flattened vectors and **Edit Slices** (e.g. `block_arbiter`).
- After changing an HDL+ core's ports, update the instance in SmartDesign and then **Generate Component**. Saving alone deletes `TOP.vhd` until it's generated again.
- The I/O Editor writes an export to `constraints/pre/` (git-ignored). The source of truth is `constraints/io.pdc`.
- **Console UART:** the template maps the E51 to MMUART1, but our design uses **MMUART0** (`g_mss_uart0_lo`, `MSS_PERIPH_MMUART0`). It reaches the FT4232H **channel D, interface 3**: `/dev/serial/by-id/usb-Microsemi_Embedded_FlashPro5_*-if03-port0`, or `/dev/pfsoc-uart0` via the udev rule.
- **Linux sees only one serial port for the board.** The kernel's `ftdi_sio` binds only interface 2 of `1514:2008` (Embedded FlashPro5). Fix: `echo 1514 2008 | sudo tee /sys/bus/usb-serial/drivers/ftdi_sio/new_id`, or permanently by installing `tools/99-pfsoc-discovery-uart.rules` in `/etc/udev/rules.d/` (it binds all interfaces, unbinds interface 0 = JTAG, and adds the `/dev/pfsoc-uart0` symlink).
- **SoftConsole project rename:** renaming in the IDE does not update the template's shared `.launch` files, so they get hidden as belonging to a "missing project". The launch files, `.project` and `.cproject` were updated by hand to `led_test`. Don't use SoftConsole's auto-created debug config: it doesn't start OpenOCD, has no `set DEVICE MPFS`, and uses rv32.
- **Only one tool at a time can use JTAG (interface 0).** If Libero says "No programmer connected", a SoftConsole debug session (OpenOCD) is probably still running. Terminate it first (`pgrep -a openocd`).
- To access FIC0 from software, call `mss_config_clk_rst(MSS_PERIPH_FIC0, …, PERIPHERAL_ON)`. The HAL startup releases the fabric reset (`mss_enable_fabric`).
- **Libero simulation silently does nothing on Ubuntu without `/etc/redhat-release`.** The generated `simulation/run.do` sources the MSS `*_compile_bfm.tcl` scripts, which `exec` `bfmtovec`. Its wrapper (`Designer/bin64/actel_setup_vars_nomotif`) runs `cat /etc/redhat-release`, which writes to stderr, and Tcl `exec` treats any stderr as failure. So `run.do` aborts at line 3 and QuestaSim opens with nothing loaded. The error is only visible in `simulation/<tb>_presynth_simulation.log`. Fix: `sudo touch /etc/redhat-release` (an empty file matches none of the script's RHEL greps). Don't edit the `*_compile_bfm.tcl` files, because Libero regenerates them.
- **I/O register combining on PolarFire:** Synplify's `syn_useioff` is not supported. Use `set_ioff` in an NDC file (Constraint Manager → Netlist Attributes) with the PolarFire syntax `set_ioff -port_name {P} -OUT_REG 1`, with one option per command. **Only one side of an I/O can be combined** (IN, OUT or EN; PDCPF-91 "No register was combined" otherwise), and the register needs fanout 1. The `set_ioff {P} -out_reg yes` form in parts of the help is for SmartFusion2/IGLOO2/RTG4 and fails with "PDCPF-426: 'P' is not a parameter within the command set_ioff".
- **Drive strength in PolarFire PDC is `-OUT_DRIVE <mA>`** (e.g. `-OUT_DRIVE 4`; default 8 for LVCMOS33). `-DRIVE` fails with "PDCPF-426: Parameter 'DRIVE' is not defined".
- **Forwarded clocks in SmartTime:** `create_generated_clock -divide_by 2 -source <CCC OUT pin> [get_ports <pin>]` on a port driven by a toggling register works. SmartTime propagates the clock through the register and the output pad (the latency appears as "Clock generation" in the expanded path), so I/O delays can be relative to the forwarded clock (`constraints/timing.sdc`). PolarFire clock insertion is large (≈ 4–8 ns), so constraining I/O to fixed clock-to-out limits relative to the CCC clock mixes corners and is far too pessimistic.
