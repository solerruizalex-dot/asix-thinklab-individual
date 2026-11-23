#!/bin/bash
# pve-06-prueba-migracion.sh - Álex Soler Ruiz
# Prueba de migración del clúster con máquinas SOLO de prueba (se borran al acabar con pve-07-limpiar.sh).
# serveis y dades NO viven en Proxmox: son VMs independientes de VirtualBox.
# Se ejecuta en pve1. Mide tiempo, datos copiados y corte de servicio (ping desde pve3).
#   CLAVE=... bash pve-06-prueba-migracion.sh > proxmox-migraciones.txt
set -u
: "${CLAVE:?define CLAVE con la contraseña del usuario alexsoler de la VM de prueba}"
VM=140; CT=130; IPVM=192.168.36.40; IPCT=192.168.36.30
IMG=/mnt/pve/truenas-nfs/template/qcow/debian-13-generic-amd64.qcow2
# los nodos del clúster ya confían entre sí por SSH (claves de root que crea el propio clúster)
en(){ n=$1; shift; case $n in pve1) h=192.168.36.32;; pve2) h=192.168.36.33;; pve3) h=192.168.36.34;; esac
     ssh -o BatchMode=yes -o HostKeyAlias=$n -o UserKnownHostsFile=/etc/pve/nodes/$n/ssh_known_hosts root@$h "$@"; }

# mide una migración: lanza ping desde pve3, ejecuta el comando en el nodo origen y cuenta pings perdidos
medir(){ destino_ip=$1; origen=$2; shift 2
  en pve3 "ping -i 0.5 -W 1 $destino_ip > /tmp/ping.$$ 2>&1 & echo \$! > /tmp/ping.pid"
  t0=$(date +%s.%N)
  en $origen "$@" 2>&1 | grep -E "starting|transferred .* (100|[0-9]{1,2}\.[0-9]+)%|copied|migration (finished|aborted)|ERROR|downtime|average|total" | tail -25
  rc=${PIPESTATUS[0]}; t1=$(date +%s.%N)
  sleep 3; en pve3 'kill -INT $(cat /tmp/ping.pid); sleep 1; tail -3 /tmp/ping.'$$
  echo "TIEMPO TOTAL: $(awk "BEGIN{printf \"%.1f\", $t1-$t0}") s (rc=$rc)"
}

echo "### Prueba de migración en grupo3-cluster - $(date '+%F %T')"
echo "Máquinas de prueba: CT $CT (web-pruebas) y VM $VM (prueba-migracion, Debian 13 sin entorno gráfico)."
pvecm status | grep -E "Nodes:|Quorate:"

echo; echo "=== 0) Crear la VM de prueba $VM en pve1 (disco en local-lvm, así la migración tiene que copiarlo)"
if ! qm status $VM >/dev/null 2>&1; then
  qm create $VM --name prueba-migracion --ostype l26 --cores 1 --memory 384 --balloon 0 --cpu host \
     --scsihw virtio-scsi-single --net0 virtio,bridge=vmbr0 --serial0 socket --vga serial0 --agent enabled=1
  qm set $VM --scsi0 local-lvm:0,import-from=$IMG,discard=on >/dev/null
  qm resize $VM scsi0 4G
  qm set $VM --ide2 local-lvm:cloudinit --boot order=scsi0 --ciuser alexsoler --cipassword "$CLAVE" \
     --ipconfig0 ip=$IPVM/24,gw=192.168.36.1 --nameserver 192.168.36.1 --searchdomain alexsoler.lan >/dev/null
  qm start $VM
fi
for i in $(seq 1 60); do en pve3 "ping -c1 -W1 $IPVM" >/dev/null 2>&1 && break; sleep 3; done
qm config $VM | grep -E "^(name|memory|cores|scsi0|net0)"
echo "La VM responde al ping tras arrancar: $(en pve3 "ping -c1 -W1 $IPVM >/dev/null && echo sí || echo no")"

echo; echo "=== 1) Contenedor $CT pve2 -> pve1 (modo restart: los contenedores LXC no migran en vivo)"
medir $IPCT pve2 pct migrate $CT pve1 --restart
echo "Ahora está en: $(pvesh get /cluster/resources --type vm --output-format json | python3 -c "import sys,json;print([r['node'] for r in json.load(sys.stdin) if r['vmid']==$CT][0])")"

echo; echo "=== 2) VM $VM pve1 -> pve2 EN VIVO con el disco LOCAL (--online --with-local-disks)"
medir $IPVM pve1 qm migrate $VM pve2 --online --with-local-disks

echo; echo "=== 3) Mejora: muevo el disco de la VM al NFS compartido de TrueNAS (sin apagarla)"
t0=$(date +%s.%N); en pve2 qm disk move $VM scsi0 truenas-nfs --format qcow2 --delete 1 2>&1 | tail -2
echo "Movimiento del disco: $(awk "BEGIN{printf \"%.1f\", $(date +%s.%N)-$t0}") s"
echo; echo "=== 4) VM $VM pve2 -> pve3 EN VIVO con el disco COMPARTIDO (solo viaja la RAM)"
medir $IPVM pve2 qm migrate $VM pve3 --online

echo; echo "=== 5) Copia de imagen (vzdump) de las dos máquinas de prueba al NAS"
en pve3 vzdump $VM --storage truenas-nfs --mode snapshot --compress zstd 2>&1 | grep -E "archive|transferred|Finished|size"
vzdump $CT --storage truenas-nfs --mode snapshot --compress zstd 2>&1 | grep -E "archive|transferred|Finished|size"
pvesm list truenas-nfs --content backup

echo; echo "=== Situación final"
pvesh get /cluster/resources --type vm --output-format json | python3 -c "
import sys,json
for r in json.load(sys.stdin): print(f\"{r['id']:9} {r['name']:18} {r['node']} {r['status']}\")"
echo "### Fin $(date '+%T')"
