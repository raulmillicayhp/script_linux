#!/bin/bash

# ==================================================
# AUDITORÍA AVANZADA DE REINICIOS Y EVENTOS
# UBUNTU / DEBIAN
# ==================================================

# ==================================================
# COLORES
# ==================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ==================================================
# LOG FILE
# ==================================================

LOG_DIR="/var/log/auditoria"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/auditoria_$(date +%F_%H-%M-%S).log"

exec > >(tee -a "$LOG_FILE")
exec 2>&1

# ==================================================
# FUNCIONES
# ==================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_critico() {
    echo -e "${RED}[CRITICO]${NC} $1"
}

linea() {
    echo -e "${CYAN}============================================================${NC}"
}

# ==================================================
# VALIDACIÓN ROOT
# ==================================================

clear

linea
echo -e "${CYAN}        AUDITORÍA AVANZADA UBUNTU${NC}"
linea
echo

if [[ $EUID -ne 0 ]]; then
    log_error "Debe ejecutar el script como root o con sudo."
    exit 1
fi

log_ok "Permisos verificados."
echo

# ==================================================
# PEDIR FECHA
# ==================================================

echo -e "${YELLOW}Formato esperado:${NC} May 18"
echo -e "${YELLOW}Ejemplo:${NC} May 18"
echo

read -p "Ingrese la fecha a buscar: " fecha

if [[ -z "$fecha" ]]; then
    log_error "Debe ingresar una fecha."
    exit 1
fi

echo

# ==================================================
# VARIABLES RESUMEN
# ==================================================

total_reboots=0
total_shutdowns=0
total_criticos=0

# ==================================================
# REBOOTS Y SHUTDOWNS
# ==================================================

linea
echo -e "${CYAN}   EVENTOS DE REBOOT / SHUTDOWN${NC}"
linea
echo

log_info "Consultando historial con last..."

resultado_last=$(last reboot shutdown | grep "$fecha")

if [[ -z "$resultado_last" ]]; then
    log_warn "No se encontraron eventos."
else
    echo -e "${GREEN}$resultado_last${NC}"

    total_reboots=$(echo "$resultado_last" | grep reboot | wc -l)
    total_shutdowns=$(echo "$resultado_last" | grep shutdown | wc -l)
fi

echo

# ==================================================
# AUTH.LOG + ROTADOS
# ==================================================

linea
echo -e "${CYAN}   EVENTOS AUTH.LOG Y ROTADOS${NC}"
linea
echo

log_info "Analizando logs auth.log y archivos rotados..."

resultado_auth=$(zgrep -h "$fecha" /var/log/auth.log* 2>/dev/null | grep -Ei "sudo|reboot|shutdown|systemd-logind")

if [[ -z "$resultado_auth" ]]; then
    log_warn "No se encontraron eventos."
else
    echo -e "${YELLOW}$resultado_auth${NC}"
fi

echo

# ==================================================
# USUARIOS DETECTADOS
# ==================================================

linea
echo -e "${CYAN}   USUARIOS DETECTADOS${NC}"
linea
echo

usuarios=$(echo "$resultado_auth" | grep sudo | awk '{print $1,$2,$3,"-> Usuario:",$9}' | sort | uniq)

if [[ -z "$usuarios" ]]; then
    log_warn "No se identificaron usuarios."
else
    echo -e "${GREEN}$usuarios${NC}"
fi

echo

# ==================================================
# HISTORIAL DE COMANDOS
# ==================================================

linea
echo -e "${CYAN}   HISTORIAL DE COMANDOS${NC}"
linea
echo

log_info "Mostrando últimos comandos ejecutados..."

echo

# ROOT

if [[ -f /root/.bash_history ]]; then

    echo -e "${MAGENTA}========== HISTORIAL ROOT ==========${NC}"

    tail -n 50 /root/.bash_history

    echo
fi

# USUARIOS

for home in /home/*; do

    usuario=$(basename "$home")

    if [[ -f "$home/.bash_history" ]]; then

        echo -e "${MAGENTA}========== HISTORIAL USUARIO: $usuario ==========${NC}"

        tail -n 50 "$home/.bash_history"

        echo
    fi
done

# ==================================================
# EVENTOS CRÍTICOS
# ==================================================

linea
echo -e "${CYAN}   EVENTOS CRÍTICOS DETECTADOS${NC}"
linea
echo

log_info "Buscando comandos potencialmente peligrosos..."

echo

eventos_criticos=$(zgrep -h "$fecha" /var/log/auth.log* 2>/dev/null | \
grep -Ei "reboot|shutdown|userdel|passwd|rm -rf|chmod 777|systemctl stop|poweroff|halt")

if [[ -z "$eventos_criticos" ]]; then

    log_ok "No se detectaron eventos críticos."

else

    while IFS= read -r linea_critica; do

        log_critico "$linea_critica"

    done <<< "$eventos_criticos"

    total_criticos=$(echo "$eventos_criticos" | wc -l)

fi

echo

# ==================================================
# JOURNALCTL
# ==================================================

linea
echo -e "${CYAN}   EVENTOS JOURNALCTL${NC}"
linea
echo

log_info "Consultando eventos systemd..."

journalctl --since "$fecha 00:00:00" \
           --until "$fecha 23:59:59" 2>/dev/null | \
grep -Ei "reboot|shutdown|sudo|power|halt" | tail -n 50

echo

# ==================================================
# RESUMEN EJECUTIVO
# ==================================================

linea
echo -e "${CYAN}   RESUMEN EJECUTIVO${NC}"
linea
echo

echo -e "${GREEN}Reinicios detectados:${NC} $total_reboots"
echo -e "${GREEN}Shutdowns detectados:${NC} $total_shutdowns"
echo -e "${GREEN}Eventos críticos:${NC} $total_criticos"

echo

echo -e "${GREEN}Usuarios involucrados:${NC}"
echo "$usuarios"

echo

echo -e "${GREEN}Archivo de auditoría generado:${NC}"
echo "$LOG_FILE"

echo

# ==================================================
# FINAL
# ==================================================

linea
log_ok "Auditoría finalizada correctamente."
linea
