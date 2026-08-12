#!/bin/bash

# ============================================================
# ABM DE USUARIOS LINUX - IT ADMINISTRATION
# ============================================================
# Funciones:
#   - Alta de usuarios
#   - Baja de usuarios
#   - Modificación
#   - Sudo
#   - Grupos
#   - Password
#   - Bloqueo / desbloqueo
#   - Información
#   - Auditoría
#
# Compatible principalmente con:
#   Debian / Ubuntu
#   RHEL / Rocky / AlmaLinux / CentOS
#
# Ejecutar como root o con sudo
# ============================================================

# -----------------------------
# COLORES
# -----------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# -----------------------------
# CONFIGURACIÓN
# -----------------------------

LOG_FILE="/var/log/abm_usuarios.log"

# -----------------------------
# FUNCIONES VISUALES
# -----------------------------

clear_screen() {
    clear
}

header() {
    clear_screen

    echo -e "${CYAN}"
    echo "============================================================"
    echo "              ABM DE USUARIOS LINUX - IT"
    echo "============================================================"
    echo -e "${NC}"
}

pause() {
    echo
    read -rp "Presione ENTER para continuar..."
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# -----------------------------
# LOG
# -----------------------------

log_action() {

    local ACTION="$1"
    local USER="$2"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | Usuario: $(whoami) | Acción: $ACTION | Target: $USER" >> "$LOG_FILE"
}

# -----------------------------
# VALIDAR ROOT
# -----------------------------

check_root() {

    if [[ $EUID -ne 0 ]]; then

        error "Este script debe ejecutarse como root."

        echo
        echo "Ejemplo:"
        echo "sudo $0"

        exit 1
    fi
}

# -----------------------------
# DETECTAR SISTEMA
# -----------------------------

detect_sudo_group() {

    if getent group sudo >/dev/null 2>&1; then

        SUDO_GROUP="sudo"

    elif getent group wheel >/dev/null 2>&1; then

        SUDO_GROUP="wheel"

    else

        SUDO_GROUP="sudo"

        warning "No se detectó grupo sudo/wheel."

    fi
}

# -----------------------------
# VALIDAR NOMBRE USUARIO
# -----------------------------

validate_username() {

    local USERNAME="$1"

    if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then

        error "Nombre de usuario inválido."

        echo
        echo "Permitido:"
        echo "- letras minúsculas"
        echo "- números"
        echo "- _"
        echo "- -"

        return 1
    fi

    return 0
}

# -----------------------------
# USUARIO EXISTE
# -----------------------------

user_exists() {

    id "$1" >/dev/null 2>&1
}

# -----------------------------
# ALTA
# -----------------------------

create_user() {

    header

    echo -e "${WHITE}ALTA DE USUARIO${NC}"
    echo

    read -rp "Ingrese nombre del usuario: " USERNAME

    if ! validate_username "$USERNAME"; then
        pause
        return
    fi

    if user_exists "$USERNAME"; then

        error "El usuario '$USERNAME' ya existe."

        pause
        return
    fi

    echo

    read -rp "Nombre completo: " FULLNAME

    echo

    info "Creando usuario..."

    useradd \
        -m \
        -s /bin/bash \
        -c "$FULLNAME" \
        "$USERNAME"

    if [[ $? -ne 0 ]]; then

        error "No fue posible crear el usuario."

        pause
        return
    fi

    success "Usuario creado."

    echo

    info "Directorio HOME:"
    echo "/home/$USERNAME"

    echo

    info "Configuración de contraseña"

    passwd "$USERNAME"

    if [[ $? -ne 0 ]]; then

        warning "El usuario fue creado pero la contraseña no pudo establecerse."

    fi

    echo

    read -rp "¿Desea otorgar permisos sudo? [s/N]: " RESPONSE

    if [[ "$RESPONSE" =~ ^[Ss]$ ]]; then

        usermod -aG "$SUDO_GROUP" "$USERNAME"

        success "Usuario agregado al grupo '$SUDO_GROUP'."

        log_action "ALTA + SUDO" "$USERNAME"

    else

        log_action "ALTA" "$USERNAME"

    fi

    echo

    info "Información final:"

    id "$USERNAME"

    echo

    ls -ld "/home/$USERNAME"

    pause
}

# -----------------------------
# BAJA
# -----------------------------

delete_user() {

    header

    echo -e "${WHITE}BAJA DE USUARIO${NC}"
    echo

    read -rp "Usuario a eliminar: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    # Protección de usuarios críticos

    case "$USERNAME" in

        root|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|gnats|nobody|systemd-network|systemd-resolve|messagebus|sshd)

            error "Usuario protegido. No se permite su eliminación."

            pause
            return

            ;;

    esac

    echo

    warning "Está a punto de eliminar:"
    echo "Usuario : $USERNAME"
    echo "HOME   : /home/$USERNAME"

    echo

    read -rp "¿Está seguro? Escriba ELIMINAR: " CONFIRM

    if [[ "$CONFIRM" != "ELIMINAR" ]]; then

        warning "Operación cancelada."

        pause
        return
    fi

    echo

    read -rp "¿Eliminar también el HOME? [s/N]: " REMOVE_HOME

    if [[ "$REMOVE_HOME" =~ ^[Ss]$ ]]; then

        userdel -r "$USERNAME"

        ACTION="BAJA + HOME"

    else

        userdel "$USERNAME"

        ACTION="BAJA"

    fi

    if [[ $? -eq 0 ]]; then

        success "Usuario eliminado."

        log_action "$ACTION" "$USERNAME"

    else

        error "No fue posible eliminar el usuario."

    fi

    pause
}

# -----------------------------
# CAMBIAR PASSWORD
# -----------------------------

change_password() {

    header

    echo -e "${WHITE}CAMBIAR CONTRASEÑA${NC}"
    echo

    read -rp "Usuario: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    passwd "$USERNAME"

    if [[ $? -eq 0 ]]; then

        success "Contraseña actualizada."

        log_action "CAMBIO PASSWORD" "$USERNAME"

    else

        error "No fue posible cambiar la contraseña."

    fi

    pause
}

# -----------------------------
# DAR SUDO
# -----------------------------

grant_sudo() {

    header

    echo -e "${WHITE}OTORGAR SUDO${NC}"
    echo

    read -rp "Usuario: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    usermod -aG "$SUDO_GROUP" "$USERNAME"

    if [[ $? -eq 0 ]]; then

        success "Usuario agregado al grupo '$SUDO_GROUP'."

        log_action "AGREGAR SUDO" "$USERNAME"

    else

        error "No fue posible otorgar sudo."

    fi

    pause
}

# -----------------------------
# QUITAR SUDO
# -----------------------------

remove_sudo() {

    header

    echo -e "${WHITE}QUITAR SUDO${NC}"
    echo

    read -rp "Usuario: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    echo

    warning "Se quitarán los permisos sudo de '$USERNAME'."

    read -rp "¿Continuar? [s/N]: " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then

        warning "Operación cancelada."

        pause
        return
    fi

    gpasswd -d "$USERNAME" "$SUDO_GROUP"

    if [[ $? -eq 0 ]]; then

        success "Sudo eliminado."

        log_action "QUITAR SUDO" "$USERNAME"

    else

        error "No fue posible quitar sudo."

    fi

    pause
}

# -----------------------------
# AGREGAR GRUPO
# -----------------------------

add_group() {

    header

    echo -e "${WHITE}AGREGAR USUARIO A GRUPO${NC}"
    echo

    read -rp "Usuario: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    read -rp "Grupo: " GROUP

    if ! getent group "$GROUP" >/dev/null; then

        error "El grupo '$GROUP' no existe."

        echo
        read -rp "¿Desea crearlo? [s/N]: " CREATE_GROUP

        if [[ "$CREATE_GROUP" =~ ^[Ss]$ ]]; then

            groupadd "$GROUP"

            success "Grupo creado."

        else

            pause
            return

        fi

    fi

    usermod -aG "$GROUP" "$USERNAME"

    if [[ $? -eq 0 ]]; then

        success "Usuario agregado al grupo."

        log_action "AGREGAR GRUPO $GROUP" "$USERNAME"

    else

        error "No fue posible agregar el usuario."

    fi

    pause
}

# -----------------------------
# QUITAR GRUPO
# -----------------------------

remove_group() {

    header

    echo -e "${WHITE}QUITAR USUARIO DE GRUPO${NC}"
    echo

    read -rp "Usuario: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    read -rp "Grupo: " GROUP

    if ! getent group "$GROUP" >/dev/null; then

        error "El grupo no existe."

        pause
        return
    fi

    gpasswd -d "$USERNAME" "$GROUP"

    if [[ $? -eq 0 ]]; then

        success "Usuario eliminado del grupo."

        log_action "QUITAR GRUPO $GROUP" "$USERNAME"

    else

        error "No fue posible quitar el grupo."

    fi

    pause
}

# -----------------------------
# BLOQUEAR
# -----------------------------

lock_user() {

    header

    echo -e "${WHITE}BLOQUEAR USUARIO${NC}"
    echo

    read -rp "Usuario: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    passwd -l "$USERNAME"

    if [[ $? -eq 0 ]]; then

        success "Usuario bloqueado."

        log_action "BLOQUEAR" "$USERNAME"

    else

        error "No fue posible bloquear el usuario."

    fi

    pause
}

# -----------------------------
# DESBLOQUEAR
# -----------------------------

unlock_user() {

    header

    echo -e "${WHITE}DESBLOQUEAR USUARIO${NC}"
    echo

    read -rp "Usuario: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    passwd -u "$USERNAME"

    if [[ $? -eq 0 ]]; then

        success "Usuario desbloqueado."

        log_action "DESBLOQUEAR" "$USERNAME"

    else

        error "No fue posible desbloquear el usuario."

    fi

    pause
}

# -----------------------------
# CAMBIAR SHELL
# -----------------------------

change_shell() {

    header

    echo -e "${WHITE}CAMBIAR SHELL${NC}"
    echo

    read -rp "Usuario: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    echo

    echo "Shells disponibles:"
    echo

    cat /etc/shells

    echo

    read -rp "Nueva shell: " SHELL

    if [[ ! -x "$SHELL" ]]; then

        error "La shell indicada no existe o no es ejecutable."

        pause
        return
    fi

    usermod -s "$SHELL" "$USERNAME"

    if [[ $? -eq 0 ]]; then

        success "Shell modificada."

        log_action "CAMBIAR SHELL $SHELL" "$USERNAME"

    else

        error "No fue posible modificar la shell."

    fi

    pause
}

# -----------------------------
# INFORMACIÓN
# -----------------------------

user_info() {

    header

    echo -e "${WHITE}INFORMACIÓN DE USUARIO${NC}"
    echo

    read -rp "Usuario: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    echo

    echo -e "${CYAN}--- IDENTIDAD ---${NC}"

    id "$USERNAME"

    echo

    echo -e "${CYAN}--- PASSWD ---${NC}"

    getent passwd "$USERNAME"

    echo

    echo -e "${CYAN}--- GRUPOS ---${NC}"

    groups "$USERNAME"

    echo

    echo -e "${CYAN}--- HOME ---${NC}"

    getent passwd "$USERNAME" | cut -d: -f6

    echo

    echo -e "${CYAN}--- SHELL ---${NC}"

    getent passwd "$USERNAME" | cut -d: -f7

    echo

    echo -e "${CYAN}--- ESTADO PASSWORD ---${NC}"

    passwd -S "$USERNAME"

    echo

    echo -e "${CYAN}--- ÚLTIMO LOGIN ---${NC}"

    lastlog -u "$USERNAME"

    pause
}

# -----------------------------
# LISTAR USUARIOS
# -----------------------------

list_users() {

    header

    echo -e "${WHITE}USUARIOS DEL SISTEMA${NC}"
    echo

    printf "%-20s %-8s %-8s %-30s %-25s\n" \
        "USUARIO" "UID" "GID" "HOME" "SHELL"

    echo "------------------------------------------------------------------------------------------"

    awk -F: '$3 >= 1000 && $1 != "nobody" {
        printf "%-20s %-8s %-8s %-30s %-25s\n",$1,$3,$4,$6,$7
    }' /etc/passwd

    echo

    pause
}

# -----------------------------
# CAMBIAR HOME
# -----------------------------

change_home() {

    header

    echo -e "${WHITE}CAMBIAR HOME${NC}"
    echo

    read -rp "Usuario: " USERNAME

    if ! user_exists "$USERNAME"; then

        error "El usuario no existe."

        pause
        return
    fi

    CURRENT_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)

    echo
    echo "HOME actual:"
    echo "$CURRENT_HOME"

    echo

    read -rp "Nuevo HOME: " NEW_HOME

    if [[ -z "$NEW_HOME" ]]; then

        error "El HOME no puede estar vacío."

        pause
        return
    fi

    usermod -d "$NEW_HOME" -m "$USERNAME"

    if [[ $? -eq 0 ]]; then

        success "HOME actualizado."

        log_action "CAMBIAR HOME $NEW_HOME" "$USERNAME"

    else

        error "No fue posible cambiar el HOME."

    fi

    pause
}

# -----------------------------
# MENU PRINCIPAL
# -----------------------------

main_menu() {

    while true; do

        header

        echo -e "${WHITE}Sistema operativo:${NC} $(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
        echo -e "${WHITE}Grupo sudo:${NC} $SUDO_GROUP"
        echo -e "${WHITE}Hostname:${NC} $(hostname)"
        echo

        echo -e "${CYAN}==================== ABM ====================${NC}"

        echo "  1) Alta de usuario"
        echo "  2) Baja de usuario"
        echo "  3) Cambiar contraseña"

        echo

        echo -e "${CYAN}================== PERMISOS ==================${NC}"

        echo "  4) Otorgar sudo"
        echo "  5) Quitar sudo"
        echo "  6) Agregar grupo"
        echo "  7) Quitar grupo"

        echo

        echo -e "${CYAN}================== ESTADO ===================${NC}"

        echo "  8) Bloquear usuario"
        echo "  9) Desbloquear usuario"

        echo

        echo -e "${CYAN}================ CONFIGURACIÓN ===============${NC}"

        echo " 10) Cambiar shell"
        echo " 11) Cambiar HOME"

        echo

        echo -e "${CYAN}================ INFORMACIÓN ================${NC}"

        echo " 12) Información de usuario"
        echo " 13) Listar usuarios"

        echo

        echo "  0) Salir"

        echo

        read -rp "Seleccione una opción: " OPTION

        case "$OPTION" in

            1)  create_user ;;
            2)  delete_user ;;
            3)  change_password ;;
            4)  grant_sudo ;;
            5)  remove_sudo ;;
            6)  add_group ;;
            7)  remove_group ;;
            8)  lock_user ;;
            9)  unlock_user ;;
            10) change_shell ;;
            11) change_home ;;
            12) user_info ;;
            13) list_users ;;

            0)

                echo
                success "Saliendo del ABM de usuarios."

                exit 0

                ;;

            *)

                error "Opción inválida."

                sleep 1

                ;;

        esac

    done
}

# ============================================================
# INICIO
# ============================================================

check_root

detect_sudo_group

touch "$LOG_FILE"

chmod 600 "$LOG_FILE"

main_menu