# Plan: one AS308G208 for both the fabric LUT and the System Controller SPI flash

## Description
Today the AS308G208 is planned as a dual-die lockstep LUT memory for the fabric (`qspi_mram_ctrl`). A separate SST26 QSPI flash holds the firmware (`concept.md`). To save cost, the proposal splits the AS308:
- **Device 1** (CS1#/CLK1/IO[3:0]): fabric-only LUT memory, 512 MB.
- **Device 2** (CS2#/CLK2/IO[7:4]): single SPI on the System Controller's dedicated SPI pins (SC_SPI), MSS only. It holds the U54 payloads (A/B), the update staging area, settings and the FPGA update image for IAP.

Your answers: LUT data is now small and preloadable, so the halved read bandwidth doesn't matter (286 µs instead of 145 µs for 8 × 880 B). One staging image is needed, maybe also a golden image. The PCB is still open. A separate SC flash is acceptable if the split isn't feasible. Keep HSS changes small; patches are allowed.

## Verdict
**Possible, but one open question decides it (B1): can the System Controller read the AS308 at all?** Datasheet evidence suggests it can't without help. Ask Avalanche and Microchip before the PCB is committed. If the answer is no, use the fallback below. Everything else is solvable, with constraints.

## Facts found (sources)
[P] = PolarFire FPGA & PolarFire SoC Programming UG DS50003191L (2026). [A] = AS308G208 datasheet rev J.1.
- The SC reads the SPI flash in **mode 3 at a fixed 20 MHz** ([P] §3.4.1.1). The AS308 supports mode 3 in SDR ([A] p.10). ✔
- The SC sends **SFDP (5Ah)** to detect 3- or 4-byte addressing, then reads with **0Bh fast read** ([P] §11.1). The AS308 has **no 5Ah** ([A] Table 34). Non-JESD216 devices "may still be used if they support 0BH with 3-byte addressing. Such devices are limited to the first 128 Mb" ([P] §11.1, worded for RT PolarFire). So **only the first 16 MB is reachable by the SC** (SPI copy, IAP, auto update, SPI directory).
- The AS308 0Bh is 3-byte since rev E.2 ([A] p.62), "for legacy boot on Xilinx" (Table 34 note 5). **But** its 1-1-1 frame with XIP is opcode + address + **XIP byte (8 clocks) + 8–15 latency clocks** ([A] p.43 Fig. 16, Table 31), while a standard 0Bh has 8 dummy clocks. → **B1**.
- The SC hands SC_SPI to the fabric/MSS after power-up. User logic reaches the pins through the **PF_SPI** macro, and any system service request takes the SPI back ([P] §3.3.1 note 1, §11.3.5). It is single-SPI only (SCK/SS/SDI/SDO).
- Straps: SPI_EN = 1 and IO_CFG_INTF = 1 (master) at power-up are required for IAP and auto update ([P] Table 3-7). The pins are powered from VDDI3.
- **SPI copy** (MSS → SC service 50h) is read-only. FlashPro6/Libero can program only listed flash parts, so the AS308 must be written from the MSS ([P] §11.1, §11.3.4).
- SPI image size: **MPFS160T 6605 KB, RTPFS160ZT 6596 KB** ([P] Tables 1-5, 1-9). The SPI directory is 1 KB at address 0. The IAP-recovery rule: pointer at address 4 null → image 0 ([P] §11.2).
- **HSS (local source, v2026.04.1):**
  - `CONFIG_SERVICE_SPI` boots one payload through `MSS_SYS_spi_copy` at `CONFIG_SERVICE_BOOT_SPI_FLASH_OFFSET` (default 0x400, which clashes with the bitstream). Code: `init/hss_boot_init.c` `getBootImageFromSpiFlash_`.
  - There is no A/B and no SPI write path.
  - `CONFIG_COLDREBOOT_TRY_AUTO_UPDATE` (`services/reboot/reboot_service.c`) authenticates image index 1 and runs auto update on cold reboot.
- Both AS308 devices share **one RESET# (J9)** and **one VCCIO** ([A] pin table). Our `qspi_init` pulses RESET# and then waits tPU = 25 ms (`device_facts.md` §3.5).
- The Discovery Kit's SC_SPI pins only have 10 k tie-offs and no flash on them (schematic, "JTAG/SC-SPI interface"). **The SC path can't be tested on our current board.**

## Blockers and risks
- **B1 (decides feasibility): SC read compatibility.** We have to confirm that the SC's `5Ah` (unsupported) is harmless and that the AS308 answers the SC's `0Bh` (3-byte, 8 dummy clocks) with data from the right cycle. Per Fig. 16 the data comes ≥ 8 clocks later than the SC expects. Ask Avalanche whether 0Bh has a no-XIP form, whether MLATS can be < 8 for 0Bh at 20 MHz, and what "legacy boot on Xilinx" means. Ask Microchip for the exact SC frame (dummy count, mode bits, any 66h/99h/B7h/ABh). If B1 fails, SPI-copy boot, IAP and auto update can't use the AS308.
- **R1: the 16 MB SC window.** Directory (1 KB) + one staging image (≈ 6.6 MB, reserve 7 MB) + payloads A and B (2 × 4 MiB, HSS staging limit) + boot control and settings (1 MB) ≈ 16 MB. **That's full, and a golden image doesn't fit.** A golden image means moving the payloads above 16 MB. The HSS then can't use SPI copy for them and needs an MSS → fabric → PF_SPI read driver (a larger HSS patch). The AS308 extended address register only shifts the window for 3-byte commands, and its volatility isn't known (Q‑A3). Not recommended.
- **R2: shared RESET#.** A fabric RESET# pulse also resets device 2, for example during an MSS write or an SC read. Proposal: the fabric never drives RESET#. Use a board power-on reset with a pull-up instead. Then remove the AS308 RESET# pulse from `qspi_init` and rely on tPU after power-up. Without a soft reset (none exists on the AS308), a hung device then needs a power cycle. If the fabric must keep RESET#, it needs a strong external pull-up so it doesn't float while IAP reprograms the fabric (I/Os tristated), plus a fabric↔MSS handshake.
- **R3: power-up timing.** tPU is 25 ms (the ‑A variant needs only 250 µs). If the SC reads the flash at power-up for auto update or IAP recovery, that may happen before the AS308 is ready. Proposal: disable power-up auto update and use IAP or auto update triggered by software (HSS cold reboot or the app). Find out from Microchip when the SC first touches SC_SPI after power-up. Consider ordering the ‑A variant.
- **R4: SC vs MSS bus ownership.** While the MSS drives PF_SPI, an SC service (SPI copy, IAP, image authentication) takes the bus away. All software must serialise access: one owner (RTEMS) for writes, and none while the HSS boots or a system service runs.
- **R5: IAP without a golden image.** After a failed IAP, recovery tries image 0, which is the staging image itself. Always authenticate first (`MSS_SYS_authenticate_iap_image`, as the HSS does). Accept that a bad image + power loss → JTAG recovery. Check with the mission whether that is acceptable.
- **R6: CR2/latency ownership.** If 0Bh compatibility depends on the CR2 MLATS value of device 2, nobody else may change device 2's CR2. `qspi_init` only touches device 1 after the split, which is good.
- **R7: HSS integrity check.** The HSS checks only the payload header CRC. The A/B selection needs a full-image CRC, either in a small HSS patch or as a "verified" flag written by the app after it checks the CRC.
- **R8: power loss during writes.** MRAM has no erase and is byte-writable. A torn write affects only the bytes in flight. Settings use two copies with a sequence number and CRC. Boot control is written last, as a single small record.
- **R9: RT part.** The RT PolarFire SoC follows the same rules (non-JESD216 devices: 0Bh, first 128 Mb). Confirm IAP/auto update support and the PF_SPI handover on the RTPFS160ZT with Microchip.
- Minor: VCCIO, VDDI3 and the fabric bank of device 1 must all be the same voltage (3.3 V recommended). WP2#/IO6 must be driven (pull-up), and IO7 can be tied high ([A] p.11). Add a 10 k pull-up on CS2# ([A] p.18). The SC_SPI SS pin is active low.

## Fallback (if B1 fails)
Keep the AS308 split (device 2 for MSS data through MSS QSPI → fabric pins, using the HSS QSPI service with a new AS308 driver, as we do now with the W25Q128JV). Add a **small SFDP-compliant SPI NOR on SC_SPI** only for the directory and the staging bitstream: ≥ 8 MB, e.g. the SST26L064-RT from `concept.md`, which fits a directory plus one 6.6 MB image. With a golden image it needs ≥ 16 MB.

## Proposed flash layout for device 2 (staging image only, all SC-read data < 16 MB)
| Range | Content | Read by |
|---|---|---|
| 0x000000–0x0003FF | SPI directory (image 0 → 0x400, address 4 null) | SC |
| 0x000400–0x6FFFFF | FPGA staging image (≤ 7 MB) | SC (IAP) |
| 0x700000–0xAFFFFF | U54 payload A (< 4 MiB) | HSS via SPI copy |
| 0xB00000–0xEFFFFF | U54 payload B (< 4 MiB) | HSS via SPI copy |
| 0xF00000–0xFFFFFF | Boot control record + settings (2 copies) | HSS, RTEMS |
| 0x1000000–0x1FFFFFFF | Incoming update data, logs, etc. (496 MB) | RTEMS only |

## Plan steps
**Phase 0: settle B1 before the PCB is committed**
1. Questions to Avalanche (0Bh frame/XIP/latency for 3-byte legacy boot, 5Ah response, RESET# min width Q‑A2, register volatility Q‑A3) and to Microchip (exact SC read frame, power-up timing, PF_SPI on RTPFS160ZT).
2. Add the programming UG to `documentation/` (LFS). Record the SC facts in `device_facts.md` (new section, with page references).
3. If possible, test on hardware: put an AS308 eval board (or the target PCB's first spin) on SC_SPI with straps SPI_EN = IO_CFG_INTF = 1. Run SPI copy and `MSS_SYS_authenticate_iap_image` against a known image.

**Phase 1: PCB**
4. Pinout: device 1 on fabric pins (IO3:0, CS1#, CLK1). Device 2 on SC_SPI (SCK → CLK2, SS → CS2#, SDO → IO4/SI, SDI ← IO5/SO). Pull-ups on IO6/IO7 and CS2#. RESET# from a POR supervisor (R2). Straps SPI_EN/IO_CFG_INTF = 1. VCCIO = VDDI3 = 3.3 V.

**Phase 2: FPGA**
5. Single-die `qspi_board`/`qspi_mram_ctrl` config (`DEVICE = DEV_AS308G208`; done 2026-11-12: the controller is single-die only, `DIE2_PRESENT` was removed) with no RESET# pulse. Make RESET# optional in `qspi_init` (generic) and extend `tb_qspi_init`.
6. Add PF_SPI and route the MSS QSPI in fabric mode (normal SPI) to it. This replaces/extends `hdl/mss_qspi_pads.vhd`, with a new `mss_sc_spi_pads` mapping the QSPI DATA0/1 to SDO/SDI. Update SmartDesign, `TOP.vhd` and the diagrams.

**Phase 3: HSS (small patch set in `hss/patches/`)**
7. Enable `CONFIG_SERVICE_SPI`. Patch `getBootImageFromSpiFlash_` to read the boot control record and try payload A/B (fallback to the other on header/CRC failure), with an optional full-image CRC (R7).
8. Disable power-up auto update. Use `CONFIG_COLDREBOOT_TRY_AUTO_UPDATE` (image index 1 → adjust the directory) or IAP from the app (decide which).
9. Initial flash programming: an HSS or RTEMS YMODEM path that writes device 2 through PF_SPI, replacing `rtems/write_qspi.sh` for the target. FlashPro can't program the AS308.

**Phase 4: RTEMS on U54**
10. AS308 single-SPI driver over the MSS QSPI (WREN + 02h write, 03h/13h read with 4-byte addresses, tCS3 600 ns), with a lock for bus ownership (R4).
11. Firmware update: receive to 0x1000000+, check the CRC, copy to the inactive payload slot, verify, then switch the boot control record.
12. Settings store (two copies + CRC + sequence number).
13. Bitstream update: receive → write the staging image + directory → `MSS_SYS_authenticate_iap_image` → `MSS_SYS_execute_iap` (program by address or index). Make sure the SC owns the bus.
