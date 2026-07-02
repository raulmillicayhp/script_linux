#!/bin/bash

LV_PATH="/dev/ubuntu-vg/ubuntu-lv"

clear

echo "=================================================="
echo "      EXPANSION DE LVM - UBUNTU"
echo "=================================================="

echo ""
echo "========== INFORMACION ACTUAL =========="
echo ""

echo "---- DISCOS Y PARTICIONES ----"
lsblk

echo ""
echo "---- VOLUME GROUPS ----"
sudo vgs

echo ""
echo "---- LOGICAL VOLUMES ----"
sudo lvs

echo ""
echo "---- ESPACIO EN DISCO ----"
df -h /

echo ""
echo "========================================"
echo ""

read -p "Desea expandir el volumen al 100% del espacio libre? (s/n): " RESPUESTA

case "$RESPUESTA" in
    s|S|si|SI|Si)
        echo ""
        echo "Expandiendo volumen..."
        echo ""

        sudo lvextend -r -l +100%FREE "$LV_PATH"

        if [ $? -eq 0 ]; then
            echo ""
            echo "========================================"
            echo "EXPANSION FINALIZADA CORRECTAMENTE"
            echo "========================================"
            echo ""

            df -h /
        else
            echo ""
            echo "========================================"
            echo "ERROR AL EXPANDIR EL VOLUMEN"
            echo "========================================"
        fi
        ;;
    *)
        echo ""
        echo "Operacion cancelada."
        ;;
esac