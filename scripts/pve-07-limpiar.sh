#!/bin/bash
# pve-07-limpiar.sh - Álex Soler Ruiz
# Deja los nodos como deben quedar en el laboratorio individual: solo la red y el clúster.
# Borra las máquinas de prueba (VM 140/141, CT 130), sus copias y plantillas del NAS,
# la tarea de copia vzdump y el almacenamiento NFS. Se ejecuta en pve1.
# Se mantiene: usuario alexsoler@pve (grupo administradores), repositorio sin suscripción y actualizaciones.
set -u
ipnodo(){ case $1 in pve1) echo 192.168.36.32;; pve2) echo 192.168.36.33;; pve3) echo 192.168.36.34;; esac; }
echo "### Limpieza de los nodos - $(date '+%F %T')"
for r in $(pvesh get /cluster/resources --type vm --output-format json | python3 -c "import sys,json;[print(f\"{x['node']}:{x['type']}:{x['vmid']}\") for x in json.load(sys.stdin)]"); do
  IFS=: read -r nodo tipo id <<<"$r"
  case $tipo in qemu) c="qm stop $id >/dev/null 2>&1; qm destroy $id --purge 1 --destroy-unreferenced-disks 1";;
                lxc)  c="pct stop $id >/dev/null 2>&1; pct destroy $id --purge 1";; esac
  ssh -n -o BatchMode=yes -o HostKeyAlias=$nodo -o UserKnownHostsFile=/etc/pve/nodes/$nodo/ssh_known_hosts root@$(ipnodo $nodo) "$c" >/dev/null 2>&1 \
    && echo "borrada $tipo $id (en $nodo)" || echo "ERROR borrando $tipo $id"
done
for v in $(pvesm list truenas-nfs 2>/dev/null | awk 'NR>1 {print $1}'); do pvesm free "$v" >/dev/null && echo "borrado del NAS: $v"; done
rm -f /mnt/pve/truenas-nfs/template/qcow/debian-13-generic-amd64.qcow2 && echo "borrada la imagen debian-13-generic del NAS"
pvesh delete /cluster/backup/copia-diaria && echo "quitada la tarea de copia vzdump 'copia-diaria'"
pvesm remove truenas-nfs && echo "quitado el almacenamiento truenas-nfs"
echo; echo "--- Estado final"
pvecm status | grep -E "Name:|Nodes:|Quorate:"
echo "Máquinas en el clúster: $(pvesh get /cluster/resources --type vm --output-format json | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))')"
pvesm status
cat /etc/pve/jobs.cfg 2>/dev/null | grep -c vzdump | sed 's/^/Tareas de copia: /'
pveum user list --output-format json | python3 -c "import sys,json;[print('Usuario:',u['userid']) for u in json.load(sys.stdin)]"
pveum group list --output-format json | python3 -c "import sys,json;[print('Grupo:',g['groupid'],'->',g.get('users','')) for g in json.load(sys.stdin)]"
grep -E '^acl' /etc/pve/user.cfg
for n in 1 2 3; do echo "pve$n: $(ssh -n -o BatchMode=yes -o HostKeyAlias=pve$n -o UserKnownHostsFile=/etc/pve/nodes/pve$n/ssh_known_hosts root@192.168.36.3$((n+1)) 'echo $(hostname -I | cut -d" " -f1) $(pveversion | cut -d/ -f2)')"; done
