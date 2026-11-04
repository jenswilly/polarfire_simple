#!/usr/bin/env bash
#
# Writes an HSS boot image (payload.bin from hss-payload-generator) to the
# QSPI flash (Flash 6 Click, W25Q128JV, on mikroBUS) through the HSS's YMODEM
# utility on the HSS console. Runs on the host:
#
#   rtems/write_qspi.sh [payload.bin] [tty]
#
# Defaults: rtems/led_test/build/payload.bin, /dev/pfsoc-uart1 (HSS console).
# Needs sb (lrzsz). Close any terminal program on the tty first.
#
# The script resets the board over JTAG (tools/mss_reset.sh; needs JTAG free:
# no OpenOCD debug session, no Libero programming). With RESET=0 it waits for
# you to reset the board instead. It catches "Press a key to enter CLI"
# (CONFIG_SERVICE_TINYCLI_TIMEOUT, 1 s), runs TinyCLI YMODEM:
#   1 = erase (whole chip in 64 KB blocks, ~40 s typ, up to ~9 min worst case)
#   3 = receive (YMODEM from sb)
#   4 = write to QSPI
#   6 = quit
# and then BOOT, which boots from QSPI (the HSS tries QSPI before the SD card).
# The boot output is shown for BOOT_LOG_SEC seconds (default 20).
#
# Needs the HSS with our QSPI patch (hss/patches/): the stock YMODEM loader
# corrupts the image (QSPI tables and receive buffer share the start of DDR).

set -eu

die() {
    echo >&2
    echo "ERROR: $*" >&2
    exit 1
}

img=${1:-$(dirname "$0")/led_test/build/payload.bin}
tty=${2:-/dev/pfsoc-uart1}
boot_log_sec=${BOOT_LOG_SEC:-20}
do_reset=${RESET:-1}
mss_reset=$(dirname "$0")/../tools/mss_reset.sh

command -v sb >/dev/null || die "sb not found (install lrzsz)"
[ -f "$img" ] || die "image $img not found"
[ -c "$tty" ] || die "$tty is not a character device"

# Same staging limit as for the SD card: the HSS copies the image to the top
# 4 MiB of DDR before it boots it
img_size=$(stat -c %s "$img")
[ "$img_size" -lt $((4 * 1024 * 1024)) ] || die "image is $img_size bytes; the HSS staging area is 4 MiB"

if command -v fuser >/dev/null && fuser -s "$tty" 2>/dev/null; then
    die "$tty is in use (close the terminal program first)"
fi

stty -F "$tty" 115200 cs8 -cstopb -parenb -crtscts -ixon -ixoff raw -echo
exec 3<>"$tty"

# Console text read so far that hasn't been matched yet
buf=""

# expect <text> <timeout s> [failure text]: shows the console output until
# <text> arrives. Dies on timeout or when [failure text] arrives first.
expect() {
    local pattern=$1 timeout=$2 fail=${3:-} chunk
    local deadline=$((SECONDS + timeout))
    while [ "$SECONDS" -lt "$deadline" ]; do
        chunk=""
        # On timeout, read keeps the partial input in chunk
        IFS= read -r -t 0.2 -n 256 -d '' chunk <&3 || true
        if [ -n "$chunk" ]; then
            printf '%s' "$chunk"
            buf+=$chunk
        fi
        if [[ $buf == *"$pattern"* ]]; then
            buf=${buf#*"$pattern"}
            return 0
        fi
        if [ -n "$fail" ] && [[ $buf == *"$fail"* ]]; then
            die "HSS reported '$fail'"
        fi
    done
    die "timeout ($timeout s) waiting for '$pattern'"
}

send() {
    printf '%s' "$1" >&3
}

echo "Image: $img ($img_size bytes), console: $tty"
if [ "$do_reset" != 0 ]; then
    # In the background: the HSS offers the CLI for only 1 s, and OpenOCD may
    # take a while to exit after the reset drops the JTAG connection. The tty
    # is already open, so no HSS output is lost.
    echo ">>> Resetting the MSS over JTAG ..."
    "$mss_reset" &
else
    echo ">>> Reset the board now."
fi
expect "Press a key to enter CLI" 120
send " "
expect "Type HELP for list of commands" 5

send $'YMODEM\r'
expect "6. Quit" 10

echo
echo ">>> Erasing the QSPI flash (about 40 s) ..."
send "1"
expect "Erasing all of QSPI" 10 "FAILED"
expect "Success" 600 "FAILED"
expect "6. Quit" 10

send "3"
expect "CTRL-C to cancel)" 10
echo
echo ">>> Sending $img with YMODEM ..."
sb -k "$img" <&3 >&3 || die "sb failed"
expect "6. Quit" 30 "YMODEM failed"

send "4"
expect "Programming QSPI" 10 "FAILED"
expect "Success" 300 "FAILED"
expect "6. Quit" 10

send "6"
sleep 0.5
echo
echo ">>> Written. Booting (BOOT) ..."
send $'BOOT\r'
end=$((SECONDS + boot_log_sec))
while [ "$SECONDS" -lt "$end" ]; do
    chunk=""
    IFS= read -r -t 0.2 -n 256 -d '' chunk <&3 || true
    printf '%s' "$chunk"
done
echo
