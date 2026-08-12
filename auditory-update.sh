#!/bin/bash

# ==================================================
# UBUNTU UPDATE REPORT
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
# FUNCIONES
# ==================================================

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

ok() {
    echo -e "${GREEN}[ OK ]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

section() {
    echo
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}==================================================${NC}"
}

# ==================================================
# VARIABLES
# ==================================================

OUTPUT="./reporte_updates_$(hostname)_$(date +%Y%m%d_%H%M).txt"

# ==================================================
# INICIO
# ==================================================

clear

echo -e "${MAGENTA}"
echo "=================================================="
echo "        UBUNTU UPDATE REPORT"
echo "=================================================="
echo -e "${NC}"

info "Host: $(hostname)"
info "Fecha: $(TZ=America/Argentina/Cordoba date '+%d-%m-%Y %H:%M:%S %Z')"
info "Kernel: $(uname -r)"
info "SO: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
info "Uptime: $(uptime -p)"

echo

# ==================================================
# ARCHIVO
# ==================================================

{
echo "=================================================="
echo "UBUNTU UPDATE REPORT"
echo "=================================================="
echo "Host: $(hostname)"
echo "Fecha: $(TZ=America/Argentina/Cordoba date '+%d-%m-%Y %H:%M:%S %Z')"
echo "Kernel: $(uname -r)"
echo "SO: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
echo "Uptime: $(uptime -p)"
echo ""
} > "$OUTPUT"

# ==================================================
# UPDATE
# ==================================================

section "ACTUALIZANDO ÍNDICES APT"

info "Actualizando repositorios..."

if sudo apt update -qq >> "$OUTPUT" 2>&1; then
    ok "Repositorios actualizados correctamente."
else
    error "Error actualizando repositorios."
    exit 1
fi

# ==================================================
# PAQUETES ACTUALIZABLES
# ==================================================

section "PAQUETES ACTUALIZABLES"

UPGRADABLE=$(apt list --upgradable 2>/dev/null)
COUNT=$(echo "$UPGRADABLE" | grep -v "Listing..." | wc -l)

echo "==================================================" >> "$OUTPUT"
echo "PAQUETES ACTUALIZABLES" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"
echo "$UPGRADABLE" >> "$OUTPUT"

info "Cantidad detectada: $COUNT"

# ==================================================
# SECURITY
# ==================================================

section "ACTUALIZACIONES DE SEGURIDAD"

SECURITY=$(apt list --upgradable 2>/dev/null | grep -i security || true)

echo "==================================================" >> "$OUTPUT"
echo "ACTUALIZACIONES DE SEGURIDAD" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

if [ -z "$SECURITY" ]; then

    ok "No se detectaron actualizaciones de seguridad."

    echo "No se detectaron actualizaciones de seguridad." >> "$OUTPUT"

else

    warn "Se detectaron actualizaciones de seguridad."

    echo "$SECURITY" >> "$OUTPUT"

    echo

    while IFS= read -r line; do
        echo -e " ${YELLOW}•${NC} $line"
    done <<< "$SECURITY"

fi

# ==================================================
# COMPONENTES CRÍTICOS
# ==================================================

section "COMPONENTES CRÍTICOS"

CRITICOS=$(apt list --upgradable 2>/dev/null | \
egrep "linux-image|linux-headers|linux-modules|openssl|libc|systemd|openssh|docker|containerd|nginx|apache2|postgresql|mysql|mariadb|redis|grafana|prometheus|wazuh" || true)

echo "==================================================" >> "$OUTPUT"
echo "COMPONENTES CRÍTICOS" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

if [ -z "$CRITICOS" ]; then

    ok "No se detectaron componentes críticos."

    echo "No se detectaron componentes críticos." >> "$OUTPUT"

else

    warn "Componentes críticos detectados."

    echo "$CRITICOS" >> "$OUTPUT"

    echo

    while IFS= read -r line; do
        echo -e " ${RED}•${NC} $line"
    done <<< "$CRITICOS"

fi

# ==================================================
# SERVICIOS ACTIVOS
# ==================================================

section "SERVICIOS CRÍTICOS ACTIVOS"

SERVICES=$(systemctl list-units --type=service --state=running | \
egrep "nginx|apache2|docker|postgresql|mysql|mariadb|redis|ssh|wazuh|grafana|prometheus|kaspersky|kesl|klnagent" || true)

echo "==================================================" >> "$OUTPUT"
echo "SERVICIOS CRÍTICOS ACTIVOS" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

if [ -z "$SERVICES" ]; then

    ok "No se detectaron servicios críticos."

    echo "No se detectaron servicios críticos." >> "$OUTPUT"

else

    warn "Servicios críticos activos detectados."

    echo "$SERVICES" >> "$OUTPUT"

    echo

    while IFS= read -r line; do
        echo -e " ${CYAN}•${NC} $line"
    done <<< "$SERVICES"

fi

# ==================================================
# SERVICIOS FALLANDO
# ==================================================

section "SERVICIOS FALLANDO"

FAILED=$(systemctl --failed --no-pager || true)

echo "==================================================" >> "$OUTPUT"
echo "SERVICIOS FALLANDO" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"
echo "$FAILED" >> "$OUTPUT"

if echo "$FAILED" | grep -q failed; then

    warn "Servicios fallando detectados."

    echo "$FAILED"

else

    ok "No hay servicios fallando."

fi

# ==================================================
# NEEDRESTART
# ==================================================

section "PROCESOS CON LIBRERÍAS ANTIGUAS"

echo "==================================================" >> "$OUTPUT"
echo "PROCESOS CON LIBRERÍAS ANTIGUAS" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

if command -v needrestart >/dev/null 2>&1; then

    NEEDRESTART_OUTPUT=$(needrestart -b 2>/dev/null || true)

    if [ -z "$NEEDRESTART_OUTPUT" ]; then

        ok "No se detectaron procesos pendientes de restart."

        echo "No se detectaron procesos pendientes de restart." >> "$OUTPUT"

    else

        warn "Procesos con librerías antiguas detectados."

        echo "$NEEDRESTART_OUTPUT" >> "$OUTPUT"

        echo "$NEEDRESTART_OUTPUT"

    fi

else

    warn "needrestart no está instalado."

fi

# ==================================================
# KERNEL
# ==================================================

section "VALIDACIÓN DE KERNEL"

RUNNING_KERNEL=$(uname -r)
LATEST_KERNEL=$(dpkg -l | grep linux-image | grep ^ii | awk '{print $2}' | sort | tail -1)

echo "==================================================" >> "$OUTPUT"
echo "VALIDACIÓN DE KERNEL" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

echo "Kernel actual: $RUNNING_KERNEL" >> "$OUTPUT"
echo "Último kernel instalado: $LATEST_KERNEL" >> "$OUTPUT"

if [[ "$LATEST_KERNEL" != *"$RUNNING_KERNEL"* ]]; then

    warn "Existe un kernel más nuevo instalado."

    echo
    echo -e " ${YELLOW}Kernel actual:${NC} $RUNNING_KERNEL"
    echo -e " ${YELLOW}Kernel instalado:${NC} $LATEST_KERNEL"

else

    ok "El kernel cargado es el más reciente."

fi

# ==================================================
# ESPACIO EN DISCO
# ==================================================

section "ESPACIO EN DISCO"

DISK=$(df -h /)

echo "==================================================" >> "$OUTPUT"
echo "ESPACIO EN DISCO" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

echo "$DISK" >> "$OUTPUT"

echo "$DISK"

USAGE=$(df / | awk 'END {print $5}' | sed 's/%//')

if [ "$USAGE" -ge 85 ]; then
    warn "Uso de disco mayor al 85%."
else
    ok "Espacio en disco OK."
fi

# ==================================================
# PAQUETES HOLD
# ==================================================

section "PAQUETES EN HOLD"

HOLDS=$(apt-mark showhold || true)

echo "==================================================" >> "$OUTPUT"
echo "PAQUETES EN HOLD" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

echo "$HOLDS" >> "$OUTPUT"

if [ -z "$HOLDS" ]; then

    ok "No hay paquetes bloqueados."

else

    warn "Paquetes bloqueados detectados."

    while IFS= read -r line; do
        echo -e " ${YELLOW}•${NC} $line"
    done <<< "$HOLDS"

fi

# ==================================================
# REPOSITORIOS EXTERNOS
# ==================================================

section "REPOSITORIOS EXTERNOS"

echo "==================================================" >> "$OUTPUT"
echo "REPOSITORIOS EXTERNOS" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

grep -rh ^deb /etc/apt/sources.list* | grep -v ubuntu.com | tee -a "$OUTPUT"

# ==================================================
# HISTORIAL REBOOTS
# ==================================================

#section "ÚLTIMOS REBOOTS"

#echo "==================================================" >> "$OUTPUT"
#echo "ÚLTIMOS REBOOTS" >> "$OUTPUT"
#echo "==================================================" >> "$OUTPUT"

#last reboot | head -5 | tee -a "$OUTPUT"

# ==================================================
# SIMULACION
# ==================================================

section "SIMULACIÓN DE UPGRADE"

info "Ejecutando simulación..."

echo "==================================================" >> "$OUTPUT"
echo "SIMULACIÓN DE UPGRADE" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

sudo apt upgrade -s >> "$OUTPUT" 2>&1

ok "Simulación completada."

# ==================================================
# REBOOT REQUIRED
# ==================================================

section "REINICIO REQUERIDO"

echo "==================================================" >> "$OUTPUT"
echo "REINICIO REQUERIDO" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

if [ -f /var/run/reboot-required ]; then

    warn "El sistema requiere reinicio."

    echo "El sistema REQUIERE reinicio." >> "$OUTPUT"

    if [ -f /var/run/reboot-required.pkgs ]; then

        echo
        info "Paquetes relacionados:"

        while IFS= read -r line; do
            echo -e " ${YELLOW}•${NC} $line"
        done < /var/run/reboot-required.pkgs

        cat /var/run/reboot-required.pkgs >> "$OUTPUT"

    fi

else

    ok "No se requiere reinicio."

    echo "No se requiere reinicio." >> "$OUTPUT"

fi

# ==================================================
# CONCLUSIÓN
# ==================================================

section "CONCLUSIÓN"

echo "==================================================" >> "$OUTPUT"
echo "CONCLUSIÓN" >> "$OUTPUT"
echo "==================================================" >> "$OUTPUT"

if [ "$COUNT" -gt 0 ]; then

    warn "Se recomienda programar mantenimiento."

    echo "Se recomienda programar mantenimiento." >> "$OUTPUT"

else

    ok "Sistema actualizado."

    echo "Sistema actualizado." >> "$OUTPUT"

fi

echo
ok "Reporte generado correctamente."
echo -e "${CYAN}Archivo:${NC} $OUTPUT"

echo

#cat "$OUTPUT"
