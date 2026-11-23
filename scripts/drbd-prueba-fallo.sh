#!/bin/bash
# drbd-prueba-fallo.sh - Álex Soler Ruiz
# Monta el espejo DRBD entre serveis y dades y prueba que si serveis se cae de golpe,
# la carpeta compartida se levanta en dades con los datos al día.
# Se ejecuta en el ANFITRIÓN. Necesita dos funciones que ejecuten como root lo que reciben:
#   RS (en serveis) y RD (en dades), p. ej.:
#   RS(){ { echo "$CLAVE"; printf '%s\n' "$*"; } | ssh -J alexsoler@127.0.0.1:2222 alexsoler@192.168.36.22 "sudo -S -p '' bash -s"; }
set -u
DIR=$(dirname "$0")
t(){ echo; echo "[$(date +%T)] $*"; }
ahora(){ date +%s.%N; }
para(){ echo "   ** $* : paro la prueba **"; exit 1; }   # si un paso falla no sigo (la primera vez seguí y escribí en el disco de sistema)
seg(){ awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", b-a}'; }

t "0) Configuración en los dos equipos (drbd-espejo.sh)"
RS "$(cat "$DIR/drbd-espejo.sh")"; RD "$(cat "$DIR/drbd-espejo.sh")"
RS "cat /proc/drbd | head -1; drbdadm --version | grep DRBDADM_VERSION=; cat /etc/drbd.d/espejo.res"

t "1) serveis pasa a primario y se hace la sincronización inicial (1 GB)"
i=$(ahora)
RS "drbdadm primary --force espejo; while ! grep -q 'ds:UpToDate/UpToDate' /proc/drbd; do sleep 1; done; cat /proc/drbd | tail -2"
echo "   sincronización inicial: $(seg $i $(ahora)) s"
RS "grep -q ds:UpToDate/UpToDate /proc/drbd" || para "el espejo no está sincronizado"

t "2) Carpeta compartida de la empresa en serveis (primario) con datos ficticios"
RS "mkfs.ext4 -q -L compartida /dev/drbd0; mkdir -p /srv/compartida; mount /dev/drbd0 /srv/compartida
    cd /srv/compartida; mkdir Administracion Comercial Informatica; chmod 750 Comercial
    for d in Administracion Comercial Informatica; do echo \"documento de \$d - \$(date +%T)\" > \$d/leeme.txt; done
    head -c 50M /dev/urandom > Informatica/imagen.bin; sync
    find . -type f ! -path './lost+found*' -exec sha256sum {} + | sort -k2 > /root/compartida.sha256
    cat /root/compartida.sha256; ls -l; cat /proc/drbd | tail -2"
RS "mountpoint -q /srv/compartida" || para "la carpeta compartida no está montada sobre DRBD"
SUMAS=$(RS "cat /root/compartida.sha256")
RD "printf '%s\n' '$SUMAS' > /root/compartida.sha256; mkdir -p /srv/compartida"

t "3) En dades (secundario) no se puede montar: solo recibe las escrituras"
RD "mount /dev/drbd0 /srv/compartida 2>&1; true"

t "4) FALLO: apago serveis de golpe desde VirtualBox (como quitar la corriente)"
f=$(ahora); VBoxManage controlvm serveis-AlexSoler poweroff 2>&1 | tail -1
RD "sleep 1; cat /proc/drbd | tail -2"

t "5) RECUPERACIÓN en dades: paso a primario, monto y compruebo los ficheros"
RD "drbdadm primary espejo && mount /dev/drbd0 /srv/compartida && cd /srv/compartida && sha256sum -c /root/compartida.sha256 && cat Administracion/leeme.txt" || para "no se pudo levantar en dades"
echo "   datos comprobados en dades $(seg $f $(ahora)) s después del fallo"
RD "stat -c '%A %U %n' /srv/compartida/Comercial; su -s /bin/sh nobody -c 'cat /srv/compartida/Comercial/leeme.txt' 2>&1 | sed 's/^/   como usuario sin permisos: /'"

t "6) Mientras serveis está caído se sigue trabajando en dades"
RD "echo \"creado en dades durante la caída de serveis \$(date +%T)\" > /srv/compartida/durante-la-caida.txt; sync; cat /proc/drbd | tail -2"

t "7) Vuelvo a encender serveis"
VBoxManage startvm serveis-AlexSoler --type headless 2>&1 | tail -1
until RS true 2>/dev/null; do sleep 3; done
RS "systemctl is-enabled drbd 2>&1; cat /proc/drbd 2>/dev/null | tail -1 || echo 'DRBD sin levantar'"
t "   serveis no se reconecta solo (drbd.service deshabilitado): lo levanto a mano, como paso del procedimiento"
r=$(ahora)
RS "drbdadm up espejo; sleep 2; while ! grep -q 'ds:UpToDate/UpToDate' /proc/drbd; do sleep 1; done; dmesg | grep -iE 'out-of-sync|resync' | tail -3; cat /proc/drbd | tail -2"
echo "   resincronizado en $(seg $r $(ahora)) s"

t "8) Vuelta a la normalidad: dades suelta el recurso y serveis vuelve a ser primario"
RD "umount /srv/compartida && drbdadm secondary espejo && echo 'dades: secundario'"
RS "drbdadm primary espejo && mkdir -p /srv/compartida && mount /dev/drbd0 /srv/compartida && cat /srv/compartida/durante-la-caida.txt; cat /proc/drbd | tail -2"
