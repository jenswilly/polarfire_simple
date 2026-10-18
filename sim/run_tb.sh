#!/bin/bash
# Compile hdl/*.vhd plus one testbench and run it in Libero's QuestaSim (command line).
#   Usage: sim/run_tb.sh <testbench> [vsim args]   e.g. sim/run_tb.sh tb_axi_led_reg
#   Extra arguments go to vsim, e.g. generic overrides: sim/run_tb.sh tb_axis_spi_master -gCPHA_I=1
#   Exit code 0 if the testbench printed "TB PASSED", 1 otherwise.
# Needs the license server (tools/start_libero.sh starts it).

LIBERO_INSTALL_DIR="/usr/local/microchip/Libero_SoC_2026.1"
QUESTA="$LIBERO_INSTALL_DIR/Libero_SoC/QuestaSim_Pro/linux_x86_64"
PORT=1702

export LM_LICENSE_FILE="$PORT@localhost"
export SALT_LICENSE_SERVER="$PORT@localhost"

TB="${1:?usage: $0 <testbench, e.g. tb_axi_led_reg> [vsim args]}"
shift
SIM_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(dirname "$SIM_DIR")"
OUT_DIR="$SIM_DIR/out"   # work library, transcript and waveforms (git-ignored)

[ -f "$SIM_DIR/$TB.vhd" ] || { echo "No such testbench: sim/$TB.vhd" >&2; exit 1; }

mkdir -p "$OUT_DIR"
cd "$OUT_DIR" || exit 1

"$QUESTA/vlib" work >/dev/null || exit 1
"$QUESTA/vcom" -2008 -quiet "$REPO_DIR"/hdl/*.vhd "$SIM_DIR/$TB.vhd" || exit 1

# -wlf keeps the waveform, so it can be opened afterwards with: vsim -view sim/out/<tb>.wlf
"$QUESTA/vsim" -c -quiet -wlf "$TB.wlf" "$@" "$TB" -do "log -r /*; run -all; quit -f" | tee "$TB.log"

grep -q 'TB PASSED' "$TB.log"
