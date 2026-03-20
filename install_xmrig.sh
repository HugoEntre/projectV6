#!/data/data/com.termux/files/usr/bin/bash

set -Eeuo pipefail

PROJECT_DIR="$HOME/masterV6_project"
BUILD_DIR="$PROJECT_DIR/xmrig_build"
SRC_DIR="$HOME/xmrig"

mkdir -p "$BUILD_DIR"

echo "INSTALLATION XMRIG TERMUX"

pkg update -y
pkg install -y git cmake make clang openssl libuv binutils hwloc

rm -rf "$SRC_DIR"
cd "$HOME"

git clone https://github.com/xmrig/xmrig.git
cd "$SRC_DIR"

# patch sécurisé
PATCH_FILE="src/backend/cpu/platform/BasicCpuInfo_arm_unix.cpp"
[ -f "$PATCH_FILE" ] && sed -i '1i#ifndef HWCAP_AES\n#define HWCAP_AES 0\n#endif' "$PATCH_FILE"

mkdir build && cd build

cmake .. \
-DWITH_HWLOC=OFF \
-DWITH_TLS=OFF \
-DCMAKE_BUILD_TYPE=Release

make -j$(nproc)

cp xmrig "$BUILD_DIR/"
chmod +x "$BUILD_DIR/xmrig"

echo "OK -> $BUILD_DIR/xmrig"
