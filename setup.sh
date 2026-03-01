#!/data/data/com.termux/files/usr/bin/bash

#=====================================================

#MASTER V6 - SETUP FINAL AUTO (ANDROID UNIVERSAL)

#=====================================================

set -Eeo pipefail
unset TMOUT 2>/dev/null || true

TARGET_DIR="$HOME/masterV6_project"
PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Vérification environnement Termux..."

#--- FIX REPO NON INTERACTIF ---

pkg update -y >/dev/null 2>&1 || true

#--- OUTILS DE BASE ---

pkg install -y curl coreutils rsync procps >/dev/null 2>&1 || true

echo "📂 Normalisation projet..."
# reset state seulement si flag explicite
[ "$M6_RESET_STATE" = "1" ] && rm -f "$HOME/.m6_state"
mkdir -p "$TARGET_DIR"

if [ "$SCRIPT_DIR" != "$TARGET_DIR" ]; then
rsync -a --ignore-existing "$SCRIPT_DIR"/ "$TARGET_DIR"/ 2>/dev/null || true
fi

cd "$TARGET_DIR"

#--- DEPENDANCES ---

echo "🔐 Installation dépendances..."
pkg upgrade -y >/dev/null 2>&1 || true
pkg install -y dos2unix jq util-linux termux-api git coreutils sed grep gawk inotify-tools >/dev/null 2>&1 || true

#--- INOTIFY FLAG ---

if command -v inotifywait >/dev/null 2>&1; then
echo "export M6_HAS_INOTIFY=1" > "$TARGET_DIR/.env_m6"
else
echo "export M6_HAS_INOTIFY=0" > "$TARGET_DIR/.env_m6"
fi

#--- NORMALISATION SCRIPTS ---

find . -name "*.sh" -exec dos2unix {} + 2>/dev/null || true
chmod +x *.sh 2>/dev/null || true

#--- XMRIG ---

[[ -f "$TARGET_DIR/install_xmrig.sh" ]] || { echo "❌ install_xmrig absent"; exit 1; }

echo "🛠️ Vérification XMRig..."

if [ -x "$TARGET_DIR/xmrig_build/xmrig" ] \
|| [ -x "$HOME/xmrig/build/xmrig" ]; then
    echo "✅ XMRig OK"
else
    [ -f "./functions.sh" ] && source ./functions.sh || true
    bash "$TARGET_DIR/install_xmrig.sh" || { echo "❌ Erreur install_xmrig"; exit 1; }
fi

#--- WALLET ---

WALLET_FILE="$HOME/.masterV6_wallet"
if [ ! -f "$WALLET_FILE" ]; then
echo "💎 Configuration Wallet VET"
[ -f "./functions.sh" ] && source ./functions.sh

while true; do
read -r -p "Adresse (0x...) : " RAW
CLEAN="$(printf '%s' "$RAW" | tr -d '[:space:]' | sed 's/^VET://I')"
[[ "$CLEAN" =~ ^0x[a-fA-F0-9]{40}$ ]] && { printf 'VET:%s\n' "$CLEAN" > "$WALLET_FILE"; break; }
echo "⚠️ Format invalide."
done
chmod 600 "$WALLET_FILE"
fi

echo "⚙️ Configuration système..."

# Safe bashrc pour Termux neuf
[ -f "$HOME/.bashrc" ] || touch "$HOME/.bashrc"

sed -i '/# AUTO_MASTER_V6/d' "$HOME/.bashrc"
echo "alias m6='cd ~/masterV6_project && ./start.sh' # AUTO_MASTER_V6" >> "$HOME/.bashrc"

# recharge alias immédiatement

[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc" 2>/dev/null || true
hash -r

printf "#!$PREFIX/bin/bash\ncd $TARGET_DIR && exec ./start.sh\n" > "$PREFIX/bin/m6"
chmod +x "$PREFIX/bin/m6"

#--- NETTOYAGE ---

echo "🧹 Nettoyage..."
pkill -f "xmrig" 2>/dev/null || true
rm -f "$TARGET_DIR/.masterV6.lock" 2>/dev/null || true

echo "------------------------------------"
echo "✅ MASTER V6 INSTALLATION TERMINÉE"
echo "👉 Tape simplement : m6"
echo "------------------------------------"

