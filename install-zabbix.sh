#!/bin/bash

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN} Instalador de Zabbix Agent 2${NC}"
echo -e "${GREEN}======================================${NC}"

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ejecutar como root.${NC}"
    exit 1
fi

# Detectar Ubuntu
UBUNTU_VERSION=$(lsb_release -rs)

echo -e "${YELLOW}Versión detectada:${NC} $UBUNTU_VERSION"

# Solicitar servidor Zabbix
read -p "Ingrese IP o FQDN del servidor Zabbix: " ZABBIX_SERVER

# Obtener hostname
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

echo -e "${YELLOW}Hostname detectado:${NC} $HOSTNAME"

# Instalar dependencias
apt update
apt install -y wget curl

# Descargar repositorio Zabbix
TMP_DEB="/tmp/zabbix-release.deb"

wget -O "$TMP_DEB" \
"https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest+ubuntu${UBUNTU_VERSION}_all.deb"

dpkg -i "$TMP_DEB"

apt update

# Instalar agente
apt install -y zabbix-agent2

CONF="/etc/zabbix/zabbix_agent2.conf"

cp "$CONF" "${CONF}.bak.$(date +%Y%m%d_%H%M%S)"

# Configuración
sed -i "s/^Server=.*/Server=${ZABBIX_SERVER}/" "$CONF"
sed -i "s/^ServerActive=.*/ServerActive=${ZABBIX_SERVER}/" "$CONF"

if grep -q "^Hostname=" "$CONF"; then
    sed -i "s/^Hostname=.*/Hostname=${HOSTNAME}/" "$CONF"
else
    echo "Hostname=${HOSTNAME}" >> "$CONF"
fi

# Habilitar e iniciar servicio
systemctl daemon-reload
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN} INSTALACIÓN COMPLETADA${NC}"
echo -e "${GREEN}======================================${NC}"

echo "Servidor Zabbix : $ZABBIX_SERVER"
echo "Hostname        : $HOSTNAME"

echo
systemctl is-enabled zabbix-agent2
echo -e "${GREEN} SERVICIO HABILITADO${NC}"
systemctl is-active zabbix-agent2
echo -e "${GREEN} SERVICIO ACTIVADO${NC}"

echo
echo "Versión instalada:"
zabbix_agent2 -V | head -1