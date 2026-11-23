# Imágenes de instalación y requisitos

Todas las ISOs son x86-64 y salen de la web oficial de cada fabricante. Calculé el SHA-256 de cada una con `sha256sum` y lo comparé con la suma que publica el fabricante:

| Imagen | Resultado |
|---|---|
| debian-13.1.0-amd64-netinst.iso | **Coincide** (SHA256SUMS de cdimage.debian.org) |
| proxmox-ve_9.2-1.iso | **Coincide** (web de descargas de Proxmox) |
| TrueNAS-SCALE-24.04.0.iso | **Coincide** |
| ubuntu-26.04.1-desktop-amd64.iso | **Coincide** |
| OPNsense-26.7-dvd-amd64.iso | **Coincide**. OPNsense solo publica la suma del `.iso.bz2`: lo descargué, su SHA-256 coincide con el oficial, y al descomprimirlo da exactamente mi ISO (`1efd5dc9…`) |
| mikrotik-7.24.6.iso | **Coincide** con `mikrotik-7.24.6.iso.sha256` de download.mikrotik.com. Al principio lo di por inexistente porque busqué un fichero de sumas general (`CHECKSUMS`); MikroTik publica uno por cada imagen |
| Windows 11 / Server 2025 (evaluación) | **N/C**: Microsoft enseña el hash solo en la página de descarga, al generar el enlace, y no lo apunté. La próxima vez: copiar el hash de esa página y comparar con `Get-FileHash` |

Sumas completas: [isos-sha256.txt](../../evidencias/tasca5/isos-sha256.txt).

Para las VMs de Proxmox uso la imagen oficial `debian-13-generic-amd64.qcow2` de cloud.debian.org, comprobada con su `SHA512SUMS` (`sha512sum -c` → OK).
