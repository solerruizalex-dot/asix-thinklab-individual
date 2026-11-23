#!/bin/bash
# pve-01-nodo.sh - Álex Soler Ruiz
# Se ejecuta en CADA nodo Proxmox: repositorios sin suscripción y actualización.
set -e
# El repositorio enterprise da error 401 sin suscripción y bloquea "apt update"
for f in /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources; do
    [ -f "$f" ] && mv "$f" "$f.desactivado"
done
cat > /etc/apt/sources.list.d/proxmox.sources <<EOT
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOT
apt-get update -q
# Si la VM viene de un clon o de un snapshot de VirtualBox, el número de serie del disco cambia
# y grub-pc sigue apuntando al antiguo: grub-install falla y dpkg se queda a medias.
if dpkg -s grub-pc >/dev/null 2>&1; then
    DISCO=$(ls /dev/disk/by-id/ata-* | grep -v part | head -1)
    echo "grub-pc grub-pc/install_devices multiselect $DISCO" | debconf-set-selections
fi
DEBIAN_FRONTEND=noninteractive apt-get -y -q full-upgrade
DEBIAN_FRONTEND=noninteractive dpkg --configure -a
pveversion
