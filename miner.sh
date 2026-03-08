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
trap cleanup EXIT SIGINT SIGTERM
trap '' SIGHUP

# --- WALLET ---
WALLET_FILE="$HOME/.masterV6_wallet"
[ -f "$WALLET_FILE" ] || { echo "❌ Fichier Wallet absent"; exit 1; }

RAW_WALLET=$(cat "$WALLET_FILE")
MY_WALLET=$(normalize_wallet "$RAW_WALLET") || { echo "❌ Wallet invalide"; exit 1; }

# MOTEUR DE MINAGE

mine_engine() {

local low_hash_counter=0
LOCKDIR="${TMPDIR:-$PREFIX/tmp}"
mkdir -p "$LOCKDIR" 2>/dev/null
exec 9>"$LOCKDIR/m6_miner.lock"

# attendre si un ancien miner termine
for i in {1..5}; do
    flock -n 9 && break
    sleep 2
done

flock -n 9 || {
    echo "Miner déjà actif"
    exit 1
}

trap 'rm -f "$LOCKDIR/m6_miner.lock"' EXIT

    local worker ref threads bat_level rx_mode user_id target_id
    local asm_flag CPU_MASK xmrig_pid
    local last_threads stable_counter

    worker="$(get_phone_model)"
    ref="${REFERRAL_CODE:-dxsf-1e9m}"
    threads=$(compute_optimal_threads)

if [[ ! "$threads" =~ ^[0-9]+$ ]] || (( threads < 3 )); then
    threads=$(compute_optimal_threads)
fi

    bat_level=$(state_get LAST_BAT_VALUE)
[[ -z "$bat_level" ]] && bat_level=$(get_battery)

     if (( bat_level <= 25 )); then
    rx_mode="light"
else
    rx_mode="fast"
fi

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

if [[ -z "$CPU_MASK" ]]; then
    CPU_MASK="0-$(($(nproc)-1))"
fi

if [[ -n "$CPU_MASK" ]] && command -v taskset >/dev/null 2>&1 && taskset -c 0 echo >/dev/null 2>&1 && (( threads > 2 )); then
    CMD=(taskset -c "$CPU_MASK" "$XMRIG_PATH")
else
    CMD=("$XMRIG_PATH")
fi

export OMP_NUM_THREADS="$threads"
export MALLOC_ARENA_MAX=2
export OMP_WAIT_POLICY=PASSIVE
export OMP_PROC_BIND=TRUE
export RANDOMX_NO_JIT=0

rx_init=$(( threads / 2 ))
(( rx_init < 1 )) && rx_init=1
(( rx_init > 6 )) && rx_init=6

nice -n 5 "${CMD[@]}" \
  -o "$POOL_URL" \
  -u "$target_id" \
  -a rx/0 \
  --donate-level="${DONATION_XMRIG:-1}" \
  --threads="$threads" \
  --cpu-memory-pool=2 \
  --cpu-priority=5 \
  --cpu-no-yield \
  --randomx-init="$rx_init" \
  --randomx-mode="$rx_mode" \
  --randomx-no-numa \
  --randomx-cache-qos \
  --keepalive \
  --retry-pause=5 \
  --retries=999999 \
  --log-file="$LOGFILE" \
  --print-time="${PRINT_TIME:-60}" &

xmrig_pid=$!
sleep 30

if ! kill -0 "$xmrig_pid" 2>/dev/null; then
    echo "⚠️ xmrig crash early — relance"
    return
fi

    # Initialisation phase apprentissage
state_set LEARN_TIME "$(date +%s)"
    [[ -z "$xmrig_pid" ]] && return
    sleep 4
pin_xmrig_threads "$xmrig_pid"
    sleep 3
pin_xmrig_threads_smart "$xmrig_pid"
    state_set LAST_ACC "$(get_accepted)"

    last_threads="$threads"
    stable_counter=0
    low_hash_counter=0

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
        state_add OWNER_ACCEPTED "$inc"
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

acc_now=$(get_accepted)
acc_last=$(state_get LAST_ACC)
: "${acc_last:=0}"

gap=$(( acc_now - acc_last ))

if (( gap > MAX_ACCEPTED_GAP )) && (( gap < 50 )) && (( acc_last > 0 )); then
    echo "⚠️ Gap shares anormal — restart miner"
    kill -TERM "$xmrig_pid" 2>/dev/null || true
wait "$xmrig_pid" 2>/dev/null || true
    break
fi

state_set LAST_ACC "$acc_now"

hs=$(get_hashrate)

if awk "BEGIN{exit !($hs < 5)}"; then
    ((low_hash_counter++))
else
    low_hash_counter=0
fi

if (( low_hash_counter >= 10 )); then
    echo "⚠️ xmrig freeze confirmé"
    kill -TERM "$xmrig_pid"
    break
fi

new_bat=$(get_cached_battery_level)

if (( new_bat <= 25 )) && [[ "$rx_mode" == "fast" ]]; then
    echo "🔋 Batterie faible → passage mode LIGHT"
    kill "$xmrig_pid"
    break
fi

if (( new_bat >= 35 )) && [[ "$rx_mode" == "light" ]]; then
    echo "🔋 Batterie remontée → passage mode FAST"
    kill "$xmrig_pid"
    break
fi

(( RANDOM % 5 == 0 )) && thread_migration_guard "$xmrig_pid"

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

        if (( stable_counter >= 15 )) && [[ "$current_threads" =~ ^[0-9]+$ ]] && (( current_threads != last_threads )); then
    echo "🌡️ Ajustement thermique appliqué : $last_threads -> $current_threads"
    last_threads="$current_threads"
    kill -TERM "$xmrig_pid" 2>/dev/null || true
    break
fi

        delay=$(adaptive_loop_delay)

# Sécurité anti-agressivité
(( delay < 8 )) && delay=8

sleep "$delay"
    done
}

mine_engine
exit 0