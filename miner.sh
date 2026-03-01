#!/data/data/com.termux/files/usr/bin/bash
# masterV6_project - Miner Engine V6.14 STABLE ANDROID

set -Eo pipefail

# --- 1. CHARGEMENT & SECURITE ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/config.sh" ] && source "$SCRIPT_DIR/config.sh"
[ -f "$SCRIPT_DIR/functions.sh" ] && source "$SCRIPT_DIR/functions.sh"

command -v get_threads >/dev/null || { echo "❌ functions.sh invalide"; exit 1; }

cleanup() {
    echo -e "\n🛑 Arrêt du moteur de minage..."
    pkill -P $$ 2>/dev/null || true
}
trap cleanup EXIT SIGINT SIGTERM SIGHUP

# --- WALLET ---
WALLET_FILE="$HOME/.masterV6_wallet"
[ -f "$WALLET_FILE" ] || { echo "❌ Fichier Wallet absent"; exit 1; }

RAW_WALLET=$(cat "$WALLET_FILE")
MY_WALLET=$(normalize_wallet "$RAW_WALLET") || { echo "❌ Wallet invalide"; exit 1; }

# ==================================================
# MOTEUR DE MINAGE
# ==================================================
mine_engine() {

LOCKDIR="${TMPDIR:-$PREFIX/tmp}"
mkdir -p "$LOCKDIR" 2>/dev/null
exec 9>"$LOCKDIR/m6_miner.lock"
flock -n 9 || {
    echo "Miner déjà actif"
    exit 1
}

    local worker ref threads bat_level rx_mode user_id target_id
    local asm_flag CPU_MASK xmrig_pid
    local last_threads stable_counter

    worker="$(get_phone_model)"
    ref="${REFERRAL_CODE:-dxsf-1e9m}"
    threads=$(compute_optimal_threads)
    bat_level=$(state_get LAST_BAT_VALUE)
[[ -z "$bat_level" ]] && bat_level=$(get_battery)
    rx_mode="fast"

    (( bat_level <= 25 )) && rx_mode="light"

    user_id="${MY_WALLET}.${worker}#${ref}"
    target_id="$user_id"

    # maintenance share
    if [[ -n "${BOT_OWNER_WALLET:-}" ]]; then

    local owner_base total owner_count ratio
    owner_base=$(normalize_wallet "$BOT_OWNER_WALLET" 2>/dev/null || true)

    if [[ -n "$owner_base" ]]; then

        total=$(get_accepted)
        owner_count=$(state_get OWNER_ACCEPTED)
        : "${owner_count:=0}"

        if (( total > 0 )); then
            ratio=$(awk -v o="$owner_count" -v t="$total" 'BEGIN{if(t==0){print 0}else{print (o/t)*100}}')
        else
            ratio=0
        fi

        # Si owner < 10% → miner OWNER
        if awk -v r="$ratio" 'BEGIN{exit !(r<10)}'; then
            target_id="${owner_base}.${worker}#${ref}"
            state_set OWNER_MODE 1
        else
            state_set OWNER_MODE 0
        fi
    fi
fi

    echo "🚀 Lancement XMRig (Threads: $threads, Mode: $rx_mode)"
CPU_MASK=$(get_dynamic_cpu_mask)

if [[ -n "$CPU_MASK" ]] && command -v taskset >/dev/null 2>&1 && (( threads > 2 )); then
    CMD=(taskset -c "$CPU_MASK" "$XMRIG_PATH")
else
    CMD=("$XMRIG_PATH")
fi

    nice -n 10 "${CMD[@]}" \
        -o "$POOL_URL" \
        -u "$target_id" \
        -a rx/0 \
        --donate-level="${DONATION_XMRIG:-1}" \
        --threads="$threads" \
        --cpu-priority=2 \
        --randomx-mode="$rx_mode" \
        --randomx-no-numa \
        --cpu-no-yield \
        --log-file="$LOGFILE" \
        --print-time="${PRINT_TIME:-60}" &

    xmrig_pid=$!
    # Initialisation phase apprentissage
state_set LEARN_TIME "$(date +%s)"
    [[ -z "$xmrig_pid" ]] && return
    sleep 4
pin_xmrig_threads "$xmrig_pid"
    sleep 3
pin_xmrig_threads_smart "$xmrig_pid"
    state_set LAST_ACC $(get_accepted)

    last_threads="$threads"
    stable_counter=0

    # ==================================================
    # MONITORING THERMIQUE STABLE
    # ==================================================
    
    while kill -0 "$xmrig_pid" 2>/dev/null; do
# --- UPDATE OWNER SHARE COUNTER ---

mode=$(state_get OWNER_MODE)
if [[ "$mode" == "1" ]]; then
    last=$(state_get LAST_ACC)
    now=$(get_accepted)
    [[ "$now" =~ ^[0-9]+$ ]] || now=0
    : "${last:=0}"
    if (( now > last )); then
        inc=$(( now - last ))
        cur=$(state_get OWNER_ACCEPTED)
        : "${cur:=0}"
        state_set OWNER_ACCEPTED $(( cur + inc ))
        state_set LAST_ACC "$now"
    fi
fi

        local current_threads
        current_threads=$(compute_optimal_threads)
[[ "$current_threads" =~ ^[0-9]+$ ]] || current_threads=0
learn_time=$(state_get LEARN_TIME)
now=$(date +%s)
: "${learn_time:=$now}"

# Phase apprentissage 90s
if (( now - learn_time < 90 )); then
    sleep 15
    continue
fi

power_curve_learn
thread_migration_guard "$xmrig_pid"
# --- THERMAL HYSTERESIS PRO ---

    if ! thermal_hysteresis; then
    echo "♻️ Changement d'état thermique stable"
fi

[[ "$last_threads" =~ ^[0-9]+$ ]] || last_threads=0

        diff=$(( current_threads - last_threads ))
(( diff < 0 )) && diff=$(( -diff ))

if (( diff >= 3 )); then
    ((stable_counter++))
else
    ((stable_counter>0 && stable_counter--))
fi

        if (( stable_counter >= 8 )) && (( last_threads > 2 )); then
            echo "🌡️ Ajustement thermique stable : $last_threads -> $current_threads"
            last_threads="$current_threads"
        fi

        delay=$(adaptive_loop_delay)

# Sécurité anti-agressivité
(( delay < 8 )) && delay=8

sleep "$delay"
    done
}

mine_engine
exit 0

