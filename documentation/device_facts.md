# Device facts: W25Q128JV and AS308G208

Extracted from the datasheets before the controller was designed. Every value has a source. `TBD` means the datasheet doesn't settle it; open questions are collected at the end.

Sources:
- **[W]** `W25Q128JV_QSPI_Flash.pdf`, Winbond W25Q128JV, Revision F (2018-03-27). Page numbers are the printed page numbers (PDF page − 1).
- **[A]** `Avalanche_AS308G208_Dual_QSPI.pdf`, Avalanche ASxxxx208 family, Revision J.1 (2025-11-13). Printed page = PDF page.

Conventions used below: `x-y-z` = number of IO lines for command-address-data. "Clocks" are SCLK cycles. All data is MSB first. In quad phases the first clock carries bits 7:4 of a byte on IO3:IO0, the second clock bits 3:0 ([W] p.23 notes 8–10; [A] Fig. 19 p.45), for both address and data.

---

## 1. Summary for the controller

| Item | W25Q128JV (prototype) | AS308G208, per CS (final) |
|---|---|---|
| Read command | EBh, 1-4-4 | EBh, 1-4-4 |
| Address | 3 bytes (24 bit), 6 clocks | 4 bytes (32 bit), 8 clocks |
| Mode / XIP byte | M7-0 = `Fxh`, 2 clocks (we send `FFh`) | XIP byte `Fxh` = XIP disabled, 2 clocks (we send `FFh`) |
| Dummy / latency after mode byte | 4 clocks, fixed | CR2.MLATS clocks; default 8, valid 8–15 at ≤ 54 MHz |
| EBh overhead (cmd + addr + mode + dummy) | 8 + 6 + 2 + 4 = 20 clocks | 8 + 8 + 2 + 8 = 26 clocks |
| Max SCLK for EBh | 133 MHz (VCC 3.0–3.6 V) | 54 MHz |
| Max SCLK for other commands used | 133 MHz | **40 MHz for 05h and 9Fh**, 50 MHz for 70h, 54 MHz otherwise |
| Quad enable needed | QE (SR2 bit 1), factory-fixed 1 on our part; init only checks it | No |
| Reset | Software: 66h + 99h, then tRST 30 µs | **Hardware only: RESET# pin**, then tPU (25 ms) |
| Power-up wait | 5 ms before writes (tPUW), 20 µs before reads (tVSL) | 25 ms (tPU); 250 µs for the -A variant |
| Expected JEDEC ID (9Fh) | `EF 40 18` (W25Q128JVSSIQ) | `E6 21 xx 01`, density nibble TBD (see §3.6) |
| Write | Erase 4 KB sector (20h), then program ≤ 256 B pages (02h / 32h), poll BUSY | Any length, no erase (02h 1-1-1 or D2h 1-4-4), no polling, 600 ns CS# high after |
| WP#/HOLD# on IO2/IO3 in 1-1-1 phases | Drive high | Drive high (WP# has no pull-up and must be driven) |
| Min CS# high after read / write | 10 ns / 50 ns | 20 ns / 600 ns |

With 8 × 880 host bytes at 50 MHz: W25Q128JV 7040 + 8 × 20 = 7200 clocks = 144 µs, AS308G208 7040 + 8 × 26 = 7248 clocks = 145 µs, plus CS# high time between requests. `tb_qspi_read_ctrl` measures 144.5 µs (W25Q) and 145.5 µs (AS).

---

## 2. W25Q128JV

### 2.1 Organisation and identification
- 128 Mbit = 16 MB, 24-bit address `000000h–FFFFFFh`; 256 blocks of 64 KB, 4 KB sectors, 256-byte pages. [W] p.10 Fig. 2, p.18 §7.1.8
- SPI mode 0 and mode 3 supported. Inputs latched on the rising edge, outputs change on the falling edge. [W] p.11 §6.1, p.9 §4.2
- JEDEC ID (9Fh) returns manufacturer `EFh`, then ID15–ID8 (memory type), then ID7–ID0 (capacity). [W] p.50 §8.2.27
  - W25Q128JV‑IQ/JQ: `EF 40 18`. W25Q128JV‑IM/JM: `EF 70 18` (the DTR variant; its own datasheet). [W] p.21 §8.1.1
- **Part on the breakout: W25Q128JVSSIQ.** Ordering code ([W] p.74–75): package S(S) = 8-pin SOIC 208-mil, I = industrial (−40…+85 °C), Q = QE fixed at 1 in SR2 and /HOLD disabled. So the JEDEC ID is `EF 40 18`, IO2/IO3 are always data pins, and the 8-pin package has no hardware /RESET pin ([W] p.11 §6.4).
- There is no QPI (4-4-4) mode in this datasheet. The 4-4-4/DTR variant (IM/JM) is covered by a separate datasheet. [W] p.21 note

### 2.2 Commands used (all 1-1-1 unless stated)

| Purpose | Opcode | Format after opcode | Ref |
|---|---|---|---|
| Write Enable | 06h | — | [W] p.22, p.24 §8.2.1 |
| Write Enable for volatile SR | 50h | — (does not set WEL) | [W] p.24 §8.2.2 |
| Read Status Register‑1 / ‑2 / ‑3 | 05h / 35h / 15h | 1 data byte out (repeats while clocked) | [W] p.22, p.25 §8.2.4 |
| Write Status Register‑1 / ‑2 / ‑3 | 01h / 31h / 11h | 1 data byte in | [W] p.22, p.26 §8.2.5 |
| Read JEDEC ID | 9Fh | 3 data bytes out | [W] p.22, p.50 |
| Enable Reset, Reset Device | 66h, then 99h | — (two separate CS# cycles, in sequence) | [W] p.22, p.59 §8.2.37 |
| Sector Erase (4 KB) | 20h | 3 address bytes | [W] p.22, p.38 §8.2.15 |
| Page Program | 02h | 3 address bytes, 1–256 data bytes in | [W] p.22, p.36 §8.2.13 |
| Quad Input Page Program (1-1-4) | 32h | 3 address bytes on IO0, data on IO3:0 (2 clocks/byte) | [W] p.23, p.37 §8.2.14 |
| **Fast Read Quad I/O (1-4-4)** | **EBh** | 3 address bytes (6 clocks), M7-0 (2 clocks), 4 dummy clocks, data (2 clocks/byte) | [W] p.23, p.33 §8.2.11 Fig. 24a |

EBh details ([W] p.23 note 11, p.33):
- QE must be 1.
- M7-0 "should be set to Fxh". We send `FFh`, which keeps the device out of continuous-read mode, so every EBh needs the opcode.
- The IOs turn from input to output after the 4 dummy clocks, so the host can release OE at the first dummy clock.
- AC table footnote 6 says "4-bytes address alignment for Quad Read" without further explanation ([W] p.64). See Q‑W2.

### 2.3 Status registers
- SR1 ([W] p.13 Fig. 4a): S7 SRP, S6 SEC, S5 TB, S4–S2 BP2–BP0, S1 WEL, S0 BUSY. BUSY and WEL are status-only.
- SR2 ([W] p.16 Fig. 4b): S15 SUS, S14 CMP, S13–S11 LB3–LB1 (OTP), S10 reserved, **S9 QE**, S8 SRL. So QE is SR2 bit 1.
- SR3 ([W] p.17 Fig. 4c): S22–S21 DRV1–DRV0 (driver strength, default 11 = 25 %), S18 WPS.
- Factory defaults: BP2–0 = 0, TB = 0, SEC = 0, CMP = 0 (nothing protected), WPS = 0 (individual block locks not used), SRP = SRL = 0 (SR writable after WREN). [W] pp.13–17
- QE default: **0** on ‑IM/‑JM, **factory-fixed 1** on ‑IQ/‑JQ. [W] p.16 §7.1.4
- Writable SR bits: SEC, TB, BP2–0; CMP, LB3–1, QE, SRL; DRV1–0, WPS. Others are read-only. LB3–1 are OTP, so **never write a 1 to SR2 bits 5:3**. The safe way to set QE is read-modify-write of SR2. [W] p.26 §8.2.5
- Non-volatile write (06h + 31h): BUSY for tW (10 ms typ, 15 ms max), and WEL clears afterwards. Volatile write (50h + 31h): takes effect within tSHSL2 (50 ns), no BUSY, and is lost on power-off or reset. [W] p.26, p.65
- While BUSY = 1, every instruction except Read Status (and Suspend) is ignored. [W] p.21, p.13 §7.1.1
- Before 66h/99h, check BUSY = 0 and SUS = 0 (a reset during program/erase can corrupt data). [W] p.59

### 2.4 Pins
- /WP = IO2, /HOLD = IO3. With QE = 0, /HOLD is active: low while CS# is low pauses the device. With QE = 1 both pins are plain IO2/IO3. [W] p.9 §4.3–4.4
- **The controller drives IO2 and IO3 high in all 1-1-1 phases.**
- /CS should track VCC at power-up; a pull-up on /CS is suggested. [W] p.9 §4.1, p.12

### 2.5 Timing (VCC 3.0–3.6 V)

| Parameter | Symbol | Value | Ref |
|---|---|---|---|
| Max SCLK, all except 03h | fC1 | 133 MHz | [W] p.64 |
| Clock high / low time | tCLH, tCLL | ≥ 45 % of 1/fC(max) | [W] p.64 note 1 |
| CS# setup / hold to CLK | tSLCH / tCHSH | ≥ 3 ns / ≥ 3 ns | [W] p.64 |
| CS# not-active hold / setup | tCHSL / tSHCH | ≥ 3 ns / ≥ 3 ns | [W] p.64 |
| Data in setup / hold | tDVCH / tCHDX | ≥ 1 ns / ≥ 2 ns | [W] p.64 |
| CS# high time after read | tSHSL1 | ≥ 10 ns | [W] p.64 |
| CS# high time after erase/program/write, **including WREN (06h)** | tSHSL2 | ≥ 50 ns | [W] p.64; on hardware, 10 ns after WREN left WEL set but the next 20h/32h was ignored |
| Clock low to output valid | tCLQV | ≤ 6 ns | [W] p.64 |
| Output hold | tCLQX | ≥ 1.5 ns | [W] p.64 |
| Output disable after CS# high | tSHQZ | ≤ 7 ns | [W] p.64 |
| VCC(min) to CS# low | tVSL | ≥ 20 µs | [W] p.61 |
| Power-up to first write instruction | tPUW | ≥ 5 ms | [W] p.61 |
| Reset (99h) to next instruction | tRST | ≤ 30 µs | [W] p.65, p.59 |
| Write Status Register (non-volatile) | tW | 10 ms typ, 15 ms max | [W] p.65 |
| Page Program | tPP | 0.4 ms typ, 3 ms max | [W] p.65 |
| Sector Erase 4 KB | tSE | 45 ms typ, 400 ms max | [W] p.65 |

### 2.6 Writes
- WREN (06h) before every program, erase and non-volatile SR write. WEL clears automatically when the operation finishes. [W] p.12, p.24
- Program only into erased (FFh) locations. Up to 256 bytes per command. If the data passes the end of the 256-byte page, the address wraps to the page start. Split writes at page boundaries. [W] p.23 note 3, p.36
- For program/erase, CS# must go high exactly on a byte boundary, or the command is ignored. [W] p.21, p.36, p.38
- **BUSY polling is required** after erase, program and non-volatile SR writes (05h, bit 0). [W] p.13 §7.1.1

---

## 3. AS308G208 (values per QSPI device, i.e. per CS#)

### 3.1 Organisation
- The package contains two independent Quad-SPI devices: device 1 on CS1#/CLK1/IO[3:0], device 2 on CS2#/CLK2/IO[7:4]. Each has its own registers. [A] p.5, p.9
- AS308G208 = 8 Gb = 8 × 1 Gb dies, i.e. **4 Gb (512 MB) per CS#**. [A] p.5 Table 2
- **Addressing:** every command uses a 4-byte (32-bit) address ([A] p.40). Per CS the range is `0000_0000h–1FFF_FFFFh` (29 address bits, A[31:29] = 0). [A] p.21 Table 12, p.22 Fig. 12. The extended address register (A[28:24]) only applies to 3-byte commands (0Bh, 6Bh), which we don't use. [A] p.26–28
- So the "8 Gb addressing" question is answered: each CS has one linear 4 Gb space, and no die-select bits are needed. The "1 of 4 die" select in the interrupt configuration register is only for the ECC test mode. [A] p.33 Table 26
- Host addressing in the controller: die byte address = host_addr / 2 < 2^29, so host_addr < 2^30.
- SPI mode 0 and mode 3 (mode 3 SDR only). SDR: inputs latched on the rising edge, outputs on the falling edge. [A] p.10, p.16 Table 7

### 3.2 Commands used ([A] p.37–38 Table 34, read from the rendered table)

| # | Purpose | Opcode | Forms | Addr bytes | Latency | Data bytes | Max f | Prereq |
|---|---|---|---|---|---|---|---|---|
| 2 | Write Enable (WREN) | 06h | 1-0-0, 4-0-0 | 0 | — | — | 54 MHz | |
| 3 | Write Disable | 04h | 1-0-0, 4-0-0 | 0 | — | — | 54 MHz | |
| 5 | Enable SPI (leave QPI) | FFh | 1-0-0, 4-0-0 | 0 | — | — | 54 MHz | |
| 6 | Read Status Register | 05h | 1-0-1, 4-0-4 | 0 | — | 1 | **40 MHz** | |
| 7 | Read Flag Status Register | 70h | 1-0-1, 4-0-4, 4-4-4 | — | — | 1 | 50 MHz | |
| 8 | Read Device ID | 9Fh | 1-0-1, 4-0-4 | 0 (see Q‑A1) | — | 4 | **40 MHz** | |
| 9 | Read Any Register | 65h | 1-1-1, 4-4-4 | 4 | yes (Table 33) | 1 | 54 MHz | |
| 10 | Write Status Register | 01h | 1-0-1, 4-0-4 | 0 | — | 1 | 54 MHz | WREN |
| 11 | Write Any Register | 71h | 1-1-1, 4-4-4 | 4 | — | 1 | 54 MHz | WREN |
| 19 | **Read Quad I/O (RDQI)** | **EBh** | **1-4-4**, XIP | 4 | yes (Table 31) | 1 to ∞ | 54 MHz | |
| 21 | Write Memory Array | 02h | 1-1-1, 4-4-4 | 4 | — | 1 to ∞ | 54 MHz | WREN |
| 24 | Write Quad I/O (4WQIO) | D2h | 1-4-4, XIP | 4 | — | 1 to ∞ | 54 MHz | WREN |

- **There is no software reset (66h/99h).** Rev F.2: "Hardware RESET is now supported instead of JEDEC RESET". [A] p.63
- Enable QPI = 38h (1-0-0 only). We never send it. [A] p.37
- EBh frame ([A] p.45 Fig. 19): opcode on IO0 (8 clocks), 4 address bytes on IO[3:0] (8 clocks), XIP byte (2 clocks), 8–15 latency clocks, then data. XIP byte `Axh` enables XIP and `Fxh` disables it ([A] p.16, p.40). We send `FFh`.
- D2h frame ([A] p.45 Fig. 19, "Write"): opcode, 4 address bytes, XIP byte, then input data directly (no latency).
- 1-1-1 register read 65h has no XIP byte: opcode, 4 address bytes, latency, data ([A] p.43 Fig. 17).
- A read or write continues with auto-incremented addresses as long as CS# is low and CLK runs. [A] p.40

### 3.3 Latency
- Table 31 (memory array read with XIP): 1-4-4 SDR 8–15 clocks at ≤ 54 MHz. 4-4-4 SDR 10–15 (changed from 8 in rev E.2, [A] p.63). [A] p.36
- Table 33 (Read Any Register): 1-1-1 / 1-4-4 / 4-4-4 SDR 8–15 at ≤ 54 MHz. [A] p.36
- CR2[3:0] MLATS sets the latency (0–15) for memory array read and Read Any Register. **Default 1000 = 8 clocks** ([A] p.32 Table 25; default confirmed in rev F.4, p.63).
- **For 50 MHz and also 25 MHz: MLATS = 8**, which is the default. The table only gives a range, not a value per frequency, so 8 is the minimum allowed at any frequency up to 54 MHz. For 4-4-4 (optional QPI reads) it would be 10.

### 3.4 Registers ([A] p.22 Table 13 addresses for 65h/71h)

| Register | 65h/71h address | Notes |
|---|---|---|
| Status Register (SR) | 0x00 | also via 05h/01h |
| Interrupt Status | 0x01 | |
| Configuration Register 1 (CR1) | 0x02 | |
| Configuration Register 2 (CR2) | 0x03 | MLATS |
| Interrupt Configuration | 0x04 | |
| Extended Address | 0x09 | |
| Flag Status (FSR) | 0x0A | also via 70h |
| Device Identification | 0x30 | 32 bit, also via 9Fh |

- **SR** ([A] p.24 Table 16): SR7 WP#EN (default 0), SR6 reserved, SR5 TBPSEL, SR4–2 BPSEL[2:0] (default 0 = nothing protected), SR1 WREN (read-only; set by 06h), SR0 reserved. The bit description of SR1 reads as inverted ("1: protection disabled"); it means 1 = writes enabled.
- **CR1** ([A] p.30 Table 23): CR1[7:5] ODSEL (driver strength), CR1[2] MAPLK, CR1[1:0] WRENS. WRENS default 00 = Normal: WREN is needed before every array write and is cleared at CS# high. Register writes always need WREN. ODSEL default: Table 23 says 011 (45 Ω), but rev J says "Output drive strength default value changed to C0" ([A] p.63), i.e. 110 (20 Ω). See Q‑A4.
- **CR2** ([A] p.32): MLATS[3:0], default 8.
- **FSR** ([A] p.28 Table 21): FSR[7] ST, 1 = ready, 0 = busy.
- **Device ID** ([A] p.29 Table 22): ID[31:24] = `E6h` (Avalanche), ID[23:20] = 0010 (HP Dual-Quad SPI), ID[19:16] = 0001 (3 V), ID[15:12] = 0010 (−40…125 °C), ID[11:8] = density (1000 1 Gb, 1001 2 Gb, 1010 4 Gb, 1100 8 Gb), ID[7:0] = 0000_0001 (54 MHz).
- **Volatility** of SR/CR1/CR2 (whether a write survives power-off) is not stated. See Q‑A3.
- Hardware block protect pins HBP[2:0] and HTBSEL have internal pull-downs; unconnected means no hardware protection. [A] p.12, p.23

### 3.5 Pins
- **RESET#** (ball J9): low = reset, outputs High-Z ([A] p.12). Shared by both devices. **The controller needs an output for it.** After RESET#, wait tPU before the first instruction ([A] p.19 Table 10: "VCC Power Up/RESET to First Instruction"). The minimum low pulse width is not specified (Q‑A2).
- WP1#/WP2# = IO[2]/IO[6] in single-SPI mode. **No internal pull-up, so they must be driven** ([A] p.11). IO[3]/IO[7] "can be tied to Vcc if not used". **The controller drives IO2/IO3 (and IO6/IO7) high in all 1-x-x phases where they're not used.**
- INT1#/INT2#: ECC error outputs. Not used.
- CS1#/CS2#: a 10 kΩ pull-up to VCCIO is recommended so the device isn't selected at power-up. [A] p.18
- VCCIO 1.71–3.6 V (3.3 V matches Bank1). [A] p.50

### 3.6 Timing (SDR)

| Parameter | Symbol | Value | Ref |
|---|---|---|---|
| Clock frequency | fCLK | 1 MHz min, 54 MHz max | [A] p.55 Table 44 |
| Clock high / low | tCH / tCL | ≥ 0.45 / fCLK | [A] p.55 |
| CS# high after read | tCS1 | ≥ 20 ns | [A] p.55 |
| CS# high after write (SPI / QPI) | tCS3 / tCS5 | ≥ 600 ns | [A] p.55 (raised to 600 ns in rev E.5) |
| CS# setup / hold to CLK | tCSS / tCSH | ≥ 5 ns / ≥ 4 ns | [A] p.55 |
| Data in setup / hold | tSU / tHD | ≥ 4 ns / ≥ 3 ns | [A] p.56 Table 46 |
| Output valid after CLK | tCO | ≤ 9 ns | [A] p.57 Table 48 |
| Output hold | tOH | ≥ 1 ns | [A] p.57 |
| Output disable after CS# high | tHZCS | ≤ 9 ns | [A] p.57 |
| Power-up / RESET to first instruction | tPU | ≥ 25 ms (‑A variant: ≥ 250 µs) | [A] p.19 Table 10, p.20 Table 11 |
| AC test load | CL | 30 pF | [A] p.53 Table 42 |

The 1 MHz minimum clock means that SCLK must not stop for long in the middle of a transaction. Our PHY runs SCLK without gaps while CS# is low, so this is fine.

### 3.7 Writes and busy
- WREN before each array write (WRENS = 00), and before every register write. [A] p.30, p.40
- No erase; any length; the address auto-increments. [A] p.40
- After an array write, CS# must stay high ≥ 600 ns (tCS3). [A] p.55
- The datasheet doesn't ask for busy polling anywhere. FSR.ST exists, and INT# can signal busy → ready ([A] p.28, p.33). Plan: no polling, just tCS3. See Q‑A5.
- Expected device ID per CS: `E6 21 2? 01`, where `?` is the density nibble (Q‑A1).

### 3.8 QPI recovery
- We never send 38h, so the device can't be in QPI mode because of us. After RESET# it is in its default (SPI) state. A "reset in QPI form, then SPI form" isn't needed: RESET# covers it. (For optional QPI reads, FFh in 4-0-0 form leaves QPI.)

---

## 4. Consequences for the design

Written before the HDL. Where the implementation differs (e.g. the AS308G208 registers are always written, CS# high times have one `clk_ctrl` cycle of margin and WREN gets the write time), the HDL header comments and `bringup.md` are authoritative.

1. **AS308G208 needs a RESET# output.** `qspi_init` drives it low at start, releases it, then waits tPU (25 ms). For the W25Q128JV, `qspi_init` uses 66h + 99h + 30 µs instead. The RESET# port is unused with the W25Q128JV.
2. **Per-transaction SCLK divider.** On the AS308G208, 05h and 9Fh are limited to 40 MHz. Either the PHY takes `sclk_div` per transaction (init uses 2 → 25 MHz for those commands, reads use 1 → 50 MHz), or init uses only 65h/71h (54 MHz). Recommendation: per-transaction divider, because it also helps bring-up and avoids depending on 65h's latency handling for the ID.
3. **Init per device:**
   - W25Q128JV: wait 5 ms → 66h, 99h → wait 30 µs → 9Fh compare → 05h/35h/15h: check that nothing is protected (SR1 BP/SEC/TB = 0, CMP = 0, WPS = 0) → check QE = 1 (fixed on ‑IQ, so no SR2 write; QE = 0 means a wrong part → `ERR_CFG`) → EBh test read. The status registers are never written, so init needs no BUSY polling.
   - AS308G208: RESET# pulse → wait 25 ms → 9Fh at 25 MHz, compare (per CS) → read SR/CR1/CR2 → if CR2 ≠ 0x08 or SR protects anything: 06h + 71h write, verify → EBh test read.
4. **EBh mode byte** = `FFh` for both devices. Latency: W25Q 4 fixed dummy clocks, AS MLATS = 8.
5. **Writes:** W25Q128JV: 20h sector erase + BUSY polling, then 32h (1-1-4) per page + BUSY polling. AS308G208: D2h (1-4-4) or 02h, then CS# high ≥ 600 ns.
6. **Min CS# high:** 20 ns after reads (both), 600 ns after writes (AS) / 50 ns (W25Q). Use one generic `CS_HIGH_WR_NS = 600` for both, since writes only happen in tests.
7. **IO2/IO3 (IO6/IO7) driven high in 1-1-1 phases.**
8. **Sampling window (first estimate; see `timing_budget.md`):** data from the device is valid from tCO (AS 9 ns / W25Q 6 ns) + board delay after the falling edge until the next falling edge + tOH (1 ns / 1.5 ns). At 50 MHz (20 ns period), sampling 20 ns after the launch edge (SAMPLE_DLY = 2 at 100 MHz, 4 at 200 MHz) works as long as tCO + round-trip delay + FPGA input setup ≤ 20 ns. For the AS308G208 that leaves about 11 ns, minus the FPGA input setup, for the round-trip delay (SCLK out + data back). `timing_budget.md` does this properly.

---

## 5. Open questions

For the user:
- **Q‑W1** *Answered:* the part is W25Q128JVSSIQ, so the ID is `EF 40 18` and QE is fixed at 1 (see §2.1).

For Winbond (or accept as written):
- **Q‑W2** AC table footnote 6 "4-bytes address alignment for Quad Read" ([W] p.64): does EBh need a 4-byte-aligned start address to reach the specified timing? Until clarified: **the BIST and tests use die addresses that are multiples of 4** (host addresses multiple of 8). `qspi_read_ctrl` keeps accepting any even host address.

For Avalanche (or accept the stated assumption):
- **Q‑A1** 9Fh: Table 34 says 0 address bytes, but Fig. 14 (1-0-1, [A] p.42) shows 4 address bytes. Assumption: **0** (the table, and "1-0-1" means no address). Also: does each CS of an AS308G208 report density 1100 (8 Gb, the package) or 1010 (4 Gb, its own size)? Assumption: compare only `E6 21 2` and `01`, and accept 1010 or 1100 as the density nibble.
- **Q‑A2** Minimum RESET# low pulse width. Assumption: 1 µs.
- **Q‑A3** Are SR, CR1 and CR2 volatile or non-volatile? Assumption: either; init reads them, writes only on mismatch, and verifies.
- **Q‑A4** ODSEL default: 011 (Table 23) or 110 ("C0", rev J history)? Assumption: leave at default, don't verify ODSEL.
- **Q‑A5** Is FSR polling ever needed after a write, or is tCS3 = 600 ns sufficient? Does tCS3 also apply after register writes (01h/71h)? Assumption: tCS3 after every write, no polling.
- **Q‑A6** Power-on default interface mode is SPI (not stated explicitly). Assumption: SPI.
