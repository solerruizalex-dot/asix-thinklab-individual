# Servidores GNU/Linux de infraestructura: serveis y dades

Son las dos máquinas que me faltaban del esquema. Las monté como **VMs dentro del clúster Proxmox** (no en VirtualBox directamente), que es donde irán en la empresa.

| | serveis | dades |
|---|---|---|
| Función | Servidor de infraestructura (servicios de red en tareas posteriores) | Servidor de datos: RAID y espejo |
| SO | Debian 13.8 sin entorno gráfico, kernel 6.12.118 | Igual |
| Dónde | VM 122, ahora en pve1 | VM 123 en pve3 |
| Recursos | 1 vCPU, 384 MB, disco de 6 GB + 1 GB | 1 vCPU, 384 MB, disco de 6 GB + 8 × 1 GB |
| IP | 192.168.30.22/24 | 192.168.30.23/24 |

## Instalación

En lugar de instalar desde la ISO con el asistente, usé la **imagen oficial de Debian para máquinas virtuales** (`debian-13-generic-amd64.qcow2` de cloud.debian.org) con cloud-init, que es como se despliegan servidores en un hipervisor:

1. Descargué la imagen y comprobé su **SHA-512** con el `SHA512SUMS` oficial (`sha512sum -c` → OK) ([pve-03-imagen-debian.sh](../../scripts/pve-03-imagen-debian.sh)).
2. Cada VM se crea con un script ([pve-04-crear-vm.sh](../../scripts/pve-04-crear-vm.sh)): importa la imagen como disco, lo amplía a 6 GB y le pasa por cloud-init el usuario, la IP, la puerta de enlace, el DNS y el dominio de búsqueda.
3. Elegí la imagen *generic* y no la *genericcloud*, porque la segunda trae un kernel recortado y no sabía si tendría los módulos de RAID y DRBD.

Tardé 23 s en crear serveis y unos 2 minutos y medio en actualizarla e instalar los paquetes. A mano, con el instalador, serían unos 15 minutos por máquina.

### Problemas en la instalación

| Problema | Causa | Solución |
|---|---|---|
| cloud-init terminó en *error* y no instaló paquetes | Las VMs anidadas no salían de la LAN: faltaba el modo promiscuo en las tarjetas de los nodos (ver [06-proxmox](06-proxmox.md)) | Activar `allow-all` y completar la instalación de paquetes a mano |
| El módulo `locale` de cloud-init falló | La imagen no trae generado `es_ES.UTF-8` | Quité esa línea del *snippet*; el sistema queda en inglés y con hora de Madrid |
| SSH muy lento la primera vez | Era el mismo problema de red | — |

## Actualización y comprobación

```
apt-get update && apt-get full-upgrade      → Debian 13.7 → 13.8
cat /etc/debian_version                      → 13.8
uname -r                                     → 6.12.118+deb13-amd64 (tras la comprobación final de las 03:30)
systemctl is-active qemu-guest-agent         → active
```

Paquetes de base: `qemu-guest-agent` (para que Proxmox vea la IP y apague bien la VM), `mdadm`, `sysstat`, `rsync`, `traceroute`, `vim`, `htop`. Además, solo lo que necesita cada una para la Tarea 6 (`drbd-utils`). Como dice el enunciado, ningún otro servicio por ahora.

## Usuarios de administración

- `alexsoler`: lo crea cloud-init, con contraseña y `sudo`. Es con el que se administra.
- `root`: sin contraseña. Por SSH solo puede entrar el NAS con su clave, limitada con `from="192.168.30.20"`, para llevarse las copias.

## Red

Configurada por cloud-init (IP estática, no DHCP: un servidor tiene que estar siempre en la misma dirección):

```
eth0   192.168.30.22/24 (serveis) · 192.168.30.23/24 (dades)
ruta   default via 192.168.30.1
DNS    192.168.30.21 (DC), 192.168.30.1 · búsqueda alexsoler.lan
```

El DC ya tenía los registros `serveis` y `dades` en la zona `alexsoler.lan`. Las pruebas de conectividad (ping a la puerta, al NAS, a Internet y traceroute) están en [red-por-maquina.txt](../../evidencias/tasca4/red-por-maquina.txt).

## Copias: qué sí y qué no

| Qué | Cómo | Por qué |
|---|---|---|
| `/etc` completo + lista de paquetes (`dpkg --get-selections`) | El NAS lo copia cada noche por SSH | Con eso rehago el servidor sobre una VM nueva en minutos |
| La VM entera | `vzdump` diario de Proxmox al NFS | Para volver al punto anterior sin reinstalar |
| **No** copio los datos de los RAID por separado | — | Por ahora son datos de prueba. Cuando haya datos reales, se copiarán al NAS con `rsync` y snapshots, porque **un RAID no es una copia de seguridad** |

Ejecución real de la copia: [copias-config-ejecucion.txt](../../evidencias/tasca5/copias-config-ejecucion.txt) (serveis y dades: `etc.tgz` de ~500 KB cada uno).
