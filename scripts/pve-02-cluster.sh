#!/bin/bash
# pve-02-cluster.sh - Álex Soler Ruiz
# Se ejecuta UNA vez en pve1: lo que va en /etc/pve se replica a todo el clúster.
set -e
: "${CLAVE:?define CLAVE con la contraseña de alexsoler@pve}"
# usuario de administración propio (no trabajar siempre con root@pam)
pveum group add administradores --comment "Administradores del laboratorio" 2>/dev/null || true
pveum acl modify / --groups administradores --roles Administrator
pveum user add alexsoler@pve --comment "Alex Soler Ruiz" --groups administradores 2>/dev/null || true
printf '%s\n%s\n' "$CLAVE" "$CLAVE" | pveum passwd alexsoler@pve

# almacenamiento compartido en TrueNAS para copias (vzdump), ISOs y plantillas
pvesm status | grep -q truenas-nfs || \
pvesm add nfs truenas-nfs --server 192.168.36.20 --export /mnt/copias/proxmox \
      --content backup,iso,vztmpl,images --options vers=4.2 --prune-backups keep-last=3

# copia programada de todas las VMs y contenedores al NAS (diaria 22:00, modo snapshot)
grep -q "vzdump: copia-diaria" /etc/pve/jobs.cfg 2>/dev/null || \
pvesh create /cluster/backup --id copia-diaria --schedule "22:00" --all 1 --storage truenas-nfs \
      --mode snapshot --compress zstd --enabled 1 --notes-template "{{guestname}} - copia diaria"

# plantilla Debian 13 para contenedores (en el NFS, así la ven los tres nodos)
pveam update
# el nombre exacto cambia con cada revisión, así que cojo la última disponible
T=$(pveam available --section system | awk '/debian-13-standard_.*_amd64/ {print $2}' | sort -V | tail -1)
pveam list truenas-nfs | grep -q debian-13-standard || pveam download truenas-nfs "$T"
pvesm status
