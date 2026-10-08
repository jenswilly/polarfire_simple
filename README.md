# polarfire_simple

A minimal PolarFire SoC test project for the **PolarFire SoC Discovery Kit** (MPFS095T-1FCSG325E). It uses Libero SoC 2026.1 for the FPGA design and SoftConsole for the bare-metal software.

It drives three LEDs:

| LED  | Source                                   | Pin  |
|------|------------------------------------------|------|
| LED1 | Push-button SWITCH1 (inverted), pure fabric | T18 |
| LED2 | MSS register write via FIC0 AXI → bit 0     | V17 |
| LED3 | MSS register write via FIC0 AXI → bit 1     | U20 |

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

The interconnect decodes `0x6000_0000 – 0x6000_0FFF`, which is in the FIC0 low (32-bit) window.

### MSS configuration (`mss/MSS_simple.cfg`)
- Reference clock 125 MHz, CPU clock 600 MHz, AXI clock 300 MHz, AHB/APB clock 150 MHz.
- DDR4, x16, 1 GB, 800 MHz (DDR4-1600), CL12. Timings are copied from Microchip's Discovery Kit reference design.
- L2 cache split: LIM 4 ways, scratchpad 4 ways. The scratchpad is needed by the HSS.
- MMUART_0 is routed to the fabric. FIC_0 AXI4 initiator is enabled. All other peripherals and FICs are off.

## Repository layout

```
mss/                MSS Configurator source (.cfg) and generated .cxz/.xml
hdl/                axi_led_reg.vhd: AXI4-Lite LED register (linked into Libero)
constraints/io.pdc  Pin and bank constraints (linked into Libero)
polarfire_simple/   Libero project (.prjx + component configs); build output is git-ignored
```

## Building

1. Open `polarfire_simple/polarfire_simple.prjx` in Libero SoC 2026.1.
2. If the MSS config changed, regenerate it with the MSS Configurator (`pfsoc_mss`) into `mss/`, then re-import it with **File → Import → MSS**.
3. In Design Flow, run Synthesize → Place and Route → Verify Timing → Generate Bitstream → Run PROGRAM Action. The board's embedded FlashPro6 is used for programming.

The `.prjx` file references `hdl/axi_led_reg.vhd` and `constraints/io.pdc` by **absolute path** (`/home/jenswilly/Projs/polarfire_simple/...`). If you clone the repository somewhere else, re-link those two files.

## Status / next steps
- [x] FPGA design built and programmed. SWITCH1 → LED1 works.
- [ ] SoftConsole bare-metal app: copy the MSS-generated config into `fpga_design_config`, write to `0x6000_0000`, read the ID at `0x6000_0004`.
- [ ] HSS in eNVM to boot the app.
