# Load led_test.elf into DDR and start it on U54_1, instead of writing the SD
# card. OpenOCD must be running (tools/openocd_mpfs.sh), and the HSS must have
# booted (DDR trained): with the old payload on the SD card, or with none, in
# which case U54_1 waits in the HSS. In the devcontainer, from rtems/led_test:
#
#   riscv-rtems6-gdb -x load.gdb build/led_test.elf
#
# The program then stops at Init; "continue" runs it. On detach (or quitting
# GDB) OpenOCD resumes the hart, so the program keeps running.
#
# _start sets gp, mtvec and sp and clears .bss itself, and the BSP uses its
# built-in device tree, so no registers need to be passed. The only state to
# reset is interrupts: the hart may be halted in a running program with
# timer/PLIC interrupts enabled, which must not fire before the new mtvec is
# set. RTEMS clears its PLIC enables and threshold during start-up.

set mem inaccessible-by-default off
target extended-remote localhost:3333

load
set $mstatus = $mstatus & ~0x8
set $mie = 0
set $pc = _start

tbreak Init
continue
