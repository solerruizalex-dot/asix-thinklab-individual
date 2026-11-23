#!/bin/bash
# dades-raid-fallo-real.sh - Álex Soler Ruiz
# Pruebas de fallo de los RAID de dades QUITANDO DE VERDAD un disco con la VM encendida
# (VirtualBox: puertos SATA marcados como extraíbles en caliente con la VM apagada) y poniendo uno NUEVO y vacío.
# Se ejecuta en el ANFITRIÓN. Necesita una función R que ejecute como root en dades lo que recibe, p. ej.:
#   R(){ { echo "$CLAVE"; printf '%s\n' "$*"; } | ssh -J alexsoler@127.0.0.1:2222 alexsoler@192.168.36.23 "sudo -S -p '' bash -s"; }
# Antes: dades-raid.sh creó md0 (puertos 1+2), md1 (puertos 3+4) y md5 (puertos 5+6+7).
#
# Cambio de un disco en caliente en Linux (lo aprendí en la primera ejecución, que falló):
#  1. el disco desaparece -> mdadm no se entera hasta que intenta escribir en él (sigue en [UU])
#  2. hay que hacer que el kernel OLVIDE el disco (/sys/block/sdX/device/delete); si no, al llegar
#     el disco nuevo al mismo puerto ve otro número de serie, falla la revalidación y no crea sdX
#  3. se conecta el nuevo y se vuelve a escanear el controlador (/sys/class/scsi_host/*/scan)
set -u
VM=dades-AlexSoler
DIR="$HOME/VirtualBox VMs/ASIX-ThinkLAB Individual/$VM"
BP=/dev/disk/by-path/pci-0000:00:0d.0-ata    # ata-N = puerto SATA N-1
t(){ echo; echo "[$(date +%T)] $*"; }
dev(){ R "readlink -f $BP-$(( $1 + 1 )) 2>/dev/null | sed 's|/dev/||'"; }   # nombre sdX del disco de un puerto
quitar(){ VBoxManage storageattach $VM --storagectl SATA --port $1 --device 0 --medium none && echo "   (anfitrión) disco del puerto SATA $1 arrancado"; }
poner(){ VBoxManage storageattach $VM --storagectl SATA --port $1 --device 0 --type hdd --medium "$2" && echo "   (anfitrión) $(basename "$2") conectado en el puerto SATA $1"; }
olvidar(){ R "[ -e /sys/block/$1/device/delete ] && echo 1 > /sys/block/$1/device/delete; echo '   el kernel ya no tiene $1'"; }
escanear(){ R "for h in /sys/class/scsi_host/host*/scan; do echo '- - -' > \$h; done; udevadm settle; sleep 2"; }
esperar_sync(){ md=$1; i=$(date +%s)
  # primero espero a que EMPIECE la reconstrucción y luego a que acabe
  R "for n in \$(seq 1 20); do grep -A3 '^$md ' /proc/mdstat | grep -q recovery && break; sleep 0.5; done
     while grep -A3 '^$md ' /proc/mdstat | grep -q recovery; do sleep 1; done"
  echo "   $md reconstruido en $(( $(date +%s) - i )) s"; }
cambio(){  # md puerto fichero_nuevo
  md=$1; p=$2; viejo=$(dev $p)
  t "   arranco el disco del puerto $p ($viejo) con dades encendida"
  quitar $p; sleep 3
  R "echo '   justo después:'; grep -A1 '^$md ' /proc/mdstat"
  t "   escribo en el RAID: así mdadm descubre que falta el disco"
  R "date > /srv/$md/despues-del-fallo.txt; sync; sleep 2; grep -A1 '^$md ' /proc/mdstat; mdadm --detail /dev/$md | grep -E 'State :|Active Devices|Failed Devices'
     dmesg | grep -E 'md/raid|$viejo' | tail -3"
  R "sha256sum -c /root/$md.sha256"
  t "   quito el disco del RAID, el kernel lo olvida y pongo un disco NUEVO y vacío en el mismo puerto"
  R "mdadm /dev/$md --fail /dev/$viejo 2>/dev/null; mdadm /dev/$md --remove failed; mdadm /dev/$md --remove detached 2>/dev/null; true"
  olvidar $viejo
  VBoxManage createmedium disk --filename "$DIR/$3" --size 1024 >/dev/null; poner $p "$DIR/$3"; escanear
  nuevo=$(dev $p)
  echo "   el disco nuevo del puerto $p aparece como /dev/$nuevo ($(R "lsblk -dno SIZE,SERIAL /dev/$nuevo"))"
  R "mdadm /dev/$md --add /dev/$nuevo"; esperar_sync $md
  R "grep -A1 '^$md ' /proc/mdstat; mdadm --detail /dev/$md | grep -E 'State :|Active Devices'; sha256sum -c /root/$md.sha256"
}

t "0) Situación inicial"
R "cat /proc/mdstat; for p in 1 2 3 4 5 6 7 8; do echo \"puerto SATA \$p -> \$(readlink -f $BP-\$((p+1)))\"; done"

t "1) Datos ficticios (100 MB aleatorios) en cada RAID y su SHA-256"
R 'for m in md0 md1 md5; do head -c 100M /dev/urandom > /srv/$m/datos.bin; sha256sum /srv/$m/datos.bin > /root/$m.sha256; done; sync; cat /root/md*.sha256'

t "2) Velocidad: dd de 200 MB saltándose la caché (oflag/iflag=direct)"
R 'dd if=/dev/zero of=/root/ref.bin bs=1M count=200 oflag=direct 2>&1 | tail -1 | sed "s/^/   disco simple (sda) escritura: /"; rm -f /root/ref.bin
   for m in md0 md1 md5; do dd if=/dev/zero of=/srv/$m/v.bin bs=1M count=200 oflag=direct 2>&1 | tail -1 | sed "s/^/   $m escritura: /"
   echo 3 > /proc/sys/vm/drop_caches; dd if=/srv/$m/v.bin of=/dev/null bs=1M iflag=direct 2>&1 | tail -1 | sed "s/^/   $m lectura:   /"; rm -f /srv/$m/v.bin; done'

t "3) RAID 1 (md1): fallo real de un disco y cambio por uno nuevo"
cambio md1 4 cambio-md1.vdi

t "4) RAID 5 (md5): fallo real de un disco y cambio por uno nuevo"
cambio md5 6 cambio-md5.vdi

t "5) RAID 0 (md0): arranco el disco del puerto 2"
viejo=$(dev 2); quitar 2; sleep 3
R "echo 3 > /proc/sys/vm/drop_caches; sha256sum -c /root/md0.sha256 2>&1 | tail -2; date > /srv/md0/prueba.txt 2>&1; sync 2>&1; sleep 2
   grep -A1 '^md0 ' /proc/mdstat; mdadm --detail /dev/md0 2>&1 | grep -E 'State :|Active Devices|Failed'; dmesg | grep -iE 'md0|EXT4-fs error|I/O error' | tail -4"
t "   vuelvo a conectar el disco ORIGINAL de md0 (con uno nuevo no habría nada que recuperar)"
R "umount -l /srv/md0; mdadm --stop /dev/md0"
olvidar $viejo; poner 2 "$DIR/raid2.vdi"; escanear
R "mdadm --assemble --scan 2>&1 | tail -2; e2fsck -fy /dev/md0 2>&1 | tail -2; mount /srv/md0; grep -A1 '^md0 ' /proc/mdstat; sha256sum -c /root/md0.sha256"

t "6) Estado final"
R "cat /proc/mdstat; mdadm --detail --scan; for p in 1 2 3 4 5 6 7; do echo \"puerto SATA \$p -> \$(readlink -f $BP-\$((p+1))) \$(lsblk -dno SERIAL \$(readlink -f $BP-\$((p+1))))\"; done"
