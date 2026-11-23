# Servidores GNU/Linux de infraestructura: serveis y dades

Son las dos máquinas Debian del esquema. En el aula irán dentro del clúster Proxmox, pero en mi entorno individual son **VMs independientes de VirtualBox**, en el mismo grupo que el resto (`ASIX-ThinkLAB Individual`), igual que el DC. Al principio las metí dentro de Proxmox y no funcionó bien: los nodos tienen 2 GB de RAM y 7 GB de disco, y el *thin pool* se llenó dos veces (lo cuento en [06-proxmox](06-proxmox.md)).

| | serveis | dades |
|---|---|---|
| Función | Servidor de infraestructura (servicios de red en tareas posteriores) | Servidor de datos: RAID y espejo |
| SO | Debian 13.8 sin entorno gráfico, kernel 6.12.118 | Igual |
| Recursos | 1 vCPU, 1 GB de RAM | 1 vCPU, 1 GB de RAM |
| Discos | Sistema 10 GB + 1 GB para el espejo DRBD | Sistema 10 GB + 7 × 1 GB para los RAID + 1 GB para el espejo DRBD |
| Red | `lan_grupo3`, tarjeta Intel 82540EM (al principio virtio, ver abajo) | Igual |
| IP | 192.168.36.22/24 | 192.168.36.23/24 |

Con 1 GB van sobradas: sin escritorio, en reposo serveis usa 247 MB y dades 301 MB (con los tres RAID montados y DRBD), medido con `free -m`.

## Instalación

Desde la ISO **netinst de Debian 13.1** que ya tenía en el equipo (SHA-256 comprobado con el `SHA256SUMS` oficial, [isos-sha256.txt](../../evidencias/tasca5/isos-sha256.txt)), con una **instalación desatendida** de VirtualBox (`VBoxManage unattended`) y mi propio *preseed*:

- [linux-00-crear-vm.sh](../../scripts/linux-00-crear-vm.sh): crea las dos VMs, sus discos y lanza la instalación.
- [preseed-servidores.cfg](../../configs/preseed-servidores.cfg): las respuestas del instalador. Teclado español, zona horaria de Madrid, disco entero con particiones automáticas, tarea *minimal* + `openssh-server` (nada de escritorio) y que **se apague al terminar**.

Como son dos máquinas iguales, hacerlo desatendido me ahorra contestar dos veces las mismas pantallas y me deja la receta para repetirlo. La instalación buena tardó **32 minutos** con las dos a la vez (de 10:00 a 10:33), casi todo descargando paquetes.

### Lo que me falló (cuatro intentos)

| Problema | Causa | Solución |
|---|---|---|
| Pantalla negra al arrancar | `unattended install` deja el **disco** primero en el orden de arranque, y el disco estaba vacío | Poner el DVD primero (`--boot1 dvd`) después de preparar la instalación |
| El instalador se quedaba colgado para siempre descargando de `deb.debian.org` | Por `lan_grupo3` el `wget` del instalador no avanzaba. No era el DNS ni IPv6, y el TrueNAS sí descargaba por la misma red. La causa la encontré después (ver «Red»): la **tarjeta virtio** | En ese momento instalé con la tarjeta en **NAT de VirtualBox** y la pasé a `lan_grupo3` al terminar. Ahora el script ya crea las VMs con la tarjeta Intel |
| Bucle de error del *mirror* | Probé a desactivar la red del instalador (`netcfg/enable false`) y la *netinst* necesita red | Lo quité |
| «Inserte el disco» en bucle | Un script mío que vigilaba la instalación expulsó el CD antes de tiempo | Reinstalar desde cero y añadir al preseed que se apague al acabar, así sé seguro cuándo ha terminado |
| Error en el *late_command* | El script de postinstalación de VirtualBox terminó con código 1 ([captura del cliente Linux, mismo fallo](../../evidencias/tasca5/linux-fallo-late-command.png)) | Lo que hacía y me importaba (instalar `sudo`) lo hice a mano desde la consola como root |
| `resolv.conf` vacío tras pasar a IP fija | Sin el paquete `resolvconf`, las líneas `dns-nameservers` de `interfaces` no hacen nada | El script escribe `/etc/resolv.conf` al final |
| `exim4` instalado sin pedirlo | `mdadm` lo recomienda para mandar avisos por correo | Instalar con `--no-install-recommends` y quitarlo |
| Arrancaba en `graphical.target` | El instalador lo deja así aunque no haya escritorio | `systemctl set-default multi-user.target` |

## Actualización y paquetes

[linux-02-paquetes.sh](../../scripts/linux-02-paquetes.sh), salida en [serveis-dades-instalacion.txt](../../evidencias/tasca5/serveis-dades-instalacion.txt):

```
== Antes: Debian 13.8, kernel 6.12.118+deb13-amd64
== Paquetes pendientes: 0
== Después: Debian 13.8, kernel 6.12.118+deb13-amd64, pendientes: 0
serveis: multi-user.target · 406 paquetes · escuchando: 0.0.0.0:22 [::]:22
```

La ISO es la 13.1, pero el instalador ya descarga los paquetes del repositorio, así que las máquinas salen directamente en **13.8** sin nada pendiente. Repositorios: `trixie`, `trixie-updates` y `trixie-security`.

Paquetes añadidos: `mdadm` y `drbd-utils` (Tarea 6), `sysstat`, `htop`, `rsync`, `traceroute`, `dnsutils`, `curl` y `vim-tiny`. Ningún servicio más: lo único que escucha es el SSH.

## Usuarios de administración

- `alexsoler`: el que se crea en la instalación, con contraseña y en el grupo `sudo`. Es con el que se administra.
- `root`: **bloqueado** (`passwd -l`). Por SSH solo puede entrar el NAS con su clave, limitada con `from="192.168.36.20"`, para llevarse las copias. Configurado con [linux-01-servidor.sh](../../scripts/linux-01-servidor.sh).

## Red

IP **estática** con `ifupdown` (un servidor tiene que estar siempre en la misma dirección), con [linux-01-servidor.sh](../../scripts/linux-01-servidor.sh):

```
enp0s3   192.168.36.22/24 (serveis) · 192.168.36.23/24 (dades)
ruta     default via 192.168.36.1 dev enp0s3 onlink
DNS      192.168.36.21 (DC), 192.168.36.1 · búsqueda alexsoler.lan
```

Pruebas desde las dos ([red-por-maquina.txt](../../evidencias/tasca4/red-por-maquina.txt)): ping a la puerta, al NAS y al DC, los nombres del dominio se resuelven con el DC (`dc01-alex → 192.168.36.21`, `truenas → 192.168.36.20`) y la descarga HTTP de Internet funciona.

**Lo que más me costó encontrar**: con la tarjeta **virtio**, las descargas desde la LAN se quedaban paradas a los pocos KB (`curl` recibía el `200` y luego nada), aunque el ping, el DNS y el traceroute iban bien y el TrueNAS descargaba sin problemas por la misma red. No era el MTU (con 1400 pasaba igual). Cambié la tarjeta a la **Intel 82540EM**, la misma que el resto de VMs, y la misma descarga tardó 1,7 s. Por eso se colgaba también el instalador. El detalle está en la [Tarea 4](../tarea4-red.md).

El 23/11 pasé toda la LAN de 192.168.30.0/24 a 192.168.36.0/24 ([Tarea 4](../tarea4-red.md)). En serveis y dades fue cambiar `interfaces`, `hosts`, `resolv.conf`, la clave del NAS y la configuración de DRBD, y reiniciar la red: el espejo volvió a `Connected UpToDate/UpToDate` con las IPs nuevas.

## Copias: qué sí y qué no

| Qué | Cómo | Por qué |
|---|---|---|
| `/etc` completo + lista de paquetes (`dpkg --get-selections`) | El NAS se lo lleva cada noche por SSH ([copias-config.sh](../../scripts/copias-config.sh)) | Con eso y los scripts de este repositorio rehago el servidor sobre una VM nueva |
| **No** copio el sistema entero | — | Con los scripts se reinstala en una media hora; una imagen de 10 GB por servidor no compensa |
| **No** copio los datos de los RAID | — | Por ahora son datos de prueba. Con datos reales irían al NAS con `rsync` y snapshots, porque **un RAID no es una copia de seguridad** |
| Si serveis cae | — | Sus datos importantes están en el espejo DRBD con dades ([Tarea 6](../tarea6-raid.md)) |
