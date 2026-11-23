#!/bin/bash
# pve-04-crear-vm.sh - Álex Soler Ruiz
# Crea una VM Debian 13 sin entorno gráfico a partir de la imagen oficial.
# Se ejecuta en el nodo donde vivirá la VM.
#   uso: pve-04-crear-vm.sh VMID NOMBRE IP [DISCOS_EXTRA]
#   ej.: pve-04-crear-vm.sh 122 serveis 192.168.30.22 1
#        pve-04-crear-vm.sh 123 dades   192.168.30.23 8    (7 discos de 1 GB para los RAID + 1 para DRBD)
#        serveis lleva 1 disco extra (el otro lado del espejo DRBD)
set -e
: "${CLAVE:?define CLAVE con la contraseña del usuario alexsoler}"
ID=$1; NOMBRE=$2; IP=$3; EXTRA=${4:-0}
IMG=/mnt/pve/truenas-nfs/template/qcow/debian-13-generic-amd64.qcow2
qm status $ID >/dev/null 2>&1 && { echo "la VM $ID ya existe"; exit 0; }

qm create $ID --name $NOMBRE --ostype l26 --cores 1 --memory 384 --balloon 0 \
   --cpu host --scsihw virtio-scsi-single --net0 virtio,bridge=vmbr0 \
   --serial0 socket --vga serial0 --agent enabled=1 --onboot 1
# el disco del sistema va al almacenamiento local del nodo (así la migración tiene que copiarlo)
qm set $ID --scsi0 local-lvm:0,import-from=$IMG,discard=on
qm resize $ID scsi0 6G
qm set $ID --ide2 local-lvm:cloudinit --boot order=scsi0
qm set $ID --ciuser alexsoler --cipassword "$CLAVE" \
   --ipconfig0 ip=$IP/24,gw=192.168.30.1 --nameserver "192.168.30.21 192.168.30.1" \
   --searchdomain alexsoler.lan --cicustom vendor=truenas-nfs:snippets/debian-base.yaml
for n in $(seq 1 $EXTRA); do
    qm set $ID --scsi$n local-lvm:1
done
qm start $ID
qm config $ID
