#!/bin/bash

###############################################################################
# Wazuh Agent Installer
# Version : 1.0
# Autor   : ChatGPT
###############################################################################

set -euo pipefail

VERSION="1.0"
LOGFILE="/var/log/wazuh-agent-installer.log"

PKG="wazuh-agent_4.14.4-1_amd64.deb"
URL="https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/${PKG}"

DEFAULT_MANAGER="172.29.230.244"

################################################################################
# Colores
################################################################################

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
WHITE="\e[97m"
GRAY="\e[90m"
BOLD="\e[1m"
RESET="\e[0m"

################################################################################

log() {
    echo "$(date '+%F %T') - $1" >> "$LOGFILE"
}

ok() {
    echo -e "${GREEN}✔${RESET} $1"
    log "$1"
}

info() {
    echo -e "${CYAN}ℹ${RESET} $1"
    log "$1"
}

warn() {
    echo -e "${YELLOW}⚠${RESET} $1"
    log "$1"
}

error() {
    echo -e "${RED}✘${RESET} $1"
    log "ERROR: $1"
    exit 1
}

################################################################################

clear

echo -e "${BLUE}${BOLD}"
echo "══════════════════════════════════════════════════════════════════════"
echo "                     WAZUH AGENT INSTALLER"
echo "                          Version ${VERSION}"
echo "══════════════════════════════════════════════════════════════════════"
echo -e "${RESET}"

################################################################################
# Root
################################################################################

[[ $EUID -eq 0 ]] || error "Este script debe ejecutarse como root."

################################################################################
# SO
################################################################################

if ! grep -qi "ubuntu\|debian" /etc/os-release; then
    error "Sistema operativo no soportado."
fi

################################################################################
# Arquitectura
################################################################################

ARCH=$(dpkg --print-architecture)

[[ "$ARCH" == "amd64" ]] || error "Arquitectura no soportada ($ARCH)."

################################################################################
# Internet
################################################################################

info "Verificando conectividad..."

ping -c2 packages.wazuh.com >/dev/null 2>&1 || \
error "No hay conectividad hacia packages.wazuh.com"

ok "Conectividad correcta."

################################################################################
# Ya instalado
################################################################################

if dpkg -l | grep -q wazuh-agent; then
    warn "Wazuh Agent ya se encuentra instalado."

    read -rp "¿Desea reinstalarlo? (s/N): " RESP

    [[ "$RESP" =~ ^[sS]$ ]] || exit 0
fi

################################################################################
# Datos
################################################################################

echo
read -rp "IP del Wazuh Manager [${DEFAULT_MANAGER}]: " MANAGER

MANAGER=${MANAGER:-$DEFAULT_MANAGER}

echo

echo -e "${WHITE}Equipo:${RESET}     $(hostname)"
echo -e "${WHITE}Sistema:${RESET}    $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
echo -e "${WHITE}Arquitectura:${RESET} ${ARCH}"
echo -e "${WHITE}Manager:${RESET}    ${MANAGER}"

echo

################################################################################
# Descarga
################################################################################

info "Descargando paquete..."

rm -f "/tmp/${PKG}"

wget -q \
-O "/tmp/${PKG}" \
"$URL" || error "No fue posible descargar el paquete."

ok "Descarga completada."

################################################################################
# Instalación
################################################################################

info "Instalando Wazuh Agent..."

WAZUH_MANAGER="$MANAGER" dpkg -i "/tmp/${PKG}" \
|| error "Falló la instalación."

ok "Instalación completada."

################################################################################
# Servicios
################################################################################

info "Configurando servicio..."

systemctl daemon-reload

systemctl enable wazuh-agent >/dev/null

systemctl restart wazuh-agent

ok "Servicio iniciado."

################################################################################
# Estado
################################################################################

echo
echo -e "${BLUE}──────────────────────────────────────────────────────────────${RESET}"

systemctl --no-pager --full status wazuh-agent | head -15

echo -e "${BLUE}──────────────────────────────────────────────────────────────${RESET}"

VERSION_INST=$(dpkg -s wazuh-agent | awk -F': ' '/Version/ {print $2}')

echo
ok "Versión instalada: ${VERSION_INST}"

################################################################################
# Limpieza
################################################################################

rm -f "/tmp/${PKG}"

echo
echo -e "${GREEN}${BOLD}"
echo "══════════════════════════════════════════════════════════════"
echo "        INSTALACIÓN FINALIZADA CORRECTAMENTE"
echo "══════════════════════════════════════════════════════════════"
echo -e "${RESET}"

exit 0