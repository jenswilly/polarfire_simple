#!/usr/bin/env bash
#
# Starts SoftConsole's OpenOCD as a GDB server for one PolarFire SoC hart, on
# the host (it needs the board's FlashPro5 JTAG, interface 0):
#
#   tools/openocd_mpfs.sh [HART]
#
# HART is 0 (E51) .. 4 (U54_4); default 1 = U54_1, where RTEMS runs.
# GDB port 3333, telnet 4444. The devcontainer uses --network=host, so
# riscv-rtems6-gdb there connects with "target extended-remote localhost:3333".
#
# One hart only (COREID): with the default COREID -1 all five harts are one
# SMP target, and halting it would also stop the E51 running the HSS.
# Only one tool at a time can use JTAG: stop this before programming in Libero.

set -eu

hart=${1:-1}
[[ $hart =~ ^[0-4]$ ]] || { echo "usage: $0 [HART 0-4]" >&2; exit 1; }

SC_INSTALL_DIR=${SC_INSTALL_DIR:-$HOME/Microchip/SoftConsole-v2022.2-RISC-V-747}
OPENOCD=$SC_INSTALL_DIR/openocd/bin/openocd

if pgrep -x openocd >/dev/null; then
    echo "OpenOCD is already running:" >&2
    pgrep -a openocd >&2
    exit 1
fi

exec "$OPENOCD" \
    --search "$SC_INSTALL_DIR/openocd/share/openocd/scripts" \
    --command "set DEVICE MPFS" \
    --command "set COREID $hart" \
    --file board/microsemi-riscv.cfg
