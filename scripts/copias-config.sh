#!/bin/bash
# copias-config.sh - Álex Soler Ruiz - ASIX ThinkLab (entorno individual)
#
# Se ejecuta en TrueNAS (tarea cron diaria) y se trae la configuración de los
# equipos críticos de la LAN 192.168.30.0/24 al dataset copias/configs.
# Modelo "pull": el NAS entra por SSH con su clave a cada equipo. Los equipos
# no guardan ninguna contraseña del NAS y en cada authorized_keys la clave
# solo se acepta si viene de 192.168.30.20.
#
# Si un equipo está apagado se apunta en el log y se sigue con el siguiente.

DEST=/mnt/copias/configs
KEY=/mnt/copias/scripts/.ssh/id_ed25519
LOG=$DEST/copias.log
HOY=$(date +%F_%H%M)
RETENCION=30   # días que se guardan las copias

SSH="ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/mnt/copias/scripts/.ssh/known_hosts"
SCP="scp -O -i $KEY -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/mnt/copias/scripts/.ssh/known_hosts"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

carpeta() { mkdir -p "$DEST/$1/$HOY"; echo "$DEST/$1/$HOY"; }

ok=0; fallos=0
resultado() {  # $1 equipo  $2 codigo
    if [ "$2" -eq 0 ]; then log "OK    $1"; ok=$((ok+1)); else log "FALLO $1 (codigo $2)"; fallos=$((fallos+1)); fi
}

log "---- inicio de copias ----"

# MikroTik: export en texto (legible y portable) + backup binario que genera su scheduler
d=$(carpeta mikrotik)
$SSH copias@192.168.30.1 "/export show-sensitive" > "$d/mikrotik.rsc" \
  && $SCP copias@192.168.30.1:/mikrotik-diario.backup "$d/"
resultado mikrotik $?

# OPNsense: todo el sistema está en un único fichero
d=$(carpeta opnsense)
$SCP root@192.168.30.2:/conf/config.xml "$d/config.xml"
resultado opnsense $?

# Router Debian con nftables: solo los ficheros que definen su función
d=$(carpeta debian-nft)
$SSH root@192.168.30.3 "tar czf - /etc/nftables.conf /etc/network /etc/dnsmasq.conf /etc/dnsmasq.d /etc/sysctl.d /etc/ssh/sshd_config /etc/hostname /etc/hosts 2>/dev/null; true" > "$d/etc.tgz" \
  && $SSH root@192.168.30.3 "dpkg --get-selections" > "$d/paquetes.txt"
resultado debian-nft $?

# Nodos Proxmox: /etc/pve es la configuración del clúster (pmxcfs), más red y corosync
for n in 32:pve1 33:pve2 34:pve3; do
    ip=192.168.30.${n%%:*}; nodo=${n##*:}
    d=$(carpeta proxmox-$nodo)
    $SSH root@$ip "tar czf - /etc/pve /etc/network/interfaces /etc/hosts /etc/corosync /var/lib/pve-cluster/config.db 2>/dev/null; true" > "$d/pve-etc.tgz"
    resultado proxmox-$nodo $?
done

# Servidores Debian de infraestructura y cliente Linux: /etc y lista de paquetes
for n in 22:serveis 23:dades 150:cliente-linux; do
    ip=192.168.30.${n%%:*}; eq=${n##*:}
    d=$(carpeta $eq)
    $SSH root@$ip "tar czf - /etc 2>/dev/null; true" > "$d/etc.tgz" \
      && $SSH root@$ip "dpkg --get-selections" > "$d/paquetes.txt"
    resultado $eq $?
done

# Las copias vacías (equipo apagado) no sirven: se borran para no confundir
find "$DEST" -mindepth 2 -type f -size 0 -delete
find "$DEST" -mindepth 2 -type d -empty -delete

# Retención
find "$DEST" -mindepth 2 -maxdepth 2 -type d -mtime +$RETENCION -exec rm -rf {} +

log "---- fin: $ok correctas, $fallos con fallo ----"
exit 0
