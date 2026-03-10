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

pkg install -y curl coreutils rsync procps --silent

echo "📂 Normalisation projet..."
# reset state seulement si flag explicite
[ "$M6_RESET_STATE" = "1" ] && rm -f "$HOME/.m6_state"
mkdir -p "$TARGET_DIR"

if [ "$SCRIPT_DIR" != "$TARGET_DIR" ]; then
rsync -a --delete "$SCRIPT_DIR"/ "$TARGET_DIR"/ 2>/dev/null || true
fi

cd "$TARGET_DIR"

#--- DEPENDANCES ---

echo "🔐 Installation dépendances..."
pkg upgrade -y -o Dpkg::Options::="--force-confold"
pkg install -y dos2unix jq util-linux termux-api git coreutils sed grep gawk inotify-tools --silent

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

echo "🛠️ Vérification XMRig..."
if [ -x "$TARGET_DIR/xmrig_build/xmrig" ] || [ -x "$HOME/xmrig/build/xmrig" ]; then
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

#--- COMMANDE GLOBALE M6 ---

echo "⚙️ Configuration système..."

BASHRC="$HOME/.bashrc"
[ -f "$BASHRC" ] || touch "$BASHRC"

sed -i '/# AUTO_MASTER_V6/d' "$BASHRC"
echo "alias m6='cd $TARGET_DIR && ./start.sh' # AUTO_MASTER_V6" >> "$BASHRC"

printf "#!$PREFIX/bin/bash\ncd $TARGET_DIR && exec ./start.sh\n" > "$PREFIX/bin/m6"
chmod +x "$PREFIX/bin/m6"

#--- NETTOYAGE ---

echo "🧹 Nettoyage..."
pkill -f "xmrig" 2>/dev/null || true
rm -f "$HOME/.masterV6.global.lock" "$TARGET_DIR/.masterV6.lock" 2>/dev/null || true

echo "------------------------------------"
echo "✅ MASTER V6 INSTALLATION TERMINÉE"
echo "👉 Tape simplement : m6"
echo "------------------------------------"

