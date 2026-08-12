#!/bin/bash

# =========================================================
# START-UP UBUNTU - ZABBIX + KASPERSKY
# VERSION ENTERPRISE SAFE (.DEB)
#
# Características:
# - Idempotente
# - Seguro para reejecutar
# - Barra de progreso
# - Logs
# - Output en tiempo real
# - Validaciones
# - Instalación segura mediante .DEB
# =========================================================

# =========================
# VARIABLES
# =========================

ZABBIX_SERVER="172.29.230.166"
KASPERSKY_SERVER="172.29.230.84"

KAS_DEB="klnagent64_15.4.0-8873_amd64.deb"
KAS_PATH="/tmp/${KAS_DEB}"

LOG_FILE="/var/log/startup_linux.log"

TOTAL_STEPS=12
CURRENT_STEP=0

# =========================
# COLORES
# =========================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# =========================
# FUNCIONES
# =========================

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

title() {
    echo ""
    echo -e "${MAGENTA}=======================================================${NC}"
    echo -e "${MAGENTA}$1${NC}"
    echo -e "${MAGENTA}=======================================================${NC}"
    echo ""
}

draw_progress_bar() {

    local progress=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local done=$((progress / 2))
    local left=$((50 - done))

    fill=$(printf "%${done}s")
    empty=$(printf "%${left}s")

    printf "${CYAN}Progress:${NC} [${GREEN}${fill// /#}${NC}${empty// /-}] %d%%\n" "$progress"
}

next_step() {
    ((CURRENT_STEP++))
    draw_progress_bar
}

check_root() {

    if [[ $EUID -ne 0 ]]; then
        error "Este script debe ejecutarse como root."
        exit 1
    fi
}

run_cmd() {

    local CMD="$1"
    local DESC="$2"

    title "$DESC"

    echo -e "${CYAN}Comando:${NC}"
    echo "$CMD"
    echo ""

    log "$DESC"
    log "CMD: $CMD"

    bash -c "$CMD" 2>&1 | tee -a "$LOG_FILE"

    CMD_EXIT=${PIPESTATUS[0]}

    echo ""

    if [[ $CMD_EXIT -eq 0 ]]; then
        ok "$DESC completado correctamente."
    else
        error "$DESC falló."
        error "Revisar log: $LOG_FILE"
        exit 1
    fi

    next_step
}

# =========================
# INICIO
# =========================

clear

echo -e "${MAGENTA}"
echo "======================================================="
echo "      START-UP UBUNTU - ZABBIX + KASPERSKY"
echo "======================================================="
echo -e "${NC}"

check_root

HOSTNAME_CURRENT=$(hostname)

info "Hostname detectado: $HOSTNAME_CURRENT"

echo ""
draw_progress_bar

# =========================
# VALIDAR INTERNET
# =========================

title "VALIDANDO CONECTIVIDAD"

if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    ok "Conectividad OK."
else
    error "Sin conectividad a Internet."
    exit 1
fi

next_step

# =========================
# UPDATE Y UPGRADE
# =========================

run_cmd \
"apt update && apt upgrade -y" \
"ACTUALIZANDO SISTEMA"

# =========================
# INSTALAR ZABBIX
# =========================

if dpkg -l | grep -q zabbix-agent; then

    warn "Zabbix Agent ya está instalado."
    next_step

else

    run_cmd \
    "apt install zabbix-agent -y" \
    "INSTALANDO ZABBIX AGENT"

fi

# =========================
# CONFIGURAR ZABBIX
# =========================

title "CONFIGURANDO ZABBIX AGENT"

ZABBIX_CONF="/etc/zabbix/zabbix_agentd.conf"

if [[ -f "$ZABBIX_CONF" ]]; then

    sed -i "s/^Server=.*/Server=${ZABBIX_SERVER}/" "$ZABBIX_CONF"
    sed -i "s/^ServerActive=.*/ServerActive=${ZABBIX_SERVER}/" "$ZABBIX_CONF"

    if grep -q "^Hostname=" "$ZABBIX_CONF"; then
        sed -i "s/^Hostname=.*/Hostname=${HOSTNAME_CURRENT}/" "$ZABBIX_CONF"
    else
        echo "Hostname=${HOSTNAME_CURRENT}" >> "$ZABBIX_CONF"
    fi

    ok "Configuración aplicada."

    echo ""
    info "Configuración actual:"
    grep -E "Server=|ServerActive=|Hostname=" "$ZABBIX_CONF"

else

    error "No se encontró:"
    echo "$ZABBIX_CONF"
    exit 1

fi

next_step

# =========================
# RESTART ZABBIX
# =========================

run_cmd \
"systemctl restart zabbix-agent && systemctl enable zabbix-agent" \
"REINICIANDO ZABBIX AGENT"

# =========================
# STATUS ZABBIX
# =========================

run_cmd \
"systemctl status zabbix-agent --no-pager -l" \
"VERIFICANDO SERVICIO ZABBIX"

# =========================
# VALIDAR DEB KASPERSKY
# =========================

title "VALIDANDO INSTALADOR KASPERSKY"

echo -e "${CYAN}Archivo esperado:${NC}"
echo "$KAS_PATH"
echo ""

if [[ ! -f "$KAS_PATH" ]]; then

    error "No se encontró el paquete .deb"
    echo ""

    warn "Copiá el archivo:"
    echo "$KAS_DEB"
    echo ""

    warn "Dentro de /tmp"
    exit 1

fi

ok "Paquete encontrado."

next_step

# =========================
# INSTALAR KASPERSKY
# =========================

if dpkg -l | grep -i -q klnagent; then

    warn "Kaspersky Agent ya está instalado."
    next_step

else

    run_cmd \
    "dpkg -i \"$KAS_PATH\"" \
    "INSTALANDO KASPERSKY AGENT"

    run_cmd \
    "apt-get install -f -y" \
    "CORRIGIENDO DEPENDENCIAS"

fi

# =========================
# VALIDAR KLMOVER
# =========================

if [[ -f "/opt/kaspersky/klnagent64/bin/klmover" ]]; then

    ok "KLMOVER encontrado."
    next_step

else

    error "No se encontró klmover."
    exit 1

fi

# =========================
# ASOCIAR KSC
# =========================

run_cmd \
"/opt/kaspersky/klnagent64/bin/klmover -address ${KASPERSKY_SERVER}" \
"ASOCIANDO KASPERSKY AL KSC"

# =========================
# RESTART KASPERSKY
# =========================

run_cmd \
"systemctl restart klnagent" \
"REINICIANDO KASPERSKY"

# =========================
# STATUS KASPERSKY
# =========================

run_cmd \
"systemctl status klnagent --no-pager -l" \
"VERIFICANDO SERVICIO KASPERSKY"

# =========================
# FIN
# =========================

echo ""

echo -e "${GREEN}"
echo "======================================================="
echo "             PROCESO FINALIZADO"
echo "======================================================="
echo -e "${NC}"

echo -e "${CYAN}Hostname:${NC} $HOSTNAME_CURRENT"
echo -e "${CYAN}Zabbix Server:${NC} $ZABBIX_SERVER"
echo -e "${CYAN}Kaspersky Server:${NC} $KASPERSKY_SERVER"
echo -e "${CYAN}Log:${NC} $LOG_FILE"

echo ""