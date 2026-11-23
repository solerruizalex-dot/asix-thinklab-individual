#!/bin/bash
# dades-raid-pruebas.sh - Álex Soler Ruiz
# Pruebas de los RAID de "dades": datos de prueba, velocidad y fallo/reconstrucción de un disco.
[ "$(id -u)" = 0 ] || exec sudo -E bash "$0" "$@"
t() { echo "[$(date +%T)] $*"; }

t "1) Datos ficticios en cada array y su suma SHA-256"
for m in md0 md1 md5; do
    head -c 100M /dev/urandom > /srv/$m/datos.bin
    sha256sum /srv/$m/datos.bin | tee /root/$m.sha256
done
sync

t "2) Velocidad (dd 200 MB, escritura directa sin caché y lectura con caché vaciada)"
dd if=/dev/zero of=/srv/sda-ref.bin bs=1M count=200 oflag=direct 2>&1 | tail -1 | sed 's/^/   disco simple (sda) escritura: /'
for m in md0 md1 md5; do
    dd if=/dev/zero of=/srv/$m/vel.bin bs=1M count=200 oflag=direct 2>&1 | tail -1 | sed "s/^/   $m escritura: /"
    echo 3 > /proc/sys/vm/drop_caches
    dd if=/srv/$m/vel.bin of=/dev/null bs=1M 2>&1 | tail -1 | sed "s/^/   $m lectura:   /"
    rm -f /srv/$m/vel.bin
done
rm -f /srv/sda-ref.bin

t "3) RAID 1: fallo de sde"
mdadm /dev/md1 --fail /dev/sde
mdadm --detail /dev/md1 | grep -E "State :|Active Devices|Failed Devices"
sha256sum -c /root/md1.sha256
t "   retiro el disco 'roto' y lo vuelvo a añadir (como si fuera uno nuevo)"
mdadm /dev/md1 --remove /dev/sde
mdadm --zero-superblock /dev/sde
mdadm /dev/md1 --add /dev/sde
grep -A2 '^md1' /proc/mdstat
inicio=$(date +%s); until mdadm --detail /dev/md1 | grep -qE 'State : (clean|active) *$'; do sleep 1; done
t "   reconstruido en $(( $(date +%s) - inicio )) s"
mdadm --detail /dev/md1 | grep -E "State :|Active Devices"

t "4) RAID 5: fallo de sdg"
mdadm /dev/md5 --fail /dev/sdg
mdadm --detail /dev/md5 | grep -E "State :|Active Devices|Failed Devices"
sha256sum -c /root/md5.sha256
mdadm /dev/md5 --remove /dev/sdg
mdadm --zero-superblock /dev/sdg
mdadm /dev/md5 --add /dev/sdg
grep -A2 '^md5' /proc/mdstat
inicio=$(date +%s); until mdadm --detail /dev/md5 | grep -qE 'State : (clean|active) *$'; do sleep 1; done
t "   reconstruido en $(( $(date +%s) - inicio )) s"
mdadm --detail /dev/md5 | grep -E "State :|Active Devices"
sha256sum -c /root/md5.sha256

t "5) RAID 0: mdadm no deja marcar un disco como fallado (no hay redundancia)"
mdadm /dev/md0 --fail /dev/sdc 2>&1
t "   simulo que falta sdc: paro el array e intento montarlo solo con sdb"
umount /srv/md0; mdadm --stop /dev/md0
mdadm --assemble /dev/md0 /dev/sdb 2>&1
mdadm --detail /dev/md0 2>&1 | grep -E "State :|Raid Devices" ; mount /srv/md0 2>&1
t "   vuelvo a conectar sdc"
mdadm --stop /dev/md0 2>/dev/null; mdadm --assemble /dev/md0 /dev/sdb /dev/sdc && mount /srv/md0
sha256sum -c /root/md0.sha256
cat /proc/mdstat
