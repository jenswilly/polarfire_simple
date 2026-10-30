#!/usr/bin/env bash
#
# Writes an HSS boot image (payload.bin from hss-payload-generator) to a
# microSD card for the Discovery Kit. Runs on the host, as root:
#
#   sudo rtems/write_sd.sh /dev/sdX [payload.bin]
#
# The default image is rtems/led_test/build/payload.bin.
#
# ALL DATA ON THE CARD IS LOST. The card gets a new GPT with one 32 MiB
# partition of type EF02 (GUID 21686148-6449-6E6F-744E-656564454649), which
# is the partition the HSS boots from (services/boot/gpt.c), and the image is
# written into it.

set -eu

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[ $# -ge 1 ] || die "usage: $0 /dev/sdX [payload.bin]"
dev=$1
img=${2:-$(dirname "$0")/led_test/build/payload.bin}

[ "$(id -u)" -eq 0 ] || die "must run as root (sudo)"
[ -f "$img" ] || die "image $img not found"
[ -b "$dev" ] || die "$dev is not a block device"
[ "$(lsblk -dno TYPE "$dev")" = "disk" ] || die "$dev is not a whole disk (give /dev/sdX, not a partition)"

# The HSS copies the whole image to 0x10_3FC0_0000, the top 4 MiB of DDR
# (CONFIG_SERVICE_BOOT_DDR_TARGET_ADDR), before it boots it
img_size=$(stat -c %s "$img")
[ "$img_size" -lt $((4 * 1024 * 1024)) ] || die "image is $img_size bytes; the HSS staging area is 4 MiB"

# Refuse anything that is mounted or doesn't look like an SD card
if lsblk -no MOUNTPOINTS "$dev" | grep -q .; then
    die "$dev (or one of its partitions) is mounted"
fi
dev_size=$(lsblk -dbno SIZE "$dev")
[ "$dev_size" -le $((256 * 1024 * 1024 * 1024)) ] || die "$dev is larger than 256 GB, which is unlikely to be a microSD card"

lsblk -o NAME,SIZE,TYPE,TRAN,MODEL "$dev"
echo
read -r -p "Erase $dev and write $img ($img_size bytes)? Type 'yes': " answer
[ "$answer" = "yes" ] || die "aborted"

sgdisk --zap-all "$dev" >/dev/null
sgdisk --new=1:2048:+32M --typecode=1:EF02 --change-name=1:hss-payload "$dev" >/dev/null
partprobe "$dev"
udevadm settle

# /dev/sdX1, but /dev/mmcblkNp1
part=$(lsblk -lnpo NAME,TYPE "$dev" | awk '$2 == "part" { print $1; exit }')
[ -b "$part" ] || die "partition on $dev not found"

dd if="$img" of="$part" bs=1M conv=fsync status=none
sync

echo "Wrote $img to $part"
sgdisk --info=1 "$dev" | grep -E "Partition GUID code|Partition size"
