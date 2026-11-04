#!/usr/bin/env bash

####################
# RTEMS BSP
####################
# Configures, builds and installs the RTEMS 6.2 BSP from the kernel source in
# the image, using the BSP options in /workspace/rtems/config.ini and the
# Discovery Kit device tree in /workspace/rtems/dts/. Run it again after
# changing config.ini or the device tree.

# Exit on error (-e), treat unset variables as errors (-u)
set -eu

# Ensure PREFIX is set (fail early if not)
: "${PREFIX:?PREFIX environment variable is not set}"

RTEMS_DIR="/opt/rtems/src/rtems"
RTEMS_CONFIG="/workspace/rtems/config.ini"

if [ ! -d "$RTEMS_DIR" ]; then
    echo "ERROR: RTEMS directory not found at $RTEMS_DIR"
    exit 1
fi

if [ ! -f "$RTEMS_CONFIG" ]; then
    echo "ERROR: BSP config not found at $RTEMS_CONFIG"
    exit 1
fi

# Device tree header for BSP_DTB_HEADER_PATH
/workspace/rtems/dts/build_dtb.sh

cd "$RTEMS_DIR"
./waf configure --prefix="$PREFIX" --rtems-config="$RTEMS_CONFIG"
./waf
./waf install
