#!/bin/bash
# linux-unir-dominio.sh - Álex Soler Ruiz
# Une el cliente Debian 13 (pc-informatica) al dominio alexsoler.lan con realmd + SSSD.
# Requisitos: DNS apuntando al DC (lo reparte el DHCP del MikroTik) y la hora sincronizada
# (Kerberos rechaza diferencias de más de 5 minutos).
set -e
DOMINIO=alexsoler.lan

# hora: el DC es el servidor NTP del dominio
sed -i 's/^#\?NTP=.*/NTP=dc01-alex.alexsoler.lan/' /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd || true

resolvectl status 2>/dev/null | grep -i "DNS Servers" || cat /etc/resolv.conf
realm discover $DOMINIO

# la contraseña llega por la entrada estándar, no se escribe en el script
realm join -v -U Administrador $DOMINIO < /dev/stdin

# usuarios del dominio sin @dominio y con carpeta personal que se crea al primer inicio
sed -i 's/^use_fully_qualified_names = .*/use_fully_qualified_names = False/' /etc/sssd/sssd.conf
sed -i 's|^fallback_homedir = .*|fallback_homedir = /home/%u|' /etc/sssd/sssd.conf
pam-auth-update --enable mkhomedir
systemctl restart sssd

# solo pueden iniciar sesión los de Informática y los administradores del dominio
realm deny --all
realm permit -g G_Informatica
realm permit adm.alex
# sudo para el grupo de Informática
echo '%G_Informatica ALL=(ALL) ALL' > /etc/sudoers.d/informatica
chmod 440 /etc/sudoers.d/informatica

realm list
id a.soler
