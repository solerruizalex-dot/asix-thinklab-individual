#!/bin/bash
# pve-03-imagen-debian.sh - Álex Soler Ruiz
# Se ejecuta UNA vez en pve1. Descarga la imagen oficial de Debian 13 para VMs,
# comprueba su SHA-512 y prepara el "vendor-data" de cloud-init que usarán serveis y dades.
# Todo va al NFS de TrueNAS, así los tres nodos lo ven.
set -e
ST=/mnt/pve/truenas-nfs
URL=https://cloud.debian.org/images/cloud/trixie/latest
IMG=debian-13-generic-amd64.qcow2
mkdir -p $ST/template/qcow $ST/snippets
cd $ST/template/qcow
[ -f $IMG ] || wget -q $URL/$IMG
wget -q -O SHA512SUMS $URL/SHA512SUMS
grep " $IMG\$" SHA512SUMS | sha512sum -c -

# el almacenamiento NFS también guarda "snippets" (ficheros de cloud-init)
pvesm set truenas-nfs --content backup,iso,vztmpl,images,snippets

# lo que añade cloud-init a la configuración que pone Proxmox (usuario, IP, DNS)
cat > $ST/snippets/debian-base.yaml <<'EOT'
#cloud-config
timezone: Europe/Madrid
ssh_pwauth: true
package_update: true
package_upgrade: true
packages: [qemu-guest-agent, mdadm, vim, htop, sysstat, rsync, traceroute]
runcmd:
  - systemctl enable --now qemu-guest-agent
EOT
ls -l $ST/template/qcow $ST/snippets
