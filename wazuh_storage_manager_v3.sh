#!/usr/bin/env bash
# WAZUH STORAGE MANAGER V3
# Compatible con Ubuntu 22.04 y Rocky Linux 9
# Autor: Ingeniero Senior DevOps - Wazuh 4.14.x, OpenSearch, Bash
#
# Uso:
#   ./wazuh_storage_manager_v3.sh
#
# Variables opcionales:
#   DISK_ALERT=80      - Umbral (%) para alertas de disco.
#   RETENTION_DAYS=90  - Retención en días para índices antiguos.
#   CLUSTER_URL=https://localhost:9200
#
# El script detecta modo CLUSTER o LOCAL y mantiene el menú interactivo.
# Genera reportes en /tmp con marcas de tiempo para TXT, HTML y CSV.

set -uo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
REPORT_DIR="/tmp"
DISK_ALERT=${DISK_ALERT:-80}
RETENTION_DAYS=${RETENTION_DAYS:-90}
CLUSTER_URL="https://localhost:9200"
CURRENT_MODE="LOCAL"
CLUSTER_AVAILABLE=false
AUTH_USER=""
AUTH_PASS=""
REPORT_PENDING=false
REPORT_ENTRIES=()

# -------------------------------------------------------------
# Utilidades
# -------------------------------------------------------------
log_info() { printf '\e[32m[INFO] %s\e[0m\n' "$1"; }
log_warn() { printf '\e[33m[WARN] %s\e[0m\n' "$1"; }
log_error() { printf '\e[31m[ERROR] %s\e[0m\n' "$1"; }

report_add() {
    if [[ "$REPORT_PENDING" == true ]]; then
        local fecha="$(date '+%Y-%m-%d %H:%M:%S')"
        REPORT_ENTRIES+=("$fecha|$1|$2|$3")
    fi
}

human_size() {
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec --format='%.2f' "$1" 2>/dev/null || echo "$1"
    else
        echo "$1"
    fi
}

# -------------------------------------------------------------
# Comprobaciones iniciales
# -------------------------------------------------------------
check_dependencies() {
    local deps=(curl awk grep sort du df find date sed cat printf)
    local missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Faltan dependencias: ${missing[*]}"
        log_error "Instala las herramientas necesarias e intenta de nuevo."
        exit 1
    fi
}

# -------------------------------------------------------------
# Cluster / Local mode
# -------------------------------------------------------------
cluster_api_get() {
    local path="$1"
    local auth_args=()
    if [[ -n "$AUTH_USER" ]]; then
        auth_args=(-u "${AUTH_USER}:${AUTH_PASS}")
    fi
    if ! curl -ksSf --max-time 10 "${auth_args[@]}" "${CLUSTER_URL%/}$path" 2>/dev/null; then
        return 1
    fi
    return 0
}

validate_cluster_connection() {
    local auth_args=()
    if [[ -n "$AUTH_USER" ]]; then
        auth_args=(-u "${AUTH_USER}:${AUTH_PASS}")
    fi
    if curl -ksSf --max-time 10 "${auth_args[@]}" "${CLUSTER_URL%/}" >/dev/null 2>&1; then
        CLUSTER_AVAILABLE=true
        CURRENT_MODE="CLUSTER"
        log_info "Conexión CLUSTER establecida con $CLUSTER_URL"
        return 0
    fi
    CLUSTER_AVAILABLE=false
    CURRENT_MODE="LOCAL"
    return 1
}

prompt_cluster_auth() {
    local option=""
    while true; do
        echo
        echo "¿Conectar al Indexer?"
        echo "1) Sí"
        echo "2) No (modo local)"
        read -rp "Seleccione una opción [1-2]: " option
        case "$option" in
            1)
                read -rp "Usuario: " AUTH_USER
                read -rsp "Password: " AUTH_PASS
                echo
                if validate_cluster_connection; then
                    break
                fi
                log_error "Fallo al autenticar o conectar con $CLUSTER_URL"
                echo "1) Reintentar"
                echo "2) Continuar en modo local"
                echo "3) Salir"
                read -rp "Seleccione una opción [1-3]: " option
                case "$option" in
                    1) continue ;;
                    2)
                        CURRENT_MODE="LOCAL"
                        CLUSTER_AVAILABLE=false
                        break
                        ;;
                    3) exit 0 ;;
                    *) log_warn "Opción inválida, continuando en modo local"; CURRENT_MODE="LOCAL"; CLUSTER_AVAILABLE=false; break ;;
                esac
                ;;
            2)
                CURRENT_MODE="LOCAL"
                CLUSTER_AVAILABLE=false
                break
                ;;
            *) log_warn "Opción inválida. Elija 1 o 2." ;;
        esac
    done
}

# -------------------------------------------------------------
# Detección de rol del nodo
# -------------------------------------------------------------
detect_node_role() {
    local roles=()
    if [[ -d "/var/ossec/etc" ]]; then
        roles+=("MASTER/WORKER")
    fi
    if [[ -d "/etc/wazuh-indexer" ]]; then
        roles+=("INDEXER")
    fi
    if [[ -d "/etc/wazuh-dashboard" ]]; then
        roles+=("DASHBOARD")
    fi
    if [[ ${#roles[@]} -eq 0 ]]; then
        echo "ROL NO DETECTADO"
    else
        echo "${roles[*]}" | tr ' ' ','
    fi
}

# -------------------------------------------------------------
# Auditorías de cluster
# -------------------------------------------------------------
cluster_health() {
    echo "\n--- Health Cluster ---"
    if [[ "$CLUSTER_AVAILABLE" != true ]]; then
        log_warn "Cluster no disponible. Modo LOCAL activo."
        return 1
    fi
    local health
    health=$(cluster_api_get "/_cluster/health?pretty=false" 2>/dev/null)
    if [[ -z "$health" ]]; then
        log_warn "No se pudo obtener health del cluster."
        return 1
    fi
    local status
    status=$(echo "$health" | grep -o '"status" *: *"[^"]*"' | head -n1 | awk -F'"' '{print $4}')
    echo "Cluster health: ${status:-UNKNOWN}"
    report_add "Cluster" "Health" "${status:-UNKNOWN}"
}

cluster_nodes() {
    echo "\n--- Estado Nodos ---"
    if [[ "$CLUSTER_AVAILABLE" != true ]]; then
        log_warn "Cluster no disponible. Modo LOCAL activo."
        return 1
    fi
    local nodes
    nodes=$(cluster_api_get "/_cat/nodes?v&h=name,ip,role,heap.percent,disk.used_percent,uptime" 2>/dev/null)
    if [[ -z "$nodes" ]]; then
        log_warn "No se pudo obtener estado de nodos."
        return 1
    fi
    echo "$nodes"
    report_add "Cluster" "Nodos" "$(echo "$nodes" | wc -l) filas"
}

cluster_shards() {
    echo "\n--- Estado Shards ---"
    if [[ "$CLUSTER_AVAILABLE" != true ]]; then
        log_warn "Cluster no disponible. Modo LOCAL activo."
        return 1
    fi
    local shards
    shards=$(cluster_api_get "/_cat/shards?v" 2>/dev/null)
    if [[ -z "$shards" ]]; then
        log_warn "No se pudo obtener shards."
        return 1
    fi
    echo "$shards"
    report_add "Cluster" "Shards" "$(echo "$shards" | wc -l) filas"
}

cluster_indices() {
    echo "\n--- Top Índices ---"
    if [[ "$CLUSTER_AVAILABLE" != true ]]; then
        log_warn "Cluster no disponible. Modo LOCAL activo."
        return 1
    fi
    local indices
    indices=$(cluster_api_get "/_cat/indices?h=index,store.size,docs.count&bytes=b&s=store.size:desc" 2>/dev/null)
    if [[ -z "$indices" ]]; then
        log_warn "No se pudo obtener índices."
        return 1
    fi
    printf '%-60s %-12s %-12s\n' "Índice" "Tamaño" "Docs"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local index size docs
        index=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        docs=$(echo "$line" | awk '{print $3}')
        printf '%-60s %-12s %-12s\n' "$index" "$(human_size "$size")" "$docs"
    done <<< "$indices"
    report_add "Cluster" "Índices" "$(echo "$indices" | wc -l) filas"
}

parse_index_date() {
    local name="$1"
    if [[ "$name" =~ ([0-9]{4})\.([0-9]{2})\.([0-9]{2})$ ]]; then
        date -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}" +%s 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

indices_antiguos() {
    echo "\n--- Índices Antiguos ---"
    if [[ "$CLUSTER_AVAILABLE" != true ]]; then
        log_warn "Cluster no disponible. Modo LOCAL activo."
        return 1
    fi
    local cutoff=$(date -d "-${RETENTION_DAYS} days" +%s)
    local candidates=()
    local indices
    indices=$(cluster_api_get "/_cat/indices?h=index,store.size&bytes=b" 2>/dev/null)
    if [[ -z "$indices" ]]; then
        log_warn "No se pudo obtener índices para auditoría antigua."
        return 1
    fi
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local index size index_date
        index=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        index_date=$(parse_index_date "$index")
        if [[ "$index_date" -gt 0 && "$index_date" -lt "$cutoff" ]]; then
            candidates+=("$index|$size")
        fi
    done <<< "$indices"
    if [[ ${#candidates[@]} -eq 0 ]]; then
        echo "No se encontraron índices antiguos anteriores a ${RETENTION_DAYS} días."
        report_add "Cluster" "Índices Antiguos" "0 índices"
        return 0
    fi
    printf '%-60s %-12s\n' "Índice" "Tamaño"
    for candidate in "${candidates[@]}"; do
        local idx=${candidate%%|*}
        local size=${candidate##*|}
        printf '%-60s %-12s\n' "$idx" "$(human_size "$size")"
    done
    report_add "Cluster" "Índices Antiguos" "${#candidates[@]} índices"
}

espacio_recuperable() {
    echo "\n--- Espacio Recuperable ---"
    if [[ "$CLUSTER_AVAILABLE" != true ]]; then
        log_warn "Cluster no disponible. Modo LOCAL activo."
        return 1
    fi
    local cutoff=$(date -d "-${RETENTION_DAYS} days" +%s)
    local total=0
    local indices
    indices=$(cluster_api_get "/_cat/indices?h=index,store.size&bytes=b" 2>/dev/null)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local index size index_date
        index=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        index_date=$(parse_index_date "$index")
        if [[ "$index_date" -gt 0 && "$index_date" -lt "$cutoff" ]]; then
            total=$((total + size))
        fi
    done <<< "$indices"
    echo "Espacio recuperable estimado: $(human_size "$total")"
    report_add "Cluster" "Espacio Recuperable" "$(human_size "$total")"
}

smart_cleanup() {
    echo "\n--- Smart Cleanup (Simulación) ---"
    if [[ "$CLUSTER_AVAILABLE" != true ]]; then
        log_warn "Cluster no disponible. Modo LOCAL activo."
    fi
    local mount_point="/var/lib/wazuh-indexer"
    local dfinfo
    if [[ -d "$mount_point" ]]; then
        dfinfo=$(df --output=pcent,size,used,avail,target "$mount_point" 2>/dev/null | tail -n1)
    else
        dfinfo=$(df --output=pcent,size,used,avail,target / 2>/dev/null | tail -n1)
    fi
    local used_pct size used avail target
    read -r used_pct size used avail target <<<"$dfinfo"
    used_pct=${used_pct//%/}
    local goal=80
    local total_bytes
    total_bytes=$(df --output=size -B1 "$target" 2>/dev/null | tail -n1)
    local current_used
    current_used=$(df --output=used -B1 "$target" 2>/dev/null | tail -n1)
    local target_bytes=$((total_bytes * goal / 100))
    local need_free=0
    if [[ "$current_used" -gt "$target_bytes" ]]; then
        need_free=$((current_used - target_bytes))
    fi
    echo "Uso actual: ${used_pct}%"
    echo "Objetivo: ${goal}%"
    echo "Espacio a liberar para alcanzar ${goal}%: $(human_size "$need_free")"
    if [[ "$CLUSTER_AVAILABLE" == true ]]; then
        echo
        echo "Índices candidatos para simulación de limpieza (antiguos):"
        indices_antiguos
    else
        echo "No hay datos de cluster para candidatos de índices."
    fi
    report_add "Cluster" "Smart Cleanup" "Liberar $(human_size "$need_free")"
}

# Preparada para futuro borrado seguro
# delete_indices() {
#     # ADVERTENCIA: esta función está preparada para eliminar índices en el futuro.
#     # Debe implementarse con extrema precaución y validarse antes de usarla.
#     # Ejemplo de uso seguro:
#     # delete_indices "wazuh-alerts-4.x-2025.10.01,wazuh-alerts-4.x-2025.10.02"
#     local indices_to_delete="$1"
#     echo "[SAFE MODE] Simulación de borrado para: $indices_to_delete"
#     return 0
# }

# -------------------------------------------------------------
# Auditorías locales
# -------------------------------------------------------------
style_title() {
    echo "\n================================================================"
    echo "${1}"
    echo "================================================================"
}

disk_audit() {
    style_title "Auditoría de Disco"
    df -h 2>/dev/null | awk 'NR==1 || $5+0 > '"$DISK_ALERT"' {print}'
    echo
    echo "Filesystems con uso superior a ${DISK_ALERT}%:"
    df -h 2>/dev/null | awk 'NR>1 && $5+0 > '"$DISK_ALERT"' {print}'
    report_add "Auditoría" "Disco" "Alerta ${DISK_ALERT}%"
}

top_directories() {
    style_title "Top Directorios"
    du -x -h --max-depth=2 / 2>/dev/null | sort -hr | head -n 20
    report_add "Auditoría" "Top Directorios" "20 entradas"
}

indexer_storage() {
    style_title "Indexer Storage"
    local base="/var/lib/wazuh-indexer"
    if [[ ! -d "$base" ]]; then
        log_warn "No existe $base"
        return 1
    fi
    du -sh "$base" 2>/dev/null
    du -sk "$base"/* 2>/dev/null | sort -nr | head -n 20 | awk '{printf "%-12s %s\n", $1"K", $2}'
    report_add "Auditoría" "Indexer Storage" "$(du -sh "$base" 2>/dev/null | awk '{print $1}')"
}

wazuh_logs() {
    style_title "Logs Wazuh"
    local base="/var/ossec/logs"
    if [[ ! -d "$base" ]]; then
        log_warn "No existe $base"
        return 1
    fi
    du -sh "$base" 2>/dev/null
    du -sk "$base"/* 2>/dev/null | sort -nr | head -n 20 | awk '{printf "%-12s %s\n", $1"K", $2}'
    report_add "Auditoría" "Logs Wazuh" "$(du -sh "$base" 2>/dev/null | awk '{print $1}')"
}

service_status() {
    style_title "Estado Servicios Wazuh"
    local services=(wazuh-manager wazuh-indexer wazuh-dashboard)
    for svc in "${services[@]}"; do
        local state="STOPPED"
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet "$svc"; then
                state="RUNNING"
            fi
        else
            if service "$svc" status >/dev/null 2>&1; then
                state="RUNNING"
            fi
        fi
        printf '%-20s %s\n' "$svc" "$state"
        report_add "Servicio" "$svc" "$state"
    done
}

find_large_files() {
    style_title "Archivos mayores a 1 GB"
    find / -xdev \(
        -path /proc -o -path /proc/* -o
        -path /sys -o -path /sys/* -o
        -path /run -o -path /run/*
    \) -prune -o -type f -size +1G -print0 2>/dev/null | xargs -0 du -h 2>/dev/null | sort -hr | head -n 50
    report_add "Auditoría" "Archivos >1GB" "Hasta 50 entradas"
}

logall_status() {
    style_title "Configuración Logall"
    local conf="/var/ossec/etc/ossec.conf"
    if [[ ! -f "$conf" ]]; then
        log_warn "No se encontró $conf"
        return 1
    fi
    local logall logall_json
    logall=$(grep -Eo '<logall>[^<]*' "$conf" | sed -e 's/<logall>//')
    logall_json=$(grep -Eo '<logall_json>[^<]*' "$conf" | sed -e 's/<logall_json>//')
    echo "logall: ${logall:-NO CONFIGURADO}"
    echo "logall_json: ${logall_json:-NO CONFIGURADO}"
    if [[ "$logall" == "yes" || "$logall_json" == "yes" ]]; then
        log_warn "logall o logall_json está habilitado."
    fi
    report_add "Auditoría" "Logall" "logall=${logall:-NO} logall_json=${logall_json:-NO}"
}

print_header() {
    echo "\n============================================================="
    echo "WAZUH STORAGE MANAGER V3"
    echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Modo actual: ${CURRENT_MODE}"
    echo "Rol detectado: $(detect_node_role)"
    echo "=============================================================\n"
}

report_header() {
    local path="$1"
    cat > "$path" <<EOH
WAZUH STORAGE MANAGER V3
Fecha: $(date '+%Y-%m-%d %H:%M:%S')
Modo: ${CURRENT_MODE}
Rol: $(detect_node_role)

EOH
}

generate_report_txt() {
    local path="${REPORT_DIR}/wazuh_storage_report_${TIMESTAMP}.txt"
    report_header "$path"
    for entry in "${REPORT_ENTRIES[@]}"; do
        IFS='|' read -r fecha tipo nombre valor <<< "$entry"
        printf '%s | %s | %s | %s\n' "$fecha" "$tipo" "$nombre" "$valor" >> "$path"
    done
    log_info "Reporte TXT generado: $path"
}

generate_report_html() {
    local path="${REPORT_DIR}/wazuh_storage_report_${TIMESTAMP}.html"
    cat > "$path" <<EOH
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Wazuh Storage Manager Report</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; }
h1 { color: #005a9c; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ccc; padding: 8px; }
th { background: #f4f4f4; }
</style>
</head>
<body>
<h1>Wazuh Storage Manager Report</h1>
<p>Fecha: $(date '+%Y-%m-%d %H:%M:%S')</p>
<p>Modo: ${CURRENT_MODE}</p>
<p>Rol: $(detect_node_role)</p>
<table>
<tr><th>Fecha</th><th>Tipo</th><th>Nombre</th><th>Valor</th></tr>
EOH
    for entry in "${REPORT_ENTRIES[@]}"; do
        IFS='|' read -r fecha tipo nombre valor <<< "$entry"
        cat >> "$path" <<ROW
<tr><td>${fecha}</td><td>${tipo}</td><td>${nombre}</td><td>${valor}</td></tr>
ROW
    done
    cat >> "$path" <<EOH
</table>
</body>
</html>
EOH
    log_info "Reporte HTML generado: $path"
}

generate_report_csv() {
    local path="${REPORT_DIR}/wazuh_storage_report_${TIMESTAMP}.csv"
    cat > "$path" <<EOH
Fecha,Tipo,Nombre,Valor
EOH
    for entry in "${REPORT_ENTRIES[@]}"; do
        IFS='|' read -r fecha tipo nombre valor <<< "$entry"
        printf '%s,%s,%s,%s\n' "$fecha" "$tipo" "$nombre" "$valor" >> "$path"
    done
    log_info "Reporte CSV generado: $path"
}

audit_complete() {
    REPORT_ENTRIES=()
    REPORT_PENDING=true
    cluster_health
    cluster_nodes
    cluster_shards
    disk_audit
    top_directories
    indexer_storage
    wazuh_logs
    cluster_indices
    smart_cleanup
    service_status
    logall_status
    REPORT_PENDING=false
    generate_report_txt
    generate_report_html
    generate_report_csv
}

show_menu() {
    print_header
    cat <<MENU
1 - Health Cluster
2 - Estado Nodos
3 - Estado Shards
4 - Uso Disco
5 - Top Directorios
6 - Indexer Storage
7 - Logs Wazuh
8 - Top Índices
9 - Índices Antiguos
10 - Espacio Recuperable
11 - Smart Cleanup (Simulación)
12 - Archivos mayores a 1 GB
13 - Estado Servicios Wazuh
14 - Generar Reporte TXT
15 - Generar Reporte HTML
16 - Generar Reporte CSV
17 - Auditoría Completa
18 - Detectar Rol del Nodo
19 - Configuración Logall
20 - Salir
MENU
}

main() {
    check_dependencies
    prompt_cluster_auth
    while true; do
        show_menu
        read -rp "Seleccione una opción [1-20]: " option
        case "$option" in
            1) cluster_health ;;
            2) cluster_nodes ;;
            3) cluster_shards ;;
            4) disk_audit ;;
            5) top_directories ;;
            6) indexer_storage ;;
            7) wazuh_logs ;;
            8) cluster_indices ;;
            9) indices_antiguos ;;
            10) espacio_recuperable ;;
            11) smart_cleanup ;;
            12) find_large_files ;;
            13) service_status ;;
            14) REPORT_ENTRIES=(); REPORT_PENDING=true; cluster_health; report_add "Reporte" "Generar" "TXT"; REPORT_PENDING=false; generate_report_txt ;;
            15) REPORT_ENTRIES=(); REPORT_PENDING=true; cluster_health; report_add "Reporte" "Generar" "HTML"; REPORT_PENDING=false; generate_report_html ;;
            16) REPORT_ENTRIES=(); REPORT_PENDING=true; cluster_health; report_add "Reporte" "Generar" "CSV"; REPORT_PENDING=false; generate_report_csv ;;
            17) audit_complete ;;
            18) echo "\nRol detectado: $(detect_node_role)" ;;
            19) logall_status ;;
            20) echo "Saliendo..."; exit 0 ;;
            *) log_warn "Opción inválida. Intenta de nuevo." ;;
        esac
        echo
        read -rp "Presiona Enter para continuar..." _
    done
}

main "$@"
EOF