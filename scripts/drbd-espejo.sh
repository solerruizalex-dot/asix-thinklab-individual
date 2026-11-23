#!/bin/bash
# drbd-espejo.sh - Álex Soler Ruiz
# Espejo (RAID 1 por red) entre un disco de serveis y otro de dades con DRBD.
# serveis y dades son VMs de VirtualBox: el disco del espejo es el del puerto SATA 1 en serveis
# y el del puerto SATA 8 en dades. Uso la ruta by-path (controlador + puerto) y no sdX, porque los
# nombres sdX cambian de orden al arrancar o al quitar discos (me pasó con los RAID).
# La ruta va entre comillas: sin ellas drbdadm se atasca en los ':' (Parse error: ';' expected).
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
    on serveis { disk "/dev/disk/by-path/pci-0000:00:0d.0-ata-2"; address 192.168.36.22:7789; }   # puerto SATA 1
    on dades   { disk "/dev/disk/by-path/pci-0000:00:0d.0-ata-9"; address 192.168.36.23:7789; }   # puerto SATA 8
    net { after-sb-0pri discard-zero-changes; after-sb-1pri discard-secondary; }
}
EOT
drbdadm status espejo >/dev/null 2>&1 || { yes yes | drbdadm create-md espejo; drbdadm up espejo; }
drbdadm status espejo
