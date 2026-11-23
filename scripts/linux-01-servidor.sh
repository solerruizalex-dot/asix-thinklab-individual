#!/bin/bash
# linux-01-servidor.sh - Álex Soler Ruiz
# Deja listo un servidor Debian 13 recién instalado (sin entorno gráfico) en la LAN del laboratorio.
# Sirve para serveis (.22) y dades (.23), que son VMs independientes de VirtualBox.
#   uso (como root):  bash linux-01-servidor.sh NOMBRE IP "CLAVE_PUBLICA_DEL_NAS"
#   ej.:              bash linux-01-servidor.sh serveis 192.168.36.22 "ssh-ed25519 AAAA... copias@truenas"
set -euo pipefail
NOMBRE=$1; IP=$2; CLAVE_NAS=$3
IF=$(ip -o link | awk -F': ' '$2!="lo" {print $2; exit}')

echo "== Red: IP fija $IP en $IF (un servidor no puede cambiar de dirección)"
cat > /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*
auto lo
iface lo inet loopback

auto $IF
iface $IF inet static
    address $IP/24
    gateway 192.168.36.1
    dns-nameservers 192.168.36.21 192.168.36.1
    dns-search alexsoler.lan
EOF
hostnamectl set-hostname "$NOMBRE"
sed -i "/^127\.0\.1\.1/d" /etc/hosts; echo "$IP $NOMBRE.alexsoler.lan $NOMBRE" >> /etc/hosts

echo "== Repositorios oficiales de Debian 13 (base, actualizaciones y seguridad)"
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian trixie main contrib non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware
EOF

echo "== Usuarios: root sin contraseña; se administra con alexsoler + sudo"
usermod -aG sudo alexsoler
passwd -l root
install -d -m 700 /root/.ssh
# El NAS entra como root solo con su clave y solo desde su IP, para llevarse las copias de /etc
echo "from=\"192.168.36.20\" $CLAVE_NAS" > /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys
mkdir -p /etc/ssh/sshd_config.d
printf 'PermitRootLogin prohibit-password\nPasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/10-laboratorio.conf

echo "== Reinicio de la red con la IP fija"
ifdown "$IF" 2>/dev/null || true; ip addr flush dev "$IF"; ifup "$IF"
systemctl restart ssh
# DNS fijo. Sin el paquete resolvconf, las líneas dns-* de interfaces no hacen nada, y el cliente DHCP
# de la instalación vacía resolv.conf al terminar (me pasó): lo escribo al final, con la red ya fija.
printf 'search alexsoler.lan\nnameserver 192.168.36.21\nnameserver 192.168.36.1\n' > /etc/resolv.conf
ip -4 -br addr show "$IF"; ip route | grep default
