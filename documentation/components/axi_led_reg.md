# axi_led_reg

AXI4-Lite slave with two LED bits, a read-only ID register and a write-triggered debug pulse.
Source: `hdl/axi_led_reg.vhd`. In TOP it sits behind CoreAXI4Interconnect at `0x6000_0000`.

## Generics

| Generic | Type | Default | Description |
|---|---|---|---|
| `ADDR_WIDTH` | integer | 38 | Width of `AWADDR` / `ARADDR` (38 = FIC0 address width). |

## Ports

| Port | Dir | Width | Description |
|---|---|---|---|
| `ACLK` | in | 1 | Clock. |
| `ARESETN` | in | 1 | Synchronous, active-low reset. |
| `AWADDR` | in | `ADDR_WIDTH` | Write address; bits 3:2 decoded. |
| `AWPROT` | in | 3 | Ignored. |
| `AWVALID` | in | 1 | Write address valid. |
| `AWREADY` | out | 1 | Write accepted (together with `WREADY`). |
| `WDATA` | in | 32 | Write data. |
| `WSTRB` | in | 4 | Byte strobes; bit 0 must be 1. |
| `WVALID` | in | 1 | Write data valid. |
| `WREADY` | out | 1 | Write accepted (together with `AWREADY`). |
| `BRESP` | out | 2 | Always OKAY (`00`). |
| `BVALID` | out | 1 | Write response valid. |
| `BREADY` | in | 1 | Write response accepted. |
| `ARADDR` | in | `ADDR_WIDTH` | Read address; bits 3:2 decoded. |
| `ARPROT` | in | 3 | Ignored. |
| `ARVALID` | in | 1 | Read address valid. |
| `ARREADY` | out | 1 | Read address accepted. |
| `RDATA` | out | 32 | Read data. |
| `RRESP` | out | 2 | Always OKAY (`00`). |
| `RVALID` | out | 1 | Read data valid. |
| `RREADY` | in | 1 | Read data accepted. |
| `LED2` | out | 1 | LED register bit 0. |
| `LED3` | out | 1 | LED register bit 1. |
| `DEBUG_PULSE` | out | 1 | High for one `ACLK` cycle per write of 1 to `DEBUG`. |

## Register map

| Offset | Name | Access | Description |
|---|---|---|---|
| 0x0 | LED | R/W | bit 0 = `LED2`, bit 1 = `LED3`. |
| 0x4 | ID | RO | `0x1ED50001`. |
| 0x8 | DEBUG | WO | Writing bit 0 = 1 pulses `DEBUG_PULSE`; writing 0 does nothing. Reads 0. |

## Usage notes

- Only address bits 3:2 are decoded, so the registers repeat every 16 bytes; 0xC reads 0.
- A write needs `AWVALID` and `WVALID` together and `WSTRB(0)` = 1 to take effect. `BRESP` / `RRESP` are always OKAY.
- `*PROT` inputs are ignored.

## Testbench

`sim/tb_axi_led_reg.vhd` — `sim/run_tb.sh tb_axi_led_reg`. Also linked in Libero as the TOP stimulus.

| Test | Checks |
|---|---|
| ID read | `0x4` returns `0x1ED50001`. |
| LED write / readback | `0x0` stores bits 1:0 and drives `LED2` / `LED3`. |
| DEBUG pulse | Writing 1 gives exactly one `DEBUG_PULSE` cycle, also with a slow `BREADY`. |
| No false pulse | Writing 0 to DEBUG, or writing the LED register, gives no pulse. |
| DEBUG read | `0x8` reads 0. |
