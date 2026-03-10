#!/data/data/com.termux/files/usr/bin/bash
# MASTER V6 - INSTALL XMRIG (ANDROID TERMUX STABLE)

set -Eeuo pipefail

PROJECT_DIR="$HOME/masterV6_project"
BUILD_DIR="$PROJECT_DIR/xmrig_build"
SRC_DIR="$HOME/xmrig"

mkdir -p "$BUILD_DIR"

echo "====================================="
echo "MASTER V6 - INSTALLATION XMRIG"
echo "====================================="

# --- DEPENDANCES ---

echo "📦 Installation dépendances..."
pkg update -y
pkg install -y git cmake make clang openssl libuv binutils hwloc --silent

# --- CLEAN BUILD ---

echo "🧹 Nettoyage ancien build..."
rm -rf "$SRC_DIR" 2>/dev/null || true

# --- CLONE XMRIG ---

echo "⬇️ Téléchargement source XMRig..."
cd "$HOME"
git clone --depth 1 https://github.com/xmrig/xmrig.git
cd "$SRC_DIR"

# --- PATCH ANDROID TERMUX ---

echo "🔧 Patch compatibilité Android..."
sed -i '1i#ifndef HWCAP_AES\n#define HWCAP_AES 0\n#endif' \
src/backend/cpu/platform/BasicCpuInfo_arm_unix.cpp

# --- DONATION MINIMALE ---

sed -i 's/kDefaultDonateLevel = 1/kDefaultDonateLevel = 1/g' src/donate.h
sed -i 's/kMinimumDonateLevel = 1/kMinimumDonateLevel = 1/g' src/donate.h

# --- BUILD DIRECTORY ---

mkdir -p build
cd build

# --- CONFIGURATION CMAKE ---

echo "⚙️ Configuration compilation..."

cmake .. \
-DWITH_HWLOC=OFF \
-DWITH_LIBCPUID=OFF \
-DWITH_TLS=openssl \
-DWITH_CUDA=OFF \
-DWITH_OPENCL=OFF \
-DWITH_ADL=OFF \
-DWITH_NVML=OFF \
-DARM_TARGET=8 \
-DCMAKE_BUILD_TYPE=Release

# --- DETECTION RAM ---

TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')

if [ "$TOTAL_RAM" -lt 1500 ]; then
THREADS=1
elif [ "$TOTAL_RAM" -lt 3000 ]; then
THREADS=2
else
THREADS=3
fi

echo "🔨 Compilation sur $THREADS thread(s)..."

# --- COMPILATION ---

make -j"$THREADS"

# --- INSTALLATION ---

if [ -f xmrig ]; then

cp xmrig "$BUILD_DIR/xmrig"
chmod +x "$BUILD_DIR/xmrig"

echo "------------------------------------"
echo "XMRIG INSTALLE"
echo "Binaire : $BUILD_DIR/xmrig"
echo "------------------------------------"

else
echo "ERREUR: compilation xmrig echouee"
exit 1
fi