#!/bin/bash
# dades-raid.sh - Álex Soler Ruiz
# Se ejecuta como root en la VM "dades". Crea tres RAID por software con mdadm:
#   md0 RAID 0 (sdb sdc) · md1 RAID 1 (sdd sde) · md5 RAID 5 (sdf sdg sdh)
# sdi queda libre para el espejo DRBD con serveis.
[ "$(id -u)" = 0 ] || exec sudo -E bash "$0" "$@"
set -e
crear() {  # dispositivo nivel discos...
    md=$1; lvl=$2; shift 2
    [ -e $md ] || mdadm --create $md --level=$lvl --raid-devices=$# "$@" --run
    blkid $md >/dev/null 2>&1 || mkfs.ext4 -q -L $(basename $md) $md
    mkdir -p /srv/$(basename $md)
    grep -q "^$md " /etc/fstab || echo "$md /srv/$(basename $md) ext4 defaults,nofail 0 2" >> /etc/fstab
}
crear /dev/md0 0 /dev/sdb /dev/sdc
crear /dev/md1 1 /dev/sdd /dev/sde
crear /dev/md5 5 /dev/sdf /dev/sdg /dev/sdh
mdadm --detail --scan > /etc/mdadm/mdadm.conf
update-initramfs -u >/dev/null 2>&1
systemctl daemon-reload; mount -a
cat /proc/mdstat
df -h /srv/md0 /srv/md1 /srv/md5
