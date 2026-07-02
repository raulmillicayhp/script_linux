#!/bin/bash
set -uo pipefail

VERSION="1.1"
LOGFILE="/var/log/ubuntu-updates-manager.log"
CONFIG="/etc/apt/apt.conf.d/20auto-upgrades"

# Colores ANSI
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'

log(){ mkdir -p /var/log 2>/dev/null; echo "$(date '+%F %T') | $1" >> "$LOGFILE" 2>/dev/null||true; }
ok() {
    echo -e "${GREEN}✔${NC} $1"
    log "$1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
    log "$1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    log "$1"
}

fail() {
    echo -e "${RED}✖${NC} $1"
    exit 1
}
pause(){ read -rp "Presione ENTER para continuar..."; }
check_root(){ [[ $EUID -eq 0 ]]||fail "Ejecute como root."; }

banner() {
    clear

    echo -e "${CYAN}"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "             Ubuntu Automatic Updates Manager v${VERSION}"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo -e "${NC}"

    printf "${WHITE}%-18s${NC} %s\n" "Host:" "$(hostname)"
    printf "${WHITE}%-18s${NC} %s\n" "Usuario:" "$USER"
    printf "${WHITE}%-18s${NC} %s\n" "Sistema:" "$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    printf "${WHITE}%-18s${NC} %s\n" "Fecha:" "$(date)"

    echo
}

create_backup(){
[[ -f "$CONFIG" ]] || return
cp "$CONFIG" "${CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
ok "Backup creado."
}

disable_updates(){
info "Deshabilitando..."
create_backup
cat >"$CONFIG"<<EOF
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
systemctl disable --now unattended-upgrades apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
ok "Actualizaciones automáticas deshabilitadas."
}

enable_updates(){
info "Habilitando..."
create_backup
cat >"$CONFIG"<<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
ok "Actualizaciones automáticas habilitadas."
}

show_status(){
echo
echo -e "${CYAN}Estado de los servicios${NC}"
echo "────────────────────────────────────────────"

printf "%-32s" "unattended-upgrades:"
systemctl is-enabled unattended-upgrades 2>/dev/null || true

printf "%-32s" "apt-daily.timer:"
systemctl is-enabled apt-daily.timer 2>/dev/null || true

printf "%-32s" "apt-daily-upgrade.timer:"
systemctl is-enabled apt-daily-upgrade.timer 2>/dev/null || true
systemctl is-enabled unattended-upgrades 2>/dev/null || true
printf "%-28s" "apt-daily.timer:"
systemctl is-enabled apt-daily.timer 2>/dev/null || true
printf "%-28s" "apt-daily-upgrade.timer:"
systemctl is-enabled apt-daily-upgrade.timer 2>/dev/null || true
echo
[[ -f "$CONFIG" ]] && cat "$CONFIG"
}

rollback(){
f=$(ls -t ${CONFIG}.bak.* 2>/dev/null|head -1)
[[ -n "$f" ]]||fail "No hay backups."
cp "$f" "$CONFIG"
ok "Backup restaurado."
}

configure_timezone() {

    echo
    echo -e "${CYAN}Configuración de Zona Horaria${NC}"
    echo "────────────────────────────────────────────"

    CURRENT_TZ=$(timedatectl show --property=Timezone --value)

    echo -e "${WHITE}Zona horaria actual:${NC} ${GREEN}${CURRENT_TZ}${NC}"
    echo

    read -rp "Ingrese la nueva zona horaria (Ej: America/Argentina/Cordoba): " NEW_TZ

    [[ -z "$NEW_TZ" ]] && {
        warn "No ingresó ninguna zona horaria."
        return
    }

    if timedatectl list-timezones | grep -Fxq "$NEW_TZ"; then

        info "Configurando zona horaria..."

        if timedatectl set-timezone "$NEW_TZ"; then
            ok "Zona horaria cambiada correctamente."

            echo
            timedatectl | grep -E "Time zone|Local time|Universal time"

            log "Zona horaria modificada a $NEW_TZ"

        else
            fail "No fue posible configurar la zona horaria."
        fi

    else
        warn "La zona horaria no existe."

        echo
        echo "Algunos ejemplos:"
        echo
        echo "  America/Argentina/Buenos_Aires"
        echo "  America/Argentina/Cordoba"
        echo "  America/Argentina/Mendoza"
        echo "  America/Santiago"
        echo "  America/Montevideo"
        echo "  America/Sao_Paulo"
        echo "  Europe/Madrid"
        echo
        echo "Para ver todas:"
        echo "timedatectl list-timezones"
    fi
}

main_menu(){
while true; do
banner
echo -e "${GREEN}1)${NC} Desactivar actualizaciones"
echo -e "${GREEN}2)${NC} Habilitar actualizaciones"
echo -e "${GREEN}3)${NC} Ver estado"
echo -e "${GREEN}4)${NC} Restaurar último backup"
echo -e "${GREEN}5)${NC} Ver log"
echo -e "${GREEN}6)${NC} Configurar zona horaria"
echo -e "${RED}0)${NC} Salir"
echo

read -rp "Seleccione una opción: " op
case "$op" in
1) disable_updates; pause;;
2) enable_updates; pause;;
3) show_status; pause;;
4) rollback; pause;;
5) ${PAGER:-less} "$LOGFILE";;
6) configure_timezone; pause;;

0) exit 0;;
*) echo "Opción inválida"; sleep 1;;
esac
done
}

check_root

if [[ $# -eq 0 ]]; then
 main_menu
 exit
fi

case "$1" in
--disable) disable_updates;;
--enable) enable_updates;;
--status) show_status;;
--rollback) rollback;;
--timezone) configure_timezone;;

*) echo "Uso: $0 [--disable|--enable|--status|--rollback|--timezone]"
esac