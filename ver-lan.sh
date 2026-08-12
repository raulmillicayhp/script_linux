#!/bin/bash

# ============================================================
# Linux Infrastructure Report
# ============================================================

# Colores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

print_header() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_ok() {
    echo -e " ${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e " ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e " ${RED}✗${NC} $1"
}

clear

print_header "LINUX INFRASTRUCTURE REPORT"

echo -e "${CYAN}Fecha:${NC}     $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${CYAN}Hostname:${NC}  $(hostname -f 2>/dev/null || hostname)"

############################################################
print_header "SISTEMA OPERATIVO"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    print_ok "Distribución : $PRETTY_NAME"
fi

print_ok "Kernel       : $(uname -r)"
print_ok "Arquitectura : $(uname -m)"
print_ok "Uptime       : $(uptime -p)"

############################################################
print_header "CPU Y MEMORIA"

CPU=$(lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')
MEM=$(free -h | awk '/Mem:/ {print $2}')

print_ok "CPU          : $CPU"
print_ok "RAM Total    : $MEM"

############################################################
print_header "ALMACENAMIENTO"

df -h --output=source,size,used,avail,pcent,target | grep -v tmpfs

############################################################
print_header "RED - INTERFACES"

ip -4 -o addr show scope global | while read -r line
do
    IFACE=$(echo "$line" | awk '{print $2}')
    IP=$(echo "$line" | awk '{print $4}')

    print_ok "$IFACE -> $IP"
done

############################################################
print_header "GATEWAY"

GW=$(ip route | awk '/default/ {print $3}')
IFACE=$(ip route | awk '/default/ {print $5}')

if [ -n "$GW" ]; then
    print_ok "Gateway  : $GW"
    print_ok "Interfaz : $IFACE"
else
    print_error "No se encontró Gateway por defecto"
fi

############################################################
print_header "DNS"

if command -v resolvectl >/dev/null 2>&1; then
    resolvectl dns 2>/dev/null | while read -r line
    do
        print_ok "$line"
    done
else
    grep '^nameserver' /etc/resolv.conf | while read -r line
    do
        print_ok "$line"
    done
fi

############################################################
print_header "NTP"

if command -v timedatectl >/dev/null 2>&1; then
    SYNC=$(timedatectl status | grep "System clock synchronized" | awk '{print $4}')
    NTP=$(timedatectl status | grep "NTP service" | awk '{print $3}')

    print_ok "Sincronizado : $SYNC"
    print_ok "NTP Service  : $NTP"
fi

############################################################
print_header "CONECTIVIDAD"

if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    print_ok "Internet Reachable"
else
    print_error "Sin acceso a Internet"
fi

if ping -c 1 -W 2 google.com >/dev/null 2>&1; then
    print_ok "Resolución DNS OK"
else
    print_error "Problema de resolución DNS"
fi

############################################################
print_header "SERVICIOS CRITICOS"

for svc in sshd cron rsyslog
do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        print_ok "$svc : Running"
    fi
done

############################################################
print_header "RESUMEN"

echo -e "${GREEN}"
echo "Hostname : $(hostname)"
echo "IP       : $(hostname -I | awk '{print $1}')"
echo "Gateway  : $GW"
echo "Kernel   : $(uname -r)"
echo "Uptime   : $(uptime -p)"
echo -e "${NC}"

echo
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}Reporte generado correctamente${NC}"
echo -e "${BLUE}============================================================${NC}"