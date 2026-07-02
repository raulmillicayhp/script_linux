#!/bin/bash

set -uo pipefail

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

# =========================
# INICIO
# =========================

clear

echo -e "${CYAN}"
echo "=================================================="
echo "      UBUNTU SECURITY PATCH INSTALLER"
echo "=================================================="
echo -e "${NC}"

info "Host: $(hostname)"
info "Kernel: $(uname -r)"
info "Fecha: $(date '+%d-%m-%Y %H:%M:%S')"

echo

# =========================
# UPDATE
# =========================

info "Actualizando índices APT..."

if apt-get update; then
    ok "Repositorios actualizados correctamente."
else
    error "Falló la actualización de repositorios."
    exit 1
fi

echo

# =========================
# SAFE PACKAGES
# =========================

info "Detectando actualizaciones seguras del sistema operativo..."

SAFE_PACKAGES=$(apt list --upgradable 2>/dev/null | \
awk -F/ 'NR>1 {print $1}' | \
grep -E '^(libc6|libssl|openssl|bash|coreutils|apt|dpkg|sudo|login|passwd|tzdata|ca-certificates|openssh-client)' | \
sort -u || true)

# =========================
# WARNING PACKAGES
# =========================

WARN_PACKAGES=$(apt list --upgradable 2>/dev/null | \
awk -F/ 'NR>1 {print $1}' | \
grep -E '^(systemd|systemd-|util-linux|linux-image|linux-headers|linux-modules|openssh-server|docker|containerd|nginx|apache2|postgresql|mysql|mariadb)' | \
sort -u || true)

# =========================
# WARNINGS
# =========================

if [ -n "${WARN_PACKAGES:-}" ]; then

    echo
    echo -e "${YELLOW}"
    echo "=================================================="
    echo "         ACTUALIZACIONES CRÍTICAS DETECTADAS"
    echo "=================================================="
    echo -e "${NC}"

    warn "Los siguientes paquetes NO serán instalados automáticamente:"
    echo

    for pkg in $WARN_PACKAGES; do
        echo -e "   ${YELLOW}•${NC} $pkg"
    done

    echo
    warn "RECOMENDACIONES:"
    echo -e "   ${CYAN}•${NC} Revisar CVEs asociados"
    echo -e "   ${CYAN}•${NC} Programar ventana de mantenimiento"
    echo -e "   ${CYAN}•${NC} Verificar impacto en servicios"
    echo -e "   ${CYAN}•${NC} Validar backups/snapshots"
    echo -e "   ${CYAN}•${NC} Monitorear Docker/Nginx/SSH luego del update"

fi

# =========================
# SAFE INSTALL
# =========================

echo

if [ -z "${SAFE_PACKAGES:-}" ]; then
    ok "No hay actualizaciones seguras para instalar."
    exit 0
fi

warn "Paquetes seguros detectados:"

echo

for pkg in $SAFE_PACKAGES; do
    echo -e "   ${CYAN}•${NC} $pkg"
done

echo

read -p "$(echo -e ${YELLOW}"¿Desea instalar las actualizaciones seguras? [y/N]: "${NC})" CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    warn "Operación cancelada."
    exit 1
fi

echo

# =========================
# SIMULACION
# =========================

info "Simulando instalación..."

echo

apt-get -s install --only-upgrade $SAFE_PACKAGES

echo

read -p "$(echo -e ${YELLOW}"¿Continuar con la instalación real? [y/N]: "${NC})" CONFIRM2

if [[ ! "$CONFIRM2" =~ ^[Yy]$ ]]; then
    warn "Instalación cancelada."
    exit 1
fi

echo

# =========================
# INSTALL
# =========================

info "Instalando actualizaciones seguras..."

export NEEDRESTART_MODE=l

if apt-get install --only-upgrade $SAFE_PACKAGES; then
    ok "Actualizaciones instaladas correctamente."
else
    error "Ocurrió un error durante la instalación."
    exit 1
fi

echo

# =========================
# AUTOREMOVE
# =========================

info "Limpiando paquetes innecesarios..."

apt-get autoremove -y >/dev/null 2>&1

ok "Limpieza completada."

echo

# =========================
# REBOOT
# =========================

if [ -f /var/run/reboot-required ]; then

    echo -e "${YELLOW}"
    echo "=================================================="
    echo "              REINICIO REQUERIDO"
    echo "=================================================="
    echo -e "${NC}"

    cat /var/run/reboot-required.pkgs 2>/dev/null || true

else

    ok "No se requiere reinicio."

fi

echo

echo -e "${GREEN}"
echo "=================================================="
echo "               PROCESO FINALIZADO"
echo "=================================================="
echo -e "${NC}"
