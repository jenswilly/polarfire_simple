#!/usr/bin/env bash
#
# Builds mpfs-discovery-kit-dtb.h, the device tree header for the RTEMS BSP
# option BSP_DTB_HEADER_PATH (rtems/config.ini), from mpfs-discovery-kit.dts.
# Needs dtc and rtems-bin2c from the RTEMS toolchain (devcontainer).
# Rebuild and install the BSP afterwards (.devcontainer/scripts/post_configuration.sh).

set -eu

cd "$(dirname "$0")"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

dtc -I dts -O dtb -o "$tmp/system.dtb" mpfs-discovery-kit.dts
rtems-bin2c -C -A 8 -N system_dtb "$tmp/system.dtb" "$tmp/system_dtb"
mv "$tmp/system_dtb.c" mpfs-discovery-kit-dtb.h

echo "Wrote $(pwd)/mpfs-discovery-kit-dtb.h ($(stat -c %s "$tmp/system.dtb") byte DTB)"
