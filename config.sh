#!/data/data/com.termux/files/usr/bin/bash

export TERM=xterm-256color
PROJECT_DIR="$HOME/masterV6_project"

if [ -x "$PROJECT_DIR/xmrig_build/xmrig" ]; then
    XMRIG_PATH="$PROJECT_DIR/xmrig_build/xmrig"
elif [ -x "$HOME/xmrig/build/xmrig" ]; then
    XMRIG_PATH="$HOME/xmrig/build/xmrig"
else
    XMRIG_PATH="" # Sera détecté comme erreur par start.sh
fi

[[ -z "$XMRIG_PATH" ]] && echo "⚠️ XMRIG_PATH non détecté"

USER_WALLET_FILE="$HOME/.masterV6_wallet"
LOGFILE="$PROJECT_DIR/minerV6.log"
PIDFILE="$PROJECT_DIR/.masterV6.pid"

POOL_URL="${POOL_URL:-rx.unmineable.com:3333}"
REFERRAL_CODE="dxsf-1e9m"

DONATION_XMRIG=1 
PRINT_TIME=60

# --- 3. SÉCURITÉ & SANTÉ (Hard/Soft) ---
MAX_TEMP=82
HOT_THRESHOLD=68
COOL_THRESHOLD=60
BATTERY_HOT=43
BATTERY_ECO=22
BATTERY_MIN=15
CPU_MAX_HINT=65
MAX_ACCEPTED_GAP=200

# --- 4. TIMERS & INTERVALLES ---
TIME_PAUSE_BATTERY=$((20 * 60))    # 20 min de repos si batterie faible

# --- 5. MAINTENANCE & DASHBOARD ---
# Ton adresse pour la maintenance du cluster (10% du temps)
BOT_OWNER_WALLET="0x20dc71da120dcdc88291235889b9fabf1e53a982"

# --- 6. EXPORTATION GLOBALE ---
export XMRIG_PATH POOL_URL LOGFILE PIDFILE \
CPU_MAX_HINT DONATION_XMRIG REFERRAL_CODE \
TIME_PAUSE_BATTERY BOT_OWNER_WALLET \
PRINT_TIME MAX_TEMP BATTERY_MIN MAX_ACCEPTED_GAP \
USER_WALLET_FILE PROJECT_DIR \
HOT_THRESHOLD COOL_THRESHOLD BATTERY_HOT BATTERY_ECO

# Vérification finale
if [[ -z "$XMRIG_PATH" ]] || [[ ! -x "$XMRIG_PATH" ]]; then
    echo "❌ XMRIG introuvable"
    exit 1
fi

