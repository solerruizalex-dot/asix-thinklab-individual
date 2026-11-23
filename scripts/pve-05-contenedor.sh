#!/bin/bash
# pve-05-contenedor.sh - Álex Soler Ruiz
# Crea en pve1 un contenedor LXC Debian 13 ligero (CT 130, "web-pruebas") para la prueba de migración.
set -e
: "${CLAVE:?define CLAVE con la contraseña de root del contenedor}"
ID=130
pct status $ID >/dev/null 2>&1 && { echo "el CT $ID ya existe"; exit 0; }
T=$(pveam list truenas-nfs | awk '/debian-13-standard/ {print $1}' | sort -V | tail -1)
pct create $ID "$T" --hostname web-pruebas --cores 1 --memory 256 --swap 256 \
   --rootfs local-lvm:2 --net0 name=eth0,bridge=vmbr0,ip=192.168.36.30/24,gw=192.168.36.1 \
   --nameserver 192.168.36.1 --unprivileged 1 --password "$CLAVE" --onboot 1
pct start $ID
sleep 5
pct exec $ID -- bash -c 'echo "<h1>web-pruebas - Alex Soler</h1>" > /root/index.html; hostname; ip -4 -br a'
