#!/usr/bin/env bash
#
# Resets the PolarFire SoC MSS over JTAG (the board has no reset button, and a
# power cycle makes the FTDI UARTs disappear). Same reset as the HSS's own
# reboot (services/reboot/reboot_service.c): writes 0xDEAD to
# SYSREG->MSS_RESET_CR at 0x2000_2018 ("full MSS reset", mss_sysreg.h). All
# harts restart and the HSS boots from eNVM again. The fabric is not
# reprogrammed.
#
#   tools/mss_reset.sh
#
# Runs on the host or in the devcontainer (SC_INSTALL_DIR as in
# openocd_mpfs.sh). Needs JTAG: fails if OpenOCD (a debug session) or Libero
# programming is using it.

set -eu

SC_INSTALL_DIR=${SC_INSTALL_DIR:-$HOME/Microchip/SoftConsole-v2022.2-RISC-V-747}
OPENOCD=$SC_INSTALL_DIR/openocd/bin/openocd

if pgrep -x openocd >/dev/null; then
    echo "OpenOCD is already running (stop the debug session first):" >&2
    pgrep -a openocd >&2
    exit 1
fi

# Through U54_1 (COREID 1), so the E51 running the HSS isn't halted first.
# The memory write needs a halted hart.
#
# The write resets the MSS, including the debug module, so OpenOCD's mww never
# gets its completion: it retries DMI accesses for about 15 s (measured with
# "riscv set_command_timeout_sec 1") and ignores SIGINT meanwhile. The write
# itself takes effect within milliseconds. So OpenOCD prints a marker just
# before mww; once that appears, the script waits a moment and stops OpenOCD.
log=$(mktemp)
trap 'rm -f "$log"' EXIT

"$OPENOCD" \
    --search "$SC_INSTALL_DIR/openocd/share/openocd/scripts" \
    --command "set DEVICE MPFS" \
    --command "set COREID 1" \
    --file board/microsemi-riscv.cfg \
    --command "riscv set_command_timeout_sec 1" \
    --command "init" \
    --command "halt" \
    --command "echo MSS_RESET_WRITE" \
    --command "catch {mww 0x20002018 0xDEAD}" \
    --command "shutdown" >"$log" 2>&1 &
ocd=$!

written=0
for _ in $(seq 100); do                 # Up to 10 s for connect + halt
    if grep -q MSS_RESET_WRITE "$log"; then
        written=1
        break
    fi
    kill -0 "$ocd" 2>/dev/null || break # OpenOCD ended early (error)
    sleep 0.1
done
[ "$written" = 1 ] && sleep 0.5         # Let the mww reach the target

kill -INT "$ocd" 2>/dev/null || true
sleep 0.3
kill -KILL "$ocd" 2>/dev/null || true
wait "$ocd" 2>/dev/null || true

if [ "$written" = 1 ]; then
    echo "MSS reset requested (SYSREG MSS_RESET_CR = 0xDEAD)"
else
    echo "ERROR: OpenOCD didn't get to the reset write. Its output:" >&2
    cat "$log" >&2
    exit 1
fi
