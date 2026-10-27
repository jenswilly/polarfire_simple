# axi_sys_ctrl

System control registers (AXI4-Lite slave): two LED bits, a read-only ID register and a write-triggered debug pulse.
Source: `hdl/axi_sys_ctrl.vhd`. In TOP it sits behind CoreAXI4Interconnect at `0x6000_0000`.
The data bus is 64 bits, the same width as FIC_0 and the interconnect crossbar, so the interconnect generates no data width converter. With a 32-bit target, its 64→32-bit DownConverter failed setup at 200 MHz (2026-10-27, worst slack −0.21 ns). The registers themselves are 32 bits.

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
| `WDATA` | in | 64 | Write data; `AWADDR(2)` selects the 32-bit lane. |
| `WSTRB` | in | 8 | Byte strobes; byte 0 of the addressed lane (bit 0 or bit 4) must be 1. |
| `WVALID` | in | 1 | Write data valid. |
| `WREADY` | out | 1 | Write accepted (together with `AWREADY`). |
| `BRESP` | out | 2 | Always OKAY (`00`). |
| `BVALID` | out | 1 | Write response valid. |
| `BREADY` | in | 1 | Write response accepted. |
| `ARADDR` | in | `ADDR_WIDTH` | Read address; bits 3:2 decoded. |
| `ARPROT` | in | 3 | Ignored. |
| `ARVALID` | in | 1 | Read address valid. |
| `ARREADY` | out | 1 | Read address accepted. |
| `RDATA` | out | 64 | Read data; the register value on both 32-bit lanes. |
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
- A write needs `AWVALID` and `WVALID` together and byte 0 of the addressed lane strobed to take effect. `BRESP` / `RRESP` are always OKAY.
- Use 32-bit accesses. A 32-bit access at offset `4n` uses lane `n mod 2` (`AWADDR(2)` / `ARADDR(2)`), so the data takes the same lane path as it would through the interconnect. Reads put the register value on both lanes, so either lane is right. A 64-bit write at `0x0` only writes LED (the upper lane, ID, is read-only); a 64-bit write at `0x8` only writes DEBUG.
- `*PROT` inputs are ignored.

## Testbench

`sim/tb_axi_sys_ctrl.vhd` — `sim/run_tb.sh tb_axi_sys_ctrl`. Also linked in Libero as the TOP stimulus.

| Test | Checks |
|---|---|
| ID read | `0x4` returns `0x1ED50001`. |
| LED write / readback | `0x0` stores bits 1:0 and drives `LED2` / `LED3`. |
| Lanes | Each access puts junk in the other lane: writes use only the addressed lane, a write with byte 0 not strobed is ignored, writes to `0x4`/`0xC` leave the LEDs alone, the alias at `0x10` works, and both `RDATA` lanes are always equal. |
| DEBUG pulse | Writing 1 gives exactly one `DEBUG_PULSE` cycle, also with a slow `BREADY`. |
| No false pulse | Writing 0 to DEBUG, or writing the LED register, gives no pulse. |
| DEBUG read | `0x8` reads 0. |
