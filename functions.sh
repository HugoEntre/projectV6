#!/data/data/com.termux/files/usr/bin/bash

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

STATE_FILE="$HOME/.m6_state"
LOGFILE="${LOGFILE:-$HOME/masterV6_project/minerV6.log}"

[ -f "$STATE_FILE" ] || touch "$STATE_FILE"
chmod 600 "$STATE_FILE" 2>/dev/null || true

export M6_START_TIME=${M6_START_TIME:-$(date +%s)}

# ==================================================
# STATE SAFE
# ==================================================

detect_charge_control() {
    local nodes=("battery_charging_enabled" "charging_enabled" "input_suspend" "store_mode")
    for node in "${nodes[@]}"; do
        if [[ -f "/sys/class/power_supply/battery/$node" ]]; then
            echo "/sys/class/power_supply/battery/$node"
            return 0
        fi
    done
    return 1
}

control_charge() {

    [[ -z "$M6_CHARGE_NODE" ]] && return 0
    [[ ! -w "$M6_CHARGE_NODE" ]] && return 0

    local level="$1"

    # Seuils industriels
    local STOP=85
    local START=65

    local current_state
    current_state=$(cat "$M6_CHARGE_NODE" 2>/dev/null)

    # --- STOP CHARGE ---
    if (( level >= STOP )); then
        if [[ "$M6_CHARGE_REVERSE" == "true" ]]; then
            echo 1 > "$M6_CHARGE_NODE"
        else
            echo 0 > "$M6_CHARGE_NODE"
        fi
        state_set CHARGE_CTRL "OFF"
        return
    fi

    # --- START CHARGE ---
    if (( level <= START )); then
        if [[ "$M6_CHARGE_REVERSE" == "true" ]]; then
            echo 0 > "$M6_CHARGE_NODE"
        else
            echo 1 > "$M6_CHARGE_NODE"
        fi
        state_set CHARGE_CTRL "ON"
        return
    fi
}

export M6_CHARGE_NODE=$(detect_charge_control)

# Déterminer si la logique est inversée (ex: input_suspend: 1=Stop)
if [[ "$M6_CHARGE_NODE" == *"input_suspend"* ]]; then
    export M6_CHARGE_REVERSE=true
else
    export M6_CHARGE_REVERSE=false
fi

state_set() {

    local key="$1"
    local val="$2"
    local tmp="${STATE_FILE}.$RANDOM.$$"
    [[ -z "$key" ]] && return 0
    (
        flock -x 9
        grep -v "^${key//./\\.}=" "$STATE_FILE" 2>/dev/null > "$tmp" || true
        printf '%s=%s\n' "$key" "$val" >> "$tmp"
        mv -f "$tmp" "$STATE_FILE"

    ) 9>"${STATE_FILE}.lock"
}

state_add() {

    local key="$1"
    local inc="$2"
    local cur tmp="${STATE_FILE}.$RANDOM.$$"

    (
        flock -x 9

        cur=$(grep "^${key}=" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        [[ "$cur" =~ ^[0-9]+$ ]] || cur=0

        grep -v "^${key}=" "$STATE_FILE" > "$tmp" 2>/dev/null || true
        printf '%s=%s\n' "$key" "$((cur + inc))" >> "$tmp"

        mv -f "$tmp" "$STATE_FILE"

    ) 9>"${STATE_FILE}.lock"
}

state_get() {

    local key="$1"

    (
        flock -s 9
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | tail -n1 | cut -d= -f2
    ) 9<"$STATE_FILE"

}

normalize_wallet() {

    [[ -z "$1" ]] && return 1

    local W
    W=$(echo "$1" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' | sed 's/^vet://')

    if [[ "$W" =~ ^0x[a-f0-9]{40}$ ]]; then
        echo "VET:${W}"
        return 0
    fi

    return 1
}

get_phone_model() {

    local brand model host

    brand=$(getprop ro.product.brand 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    model=$(getprop ro.product.model 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')

    host=$(uname -n 2>/dev/null)
    [[ "$host" == "localhost" || -z "$host" ]] && host=$(echo "${brand}${model}" | cksum | cut -d' ' -f1)

    echo "m6_${brand:0:5}_${model:0:8}_${host:0:4}"
}

# ==================================================
# CPU TOPOLOGY (DETECTION UNIQUE)
# ==================================================

CPU_LITTLE=""
CPU_BIG=""
CPU_TOPOLOGY_READY=0

detect_cpu_topology() {

    [[ "$CPU_TOPOLOGY_READY" == "1" ]] && return

    local idx cap

    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do

        idx=$(basename "$cpu" | tr -dc '0-9')
        [[ -f "$cpu/cpu_capacity" ]] || continue

        read -r cap < "$cpu/cpu_capacity" 2>/dev/null || continue
        [[ "$cap" =~ ^[0-9]+$ ]] || continue

        if (( cap < 600 )); then
            CPU_LITTLE+="${idx},"
        else
            CPU_BIG+="${idx},"
        fi
    done

    CPU_LITTLE="${CPU_LITTLE%,}"
CPU_BIG="${CPU_BIG%,}"

# fallback universel si cpu_capacity absent
if [[ -z "$CPU_BIG" ]]; then
    CPU_BIG=$(seq -s, 0 $(( $(nproc)-1 )))
fi

CPU_TOPOLOGY_READY=1
}

# ==================================================
# DEVICE METRICS (ANDROID SAFE)
# ==================================================

get_cpu_temp() {

    local zone type raw temp
    local temps=()

    [ -d /sys/class/thermal ] || { echo 35; return; }

    for zone in /sys/class/thermal/thermal_zone*; do

        [ -r "$zone/type" ] || continue
        read -r type < "$zone/type" 2>/dev/null || continue
        type=$(echo "$type" | tr '[:upper:]' '[:lower:]')

        # --- Inclusion CPU uniquement ---
        case "$type" in
            cpu*|cpuss*|cluster*|tsens*|soc*)
                ;;
            *)
                continue
                ;;
        esac

        # --- Exclusions sûres ---
        case "$type" in
            *step*|*skin*|*camera*|*battery*|*modem*|*gpuss*|*ddr*|*wlan*|*pa*|*audio*|*video*)
                continue
                ;;
        esac

        [ -r "$zone/temp" ] || continue
        read -r raw < "$zone/temp" 2>/dev/null || continue
        [[ "$raw" =~ ^[0-9]+$ ]] || continue

        temp=$raw

        # --- Normalisation unités ---
        if (( temp > 1000000 )); then
            temp=$((temp/1000000))
        elif (( temp > 1000 )); then
            temp=$((temp/1000))
        fi

        # --- Plage réaliste CPU ---
        (( temp < 25 || temp > 100 )) && continue

        temps+=("$temp")
    done

    # --- Aucun capteur valide ---
    (( ${#temps[@]} == 0 )) && { echo 35; return; }

    # --- Trier décroissant ---
    IFS=$'\n' temps=($(sort -nr <<<"${temps[*]}"))
    unset IFS

    # --- Moyenne des 3 plus chaudes CPU ---
    local sum=0 count=0
    for t in "${temps[@]}"; do
        (( sum += t ))
        (( count++ ))
        (( count == 3 )) && break
    done

    echo $(( sum / count ))
}

get_cached_cpu_temp() {
    local t
    t=$(state_get CPU_TEMP)
    [[ -z "$t" ]] && t=$(get_cpu_temp)
    echo "$t"
}

get_battery_temp() {

    local t

    # --- SOURCE 1 : TERMUX API ---
    if command -v termux-battery-status >/dev/null 2>&1; then
        if command -v jq >/dev/null 2>&1; then
            t=$(termux-battery-status 2>/dev/null | jq -r '.temperature' 2>/dev/null)
        else
            t=$(termux-battery-status 2>/dev/null | sed -n 's/.*"temperature":[ ]*\([0-9.]*\).*/\1/p')
        fi

        [[ "$t" =~ ^[0-9.]+$ ]] && echo "$t" && return
    fi

    # --- SOURCE 2 : SYSFS ANDROID ---
    for B in /sys/class/power_supply/*; do
        [[ -f "$B/temp" ]] || continue
        read -r t < "$B/temp" 2>/dev/null || continue
        [[ "$t" =~ ^[0-9]+$ ]] || continue

        # Correction universelle unités
        if (( t > 20000 )); then
            t=$((t/1000))   # millidegrés
        elif (( t > 1000 )); then
            t=$((t/10))     # décicelsius
        fi

        # plage réaliste batterie
        (( t >= 15 && t <= 60 )) && { echo "$t"; return; }
    done

    echo 0
}

get_cached_battery_level() {
    local b
    b=$(state_get BAT_LVL)
    [[ -z "$b" ]] && b=$(get_battery)
    echo "$b"
}

update_thermal_cache() {
    local now last cpu bat
    now=$(date +%s)
    last=$(state_get THERM_LAST)
    : "${last:=0}"
    (( now - last < 8 )) && return 0
    state_set THERM_LAST "$now"
    cpu=$(get_cpu_temp)
    bat=$(get_battery_temp 2>/dev/null || echo "")
    [[ "$cpu" =~ ^[0-9.]+$ ]] || cpu=0
    [[ "$bat" =~ ^[0-9.]+$ ]] || bat=0
    state_set CPU_TEMP "$cpu"
    state_set BAT_TEMP "$bat"
}

get_battery() {

    local json bat status temp current mode

    # --- SOURCE PRINCIPALE : TERMUX API ---
    if command -v termux-battery-status >/dev/null 2>&1; then

        json=$(termux-battery-status 2>/dev/null)

NOW=$(date +%s)
LAST_BAT_TIME=$(state_get LAST_BAT_TIME)
: "${LAST_BAT_TIME:=0}"

if (( NOW - LAST_BAT_TIME < 15 )); then
    state_get LAST_BAT_VALUE
    return
fi

        bat=$(printf '%s\n' "$json" | sed -n 's/.*"percentage":[ ]*\([0-9]*\).*/\1/p') || true
        status=$(printf '%s\n' "$json" | sed -n 's/.*"status":[ ]*"\([^"]*\)".*/\1/p') || true
        temp=$(printf '%s\n' "$json" | sed -n 's/.*"temperature":[ ]*\([0-9.]*\).*/\1/p') || true
        current=$(printf '%s\n' "$json" | sed -n 's/.*"current":[ ]*\([-0-9]*\).*/\1/p') || true

        [[ "$bat" =~ ^[0-9]+$ ]] || bat=50

        # --- MODE INTELLIGENT ---
        mode="normal"

        # Batterie faible non branchée
        if [[ "$status" != "CHARGING" && "$status" != "FULL" ]] && (( bat <= 22 )); then
            mode="eco"
        fi

        # Charge rapide détectée
        if [[ "$status" == "CHARGING" ]]; then
    if [[ "$current" =~ ^-?[0-9]+$ ]] && (( current > 300000 )); then
        mode="charging_fast"
    else
        mode="charging"
    fi
fi

        # Batterie chaude
        if [[ "$temp" =~ ^[0-9.]+$ ]] && awk "BEGIN{exit !($temp > 38)}"; then
            mode="battery_hot"
        fi
# Sauvegarde état pour le bot
state_set BAT_MODE "$mode"
state_set BAT_LVL "$bat"
state_set BAT_STATUS "$status"

# --- CACHE BATTERIE ---
state_set LAST_BAT_VALUE "$bat"
state_set LAST_BAT_TIME "$NOW"

echo "$bat"

return

    fi

    # --- FALLBACK ANDROID ---
    if command -v dumpsys >/dev/null 2>&1; then
        bat=$(dumpsys battery 2>/dev/null | awk '/level/ {print $2}')
        [[ "$bat" =~ ^[0-9]+$ ]] && echo "$bat" && return
    fi

    echo 50
}

get_uptime() {
    local now elapsed
    now=$(date +%s)
    elapsed=$(( now - M6_START_TIME ))
    (( elapsed<0 )) && elapsed=0
    printf "%dh %02dm" $((elapsed/3600)) $(((elapsed%3600)/60))
}

# ==================================================
# THREAD CONTROL 
# ==================================================

get_threads() {
    compute_optimal_threads
}

# ==================================================
# HASHRATE / LOG SAFE
# ==================================================

get_hashrate() {

    [[ -f "$LOGFILE" ]] || { echo 0; return; }

    local line hs

    line=$(grep -a "speed" "$LOGFILE" | tail -n1)

    [[ -z "$line" ]] && { echo 0; return; }

    line=$(printf '%s\n' "$line" | sed 's/\x1b\[[0-9;]*m//g')

    hs=$(printf '%s\n' "$line" | awk '
    {
        for(i=1;i<=NF;i++){
            if($i ~ /^[0-9]+(\.[0-9]+)?$/){
                print $i
                exit
            }
        }
    }')

    [[ "$hs" =~ ^[0-9.]+$ ]] || hs=0

    printf "%.1f\n" "$hs"
}

get_accepted() {

[[ -f "$LOGFILE" ]] || { echo 0; return; }

grep -a "accepted (" "$LOGFILE" \
| tail -1 \
| sed -E 's/.*accepted \(([0-9]+)\/.*/\1/'

}

is_miner_running() {
pgrep -u "$USER" -f "$XMRIG_PATH" >/dev/null 2>&1
}

# ==================================================
# HEALTH CHECK (TA LOGIQUE)
# ==================================================

check_system_health() {
    local temp bat
    temp=$(get_cached_cpu_temp)
    bat=$(get_cached_battery_level)
    (( temp>=${MAX_TEMP:-80} )) && return 1
    (( bat<${BATTERY_MIN:-15} )) && return 1
    return 0
}

get_dynamic_cpu_mask() {

detect_cpu_topology

local temp
temp=$(get_cached_cpu_temp)

# froid ou normal → tous les cores
if (( temp < 68 )); then
echo "$CPU_LITTLE,$CPU_BIG"
return
fi

# chaud → LITTLE seulement
echo "$CPU_LITTLE"

}

pin_xmrig_threads() {
    detect_cpu_topology
    [[ -z "$CPU_BIG" ]] && return
    local pid="$1"
    [[ -z "$pid" ]] && return

    # récupération TID xmrig
    local tids
    tids=$(ps -T -p "$pid" -o tid= 2>/dev/null)

    local i=0
    for tid in $tids; do
big_list=($(echo "$CPU_BIG" | tr ',' ' '))
little_list=($(echo "$CPU_LITTLE" | tr ',' ' '))

big_count=${#big_list[@]}

if (( i < big_count )); then
    taskset -pc "${big_list[$i]}" "$tid"
else
    idx=$(( (i-big_count) % ${#little_list[@]} ))
    taskset -pc "${little_list[$idx]}" "$tid"
fi

        ((i++))
    done
}

measure_thread_load() {
    local pid="$1"
    local TMPDIR="${TMPDIR:-$PREFIX/tmp}"
    mkdir -p "$TMPDIR" 2>/dev/null || true
    local tmpfile="$TMPDIR/m6_thread_load.$$"
    
    [[ -z "$pid" ]] && return 1
    
    # Vérifier que le processus existe
    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    
    rm -f "$tmpfile" 2>/dev/null || true
    
    if command -v ps >/dev/null 2>&1; then
       ps -T -p "$pid" -o tid=,pcpu= 2>/dev/null | sort -k2 -rn > "$tmpfile" 2>/dev/null || true
    fi
    
    # Si le fichier est vide ou n'existe pas, méthode 2: /proc
    if [[ ! -s "$tmpfile" ]]; then
        if [[ -d "/proc/$pid/task" ]]; then
            for tid_path in /proc/$pid/task/*; do
                tid=$(basename "$tid_path")
                if [[ -f "/proc/$pid/task/$tid/stat" ]]; then
                    # Récupérer le temps CPU
                    local utime stime total
                    read -r _ _ _ _ _ _ _ _ _ _ _ _ _ utime stime _ < "/proc/$pid/task/$tid/stat" 2>/dev/null || continue
                    total=$((utime + stime))
                    printf '%s %s\n' "$tid" "$total" >> "$tmpfile" 2>/dev/null || :
                fi
            done
            if [[ -s "$tmpfile" ]]; then
                sort -k2 -rn "$tmpfile" -o "$tmpfile" 2>/dev/null || true
            fi
        fi
    fi
    
    # Si toujours pas de données, retourner 1
    if [[ ! -s "$tmpfile" ]]; then
        rm -f "$tmpfile" 2>/dev/null || true
        return 1
    fi
    
    echo "$tmpfile"
}

pin_xmrig_threads_smart() {
    detect_cpu_topology
    local tmpfile sortedfile
    [[ -z "$CPU_BIG" ]] && return
    local pid="$1"
    [[ -z "$pid" ]] && return
    
    # Vérifier que le processus existe
    if ! kill -0 "$pid" 2>/dev/null; then
        return
    fi
    [[ -z "$CPU_BIG" ]] && return
    local TMPDIR="${TMPDIR:-$PREFIX/tmp}"
    mkdir -p "$TMPDIR" 2>/dev/null || true
    
    # Mesurer la charge
    tmpfile=$(measure_thread_load "$pid")
    
    # Vérifier que le fichier a été créé
    if [[ ! -f "$tmpfile" ]]; then
        return
    fi
    
    sortedfile="${tmpfile}.sorted"
    
    # Trier par charge (du plus chargé au moins chargé)
    if [[ -s "$tmpfile" ]]; then
        sort -k2 -rn "$tmpfile" > "$sortedfile" 2>/dev/null || true
    else
        rm -f "$tmpfile" 2>/dev/null || true
        return
    fi
    
    # Vérifier que le fichier trié existe
    if [[ ! -f "$sortedfile" ]]; then
        rm -f "$tmpfile" 2>/dev/null || true
        return
    fi
    
    local i=0
    big_count=$(echo "$CPU_BIG" | tr ',' '\n' | wc -l)

while read -r tid pcpu; do

# Nettoyer tid
tid=${tid%% *}
[[ -z "$tid" ]] && continue

# vérifier que le thread existe encore
    if [[ -d "/proc/$pid/task/$tid" ]]; then

    big_list=($(echo "$CPU_BIG" | tr ',' ' '))
little_list=($(echo "$CPU_LITTLE" | tr ',' ' '))

big_count=${#big_list[@]}

    if (( i < big_count )); then
    taskset -pc "${big_list[$i]}" "$tid" >/dev/null 2>&1
else
    idx=$(( (i-big_count) % ${#little_list[@]} ))
    taskset -pc "${little_list[$idx]}" "$tid" >/dev/null 2>&1
    fi
  fi

((i++))

done < "$sortedfile" 2>/dev/null || true
    
    # Nettoyage
    rm -f "$tmpfile" "$sortedfile" 2>/dev/null || true
}

thread_migration_guard() {
    
    detect_cpu_topology
    [[ -z "$CPU_BIG" ]] && return
    local pid="$1"
    [[ -z "$pid" ]] && return

    local tid cpu

    for tid_path in /proc/$pid/task/*; do

    tid=$(basename "$tid_path")

    [[ -f "$tid_path/stat" ]] || continue

    cpu=$(awk '{print $39}' "$tid_path/stat")

    if echo "$CPU_BIG" | grep -qw "$cpu"; then
        continue
    fi

    taskset -pc "$CPU_BIG" "$tid" >/dev/null 2>&1

done
}

send_notif() {

    command -v termux-notification >/dev/null 2>&1 || return 0

    local title="${1:-MasterV6}"
    local message="${2:-info}"

    termux-notification \
        --title "$title" \
        --content "$message" \
        --id "v6_status" \
        --priority high 2>/dev/null || true
}

compute_optimal_threads() {

    local best
    best=$(power_curve_best_threads)

    # recalibrage périodique
    local last_test now
    last_test=$(state_get LAST_THREAD_TEST)
    now=$(date +%s)
    : "${last_test:=0}"

    if (( now - last_test > 1800 )); then
        state_set LAST_THREAD_TEST "$now"
        best=""
    fi

    if [[ "$best" =~ ^[0-9]+$ ]] && (( best > 0 )); then
        echo "$best"
        return
    fi

    local total temp battemp limit
    local little big nominal

    total=$(nproc 2>/dev/null || echo 4)
    (( total > 32 )) && total=32

    temp=$(get_cached_cpu_temp)
    battemp=$(state_get BAT_TEMP)

    # protection SoC
    if (( temp >= MAX_TEMP+2 )); then
        echo 1
        return
    fi

    # batterie chaude
    if [[ "$battemp" =~ ^[0-9.]+$ ]] && (( ${battemp%.*} >= BATTERY_HOT )); then
        echo $(( total*60/100 ))
        return
    fi

    if (( temp > 70 )); then
        echo $(( total/2 ))
        return
    fi

    # limite CPU hint
    limit=$(( total*CPU_MAX_HINT/100 ))

    detect_cpu_topology

    little=$(echo "$CPU_LITTLE" | tr ',' '\n' | wc -l)
    big=$(echo "$CPU_BIG" | tr ',' '\n' | wc -l)

    nominal=$(( little + big/2 ))

    (( nominal > limit )) && nominal=$limit
    (( nominal < 2 )) && nominal=2

    echo "$nominal"
}

thermal_pause_needed() {

    local temp bat charging status
    temp=$(get_cached_cpu_temp)
    bat=$(get_cached_battery_level)

    # Détection état charge Android universel
    status=$(state_get BAT_STATUS)

charging=0
[[ "$status" == "CHARGING" || "$status" == "FULL" ]] && charging=1

    # pause douce avant throttling
    (( temp >= HOT_THRESHOLD+5 )) && return 0

    # batterie basse seulement si NON branché
    if (( bat <= BATTERY_ECO )) && (( charging == 0 )); then
        return 0
    fi

    return 1
}

thermal_hysteresis() {

    local temp state
    temp=$(get_cached_cpu_temp)
    state=$(state_get THERMAL_STATE)
    : "${state:=normal}"

    # Passage en mode chaud
    if (( temp >= HOT_THRESHOLD )) && [[ "$state" != "hot" ]]; then
        state_set THERMAL_STATE hot
        return 1
    fi

    # Retour en mode normal uniquement si bien refroidi
    if (( temp <= COOL_THRESHOLD )) && [[ "$state" != "normal" ]]; then
        state_set THERMAL_STATE normal
        return 1
    fi

    return 0
}

adaptive_loop_delay() {

    local temp running
    temp=$(get_cached_cpu_temp)

    if is_miner_running; then
        running=1
    else
        running=0
    fi

    # Miner actif et froid
    if (( running == 1 )) && (( temp < 60 )); then
        echo 45
        return
    fi

    # Température modérée
    if (( temp >= 60 && temp < 68 )); then
        echo 30
        return
    fi

    # Température élevée
    if (( temp >= 68 && temp < 75 )); then
        echo 20
        return
    fi

    # Très chaud
    if (( temp >= 75 )); then
        echo 12
        return
    fi

    # Idle
    echo 25
}

# ==================================================
# POWER CURVE LEARNING PERSISTANT (PHASE 3)
# ==================================================

power_curve_learn() {

    local thr hs key old avg mode

    thr=$(get_threads)
    hs=$(get_hashrate)
    mode=$(get_cpu_cluster_mode)

    [[ "$thr" =~ ^[0-9]+$ ]] || return 0
    [[ "$hs" =~ ^[0-9.]+$ ]] || return 0
awk "BEGIN{exit !($hs > 50)}" || return 0

    key="POWER_${mode}_${thr}"

    old=$(state_get "$key")
    : "${old:=0}"

    avg=$(awk -v o="$old" -v n="$hs" 'BEGIN{
        if(o==0){print n}else{print (o*0.7)+(n*0.3)}
    }')

    state_set "$key" "$avg"

    local best_thr best_hs t val

    best_thr="$thr"
    best_hs="$avg"

    for t in $(seq 1 "$(nproc)"); do

        val=$(state_get "POWER_${mode}_${t}")

        [[ "$val" =~ ^[0-9.]+$ ]] || continue

        if awk "BEGIN{exit !($val > $best_hs)}"; then
            best_hs="$val"
            best_thr="$t"
        fi

    done

    state_set DEVICE_PROFILE_THREADS "$best_thr"
}

get_cpu_cluster_mode() {

    local mask cpu
    mask=$(get_dynamic_cpu_mask)

    [[ -z "$mask" ]] && { echo "MIXED"; return; }

    local has_big=0
    local has_little=0

    for cpu in $(echo "$mask" | tr ',' ' '); do
        if echo "$CPU_BIG" | grep -qw "$cpu"; then
            has_big=1
        fi
        if echo "$CPU_LITTLE" | grep -qw "$cpu"; then
            has_little=1
        fi
    done

    if (( has_big == 1 && has_little == 1 )); then
        echo "MIXED"
    elif (( has_big == 1 )); then
        echo "BIG"
    else
        echo "LITTLE"
    fi
}

power_curve_best_threads() {

    local best_thr=0
    local best_hs=0
    local line thr hs mode

    mode=$(get_cpu_cluster_mode)

    while read -r line; do

        case "$line" in
            POWER_${mode}_*) ;;
            *) continue ;;
        esac

        thr="${line%%=*}"
        hs="${line##*=}"
        thr="${thr#POWER_${mode}_}"

        [[ "$thr" =~ ^[0-9]+$ ]] || continue
        [[ "$hs" =~ ^[0-9.]+$ ]] || continue

        if awk "BEGIN{exit !($hs > $best_hs)}"; then
            best_hs="$hs"
            best_thr="$thr"
        fi

    done < "$STATE_FILE"

    echo "$best_thr"
}

metrics_loop() {

    local last_flush=0
    local now

    while true; do

        now=$(date +%s)

        # Mise à jour thermique toujours active
        update_thermal_cache

        # Flush complet toutes les 2 minutes
        if (( now - last_flush >= 120 )); then
            state_set HS "$(get_hashrate)"
            state_set ACC "$(get_accepted)"
            state_set BAT_LVL "$(get_battery)"
            state_set THR "$(get_threads)"
            last_flush=$now
        fi

        sleep 45
      done
}

optimize_cache_affinity() {
    return 0
}

auto_update() {

local DIR="$HOME/masterV6_project"

cd "$DIR" || return
[[ -d .git ]] || return

# --- JITTER : éviter que tous les bots se connectent en même temps
sleep $(( RANDOM % 900 ))

git remote update >/dev/null 2>&1

LOCAL=$(git rev-parse HEAD 2>/dev/null)
REMOTE=$(git rev-parse @{u} 2>/dev/null)

[[ -z "$LOCAL" || -z "$REMOTE" ]] && return

if [[ "$LOCAL" != "$REMOTE" ]]; then

echo "🔄 Nouvelle version détectée — mise à jour..."

git pull --rebase --autostash

echo "♻️ Redémarrage moteur"

kill -TERM "$$"

fi

}