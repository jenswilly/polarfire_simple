#!/usr/bin/env bash
#
# Builds the HSS (Hart Software Services) for the Discovery Kit with our MSS
# configuration. Runs in the devcontainer (HSS source in $HSS_SRC, xPack
# riscv-none-elf-gcc on the PATH).
#
# Our changes to the HSS are in hss/drivers/ (extra drivers) and hss/patches/ (applied to the
# copy of the source), see below.
#
# Output: hss/build/hss-envm-wrapper.elf and, when SoftConsole and Libero are
# mounted (SC_INSTALL_DIR, FPGENPROG in devcontainer.json), the Libero eNVM
# client hex hss/build/bootmode1/hss-envm-wrapper-bm1-p0.hex via
# hss/make_envm_hex.sh.

set -eu

: "${HSS_SRC:?HSS_SRC environment variable is not set}"

BOARD=mpfs-disco-kit
HSS_DIR=$(cd "$(dirname "$0")" && pwd)
WORK="$HSS_DIR/build/hart-software-services"

# Build in a copy of the source; only newer files are copied, so rebuilds
# are incremental. --remove-destination because git's object files are
# read-only, and a new image (new clone of $HSS_SRC) makes every file newer.
mkdir -p "$WORK"
cp -a -u --remove-destination "$HSS_SRC/." "$WORK/"

# Our additions to the HSS: drivers/ is copied into baremetal/drivers/, patches/*.patch are
# applied to the copy. A patch is skipped when it is already applied (cp -u above keeps the
# patched files, because they are newer than the source; a new $HSS_SRC replaces them and
# the patch is applied again).
cp -a -u "$HSS_DIR/drivers/." "$WORK/baremetal/drivers/"
for p in "$HSS_DIR"/patches/*.patch; do
    if git -C "$WORK" apply --reverse --check "$p" 2>/dev/null; then
        continue
    fi
    git -C "$WORK" apply "$p"
    echo "Applied $(basename "$p")"
done

# .config = board def_config with the symbols from config_overrides replaced.
# Only replaced when it changes, so make doesn't regenerate config.h for
# nothing.
overrides=$(grep -E '^CONFIG_' "$HSS_DIR/config_overrides")
# Drop both forms of each overridden symbol: "CONFIG_X=..." and "# CONFIG_X is not set".
keys=$(sed -E 's/=.*/=/' <<<"$overrides")
unset_keys=$(sed -E 's/^(CONFIG_[A-Za-z0-9_]+)=.*/# \1 is not set/' <<<"$overrides")
{
    grep -v -F -e "$keys" -e "$unset_keys" "$WORK/boards/$BOARD/def_config"
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

# The wrapper target also calls SoftConsole's mpfsBootmodeProgrammer. It runs
# with SC_INSTALL_DIR unset, so its "SC_INSTALL_DIR environment variable is
# unset" and "cannot stat ...bm1-p0.hex" messages are expected and don't fail
# the build; make_envm_hex.sh does that step afterwards.
#
# Two make runs: build/hss-l2scratch.bin (compressed into the wrapper) is only
# a side effect of linking hss-l2scratch.elf, with no rule of its own. In a
# single run make checks its timestamp before the relink and keeps the old
# .bin.deflate, so the wrapper would still contain the previous HSS.
make -C "$WORK" -j"$(nproc)" BOARD="$BOARD" hss-l2scratch.elf
env -u SC_INSTALL_DIR make -C "$WORK" -j"$(nproc)" BOARD="$BOARD" hss-envm-wrapper.elf

cp "$WORK/build/hss-envm-wrapper.elf" "$HSS_DIR/build/"
echo "Wrote $HSS_DIR/build/hss-envm-wrapper.elf"

if [ -n "${SC_INSTALL_DIR:-}" ] && [ -d "$SC_INSTALL_DIR" ]; then
    "$HSS_DIR/make_envm_hex.sh"
else
    echo "SoftConsole not found (SC_INSTALL_DIR); run hss/make_envm_hex.sh on the host"
fi
