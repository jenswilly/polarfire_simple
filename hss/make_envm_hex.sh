#!/usr/bin/env bash
#
# Turns hss/build/hss-envm-wrapper.elf (from build_hss.sh) into the Libero
# "Boot Mode 1" eNVM client hex, hss/build/bootmode1/hss-envm-wrapper-bm1-p0.hex.
# Runs on the host: needs SoftConsole (mpfsBootmodeProgrammer, Java) and
# Libero (fpgenprog). Same step as the led_test eNVM-Scratchpad-Release
# post-build.

set -eu

SC_INSTALL_DIR=${SC_INSTALL_DIR:-$HOME/Microchip/SoftConsole-v2022.2-RISC-V-747}
FPGENPROG=${FPGENPROG:-/usr/local/microchip/Libero_SoC_2026.1/Libero_SoC/Designer/bin64/fpgenprog}
export SC_INSTALL_DIR FPGENPROG

cd "$(dirname "$0")/build"

"$SC_INSTALL_DIR/eclipse/jre/bin/java" -jar "$SC_INSTALL_DIR/extras/mpfs/mpfsBootmodeProgrammer.jar" \
    --workdir "$PWD" --die MPFS095T --package FCSG325 --bootmode 1 --dryrun \
    hss-envm-wrapper.elf

echo "Wrote $PWD/bootmode1/hss-envm-wrapper-bm1-p0.hex"
