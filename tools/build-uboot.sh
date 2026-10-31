#!/usr/bin/env bash
set -euo pipefail

UBOOT_VERSION=v2026.07
TFA_VERSION=v2.14.0
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
JOBS=$(nproc)

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$ROOT/build
TFA=$BUILD/tf-a
UBOOT=$BUILD/u-boot

for cmd in git make "${CROSS_COMPILE}gcc" bison flex swig; do
    if ! command -v "$cmd" >/dev/null; then
        echo "error: missing '$cmd'. Install the build dependencies with:" >&2
        echo "  sudo apt install gcc-aarch64-linux-gnu bison flex swig python3-dev \\" >&2
        echo "    python3-setuptools python3-pyelftools libssl-dev libgnutls28-dev uuid-dev" >&2
        exit 1
    fi
done

mkdir -p "$BUILD"
[ -d "$TFA" ]   || git clone --depth 1 --branch "$TFA_VERSION" \
    https://github.com/ARM-software/arm-trusted-firmware.git "$TFA"
[ -d "$UBOOT" ] || git clone --depth 1 --branch "$UBOOT_VERSION" \
    https://github.com/u-boot/u-boot.git "$UBOOT"

make -C "$TFA" -j"$JOBS" CROSS_COMPILE="$CROSS_COMPILE" PLAT=sun50i_h616 DEBUG=0 bl31

make -C "$UBOOT" CROSS_COMPILE="$CROSS_COMPILE" orangepi_zero3_defconfig
make -C "$UBOOT" -j"$JOBS" CROSS_COMPILE="$CROSS_COMPILE" \
    BL31="$TFA/build/sun50i_h616/release/bl31.bin" SCP=/dev/null

echo
echo "done: $UBOOT/u-boot-sunxi-with-spl.bin"
