# CLAUDE.md

Learning project: PolarFire SoC Discovery Kit, Libero SoC 2026.1, and SoftConsole (bare-metal). See README.md for the design overview and register map.

## How we work
- **The user does all GUI work in Libero, the MSS Configurator and SoftConsole.** Claude gives step-by-step instructions and then **verifies by reading the generated files**. Claude does not drive the tools.
  - Project/device settings: `polarfire_simple/polarfire_simple.prjx`
  - MSS: `mss/MSS_simple.cfg`
  - SmartDesign result: `polarfire_simple/component/work/TOP/TOP.vhd`
  - IP configs: `polarfire_simple/component/work/<comp>/<comp>.cxf` (`configurableElement` values)
- HDL is **VHDL** (project is set to VHDL-2008). Do not write Verilog.
- Hand-written sources live outside the Libero folder (`hdl/`, `constraints/`, `mss/`) and are *linked* into the project, not imported.
- Testbenches are in `sim/tb_<entity>.vhd`. They are self-checking and must print `TB PASSED` / `TB FAILED`. Run them with `sim/run_tb.sh tb_<entity>`, which compiles `hdl/*.vhd` and uses Libero's QuestaSim (needs the license server). Claude can run these directly. Extend the testbench whenever HDL behaviour changes.
- **Libero simulation setup:** link the testbench as a stimulus file (type `tb_hdl` in the `.prjx`). Associate it via Design Flow → Verify Pre-Synthesized Design → Simulate → right-click → Organize Input Files → Organize Stimulus Files. That writes `LIST AssociatedStimulus` / `LIST TOP`. The Stimulus Hierarchy has **no** "Set as Active Stimulus" in 2026.1, and the Tcl `set_active_testbench "<tb>::work,<path>"` fails ("Cannot find module named …"). The testbench name and instance go in Project Settings → Simulation Options (`EntityName` / `TopInstanceName` in the `.prjx`). Only one testbench can be the Simulation Options testbench at a time.

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
  - SWITCH1 T19 (active low), SWITCH2 U18
  - LED1–7: T18, V17, U20, U21, AA18, V16, U15 (active high)
  - FTDI UART: MSS TX → Y21, MSS RX ← W21
- MSS reference clock is **125 MHz**. DDR4 is x16, 1 GB.

## Gotchas learned
- **CoreAXI4Interconnect is v3.0.130** here, not v2.9 like the reference design. It uses Initiator/Target naming, and its bus interfaces are `AXI4minitiator0` and `AXI4Lmtarget0`. The data width is set under "Crossbar Configuration" ("User Width" is the AXI USER sideband, not the data width).
- Libero has **no AXI4-Lite bus definition**. For a custom AXI4-Lite slave, use AMBA4 → AXI4 → slave in Create Core from HDL and map only the Lite signals; the others have defaults.
- An address-validation warning that the target can't be reached from FIC0 `0x20_0000_0000–0x2F_FFFF_FFFF` is expected. That is the FIC0 64-bit window; we use the low window `0x6000_0000`.
- "Open Component" on the MSS opens the MSS Configurator. Its ports are visible only on a SmartDesign canvas.
- MSS outputs that are not used must be marked unused: `PLL_CPU_LOCK_M2F`, `PLL_DDR_LOCK_M2F`, `MMUART_0_TXD_OE_M2F`.
- MSS cfg items that needed fixing compared with the defaults: `DDR4_READ_PREAMBLE 1`, `L2CACHE_LIM_SIZE 4` / `L2CACHE_SCRATCH_SIZE 4`. The scratchpad is needed by the HSS.
- The `.prjx` stores linked files as absolute paths.
- **Libero's working directory matters.** When an HDL+ core is updated, Libero writes `component/User/Private/<core>/…xml` relative to its working directory. Started from the repo root, that creates a stray `component/` there. `tools/start_libero.sh` therefore `cd`s into `polarfire_simple/` first.
- **Libero needs `designer/impl1/` to exist.** Each revision (`Impl1` in the `.prjx` `LIST REVISIONS` / `CURREV`) has a folder `designer/impl<N>/`. If that folder is missing (e.g. on a fresh clone, because `designer/` is git-ignored), Libero quietly creates a new revision `Impl2` on open. `designer/impl1/simulation/.gitkeep` is tracked to prevent this. `designer/TOP/` is per root module, not per revision.
- After changing an HDL+ core's ports, update the instance in SmartDesign and then **Generate Component**. Saving alone deletes `TOP.vhd` until it's generated again.
- The I/O Editor writes an export to `constraints/pre/` (git-ignored). The source of truth is `constraints/io.pdc`.
- **Console UART:** the template maps the E51 to MMUART1, but our design uses **MMUART0** (`g_mss_uart0_lo`, `MSS_PERIPH_MMUART0`). It reaches the FT4232H **channel D, interface 3**: `/dev/serial/by-id/usb-Microsemi_Embedded_FlashPro5_*-if03-port0`, or `/dev/pfsoc-uart0` via the udev rule.
- **Linux sees only one serial port for the board.** The kernel's `ftdi_sio` binds only interface 2 of `1514:2008` (Embedded FlashPro5). Fix: `echo 1514 2008 | sudo tee /sys/bus/usb-serial/drivers/ftdi_sio/new_id`, or permanently by installing `tools/99-pfsoc-discovery-uart.rules` in `/etc/udev/rules.d/` (it binds all interfaces, unbinds interface 0 = JTAG, and adds the `/dev/pfsoc-uart0` symlink).
- **SoftConsole project rename:** renaming in the IDE does not update the template's shared `.launch` files, so they get hidden as belonging to a "missing project". The launch files, `.project` and `.cproject` were updated by hand to `led_test`. Don't use SoftConsole's auto-created debug config: it doesn't start OpenOCD, has no `set DEVICE MPFS`, and uses rv32.
- **Only one tool at a time can use JTAG (interface 0).** If Libero says "No programmer connected", a SoftConsole debug session (OpenOCD) is probably still running. Terminate it first (`pgrep -a openocd`).
- To access FIC0 from software, call `mss_config_clk_rst(MSS_PERIPH_FIC0, …, PERIPHERAL_ON)`. The HAL startup releases the fabric reset (`mss_enable_fabric`).
