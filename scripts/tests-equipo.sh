#!/bin/bash
# tests-equipo.sh - Álex Soler Ruiz
# Tests de memoria, disco y red del equipo físico (Tarea 2), sin instalar nada y sin root.
# Ejecutar con TODAS las VMs apagadas, para que la línea base sea limpia:
#     bash tests-equipo.sh > resultado-$(hostname).txt
# Disco que se prueba: el del directorio $HOME (en mi caso el SSD de clase por USB).
set -u
DIR=${DIR:-$HOME/.tests-equipo}; mkdir -p "$DIR"
URL=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.8.0-amd64-netinst.iso
echo "### Tests de $(hostname) - $(date '+%F %T')"
echo "Equipo: $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/class/dmi/id/product_name 2>/dev/null)"
echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2) · $(nproc) hilos"
echo "VMs de VirtualBox encendidas: $(VBoxManage list runningvms 2>/dev/null | wc -l)"
echo "Carga al empezar: $(cut -d' ' -f1-3 /proc/loadavg)"
echo

echo "=== 1. MEMORIA ==="
free -m | sed -n 1,3p
echo "--- errores de memoria en el registro del kernel (MCE/EDAC)"
journalctl -k -b 0 --no-pager 2>/dev/null | grep -iE "mce: \[hardware error\]|edac.*(ce|ue) |memory error" | head -5 || true
echo "(si no sale nada arriba: ninguno)"
echo "--- prueba de patrones y ancho de banda (Python, 2 GB)"
python3 -I - <<'EOF'
import time
TAM = 2 * 1024**3; BLOQ = 64 * 1024**2
pat = [b'\x00', b'\xff', b'\x55', b'\xaa']
errores = 0; t0 = time.time(); escritos = 0
bloques = [bytearray(BLOQ) for _ in range(TAM // BLOQ)]
for p in pat:
    ref = p * BLOQ
    for b in bloques: b[:] = ref; escritos += BLOQ
    for b in bloques:
        if b != ref: errores += 1
dt = time.time() - t0
print(f"patrones 00/FF/55/AA sobre {TAM//1024**3} GB: {errores} bloques con error · "
      f"escritura+verificación a {2*escritos/dt/1e9:.1f} GB/s en {dt:.1f} s")
print("(esto detecta fallos gordos; el test completo es memtest86+ desde el arranque)")
EOF
echo

echo "=== 2. DISCO ==="
D=$(df --output=source "$HOME" | tail -1); DEV=$(lsblk -no pkname "$D" 2>/dev/null | head -1)
echo "Disco de \$HOME: $D en /dev/$DEV · $(lsblk -dno TRAN,MODEL,SIZE /dev/$DEV 2>/dev/null)"
echo "Espacio: $(df -h --output=size,used,avail,pcent "$HOME" | tail -1)"
echo "--- escritura secuencial 1 GB sin caché (dd oflag=direct)"
dd if=/dev/zero of="$DIR/prueba.bin" bs=1M count=1024 oflag=direct 2>&1 | tail -1
echo "--- lectura secuencial 1 GB sin caché (dd iflag=direct)"
dd if="$DIR/prueba.bin" of=/dev/null bs=1M iflag=direct 2>&1 | tail -1
echo "--- escritura de bloques pequeños: 4000 x 4 KB con sincronización (como una base de datos)"
dd if=/dev/zero of="$DIR/peq.bin" bs=4k count=4000 oflag=direct,dsync 2>&1 | tail -1
rm -f "$DIR/prueba.bin" "$DIR/peq.bin"
echo "--- errores de disco/USB en el registro"
journalctl -k -b 0 --no-pager 2>/dev/null | grep -iE "I/O error|uas.*(reset|abort)|usb.*reset high-speed|blk_update_request" | tail -5 || true
echo "(si no sale nada arriba: ninguno)"
echo

echo "=== 3. RED ==="
IF=$(ip route show default | awk '{print $5; exit}'); GW=$(ip route show default | awk '{print $3; exit}')
echo "Interfaz $IF · enlace $(cat /sys/class/net/$IF/speed 2>/dev/null) Mbit/s · dúplex $(cat /sys/class/net/$IF/duplex 2>/dev/null) · puerta $GW"
echo "--- latencia a la puerta de enlace (20 pings)"
ping -c 20 -i 0.2 -q "$GW" | tail -2
echo "--- latencia a Internet (1.1.1.1, 20 pings)"
ping -c 20 -i 0.2 -q 1.1.1.1 | tail -2
echo "--- descarga de 100 MB (cdimage.debian.org)"
curl -sL -r 0-104857599 -o /dev/null -w "%{size_download} bytes en %{time_total} s = %{speed_download} B/s\n" "$URL"
echo "--- errores de la tarjeta"
ip -s link show "$IF" | sed -n '3,6p'
echo
echo "### Fin $(date '+%T')"
