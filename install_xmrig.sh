#!/data/data/com.termux/files/usr/bin/bash
#=====================================================
# MASTER V6 - XMRIG INSTALLER PRO (ANDROID UNIVERSAL)
#=====================================================

set -Eeuo pipefail

PROJECT_DIR="$HOME/masterV6_project"
BUILD_DIR="$PROJECT_DIR/xmrig_build"
SRC_DIR="$HOME/xmrig"

mkdir -p "$BUILD_DIR"

echo "====================================="
echo "🚀 MASTER V6 - INSTALL XMRIG PRO"
echo "====================================="

# --- SYSTEM UPDATE ---
echo "[1/6] Mise à jour..."
pkg update -y
pkg upgrade -y

# --- DEPENDANCES STABLE ---
echo "[2/6] Installation dépendances..."
pkg install -y git cmake clang make libuv openssl binutils libandroid-support

# --- CLEAN ---
echo "[3/6] Nettoyage..."
rm -rf "$SRC_DIR" 2>/dev/null || true

# --- DOWNLOAD AVEC RETRY ---
echo "[4/6] Téléchargement XMRig..."

cd "$HOME"

git clone --depth 1 https://github.com/xmrig/xmrig.git || {
    echo "⚠️ Retry clone..."
    sleep 3
    git clone --depth 1 https://github.com/xmrig/xmrig.git || {
        echo "❌ Impossible de télécharger XMRig"
        exit 1
    }
}

cd "$SRC_DIR"

# --- PATCH ARM (ANDROID SAFE) ---
echo "[5/6] Patch ARM..."

PATCH_FILE="src/backend/cpu/platform/BasicCpuInfo_arm_unix.cpp"

if [ -f "$PATCH_FILE" ]; then
    sed -i '1i#ifndef HWCAP_AES\n#define HWCAP_AES 0\n#endif' "$PATCH_FILE"
fi

# --- BUILD ---
echo "[6/6] Compilation..."

mkdir -p build
cd build

cmake .. \
-DWITH_HWLOC=OFF \
-DWITH_LIBCPUID=OFF \
-DWITH_TLS=openssl \
-DWITH_CUDA=OFF \
-DWITH_OPENCL=OFF \
-DWITH_ADL=OFF \
-DWITH_NVML=OFF \
-DWITH_HTTP=OFF \
-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_C_FLAGS="-O3 -march=native" \
-DCMAKE_CXX_FLAGS="-O3 -march=native"

# --- THREAD SAFE BUILD ---
THREADS=$(nproc)
(( THREADS > 4 )) && THREADS=4

echo "🔨 Compilation avec $THREADS threads"

make -j"$THREADS" || {
    echo "❌ Build échoué"
    exit 1
}

# --- INSTALL ---
if [ -f xmrig ]; then

    cp xmrig "$BUILD_DIR/xmrig"
    chmod +x "$BUILD_DIR/xmrig"

else
    echo "❌ Binaire introuvable"
    exit 1
fi

# --- TEST ---
echo "🔍 Vérification..."

"$BUILD_DIR/xmrig" --version >/dev/null 2>&1 || {
    echo "❌ XMRig invalide"
    exit 1
}

# --- OPTIMISATION RUNTIME ---
ulimit -n 4096
ulimit -u 4096

echo "-------------------------------------"
echo "✅ XMRIG INSTALLÉ (PRO VERSION)"
echo "📍 $BUILD_DIR/xmrig"
echo "-------------------------------------"
