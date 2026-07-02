#!/bin/bash

# =========================================================
# DOCKER AUDIT PRE / POST - VERSION 3
# =========================================================
# OBJETIVO:
# - El PRE es el baseline esperado
# - El POST debe coincidir EXACTAMENTE
# - Detecta:
#   * containers faltantes
#   * containers nuevos
#   * cambios de estado
#   * cambios de imagen
#   * cambios de restart policy
#   * cambios de healthcheck
#   * docker service caído
# =========================================================

# ---------------- COLORES ----------------

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ---------------- VALIDAR ROOT ----------------

if [[ $EUID -ne 0 ]]
then
    echo -e "${RED}"
    echo "=================================================="
    echo "[ERROR] Ejecutar con sudo/root"
    echo "=================================================="
    echo ""
    echo "Ejemplo:"
    echo "sudo ./docker_audit_v3.sh"
    echo -e "${NC}"
    exit 1
fi

# ---------------- VALIDAR TMP ----------------

SCRIPT_PATH=$(realpath "$0")

if [[ "$SCRIPT_PATH" == /tmp/* ]]
then
    echo -e "${RED}"
    echo "[ERROR] No ejecutar desde /tmp"
    echo -e "${NC}"
    exit 1
fi

# ---------------- VARIABLES ----------------

BASE_DIR="/opt/docker_audit"

PRE_DIR="$BASE_DIR/pre"
POST_DIR="$BASE_DIR/post"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$PRE_DIR"
mkdir -p "$POST_DIR"
mkdir -p "$LOG_DIR"

HOSTNAME=$(hostname)

# ---------------- FUNCIONES ----------------

banner() {

clear

echo -e "${CYAN}"
echo "=================================================="
echo "         DOCKER AUDIT PRE / POST V3"
echo "=================================================="
echo -e "${NC}"

}

pause() {
    read -p "Presione ENTER para continuar..."
}

check_docker() {

if ! command -v docker &>/dev/null
then
    echo -e "${RED}[ERROR] Docker no instalado.${NC}"
    return 1
fi

if ! systemctl is-active docker &>/dev/null
then
    echo -e "${RED}[ERROR] Docker service no activo.${NC}"
    return 1
fi

return 0

}

# =========================================================
# GENERAR AUDITORIA
# =========================================================

generate_audit() {

TYPE=$1

DATE=$(date +"%Y-%m-%d_%H-%M-%S")

FILE="$BASE_DIR/$TYPE/audit_${HOSTNAME}_${DATE}.csv"

echo ""
echo -e "${BLUE}[INFO] Generando auditoría ${TYPE^^}...${NC}"
echo ""

# HEADER CSV
echo "container,status,image,restart_policy,health" > "$FILE"

docker ps -a --format "{{.Names}}" | while read CONTAINER
do

    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null)

    IMAGE=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER" 2>/dev/null)

    RESTART=$(docker inspect --format='{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER" 2>/dev/null)

    HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER" 2>/dev/null)

    echo "$CONTAINER,$STATUS,$IMAGE,$RESTART,$HEALTH" >> "$FILE"

done

# GUARDAR STATUS DOCKER
DOCKER_STATUS_FILE="$BASE_DIR/$TYPE/docker_service_${DATE}.txt"

systemctl is-active docker > "$DOCKER_STATUS_FILE"

echo -e "${GREEN}[OK] Auditoría generada:${NC}"
echo -e "${YELLOW}$FILE${NC}"

echo ""
echo "$(date) - Auditoría $TYPE generada" >> "$LOG_DIR/history.log"

}

# =========================================================
# COMPARAR AUDITORIAS
# =========================================================

compare_audits() {

PRE_FILE=$(ls -t $PRE_DIR/*.csv 2>/dev/null | head -1)
POST_FILE=$(ls -t $POST_DIR/*.csv 2>/dev/null | head -1)

if [[ -z "$PRE_FILE" || -z "$POST_FILE" ]]
then
    echo -e "${RED}[ERROR] Faltan auditorías PRE/POST.${NC}"
    return
fi

echo ""
echo -e "${CYAN}=================================================="
echo "              COMPARACION PRE vs POST"
echo -e "==================================================${NC}"
echo ""

# =========================================================
# VALIDAR SERVICIO DOCKER
# =========================================================

PRE_DOCKER=$(ls -t $PRE_DIR/docker_service_* 2>/dev/null | head -1)
POST_DOCKER=$(ls -t $POST_DIR/docker_service_* 2>/dev/null | head -1)

PRE_SERVICE=$(cat "$PRE_DOCKER")
POST_SERVICE=$(cat "$POST_DOCKER")

echo -e "${WHITE}SERVICIO DOCKER${NC}"
echo ""

if [[ "$PRE_SERVICE" == "$POST_SERVICE" ]]
then

    echo -e "${GREEN}[OK]${NC} Docker mantiene estado: $POST_SERVICE"

else

    echo -e "${RED}[ERROR] Docker cambió estado${NC}"
    echo "PRE  = $PRE_SERVICE"
    echo "POST = $POST_SERVICE"

fi

echo ""

# =========================================================
# COMPARAR CONTAINERS
# =========================================================

echo -e "${WHITE}CONTAINERS${NC}"
echo ""

tail -n +2 "$PRE_FILE" | while IFS=',' read NAME STATUS IMAGE RESTART HEALTH
do

    POST_LINE=$(grep "^$NAME," "$POST_FILE")

    # -----------------------------------------------------
    # CONTAINER FALTANTE
    # -----------------------------------------------------

    if [[ -z "$POST_LINE" ]]
    then

        echo -e "${RED}[ERROR] Container faltante:${NC} $NAME"
        echo ""
        continue

    fi

    # -----------------------------------------------------
    # OBTENER DATOS POST
    # -----------------------------------------------------

    POST_STATUS=$(echo "$POST_LINE" | cut -d',' -f2)
    POST_IMAGE=$(echo "$POST_LINE" | cut -d',' -f3)
    POST_RESTART=$(echo "$POST_LINE" | cut -d',' -f4)
    POST_HEALTH=$(echo "$POST_LINE" | cut -d',' -f5)

    # -----------------------------------------------------
    # STATUS
    # -----------------------------------------------------

    if [[ "$STATUS" == "$POST_STATUS" ]]
    then

        echo -e "${GREEN}[OK]${NC} $NAME mantiene estado: $STATUS"

    else

        echo -e "${RED}[ERROR] Estado distinto:${NC} $NAME"
        echo "PRE  = $STATUS"
        echo "POST = $POST_STATUS"

    fi

    # -----------------------------------------------------
    # IMAGE
    # -----------------------------------------------------

    if [[ "$IMAGE" != "$POST_IMAGE" ]]
    then

        echo -e "${YELLOW}[WARNING] Imagen distinta:${NC} $NAME"
        echo "PRE  = $IMAGE"
        echo "POST = $POST_IMAGE"

    fi

    # -----------------------------------------------------
    # RESTART POLICY
    # -----------------------------------------------------

    if [[ "$RESTART" != "$POST_RESTART" ]]
    then

        echo -e "${YELLOW}[WARNING] Restart policy distinta:${NC} $NAME"
        echo "PRE  = $RESTART"
        echo "POST = $POST_RESTART"

    fi

    # -----------------------------------------------------
    # HEALTHCHECK
    # -----------------------------------------------------

    if [[ "$HEALTH" != "$POST_HEALTH" ]]
    then

        echo -e "${YELLOW}[WARNING] Healthcheck distinto:${NC} $NAME"
        echo "PRE  = $HEALTH"
        echo "POST = $POST_HEALTH"

    fi

    echo ""

done

# =========================================================
# NUEVOS CONTAINERS
# =========================================================

echo -e "${WHITE}NUEVOS CONTAINERS${NC}"
echo ""

tail -n +2 "$POST_FILE" | while IFS=',' read NAME STATUS IMAGE RESTART HEALTH
do

    if ! grep -q "^$NAME," "$PRE_FILE"
    then

        echo -e "${BLUE}[INFO] Nuevo container detectado:${NC} $NAME"

    fi

done

echo ""

echo "$(date) - Comparación ejecutada" >> "$LOG_DIR/history.log"

}

# =========================================================
# STATUS ACTUAL
# =========================================================

docker_status() {

echo ""
echo -e "${WHITE}SERVICIO DOCKER${NC}"
systemctl is-active docker

echo ""

echo -e "${WHITE}CONTAINERS${NC}"
docker ps -a

echo ""

echo -e "${WHITE}CPU / RAM${NC}"
docker stats --no-stream

echo ""

}

# =========================================================
# LOGS
# =========================================================

view_logs() {

LOGFILE="$LOG_DIR/history.log"

if [[ ! -f "$LOGFILE" ]]
then
    echo -e "${RED}No existen logs.${NC}"
else
    cat "$LOGFILE"
fi

}

# =========================================================
# MENU
# =========================================================

while true
do

banner

echo -e "${WHITE}1) Generar auditoría PRE${NC}"
echo -e "${WHITE}2) Generar auditoría POST${NC}"
echo -e "${WHITE}3) Comparar PRE vs POST${NC}"
echo -e "${WHITE}4) Ver estado actual Docker${NC}"
echo -e "${WHITE}5) Ver logs${NC}"
echo -e "${WHITE}6) Salir${NC}"

echo ""
read -p "Seleccione una opción: " OPTION

case $OPTION in

1)

    check_docker || pause
    generate_audit "pre"
    pause
    ;;

2)

    check_docker || pause
    generate_audit "post"
    pause
    ;;

3)

    compare_audits
    pause
    ;;

4)

    docker_status
    pause
    ;;

5)

    view_logs
    pause
    ;;

6)

    echo ""
    echo -e "${GREEN}Saliendo...${NC}"
    echo ""
    exit 0
    ;;

*)

    echo ""
    echo -e "${RED}Opción inválida.${NC}"
    pause
    ;;

esac

done