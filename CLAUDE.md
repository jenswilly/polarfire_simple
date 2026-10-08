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

## Tools / paths
- Libero: `/usr/local/microchip/Libero_SoC_2026.1`, started via `~/Microchip/start_libero.sh` (license daemon).
- MSS Configurator: `/usr/local/microchip/Libero_SoC_2026.1/Libero_SoC/Designer/bin64/pfsoc_mss`
- IP vault: `/usr/local/microchip/common/vault/Components/` (core GUI labels are in `fs/p0f0/<CORE>.xml`)
- SoftConsole v2022.2 is in `~/Microchip`. It is older than Libero 2026.1, so check compatibility at the software stage.
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
- The I/O Editor writes an export to `constraints/pre/` (git-ignored). The source of truth is `constraints/io.pdc`.
