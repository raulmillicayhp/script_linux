#!/bin/bash

# =========================================================
# START-UP UBUNTU - ZABBIX + KASPERSKY
# VERSION CON BARRA DE PROGRESO
# =========================================================

# =========================
# VARIABLES
# =========================

ZABBIX_SERVER="172.29.230.10"
KASPERSKY_SERVER="172.29.230.84"

KAS_SCRIPT="klnagent64_15.4.0-8873_amd64.sh"
KAS_PATH="/nas4/it/Software/Kaspersky"

LOG_FILE="/var/log/startup_linux.log"

TOTAL_STEPS=9
CURRENT_STEP=0

# =========================
# COLORES
# =========================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

draw_progress_bar() {

    local progress=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local done=$((progress / 2))
    local left=$((50 - done))

    fill=$(printf "%${done}s")
    empty=$(printf "%${left}s")

    printf "\r${CYAN}Progress:${NC} [${GREEN}${fill// /#}${NC}${empty// /-}] %d%%" "$progress"
}

next_step() {
    ((CURRENT_STEP++))
    draw_progress_bar
    echo ""
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

    info "$DESC"

    eval "$CMD" >> "$LOG_FILE" 2>&1

    if [[ $? -eq 0 ]]; then
        ok "$DESC completado."
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

echo "======================================================="
echo "      START-UP UBUNTU - ZABBIX + KASPERSKY"
echo "======================================================="
echo ""

check_root

HOSTNAME_CURRENT=$(hostname)

info "Hostname detectado: $HOSTNAME_CURRENT"
echo ""

draw_progress_bar
echo ""

# =========================
# UPDATE Y UPGRADE
# =========================

run_cmd \
"apt update && apt upgrade -y" \
"Actualizando sistema"

# =========================
# INSTALAR ZABBIX
# =========================

run_cmd \
"apt install zabbix-agent -y" \
"Instalando Zabbix Agent"

# =========================
# CONFIGURAR ZABBIX
# =========================

ZABBIX_CONF="/etc/zabbix/zabbix_agentd.conf"

info "Configurando Zabbix Agent"

if [[ -f "$ZABBIX_CONF" ]]; then

    sed -i "s/^Server=.*/Server=${ZABBIX_SERVER}/" "$ZABBIX_CONF"
    sed -i "s/^ServerActive=.*/ServerActive=${ZABBIX_SERVER}/" "$ZABBIX_CONF"

    if grep -q "^Hostname=" "$ZABBIX_CONF"; then
        sed -i "s/^Hostname=.*/Hostname=${HOSTNAME_CURRENT}/" "$ZABBIX_CONF"
    else
        echo "Hostname=${HOSTNAME_CURRENT}" >> "$ZABBIX_CONF"
    fi

    ok "Configuración de Zabbix aplicada."

else
    error "No se encontró el archivo:"
    echo "$ZABBIX_CONF"
    exit 1
fi

next_step

# =========================
# RESTART ZABBIX
# =========================

run_cmd \
"systemctl restart zabbix-agent && systemctl enable zabbix-agent" \
"Reiniciando y habilitando Zabbix Agent"

# =========================
# COPIAR KASPERSKY
# =========================

FULL_KAS_SCRIPT="${KAS_PATH}/${KAS_SCRIPT}"

if [[ ! -f "$FULL_KAS_SCRIPT" ]]; then
    error "No se encontró el instalador:"
    echo "$FULL_KAS_SCRIPT"
    exit 1
fi

run_cmd \
"cp $FULL_KAS_SCRIPT /tmp/" \
"Copiando instalador de Kaspersky"

# =========================
# DAR PERMISOS
# =========================

run_cmd \
"chmod +x /tmp/${KAS_SCRIPT}" \
"Asignando permisos al instalador"

# =========================
# INSTALAR KASPERSKY
# =========================

run_cmd \
"/tmp/${KAS_SCRIPT}" \
"Instalando Kaspersky Agent"

# =========================
# MOVER AGENTE
# =========================

run_cmd \
"/opt/kaspersky/klnagent64/bin/klmover -address ${KASPERSKY_SERVER}" \
"Conectando Kaspersky al servidor"

# =========================
# RESTART KASPERSKY
# =========================

run_cmd \
"systemctl restart klnagent" \
"Reiniciando servicio Kaspersky"

# =========================
# VALIDACIONES
# =========================

echo ""
echo "======================================================="
echo "                   VALIDACIONES"
echo "======================================================="
echo ""

systemctl is-active --quiet zabbix-agent

if [[ $? -eq 0 ]]; then
    ok "Zabbix Agent funcionando."
else
    error "Zabbix Agent NO está funcionando."
fi

systemctl is-active --quiet klnagent

if [[ $? -eq 0 ]]; then
    ok "Kaspersky Agent funcionando."
else
    error "Kaspersky Agent NO está funcionando."
fi

echo ""

echo "======================================================="
ok "Proceso finalizado correctamente."
echo "======================================================="
echo ""

echo -e "${CYAN}Log:${NC} $LOG_FILE"
echo ""