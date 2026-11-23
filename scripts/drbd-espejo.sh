#!/bin/bash
# drbd-espejo.sh - Álex Soler Ruiz
# Espejo (RAID 1 por red) entre el disco scsi1 de serveis y el scsi8 de dades con DRBD.
# Uso la ruta by-id porque los nombres sdX pueden cambiar de orden al arrancar (me pasó).
# Se ejecuta como root en LOS DOS equipos con el mismo contenido; el primario se elige después.
[ "$(id -u)" = 0 ] || exec sudo -E bash "$0" "$@"
set -e
DEBIAN_FRONTEND=noninteractive apt-get install -y -q drbd-utils >/dev/null
modprobe drbd
echo drbd > /etc/modules-load.d/drbd.conf
cat > /etc/drbd.d/espejo.res <<'EOT'
resource espejo {
    protocol C;                 # síncrono: la escritura acaba cuando está en los dos discos
    device    /dev/drbd0;
    meta-disk internal;
    on serveis { disk /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1; address 192.168.30.22:7789; }
    on dades   { disk /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi8; address 192.168.30.23:7789; }
    net { after-sb-0pri discard-zero-changes; after-sb-1pri discard-secondary; }
}
EOT
drbdadm status espejo >/dev/null 2>&1 || { yes yes | drbdadm create-md espejo; drbdadm up espejo; }
drbdadm status espejo
