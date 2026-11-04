# RTEMS plan

Goal: RTEMS 6.2 on U54_1 of the Discovery Kit, booted by the HSS, with the same function as the bare-metal `led_test`. Overview and build steps are in README.md ("RTEMS on U54_1 (HSS boot)").

## Done
- Devcontainer: RTEMS 6.2 toolchain (RSB), kernel source, BSP build (`post_configuration.sh`), HSS source, xPack GCC, `hss-payload-generator`, `pkg-config`.
- BSP `riscv/mpfs64imafdc` with the Discovery Kit device tree (`rtems/dts/`): console on MMUART0, 896 MB DDR.
- MSS and Libero changes for the HSS: MMUART1, MMUART4, SD card.
- HSS build (`hss/build_hss.sh`, `hss/make_envm_hex.sh`); eNVM client points at the HSS hex.
- RTEMS `led_test` (CMake via rtems-cmake), HSS payload config, `rtems/write_sd.sh`.
- **Board bring-up: HSS.** Program the bitstream with the HSS in eNVM. Check the HSS console on `/dev/pfsoc-uart1`: banner, DDR training, SD card found, "no boot image".
- **Board bring-up: RTEMS.** Write `payload.bin` to a microSD card (`sudo rtems/write_sd.sh /dev/sdX`) and boot. Check on `/dev/pfsoc-uart0`: banner, ID register `0x1ED50001`, LED counter and readback; LED2/LED3 count.
- CMake presets: `rtems/led_test/CMakePresets.json` (configure/build preset `mpfs`, Ninja, `build/`), used by the command line and VS Code CMake Tools.
- Debugging over JTAG: `tools/openocd_mpfs.sh` (host, U54_1 only), `rtems/led_test/attach.gdb` and `.vscode/launch.json` (devcontainer). Attach, breakpoints and detach/resume checked on the board. README: "Debugging RTEMS over JTAG".
- Faster development loop: `rtems/led_test/load.gdb` and the VS Code configuration "load and run U54_1" load `led_test.elf` into DDR and start it on U54_1 (checked on the board, over a running SD-booted image).
- **Boot from QSPI flash** (2026-11-04). Flash 6 Click (W25Q128JVPIQ) on mikroBUS, driven by the MSS QSPI routed through the fabric (`mss_qspi_pads`). The HSS's own QSPI boot service is used, with our driver `hss/drivers/winbond_w25q128jv/` and `hss/patches/0001-qspi-winbond-w25q128jv.patch` (driver selection plus three YMODEM loader fixes, see CLAUDE.md). Reads are 1-1-4 (6Bh) at 25 MHz after a calibration at init; on the board all sample points pass. Copying the 96 KB image takes about 13 ms. Written with `rtems/write_qspi.sh`; `tools/mss_reset.sh` resets over JTAG. Boots without the SD card, and an erased flash falls back to the SD card. Rejected alternatives: a custom HSS boot source through `qspi_board`, and the MSS QSPI pads (not wired on this board). EBh (1-4-4) isn't used, because its mode byte would come from undocumented MSS idle cycles.
- **Docs** (2026-11-04): RTEMS/HSS facts and gotchas in CLAUDE.md, "Boot from QSPI flash" in README.md, and `top_level.drawio` with `mss_qspi_pads`, the mikroBUS pins and the MSS roles.
