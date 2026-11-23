# Imágenes de instalación y requisitos

Todas las ISOs son x86-64 y salen de la web oficial de cada fabricante. Calculé el SHA-256 de cada una con `sha256sum` y lo comparé con la suma que publica el fabricante:

| Imagen | Resultado |
|---|---|
| debian-13.1.0-amd64-netinst.iso | **Coincide** (SHA256SUMS de cdimage.debian.org) |
| proxmox-ve_9.2-1.iso | **Coincide** (web de descargas de Proxmox) |
| TrueNAS-SCALE-24.04.0.iso | **Coincide** |
| ubuntu-26.04.1-desktop-amd64.iso | **Coincide** |
| OPNsense-26.7-dvd-amd64.iso | N/C: publican la suma del `.iso.bz2`, no de la ISO descomprimida |
| mikrotik-7.24.6.iso | N/C: no encontré fichero de sumas publicado |
| Windows 11 / Server 2025 (evaluación) | N/C: Microsoft muestra el hash en la página de descarga y no lo guardé |

Sumas completas: [isos-sha256.txt](../../evidencias/tasca5/isos-sha256.txt).

Para las VMs de Proxmox uso la imagen oficial `debian-13-generic-amd64.qcow2` de cloud.debian.org, comprobada con su `SHA512SUMS` (`sha512sum -c` → OK).
