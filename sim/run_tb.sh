#!/bin/bash
# Compile hdl/*.vhd plus one testbench and run it in Libero's QuestaSim (command line).
#   Usage: sim/run_tb.sh <testbench> [vsim args]   e.g. sim/run_tb.sh tb_axi_led_reg
#   Extra arguments go to vsim, e.g. generic overrides: sim/run_tb.sh tb_axis_spi_master -gCPHA_I=1
#   Exit code 0 if the testbench printed "TB PASSED", 1 otherwise.
# A testbench that needs Libero-generated cores names them in a header line, e.g.
#   -- run_tb cores: BLOCK_FIFO_CORE
# The HDL sources of each core are read from polarfire_simple/component/work/<core>/<core>_manifest.txt
# and compiled first (Verilog with vlog -sv, like Libero does; COREFIFO.v needs it). Libero's precompiled PolarFire primitives are always linked.
# Needs the license server (tools/start_libero.sh starts it).

LIBERO_INSTALL_DIR="/usr/local/microchip/Libero_SoC_2026.1"
QUESTA="$LIBERO_INSTALL_DIR/Libero_SoC/QuestaSim_Pro/linux_x86_64"
PF_LIB="$LIBERO_INSTALL_DIR/Libero_SoC/Designer/lib/questasim/precompiled/vlog/polarfire"
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
"$QUESTA/vmap" polarfire "$PF_LIB" >/dev/null || exit 1

# Libero cores listed in the testbench header
for CORE in $(sed -n 's/^-- run_tb cores:\(.*\)$/\1/p' "$SIM_DIR/$TB.vhd"); do
    MANIFEST="$REPO_DIR/polarfire_simple/component/work/$CORE/${CORE}_manifest.txt"
    [ -f "$MANIFEST" ] || { echo "No manifest for core $CORE: $MANIFEST (generate the core in Libero)" >&2; exit 1; }
    # The section "HDL source files for all Synthesis and Simulation tools:" ends at the first blank line
    SRCS=$(sed -n '/^HDL source files/,/^$/{/^ /p}' "$MANIFEST")
    VLOG_SRCS=$(echo "$SRCS" | grep -E '\.s?v$')
    VHDL_SRCS=$(echo "$SRCS" | grep -E '\.vhdl?$')
    [ -n "$VLOG_SRCS" ] && { "$QUESTA/vlog" -sv -quiet -L polarfire $VLOG_SRCS || exit 1; }
    [ -n "$VHDL_SRCS" ] && { "$QUESTA/vcom" -2008 -quiet $VHDL_SRCS || exit 1; }
done

"$QUESTA/vcom" -2008 -quiet "$REPO_DIR"/hdl/*.vhd "$SIM_DIR/$TB.vhd" || exit 1

# -wlf keeps the waveform, so it can be opened afterwards with: vsim -view sim/out/<tb>.wlf
"$QUESTA/vsim" -c -quiet -t 1ps -L polarfire -wlf "$TB.wlf" "$@" "$TB" -do "log -r /*; run -all; quit -f" | tee "$TB.log"

grep -q 'TB PASSED' "$TB.log"
