#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/functions.sh"

LOGFILE="${LOGFILE:-$SCRIPT_DIR/minerV6.log}"
PIDFILE="$SCRIPT_DIR/.masterV6.pid"

stop_mining() {
    echo -e "${YELLOW}⏹️ Arrêt du minage...${RESET}"
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
    fi
    termux-wake-unlock 2>/dev/null || true
}

restart_master() {
    stop_mining
    nohup "$SCRIPT_DIR/start.sh" >/dev/null 2>&1 &
    disown
}

check_vet_threshold() {
    local bal=$(state_get VET_BAL || echo "0")
    local goal=50
    [[ ! "$bal" =~ ^[0-9.]+$ ]] && bal=0
    
    echo -e "${CYAN}💰 Solde : ${YELLOW}${bal} VET${RESET}"
    
    # Version AWK sans aucune syntaxe avancée pour compatibilité totale
    local reste=$(awk -v b="$bal" -v g="$goal" 'BEGIN { r=g-b; if(r<0){r=0}; print r }')
    local prog=$(awk -v b="$bal" -v g="$goal" 'BEGIN { p=(b/g)*100; if(p>100){p=100}; printf "%.1f", p }')
    
    echo -e "${WHITE}📉 Manque : ${RED}${reste} VET${RESET} | 📊 Progression : ${GREEN}${prog}%${RESET}"
}

show_logs_live() {
    if [ ! -f "$LOGFILE" ] || [ ! -s "$LOGFILE" ]; then
        echo -e "${RED}⚠️ Aucun log trouvé.${RESET}"
        pgrep xmrig > /dev/null && echo "✅ xmrig est actif." || echo "❌ xmrig est à l'arrêt."
        return
    fi
    echo -e "${YELLOW}Appuyez sur CTRL+C pour quitter${RESET}"
    tail -n 40 -f "$LOGFILE" | sed -u \
        -e "s/accepted/${GREEN}accepted${RESET}/g" \
        -e "s/rejected/${RED}rejected${RESET}/g" \
        -e "s/error/${RED}ERROR${RESET}/g" || true
}

# --- 3. MENU PRINCIPAL ---

while true; do
    printf "\033c"
    echo -e "${CYAN}🔧 MASTER V6 — ADMIN (Fixed)${RESET}"
    echo "=========================================="
    # On utilise un try/catch pour show_stats au cas où il contiendrait encore du vieux AWK
    show_stats || echo "Initialisation des statistiques..."
    echo "------------------------------------------"
    echo "1) 💰 Voir progression VET"
    echo "2) 📝 Logs Live"
    echo "3) 🚀 Redémarrer"
    echo "4) 🛑 STOP"
    echo "q) ❌ Quitter"
    echo ""
    read -rp "👉 Choix : " CHOICE
    case "$CHOICE" in
        1) check_vet_threshold ;;
        2) show_logs_live ;;
        3) restart_master ;;
        4) stop_mining ;;
        q|Q) exit 0 ;;
    esac
    echo -e "\nAppuyez sur Entrée..."
    read -r
done

