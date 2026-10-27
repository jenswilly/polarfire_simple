#!/bin/bash
# Batch Synplify Pro run on hand-written HDL, outside the Libero project (the project isn't touched).
#   Usage: tools/syn_check.sh <top entity> <config name> [generic=value ...] [-- file ...]
#   e.g.   tools/syn_check.sh qspi_mram_ctrl as2 DEVICE=DEV_AS308G208 DIE2_PRESENT=true
#   Default sources: hdl/util_pkg.vhd, hdl/qspi_pkg.vhd and hdl/qspi_*.vhd (VHDL-2008);
#   after "--" give hdl file names (without .vhd) instead.
#   Target: PolarFire SoC MPFS095T FCSG325 -1, 200 MHz (the fabric clock; FREQ=<MHz> to change),
#   no I/O insertion (module check only; IO=1 tools/syn_check.sh ... inserts I/O buffers, e.g. for
#   a board-level wrapper).
#   Output in sim/out/syn/<config>/ (git-ignored). Prints errors, latches, multiple drivers and
#   combinational loops, then the resource summary and Synplify's estimated clock frequency (a
#   pre-P&R estimate, only a hint); exit code 1 if any of those were found.
# Needs the license server (tools/start_libero.sh starts it).

LIBERO_INSTALL_DIR="/usr/local/microchip/Libero_SoC_2026.1"
SYNPLIFY="$LIBERO_INSTALL_DIR/Libero_SoC/Synplify_Pro/bin/synplify_pro"
PORT=1702

export LM_LICENSE_FILE="$PORT@localhost"
export SNPSLMD_LICENSE_FILE="$PORT@localhost"
export SALT_LICENSE_SERVER="$PORT@localhost"

TOP="${1:?usage: $0 <top entity> <config name> [generic=value ...] [-- file ...]}"
CFG="${2:?usage: $0 <top entity> <config name> [generic=value ...] [-- file ...]}"
shift 2

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
OUT_DIR="$REPO_DIR/sim/out/syn/$CFG"

PARAMS=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    PARAMS+=("$1")
    shift
done
[ "$1" = "--" ] && shift
if [ $# -gt 0 ]; then
    FILES=()
    for f in "$@"; do FILES+=("$REPO_DIR/hdl/$f.vhd"); done
else
    FILES=("$REPO_DIR/hdl/util_pkg.vhd" "$REPO_DIR/hdl/qspi_pkg.vhd")
    for f in "$REPO_DIR"/hdl/qspi_*.vhd; do
        [ "$f" = "$REPO_DIR/hdl/qspi_pkg.vhd" ] || FILES+=("$f")
    done
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
TCL="$OUT_DIR/run.tcl"
{
    echo "project -new \"$OUT_DIR/$CFG.prj\""
    for f in "${FILES[@]}"; do echo "add_file -vhdl -lib work \"$f\""; done
    echo "set_option -technology PolarFireSoC"
    echo "set_option -part MPFS095T"
    echo "set_option -package FCSG325"
    echo "set_option -speed_grade -1"
    echo "set_option -vhdl2008 1"
    echo "set_option -top_module \"work.$TOP\""
    echo "set_option -frequency ${FREQ:-200}"
    echo "set_option -disable_io_insertion $((1 - ${IO:-0}))"
    echo "set_option -resolve_multiple_driver 0"
    for p in "${PARAMS[@]}"; do echo "set_option -hdl_param -set ${p%%=*} ${p#*=}"; done
    echo "project -result_file \"$OUT_DIR/rev/$TOP.vm\""
    echo "project -run"
    echo "project -save"
} > "$TCL"

# Run from the output directory: Synplify writes synlog.tcl into the current directory
(cd "$OUT_DIR" && "$SYNPLIFY" -batch "$TCL" > "$OUT_DIR/synplify.out" 2>&1)
SRR="$OUT_DIR/rev/$TOP.srr"
[ -f "$SRR" ] || { echo "Synthesis did not produce $SRR, see $OUT_DIR/synplify.out" >&2; exit 1; }

PROBLEMS=$(grep -E '^@E:' "$SRR"; grep -iE 'latch|multiple driver|combinational loop' "$SRR")
echo "== $TOP ($CFG${PARAMS:+: ${PARAMS[*]}}): $SRR"
if [ -n "$PROBLEMS" ]; then
    echo "$PROBLEMS"
else
    echo "No errors, latches, multiple drivers or combinational loops."
fi
grep -A25 -E '^Resource Usage Report' "$SRR" | grep -E 'SLE|Total LUTs|Total ARI1|RAM'
grep -A12 -E '^Performance Summary' "$SRR" | grep -E 'MHz' | grep -v -E '^\s*Starting'
[ -z "$PROBLEMS" ]
