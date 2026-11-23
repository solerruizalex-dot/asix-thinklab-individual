#!/bin/bash
# linux-00-crear-vm.sh - Álex Soler Ruiz
# Crea en el ANFITRIÓN las VMs serveis y dades (independientes, grupo de VirtualBox del proyecto) y las instala
# desatendidas desde la ISO netinst de Debian 13 con mi preseed (configs/preseed-servidores.cfg).
#   uso: CLAVE=... ISO=/ruta/debian-13.1.0-amd64-netinst.iso bash linux-00-crear-vm.sh
# Después: linux-02-paquetes.sh (aún por NAT) y linux-01-servidor.sh (IP fija), y se pasa la tarjeta a lan_grupo3
#   (VBoxManage controlvm VM nic1 intnet lan_grupo3) y se quita la redirección: VBoxManage modifyvm VM --natpf1 delete ssh
set -e
: "${CLAVE:?falta CLAVE}" "${ISO:?falta ISO}"
G="/ASIX-ThinkLAB Individual"; B="$HOME/VirtualBox VMs/ASIX-ThinkLAB Individual"
PRESEED="$(dirname "$0")/../configs/preseed-servidores.cfg"
for N in serveis dades; do
  V=$N-AlexSoler
  VBoxManage createvm --name $V --groups "$G" --ostype Debian_64 --register >/dev/null
  # 1 vCPU y 1 GB: sin entorno gráfico sobra. Sin audio ni USB.
  # Tarjeta Intel 82540EM y NO virtio: con virtio en la red interna de VirtualBox las descargas se quedaban
  # paradas a los pocos KB (por eso se colgaba el instalador). La instalación va por NAT y luego se pasa a lan_grupo3.
  VBoxManage modifyvm $V --cpus 1 --memory 1024 --vram 16 --graphicscontroller vmsvga --nic1 nat --nictype1 82540EM \
      --audio-driver none --usb-ohci off --rtc-use-utc on
  VBoxManage storagectl $V --name SATA --add sata --controller IntelAhci --portcount 10 --hostiocache on
  VBoxManage createmedium disk --filename "$B/$V/$V.vdi" --size 10240 >/dev/null
  VBoxManage storageattach $V --storagectl SATA --port 0 --device 0 --type hdd --medium "$B/$V/$V.vdi"
  p=1
  if [ $N = dades ]; then   # 7 discos de 1 GB para los RAID, extraíbles en caliente para las pruebas de fallo
    for i in 1 2 3 4 5 6 7; do VBoxManage createmedium disk --filename "$B/$V/raid$i.vdi" --size 1024 >/dev/null
      VBoxManage storageattach $V --storagectl SATA --port $p --device 0 --type hdd --hotpluggable on --medium "$B/$V/raid$i.vdi"; p=$((p+1)); done
  fi
  VBoxManage createmedium disk --filename "$B/$V/drbd.vdi" --size 1024 >/dev/null   # disco del espejo DRBD
  VBoxManage storageattach $V --storagectl SATA --port $p --device 0 --type hdd --medium "$B/$V/drbd.vdi"
  VBoxManage modifyvm $V --natpf1 "ssh,tcp,127.0.0.1,$([ $N = serveis ] && echo 2232 || echo 2233),,22"
  VBoxManage unattended install $V --iso="$ISO" --user=alexsoler --password="$CLAVE" --full-user-name="Alex Soler Ruiz" \
      --hostname=$N.alexsoler.lan --locale=es_ES --country=ES --time-zone=Europe/Madrid --script-template="$PRESEED"
  # 'unattended' deja el disco primero en el orden de arranque: con el disco vacío la VM se quedaba en negro
  VBoxManage modifyvm $V --boot1 dvd --boot2 disk --boot3 none --boot4 none
  VBoxManage startvm $V --type headless
done
echo "Instalando. El preseed apaga las VMs al terminar; luego: quitar el DVD y arrancar desde el disco:"
echo "  VBoxManage storageattach VM --storagectl IDE --port 0 --device 0 --type dvddrive --medium emptydrive"
echo "  VBoxManage modifyvm VM --boot1 disk"
