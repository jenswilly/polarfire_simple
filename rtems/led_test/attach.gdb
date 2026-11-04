# Attach to RTEMS on U54_1 through OpenOCD on the host (tools/openocd_mpfs.sh).
# In the devcontainer, from rtems/led_test:
#
#   riscv-rtems6-gdb -x attach.gdb build/led_test.elf
#
# Attaching halts the hart where it is; nothing is loaded or reset. On detach
# (or quitting GDB) OpenOCD resumes the hart.

set mem inaccessible-by-default off
target extended-remote localhost:3333
