#!/usr/bin/env bash
set -euo pipefail

UBOOT_VERSION=v2026.07
TFA_VERSION=v2.14.0

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$ROOT/build
TFA=$BUILD/tf-a
UBOOT=$BUILD/u-boot

OS_NAME="$(uname -s)"

if [ "$OS_NAME" = "Darwin" ]; then
    BREW_PREFIX=$(brew --prefix 2>/dev/null || echo /opt/homebrew)
    for dir in make/libexec/gnubin gnu-sed/libexec/gnubin bison/bin flex/bin bash/bin; do
        if [ -d "$BREW_PREFIX/opt/$dir" ]; then
            export PATH="$BREW_PREFIX/opt/$dir:$PATH"
        fi
    done
fi

if command -v gmake >/dev/null 2>&1; then
    MAKE_CMD="gmake"
else
    MAKE_CMD="make"
fi

# 交叉編譯
if [ -z "${CROSS_COMPILE:-}" ]; then
    case "$OS_NAME" in
        Darwin)
            if command -v aarch64-none-elf-gcc >/dev/null 2>&1; then
                CROSS_COMPILE="aarch64-none-elf-"
            elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
                CROSS_COMPILE="aarch64-linux-gnu-"
            else
                CROSS_COMPILE="aarch64-none-elf-"
            fi
            ;;
        Linux)
            if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
                CROSS_COMPILE="aarch64-linux-gnu-"
            elif command -v aarch64-none-elf-gcc >/dev/null 2>&1; then
                CROSS_COMPILE="aarch64-none-elf-"
            else
                CROSS_COMPILE="aarch64-linux-gnu-"
            fi
            ;;
        *)
            CROSS_COMPILE="aarch64-linux-gnu-"
            ;;
    esac
fi

# 取得 CPU 核心數量以加速編譯速度
if command -v nproc >/dev/null 2>&1; then
    JOBS=$(nproc)
elif [ "$OS_NAME" = "Darwin" ]; then
    JOBS=$(sysctl -n hw.ncpu)
else
    JOBS=4
fi

# 檢查環境
DEPS="git $MAKE_CMD ${CROSS_COMPILE}gcc bison flex swig"
# TF-A 需要 GNU sed，U-Boot 的 scripts 需要 bash >= 4.2
[ "$OS_NAME" = "Darwin" ] && DEPS="$DEPS gsed"
if ! bash -c 'shopt -s lastpipe' 2>/dev/null; then
    DEPS="$DEPS bash>=4.2"
fi
for cmd in $DEPS; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: missing '$cmd'." >&2
        if [ "$OS_NAME" = "Darwin" ]; then
            echo "Install build dependencies on macOS via Homebrew:" >&2
            echo "  brew install make gnu-sed bash bison flex swig python3 openssl gnutls" >&2
            echo "  brew install --cask gcc-aarch64-embedded" >&2
        else
            echo "Install build dependencies on Linux via apt:" >&2
            echo "  sudo apt install gcc-aarch64-linux-gnu bison flex swig python3-dev \\" >&2
            echo "    python3-setuptools python3-pyelftools libssl-dev libgnutls28-dev uuid-dev make" >&2
        fi
        exit 1
    fi
done

# 下載 source code
mkdir -p "$BUILD"
[ -d "$TFA" ]   || git clone --depth 1 --branch "$TFA_VERSION" \
    https://github.com/ARM-software/arm-trusted-firmware.git "$TFA"
[ -d "$UBOOT" ] || git clone --depth 1 --branch "$UBOOT_VERSION" \
    https://github.com/u-boot/u-boot.git "$UBOOT"

# 編譯 TF-A BL31
"$MAKE_CMD" -C "$TFA" -j"$JOBS" CROSS_COMPILE="$CROSS_COMPILE" PLAT=sun50i_h616 DEBUG=0 bl31

HOST_CFLAGS="-DPyString_FromString=PyUnicode_FromString -DPyInt_AsLong=PyLong_AsLong"
HOST_LDFLAGS=""

if [ "$OS_NAME" = "Darwin" ]; then
    OPENSSL_PREFIX="$BREW_PREFIX/opt/openssl@3"
    HOST_CFLAGS="$HOST_CFLAGS -I$OPENSSL_PREFIX/include -I$BREW_PREFIX/include"
    HOST_LDFLAGS="-L$OPENSSL_PREFIX/lib -L$BREW_PREFIX/lib -Wl,-undefined,dynamic_lookup"
fi

# 編譯 U-Boot
"$MAKE_CMD" -C "$UBOOT" CROSS_COMPILE="$CROSS_COMPILE" orangepi_zero3_defconfig
"$MAKE_CMD" -C "$UBOOT" -j"$JOBS" CROSS_COMPILE="$CROSS_COMPILE" \
    HOSTCFLAGS="$HOST_CFLAGS" HOSTLDFLAGS="$HOST_LDFLAGS" \
    BL31="$TFA/build/sun50i_h616/release/bl31.bin" SCP=/dev/null

echo
echo "done: $UBOOT/u-boot-sunxi-with-spl.bin"