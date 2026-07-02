#!/bin/bash

# ==================================================
# CONFIGURACIÓN DE COLORES
# ==================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

log_step() {
    echo -e "${CYAN}[CHECK]${NC} $1"
}

# ==================================================
# INICIO
# ==================================================

echo
echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}      REINICIO SEGURO DE SWAP           ${NC}"
echo -e "${CYAN}=========================================${NC}"
echo

# ==================================================
# VALIDACIÓN ROOT
# ==================================================

log_step "Verificando privilegios de ejecución..."

if [[ $EUID -ne 0 ]]; then
    log_error "El script debe ejecutarse como root."
    echo -e "${YELLOW}Uso:${NC} sudo $0"
    exit 1
fi

log_ok "Privilegios root verificados."

# ==================================================
# VALIDACIÓN SWAP ACTIVA
# ==================================================

echo
log_step "Verificando si existe swap activa..."

if ! swapon --show | grep -q '^'; then
    log_warn "No se detectó ninguna swap activa."
    exit 0
fi

log_ok "Swap activa detectada."

# ==================================================
# MOSTRAR ESTADO ACTUAL
# ==================================================

echo
log_step "Obteniendo estado actual de memoria..."

echo
free -h
echo

log_step "Mostrando dispositivos swap activos..."

swapon --show
echo

# ==================================================
# VALIDACIÓN DE MEMORIA DISPONIBLE
# ==================================================

log_step "Calculando memoria disponible..."

AVAILABLE_RAM_MB=$(free -m | awk '/^Mem:/ {print $7}')
USED_SWAP_MB=$(free -m | awk '/^Swap:/ {print $3}')

echo -e "${BLUE}[INFO]${NC} RAM disponible : ${GREEN}${AVAILABLE_RAM_MB} MB${NC}"
echo -e "${BLUE}[INFO]${NC} Swap utilizada : ${YELLOW}${USED_SWAP_MB} MB${NC}"

# ==================================================
# VALIDAR SI HAY RAM SUFICIENTE
# ==================================================

echo
log_step "Validando capacidad para vaciar la swap..."

if (( USED_SWAP_MB > AVAILABLE_RAM_MB )); then
    log_error "No hay suficiente RAM disponible."
    log_error "La swap utilizada es mayor a la RAM libre."
    log_warn "Operación cancelada por seguridad."
    exit 1
fi

log_ok "Memoria suficiente detectada."

# ==================================================
# CONFIRMACIÓN
# ==================================================

echo
log_step "Solicitando confirmación del usuario..."

read -r -p "$(echo -e ${YELLOW}¿Desea reiniciar la swap? [s/N]: ${NC})" RESP

case "$RESP" in
    s|S|si|SI|yes|YES)
        log_ok "Confirmación recibida."
        ;;
    *)
        log_warn "Operación cancelada por el usuario."
        exit 0
        ;;
esac

# ==================================================
# DESACTIVAR SWAP
# ==================================================

echo
log_step "Iniciando desactivación de swap..."

if swapoff -a; then
    log_ok "Swap desactivada correctamente."
else
    log_error "Falló la desactivación de swap."
    exit 1
fi

sleep 2

# ==================================================
# REACTIVAR SWAP
# ==================================================

echo
log_step "Iniciando reactivación de swap..."

if swapon -a; then
    log_ok "Swap reactivada correctamente."
else
    log_error "Falló la reactivación de swap."

    echo
    log_warn "Intentando recuperación manual..."

    for SWAPDEV in $(awk '!/^#/ && $3 == "swap" {print $1}' /etc/fstab); do
        log_info "Reactivando dispositivo: $SWAPDEV"
        swapon "$SWAPDEV"
    done

    echo
    log_error "Revisar manualmente el estado de swap."
    exit 1
fi

sleep 1

# ==================================================
# VALIDACIÓN FINAL
# ==================================================

echo
log_step "Validando estado final de swap..."

if swapon --show | grep -q '^'; then
    log_ok "La swap quedó activa correctamente."
else
    log_error "La swap NO quedó activa."
    exit 1
fi

# ==================================================
# MOSTRAR RESULTADO FINAL
# ==================================================

echo
log_step "Mostrando estado final de memoria..."

echo
free -h
echo

log_step "Mostrando swap activa..."

swapon --show
echo

# ==================================================
# FIN
# ==================================================

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   PROCESO FINALIZADO CORRECTAMENTE     ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
