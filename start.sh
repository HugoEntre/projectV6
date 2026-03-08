#!/data/data/com.termux/files/usr/bin/bash
set -Eo pipefail
shopt -s lastpipe
ulimit -n 4096
ulimit -u 4096
trap '' SIGHUP

# ==================================================
# MASTER V6 - START ENGINE FINAL MOBILE STABLE
# ==================================================

# --- GUARD TTY UNIQUE ---

LOCKDIR="${TMPDIR:-$PREFIX/tmp}"
mkdir -p "$LOCKDIR"
exec 9>"$LOCKDIR/m6_start.lock"
flock -n 9 || exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDFILE="$SCRIPT_DIR/.masterV6.pid"

# --- PID LOCK ---
if [[ -f "$PIDFILE" ]]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Instance déjà active."
        exit 1
    else
        echo "⚠️ PID zombie détecté — nettoyage"
        rm -f "$PIDFILE"
    fi
fi

echo "$$" > "$PIDFILE"
export M6_START_TIME=${M6_START_TIME:-$(date +%s)}

# --- LOAD CORE ---
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/functions.sh"
trap 'echo "[ENGINE ERROR] line $LINENO command:$BASH_COMMAND $(date)" >> "$SCRIPT_DIR/engine_error.log"' ERR
export OMP_NUM_THREADS=$(nproc)
export MALLOC_ARENA_MAX=2
state_set DEVICE_ID "$(get_phone_model)"

PROFILE=$(state_get DEVICE_PROFILE_THREADS)
[[ -n "$PROFILE" ]] && echo "📊 Profil CPU appris"

[[ -x "$XMRIG_PATH" ]] || {
    echo "❌ xmrig introuvable"
    exit 1
}

[[ -z "$(state_get CPU_MAX_HINT)" ]] && state_set CPU_MAX_HINT "$CPU_MAX_HINT"
# --- OPTIMISATION PROCESS ---
renice 10 -p $$ >/dev/null 2>&1 || true
ionice -c3 -p $$ >/dev/null 2>&1 || true

# --- WAKELOCK ---
wakelock_guard() {
    command -v termux-wake-lock >/dev/null 2>&1 || return
    termux-wake-lock >/dev/null 2>&1
}

cleanup() {

    echo "🛑 Arrêt complet du cluster..."

    # empêcher boucle trap
    trap - EXIT INT TERM

    # --- STOP MINER ---
    if [[ -n "$MINER_PID" ]] && kill -0 "$MINER_PID" 2>/dev/null; then
        pkill -TERM -P "$MINER_PID" 2>/dev/null || true
        kill -TERM "$MINER_PID" 2>/dev/null || true
    fi

    # --- STOP METRICS ---
    if [[ -n "$METRICS_PID" ]] && kill -0 "$METRICS_PID" 2>/dev/null; then
        kill -TERM "$METRICS_PID" 2>/dev/null || true
    fi

    # --- attente arrêt propre ---
    sleep 2

    # --- FORCE KILL SI NECESSAIRE ---
    if [[ -n "$MINER_PID" ]] && kill -0 "$MINER_PID" 2>/dev/null; then
        pkill -KILL -P "$MINER_PID" 2>/dev/null || true
        kill -KILL "$MINER_PID" 2>/dev/null || true
    fi

    pkill -KILL -P $$ 2>/dev/null || true

    # --- CLEAN ---
    rm -f "$PIDFILE"

    command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock

    echo "✅ Cluster stoppé proprement."
    exit 0
}

trap cleanup INT TERM

# --- SERVICES ---

LAST_REFRESH=${LAST_REFRESH:-$(date +%s)}
LAST_NET=0

pkill -f metrics_loop 2>/dev/null || true

# --- START SERVICES ---
wakelock_guard
metrics_loop &
METRICS_PID=$!
MINER_PID=""

# ==================================================
# DASHBOARD UI
# ==================================================

show_stats() {

local last_ui=$(state_get UI_LAST)
local now=$(date +%s)
: "${last_ui:=0}"

(( now - last_ui < 10 )) && return 0
state_set UI_LAST "$now"

    local bat hs thr up acc raw cpu battemp
bat=$(state_get BAT_LVL)
thr=$(state_get THR)
acc=$(state_get ACC)
hs=$(state_get HS)
cpu=$(state_get CPU_TEMP)
battemp=$(state_get BAT_TEMP)
up=$(get_uptime)

    read -r raw < "$HOME/.masterV6_wallet" 2>/dev/null || true
    raw="${raw#VET:}"
    raw="${raw:-waiting}"

    # =========================
    # API UNMINEABLE SAFE
    # =========================
    local goal=50 bar="" vet_bal last_api
    now=$(date +%s)
    last_api=$(state_get API_LAST)
    vet_bal=$(state_get VET_BAL)
    : "${last_api:=0}"

    if [[ "$raw" != "waiting" ]] && (( now - last_api >= 120 )); then
        if command -v curl >/dev/null && command -v jq >/dev/null; then
            local new_bal
            new_bal=$(curl -s --max-time 3 \
                "https://api.unmineable.com/v4/address/${raw}?coin=VET" \
                | jq -r '.data.balance' 2>/dev/null)

            if [[ "$new_bal" =~ ^[0-9.]+$ ]]; then
                state_set VET_BAL "$new_bal"
                state_set API_LAST "$now"
                vet_bal="$new_bal"
            fi
        fi
    fi

    # =========================
    # BARRE OBJECTIF
    # =========================
    if [[ "$vet_bal" =~ ^[0-9.]+$ ]]; then
        local percent filled empty
        percent=$(awk -v b="$vet_bal" -v g="$goal" 'BEGIN{p=(b/g)*100; if(p>100)p=100; printf "%d",p}')
        filled=$(( percent/5 ))
        empty=$(( 20-filled ))

        local hash_bar dash_bar
        hash_bar=$(printf "%${filled}s" | tr ' ' '#')
        dash_bar=$(printf "%${empty}s" | tr ' ' '-')

        bar="[${hash_bar}${dash_bar}] ${percent}% (${vet_bal}/${goal} VET)"
    fi

    # =========================
    # UI LIVE
    # =========================

    echo -e "${WHITE}🚀 MASTER V6 LIVE CLUSTER${RESET}"
    echo -e "${CYAN}Wallet:${RESET} ${raw}"

    [[ -n "$bar" ]] \
        && echo -e "${YELLOW}🎯 ${bar}${RESET}" \
        || echo -e "${YELLOW}🎯 [--------------------] 0% (0/${goal} VET)${RESET}"

    if [[ "$battemp" =~ ^[0-9.]+$ ]] && awk "BEGIN{exit !($battemp>0)}"; then
    BAT_STR="🔋BAT:${battemp}°C"
else
    BAT_STR="🔋BAT:n/a"
fi

echo -e "${CYAN}⚡ ${hs} H/s | ✅ ${GREEN}Acc:${acc}${CYAN} | 🧵 ${thr} Thr | 🌡️ CPU:${cpu}°C ${BAT_STR} | 🔋 ${bat}% | ⏱️ ${up}${RESET}"
}

# ==================================================
# LOOP PRINCIPALE (UI + ENGINE)
# ==================================================

LAST_NET=0

set +e
while true; do

    NOW=$(date +%s)
(( NOW - ${LAST_LIGHT_CHECK:-0} < 5 )) && skip_light=1 || skip_light=0
    LAST_LIGHT_CHECK=$NOW

# --- WATCHDOG METRICS ---
if [[ -z "$METRICS_PID" ]] || ! kill -0 "$METRICS_PID" 2>/dev/null; then
    echo "⚠️ metrics_loop relancé"
    sleep 2
    metrics_loop &
    METRICS_PID=$!
fi

    # --- DASHBOARD ---
    if (( NOW - ${LAST_DASH:-0} >= 60 )); then
        LAST_DASH=$NOW
        echo "📊 TABLEAU DE BORD $(date)"
        show_stats
    fi
    
# --- CHARGE CONTROL ---
BAT_NOW=$(state_get BAT_LVL)
[[ "$BAT_NOW" =~ ^[0-9]+$ ]] && control_charge "$BAT_NOW"

    # --- SURVEILLANCE RÉSEAU ---
    if (( NOW - LAST_NET >= 120 )); then
        LAST_NET=$NOW
        if grep -qiE "net error|connection lost|timeout|failed to connect" "$LOGFILE" 2>/dev/null; then
            echo "🌐 Reconnexion réseau détectée"
        fi
    fi

# --- COMPACTAGE QUOTIDIEN ---
if (( NOW - ${LAST_COMPACT:-0} >= 86400 )); then
    echo "🗜️ Compactage STATE"

    (
        flock -x 9
        sort -u "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv -f "${STATE_FILE}.tmp" "$STATE_FILE"
    ) 9>"${STATE_FILE}.lock"

    LAST_COMPACT=$NOW
fi

    # --- PROTECTION HARD ---

if (( !skip_light )); then
    hs=$(state_get HS)
fi
: "${hs:=0}"

start_time=$(state_get MINER_START)
now=$(date +%s)

# attendre 120s après lancement miner
if [[ -n "$start_time" ]] && (( now - start_time > 180 )); then

    if awk "BEGIN{exit !($hs < 10)}"; then
        echo "⚠️ Miner freeze détecté"

        if [[ -n "$MINER_PID" ]] && kill -0 "$MINER_PID" 2>/dev/null; then
            kill -TERM "$MINER_PID"
        fi

        MINER_PID=""
    fi

fi
    
    if ! check_system_health; then
        if [[ -n "$MINER_PID" ]] && kill -0 "$MINER_PID" 2>/dev/null; then
            kill "$MINER_PID"
            MINER_PID=""
        fi
        sleep 10
        continue
    fi

# --- PAUSE SOFT ---
if thermal_pause_needed && ! thermal_hysteresis; then
    if [[ -n "$MINER_PID" ]] && kill -0 "$MINER_PID" 2>/dev/null; then
        mode=$(state_get BAT_MODE)
if [[ "$mode" == "eco" ]]; then
    echo "🔋 Pause batterie — niveau bas"
else
    echo "🌡️ Pause thermique CPU"
fi
        kill -TERM "$MINER_PID" 2>/dev/null || true
        MINER_PID=""
    fi
    sleep "${TIME_PAUSE_BATTERY:-1200}"
continue
fi

# --- LANCEMENT / SUPERVISION ---

if [[ -z "$MINER_PID" ]] || ! kill -0 "$MINER_PID" 2>/dev/null; then

    nice -n 5 bash "$SCRIPT_DIR/miner.sh" &
    MINER_PID=$!

    state_set MINER_START "$(date +%s)"

    sleep 2

fi
# --- MAINTENANCE 4H ---
if (( NOW - ${LAST_MAINT:-0} >= 14400 )); then
    echo "🧹 Maintenance légère"
    auto_update
    
    (
        flock -x 9
        grep -Ev '^TMP_' "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv -f "${STATE_FILE}.tmp" "$STATE_FILE"
    ) 9>"${STATE_FILE}.lock"

    LAST_MAINT=$NOW
fi

# --- RESET APPRENTISSAGE 14j ---
# --- RESET APPRENTISSAGE ---
if (( NOW - ${LAST_LEARN_RESET:-0} >= 1209600 )); then
    echo "🧠 Reset power curve"

    (
        flock -x 9
        grep -Ev '^(POWER_|DEVICE_PROFILE_THREADS)' "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv -f "${STATE_FILE}.tmp" "$STATE_FILE"
    ) 9>"${STATE_FILE}.lock"

    LAST_LEARN_RESET=$NOW
fi

    # --- ROTATION 24h ---
    if (( NOW - LAST_REFRESH >= 86400 )); then
        echo "🔄 Rotation du mineur"
        if [[ -n "$MINER_PID" ]] && kill -0 "$MINER_PID" 2>/dev/null; then
            kill -TERM "$MINER_PID" 2>/dev/null || true
            MINER_PID=""
        fi
        LAST_REFRESH=$NOW
        continue
    fi

    # --- MAINTENANCE LOG ---
    if [[ -f "$LOGFILE" ]] && (( $(stat -c%s "$LOGFILE") > 5000000 )); then
        tail -n 500 "$LOGFILE" > "${LOGFILE}.tmp" && mv "${LOGFILE}.tmp" "$LOGFILE"
    fi

    DELAY=$(adaptive_loop_delay)

# sécurité
[[ "$DELAY" =~ ^[0-9]+$ ]] || DELAY=15
(( DELAY < 8 )) && DELAY=8

sleep "$DELAY"

done