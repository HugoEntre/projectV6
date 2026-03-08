#!/data/data/com.termux/files/usr/bin/bash
# masterV6_project - Install XMRig (Android ARMv8 Optimized)

set -Eeuo pipefail

# --- CONFIGURATION ---
PROJECT_DIR="$HOME/masterV6_project"
BUILD_TARGET="$PROJECT_DIR/xmrig_build"
mkdir -p "$BUILD_TARGET"

echo "====================================="
echo "🚀 COMPILATION XMRIG MASTER V6"
echo "====================================="

# 1. NETTOYAGE & DÉPENDANCES
echo "📦 Préparation des outils..."
pkg update -y
pkg install -y git cmake make clang openssl libuv binutils -y --silent

# 2. RÉCUPÉRATION SOURCE
cd "$HOME"
rm -rf xmrig 2>/dev/null
git clone --depth 1 https://github.com/xmrig/xmrig.git
cd xmrig

# 3. OPTIMISATION DU CODE (DONATION REDUITE)
# On règle la donation xmrig interne à 1% minimum pour la santé du réseau
sed -i 's/kDefaultDonateLevel = 1/kDefaultDonateLevel = 1/g' src/donate.h
sed -i 's/kMinimumDonateLevel = 1/kMinimumDonateLevel = 1/g' src/donate.h

mkdir -p build && cd build

# 4. CONFIGURATION CMAKE (Optimisée ARM)
echo "⚙️ Configuration ARMv8 / AArch64..."
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_HWLOC=OFF \
    -DWITH_LIBCPUID=OFF \
    -DWITH_ASM=ON \
    -DWITH_ADL=OFF \
    -DWITH_NVML=OFF \
    -DWITH_CUDA=OFF \
    -DWITH_OPENCL=OFF \
    -DWITH_TLS=openssl \
    -DARM_TARGET=8

# 5. COMPILATION INTELLIGENTE
# On détecte la RAM pour éviter de faire crash le téléphone
TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
if [ "$TOTAL_RAM" -lt 1500 ]; then
    echo "⚠️ RAM faible détectée, compilation sur 1 coeur pour la stabilité..."
    THREADS=1
else
    THREADS=$(nproc)
    [ "$THREADS" -gt 4 ] && THREADS=4
fi

echo "🔨 Compilation sur $THREADS coeur(s)..."
make -j"$THREADS"

# 6. INSTALLATION FINALE
if [ -f "xmrig" ]; then
    cp xmrig "$BUILD_TARGET/xmrig"
    chmod +x "$BUILD_TARGET/xmrig"
    echo "------------------------------------"
    echo "✅ XMRIG INSTALLÉ AVEC SUCCÈS"
    echo "📍 Chemin : $BUILD_TARGET/xmrig"
    echo "------------------------------------"
else
    echo "❌ Erreur : Le binaire n'a pas été généré."
    exit 1
fi

