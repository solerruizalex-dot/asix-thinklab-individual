#!/bin/bash
# linux-02-paquetes.sh - Álex Soler Ruiz
# Actualiza el servidor y le pone solo lo necesario (sin entorno gráfico ni servicios extra).
[ "$(id -u)" = 0 ] || exec sudo -E bash "$0" "$@"
set -e
export DEBIAN_FRONTEND=noninteractive
echo "== Antes: Debian $(cat /etc/debian_version), kernel $(uname -r)"
apt-get update -q
echo "== Paquetes pendientes: $(apt list --upgradable 2>/dev/null | grep -c upgradable)"
apt-get -y -q full-upgrade
# administración y diagnóstico + lo que necesitan los RAID (mdadm) y el espejo entre equipos (drbd-utils)
apt-get -y -q install --no-install-recommends mdadm drbd-utils sysstat htop rsync traceroute dnsutils curl vim-tiny
# teclado español en la consola
sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="es"/' /etc/default/keyboard && setupcon -k 2>/dev/null || true
systemctl enable --now sysstat >/dev/null 2>&1 || true
# sin entorno gráfico: arranque en modo texto (el instalador deja graphical.target aunque no haya escritorio)
systemctl set-default multi-user.target
echo "== Después: Debian $(cat /etc/debian_version), kernel $(uname -r), pendientes: $(apt list --upgradable 2>/dev/null | grep -c upgradable)"
apt-get -y -q purge "exim4*" bsd-mailx >/dev/null 2>&1 || true; apt-get -y -q autoremove --purge >/dev/null
echo "== Sin entorno gráfico: $(systemctl get-default) · paquetes instalados: $(dpkg -l | grep -c '^ii')"
