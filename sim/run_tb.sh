#!/bin/bash
# Compile hdl/*.vhd plus one testbench and run it in Libero's QuestaSim (command line).
#   Usage: sim/run_tb.sh <testbench> [vsim args]   e.g. sim/run_tb.sh tb_axi_sys_ctrl
#   Extra arguments go to vsim, e.g. generic overrides: sim/run_tb.sh tb_axis_spi_master -gCPHA_I=1
#   Exit code 0 if the testbench printed "TB PASSED", 1 otherwise.
# A testbench that needs Libero-generated cores names them in a header line, e.g.
#   -- run_tb cores: BLOCK_FIFO_CORE
# The HDL sources of each core are read from polarfire_simple/component/work/<core>/<core>_manifest.txt
# and compiled first (Verilog with vlog -sv, like Libero does; COREFIFO.v needs it). Libero's precompiled PolarFire primitives are always linked.
# Simulation-only models in sim/models/ are named the same way (file names without .vhd), e.g.
#   -- run_tb models: qspi_mem_model
# VHDL compile order: hdl/*_pkg.vhd first, then the other hdl files, the models and the testbench
# in dependency order (files that fail because a unit they use isn't compiled yet are retried).
# The work library is rebuilt on every run, so nothing stale from an earlier run is used.
# Needs the license server (tools/start_libero.sh starts it).

LIBERO_INSTALL_DIR="/usr/local/microchip/Libero_SoC_2026.1"
QUESTA="$LIBERO_INSTALL_DIR/Libero_SoC/QuestaSim_Pro/linux_x86_64"
PF_LIB="$LIBERO_INSTALL_DIR/Libero_SoC/Designer/lib/questasim/precompiled/vlog/polarfire"
PORT=1702

export LM_LICENSE_FILE="$PORT@localhost"
export SALT_LICENSE_SERVER="$PORT@localhost"

TB="${1:?usage: $0 <testbench, e.g. tb_axi_sys_ctrl> [vsim args]}"
shift
SIM_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(dirname "$SIM_DIR")"
OUT_DIR="$SIM_DIR/out"   # work library, transcript and waveforms (git-ignored)

[ -f "$SIM_DIR/$TB.vhd" ] || { echo "No such testbench: sim/$TB.vhd" >&2; exit 1; }

mkdir -p "$OUT_DIR"
cd "$OUT_DIR" || exit 1

rm -rf work
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

# Compile VHDL files in dependency order: compile what compiles, retry the rest until nothing
# changes. If files are left, compile them once more to show the errors.
compile_vhdl() {
    local pending=("$@") failed progress f
    while [ ${#pending[@]} -gt 0 ]; do
        failed=()
        progress=0
        for f in "${pending[@]}"; do
            if "$QUESTA/vcom" -2008 -quiet "$f" >/dev/null 2>&1; then
                progress=1
            else
                failed+=("$f")
            fi
        done
        [ $progress -eq 1 ] || { "$QUESTA/vcom" -2008 -quiet "${failed[@]}"; return 1; }
        pending=("${failed[@]}")
    done
}

MODELS=()
for MODEL in $(sed -n 's/^-- run_tb models:\(.*\)$/\1/p' "$SIM_DIR/$TB.vhd"); do
    [ -f "$SIM_DIR/models/$MODEL.vhd" ] || { echo "No such model: sim/models/$MODEL.vhd" >&2; exit 1; }
    MODELS+=("$SIM_DIR/models/$MODEL.vhd")
done

PKGS=("$REPO_DIR"/hdl/*_pkg.vhd)
[ -e "${PKGS[0]}" ] || PKGS=()
OTHERS=()
for f in "$REPO_DIR"/hdl/*.vhd; do
    [[ "$f" == *_pkg.vhd ]] || OTHERS+=("$f")
done

compile_vhdl "${PKGS[@]}" || exit 1
compile_vhdl "${OTHERS[@]}" "${MODELS[@]}" "$SIM_DIR/$TB.vhd" || exit 1

# -wlf keeps the waveform, so it can be opened afterwards with: vsim -view sim/out/<tb>.wlf
"$QUESTA/vsim" -c -quiet -t 1ps -L polarfire -wlf "$TB.wlf" "$@" "$TB" -do "log -r /*; run -all; quit -f" | tee "$TB.log"

grep -q 'TB PASSED' "$TB.log"
