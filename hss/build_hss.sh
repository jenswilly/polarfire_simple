#!/usr/bin/env bash
#
# Builds the HSS (Hart Software Services) for the Discovery Kit with our MSS
# configuration. Runs in the devcontainer (HSS source in $HSS_SRC, xPack
# riscv-none-elf-gcc on the PATH).
#
# Output: hss/build/hss-envm-wrapper.elf. Turn it into the Libero eNVM client
# hex on the host with hss/make_envm_hex.sh.

set -eu

: "${HSS_SRC:?HSS_SRC environment variable is not set}"

BOARD=mpfs-disco-kit
HSS_DIR=$(cd "$(dirname "$0")" && pwd)
WORK="$HSS_DIR/build/hart-software-services"

# Build in a copy of the source; only newer files are copied, so rebuilds
# are incremental
mkdir -p "$WORK"
cp -a -u "$HSS_SRC/." "$WORK/"

# .config = board def_config with the symbols from config_overrides replaced.
# Only replaced when it changes, so make doesn't regenerate config.h for
# nothing.
overrides=$(grep -E '^CONFIG_' "$HSS_DIR/config_overrides")
keys=$(sed -E 's/=.*/=/' <<<"$overrides")
{
    grep -v -F "$keys" "$WORK/boards/$BOARD/def_config"
    echo "$overrides"
} > "$WORK/.config.new"
# Let Kconfig resolve it: the Makefiles include .config directly, so a
# disabled symbol must become "# ... is not set" (make's ifdef is true for
# "=n") and symbols whose dependencies are now off must be dropped.
(cd "$WORK" && BOARD=$BOARD OPENSBI_SRC_DIR=thirdparty/opensbi \
    KCONFIG_CONFIG=.config.new PYTHONPATH=thirdparty/Kconfiglib \
    python3 thirdparty/Kconfiglib/olddefconfig.py Kconfig >/dev/null)
if cmp -s "$WORK/.config.new" "$WORK/.config"; then
    rm "$WORK/.config.new"
else
    mv "$WORK/.config.new" "$WORK/.config"
fi

# The wrapper target also calls SoftConsole's mpfsBootmodeProgrammer, which
# isn't in the container. Its "SC_INSTALL_DIR environment variable is unset"
# and "cannot stat ...bm1-p0.hex" messages are expected and don't fail the
# build; make_envm_hex.sh does that step on the host.
#
# Two make runs: build/hss-l2scratch.bin (compressed into the wrapper) is only
# a side effect of linking hss-l2scratch.elf, with no rule of its own. In a
# single run make checks its timestamp before the relink and keeps the old
# .bin.deflate, so the wrapper would still contain the previous HSS.
make -C "$WORK" -j"$(nproc)" BOARD="$BOARD" hss-l2scratch.elf
make -C "$WORK" -j"$(nproc)" BOARD="$BOARD" hss-envm-wrapper.elf

cp "$WORK/build/hss-envm-wrapper.elf" "$HSS_DIR/build/"
echo "Wrote $HSS_DIR/build/hss-envm-wrapper.elf"
