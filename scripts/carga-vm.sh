# carga de trabajo dentro de una VM: CPU al 100 %, escritura en disco y descarga, a la vez
( timeout 90 sh -c 'while :; do :; done' ) &
( for i in 1 2 3; do dd if=/dev/zero of=/var/tmp/carga.bin bs=1M count=300 oflag=direct 2>&1 | tail -1; rm -f /var/tmp/carga.bin; done ) &
curl -sL -r 0-104857599 -o /dev/null -w "descarga 100 MB: %{speed_download} B/s en %{time_total} s\n" https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.8.0-amd64-netinst.iso || true
wait
