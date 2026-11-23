#!/bin/bash
# dades-raid.sh - Álex Soler Ruiz
# Se ejecuta como root en la VM "dades" (VirtualBox, controlador SATA). Crea tres RAID por software con mdadm:
#   md0 RAID 0 (puertos 1 y 2) · md1 RAID 1 (puertos 3 y 4) · md5 RAID 5 (puertos 5, 6 y 7)
# El puerto 8 queda libre para el espejo DRBD con serveis.
# Los discos se eligen por PUERTO (/dev/disk/by-path) y no por nombre: en dades el disco del puerto 3
# arrancó como sdi y no como sdd. Con nombres sdX habría metido un disco equivocado en un RAID.
[ "$(id -u)" = 0 ] || exec sudo -E bash "$0" "$@"
set -e
P=/dev/disk/by-path/pci-0000:00:0d.0-ata   # ata-N = puerto SATA N-1
puerto() { readlink -f $P-$(( $1 + 1 )); }
crear() {  # dispositivo nivel puertos...
    md=$1; lvl=$2; shift 2
    discos=$(for p in "$@"; do puerto $p; done)
    echo "$md (RAID $lvl): $(echo $discos)"
    [ -e $md ] || mdadm --create $md --level=$lvl --raid-devices=$# $discos --run
    blkid $md >/dev/null 2>&1 || mkfs.ext4 -q -L $(basename $md) $md
    mkdir -p /srv/$(basename $md)
    grep -q "LABEL=$(basename $md) " /etc/fstab || echo "LABEL=$(basename $md) /srv/$(basename $md) ext4 defaults,nofail 0 2" >> /etc/fstab
}
crear /dev/md0 0 1 2
crear /dev/md1 1 3 4
crear /dev/md5 5 5 6 7
# espero a que acabe la sincronización inicial: si no, mdadm.conf apunta el RAID 5 con 'spares=1' (me pasó)
while grep -qE 'resync|recovery' /proc/mdstat; do sleep 2; done
# los arrays se reconocen por su UUID (superbloque), no por los discos: así se montan aunque cambien los nombres
mdadm --detail --scan > /etc/mdadm/mdadm.conf
update-initramfs -u >/dev/null 2>&1
systemctl daemon-reload; mount -a
cat /proc/mdstat
df -h /srv/md0 /srv/md1 /srv/md5
