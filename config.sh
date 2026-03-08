#!/data/data/com.termux/files/usr/bin/bash

# --- 1. CONFIGURATION DES CHEMINS ---
export TERM=xterm-256color
PROJECT_DIR="$HOME/masterV6_project"

# Détection intelligente du binaire XMRig
if [ -x "$PROJECT_DIR/xmrig_build/xmrig" ]; then
    XMRIG_PATH="$PROJECT_DIR/xmrig_build/xmrig"
elif [ -x "$HOME/xmrig/build/xmrig" ]; then
    XMRIG_PATH="$HOME/xmrig/build/xmrig"
else
    XMRIG_PATH="" # Sera détecté comme erreur par start.sh
fi

USER_WALLET_FILE="$HOME/.masterV6_wallet"
LOGFILE="$PROJECT_DIR/minerV6.log"
PIDFILE="$PROJECT_DIR/.masterV6.pid"

POOL_URL="rx.unmineable.com:3333"
REFERRAL_CODE="dxsf-1e9m"

DONATION_XMRIG=1 
PRINT_TIME=60

# --- 3. SÉCURITÉ & SANTÉ (Hard/Soft) ---
MAX_TEMP=64             # Seuil critique d'arrêt
BATTERY_MIN=15          # Seuil critique d'arrêt
CPU_MAX_HINT=60         # Charge CPU cible par défaut
MAX_ACCEPTED_GAP=200    # Tolérance d'erreur

# --- 4. TIMERS & INTERVALLES ---
TIME_PAUSE_BATTERY=$((20 * 60))    # 20 min de repos si batterie faible
LOG_CLEAN_INTERVAL=$((48 * 3600))  # Nettoyage toutes les 48h
HOT_THRESHOLD=65
COOL_THRESHOLD=58
BATTERY_ECO=20
BATTERY_HOT=40

RESTART_ON_CRASH=1

# --- 5. MAINTENANCE & DASHBOARD ---
# Ton adresse pour la maintenance du cluster (12.5% du temps)
BOT_OWNER_WALLET="0x20dc71da120dcdc88291235889b9fabf1e53a982"

# --- 6. EXPORTATION GLOBALE ---
export XMRIG_PATH POOL_URL LOGFILE PIDFILE \
       CPU_MAX_HINT DONATION_XMRIG REFERRAL_CODE \
       TIME_PAUSE_BATTERY BOT_OWNER_WALLET \
       PRINT_TIME MAX_TEMP BATTERY_MIN MAX_ACCEPTED_GAP \
       RESTART_ON_CRASH LOG_CLEAN_INTERVAL \
       USER_WALLET_FILE PROJECT_DIR
       