# RTEMS plan

Goal: RTEMS 6.2 on U54_1 of the Discovery Kit, booted by the HSS, with the same function as the bare-metal `led_test`. Overview and build steps are in README.md ("RTEMS on U54_1 (HSS boot)").

## Done
- Devcontainer: RTEMS 6.2 toolchain (RSB), kernel source, BSP build (`post_configuration.sh`), HSS source, xPack GCC, `hss-payload-generator`, `pkg-config`.
- BSP `riscv/mpfs64imafdc` with the Discovery Kit device tree (`rtems/dts/`): console on MMUART0, 896 MB DDR.
- MSS and Libero changes for the HSS: MMUART1, MMUART4, SD card.
- HSS build (`hss/build_hss.sh`, `hss/make_envm_hex.sh`); eNVM client points at the HSS hex.
- RTEMS `led_test` (CMake via rtems-cmake), HSS payload config, `rtems/write_sd.sh`.

## Next steps
1. **Board bring-up: HSS.** Program the bitstream with the HSS in eNVM. Check the HSS console on `/dev/pfsoc-uart1`: banner, DDR training, SD card found, "no boot image".
2. **Board bring-up: RTEMS.** Write `payload.bin` to a microSD card (`sudo rtems/write_sd.sh /dev/sdX`) and boot. Check on `/dev/pfsoc-uart0`: banner, ID register `0x1ED50001`, LED counter and readback; LED2/LED3 count.
3. **CMake presets.** Add `rtems/led_test/CMakePresets.json` (CMake reads only this file name, not `CMakePresets.txt`):
   - a configure preset with the Ninja generator, `binaryDir` `${sourceDir}/build`, and the cache variables `RTEMS_PREFIX` and `RTEMS_BSP`;
   - a build preset for it;
   - check that `cmake --preset …` / `cmake --build --preset …` and VS Code CMake Tools in the devcontainer pick it up. Update the build steps in README.md.
4. **Debugging over JTAG.** Run SoftConsole's OpenOCD on the host (`microsemi-riscv.cfg`, `set DEVICE MPFS`) and connect `riscv-rtems6-gdb` from the devcontainer (`--network=host`, `target extended-remote localhost:3333`) to hart 1 after the HSS has started RTEMS. Document the steps; optionally add a VS Code launch configuration.
5. **Faster development loop.** Load `led_test.elf` with GDB into DDR instead of writing the SD card for every change (HSS boots with no or an old payload, then GDB loads and starts the new image on U54_1).
6. **Boot time (optional).** The HSS zeroes the 256 MB `.work` section at every boot. Check how long it takes (HSS log timestamps) and, if it matters, reduce `RISCV_RAM_REGION_SIZE` in `rtems/config.ini` (the work area end still comes from the device tree).
7. **Later: boot from QSPI flash.** The HSS QSPI boot service uses the MSS QSPI controller, but our W25Q128 breakout is on fabric pins driven by `qspi_board`. Options: a custom HSS boot source that reads through the fabric controller, or moving the flash to the MSS QSPI pins. Decide before starting.
8. **Docs.** Add the RTEMS/HSS facts to CLAUDE.md (build flow, UART mapping, staging limit of 4 MiB) and update `documentation/top_level.drawio` with the new MSS pads.
