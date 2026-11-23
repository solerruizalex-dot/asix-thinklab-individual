# Proxmox VE · clúster de tres nodos

## Instalación, versión y actualización

- Imagen `proxmox-ve_9.2-1.iso`, **SHA-256 verificado** (coincide con la web de Proxmox).
- Tres VMs de VirtualBox (pve1, pve2, pve3) con 2 vCPU, disco de 20 GB y **virtualización anidada activada** (`nested-hw-virt on`), si no, no podrían arrancar VMs dentro.
- RAM: pve1 y pve2 con 2 GB, pve3 con 2,5 GB (es el que lleva la VM con más discos).
- Antes de usarlos los actualicé ([pve-01-nodo.sh](../../scripts/pve-01-nodo.sh)):

| | Antes | Después |
|---|---|---|
| pve-manager | 9.2.2 | **9.2.32** |
| Kernel | 7.0.2-6-pve | **7.0.14-30-pve** (reinicié los nodos uno a uno) |
| Repositorio | *enterprise* (error 401 sin suscripción) | `pve-no-subscription` |

## Usuarios de administración

- `root@pam`: solo para lo que lo exige (unirse al clúster, consola).
- `alexsoler@pve`: mi cuenta, en el grupo `administradores` con el rol *Administrator* sobre `/`. Al estar en `/etc/pve` vale para los tres nodos ([pve-02-cluster.sh](../../scripts/pve-02-cluster.sh)).

## Red

| Nodo | Interfaz | IP | Puerta | Puente |
|---|---|---|---|---|
| pve1 | vmbr0 (sobre la tarjeta de `lan_grupo3`) | 192.168.30.32/24 | 192.168.30.1 | vmbr0 |
| pve2 | vmbr0 | 192.168.30.33/24 | 192.168.30.1 | vmbr0 |
| pve3 | vmbr0 | 192.168.30.34/24 | 192.168.30.1 | vmbr0 |

Las VMs y contenedores se conectan a `vmbr0`, así que están en la misma LAN que el resto (192.168.30.0/24).

**Problema importante**: las VMs creadas dentro de Proxmox hacían ping a su nodo pero no al MikroTik ni al router Debian. La causa: VirtualBox, en una red interna, solo entrega a la tarjeta las tramas dirigidas a **su** MAC, y las VMs anidadas tienen MAC propias (`BC:24:11:…`). Hay que poner la tarjeta de cada nodo en modo promiscuo:

```
VBoxManage modifyvm clusterProxMox-pveN-AlexSoler --nicpromisc1 allow-all
```

Por culpa de esto, el primer arranque de cloud-init de serveis no pudo instalar paquetes; lo completé después a mano.

## Clúster

- `grupo3-cluster`, transporte *knet*, un voto por nodo: **quórum = 2 de 3**.
- `pvecm status` → `Nodes: 3`, `Quorate: Yes`.
- Lo comprobé sin querer: con solo pve1 encendido no hay quórum, `/etc/pve` queda en solo lectura y la actualización se quedó parada en `systemctl reload-or-restart pvescheduler`. En cuanto arrancó pve2 (2 votos) siguió sola.
- **Gestión conjunta, migración y alta disponibilidad no son lo mismo**: el clúster me deja administrar los tres nodos desde cualquiera y mover máquinas entre ellos; la alta disponibilidad (HA) además las rearrancaría solas en otro nodo si uno cae, pero para eso los discos tienen que estar en almacenamiento compartido. No la he activado: con discos locales no podría funcionar.

## Almacenamiento

| Nombre | Tipo | Qué guarda |
|---|---|---|
| `local` | directorio (8,9 GB) | ISOs locales, nada importante |
| `local-lvm` | LVM-thin (6,78 GB por nodo) | discos de las VMs y contenedores |
| `truenas-nfs` | NFS 4.2 en 192.168.30.20:/mnt/copias/proxmox (58 GB) | copias `vzdump`, plantillas, imagen de Debian, *snippets* de cloud-init y los 7 discos de RAID de dades |

## Máquinas dentro del clúster

| ID | Nombre | Tipo | Dónde está | Recursos | IP |
|---|---|---|---|---|---|
| 122 | serveis | VM Debian 13 sin entorno gráfico | pve1 (migrada desde pve2) | 1 vCPU, 384 MB, 6 GB + 1 GB (DRBD) | 192.168.30.22 |
| 123 | dades | VM Debian 13 sin entorno gráfico | pve3 | 1 vCPU, 384 MB, 6 GB + 7 × 1 GB (RAID) + 1 GB (DRBD) | 192.168.30.23 |
| 130 | web-pruebas | contenedor LXC Debian 13 | pve2 (migrado desde pve1) | 1 vCPU, 256 MB, 2 GB | 192.168.30.30 |

Detalle de serveis y dades en [08-servidores-linux](08-servidores-linux.md).

## Migraciones (medidas)

Evidencia completa: [proxmox-migraciones.txt](../../evidencias/tasca5/proxmox-migraciones.txt). Durante cada prueba tenía un `ping` cada 0,5 s desde el router Debian.

| Prueba | Tipo | Datos copiados | Tiempo | Corte de servicio | Resultado |
|---|---|---|---|---|---|
| CT 130 pve1 → pve2 | *restart* (los contenedores no migran en vivo) | volumen entero: **2,0 GiB** (usaba ~660 MB) a ~160 MB/s | **24 s** | ~21 s (42 de 236 pings perdidos) | Correcta |
| VM 122 pve2 → pve1 | **en vivo** con discos locales | iba copiando 6 GiB + 1 GiB | 1 min 40 s | 0 pings perdidos | **Falló y se canceló sola**: llenó el thin pool de pve1 |
| VM 122 pve2 → pve1 | **en frío** | 6 GiB + 1 GiB a ~200 MB/s | **44 s** + 5 s de apagado | 70 s desde que empecé a apagarla hasta que respondió SSH | Correcta |

### Cómo lo interpreto

- **Se copia el disco entero, no lo que está ocupado.** Con discos en `local-lvm`, Proxmox tiene que mandar el volumen completo al otro nodo: 2 GiB del contenedor cuando solo usaba 660 MB, y 7 GiB de la VM.
- **La migración en vivo no respeta los huecos en LVM-thin.** Copia con *drive-mirror* y escribe también los ceros en el destino. 7 GiB no caben en un thin pool de 6,78 GiB, así que se llenó (`Thin pool pve-data-tpool data is now 100.00% full`) y Proxmox canceló la migración. Lo bueno: la VM siguió funcionando en el origen sin perder ni un ping.
- **La migración en frío sí respeta los huecos.** En destino el disco de 6 GiB ocupa un 25 % y el de DRBD un 5 %.
- El espacio es el recurso que manda: con discos locales, para migrar hace falta en el destino tanto espacio libre como el disco de la VM.

### Mejoras que haría

1. **Discos en almacenamiento compartido** (NFS de TrueNAS o Ceph). La migración solo movería la RAM (384 MB): sería en vivo, de segundos y sin corte. Es también el requisito para la alta disponibilidad. El precio es que todo depende del NAS y de la red.
2. **Red de migración separada** y más rápida que la LAN de usuarios.
3. **No sobreasignar el thin pool**, o vigilarlo con una alerta del 80 %: me pasó dos veces esta noche (también con dades, ver [Tarea 6](../tarea6-raid.md)).

## Copias de configuración e imágenes

| Qué | Dónde | Cómo | Por qué |
|---|---|---|---|
| Imágenes de VMs y contenedores (`vzdump`) | `truenas-nfs` | Tarea del clúster `copia-diaria`, todos los días a las 22:00, modo *snapshot* (sin parar las máquinas), zstd, se guardan 3 | Restaurar una máquina entera en minutos |
| `/etc/pve`, `/etc/network/interfaces`, corosync, `config.db` de cada nodo | `copias/configs` del NAS | El NAS se lo lleva por SSH cada noche ([copias-config.sh](../../scripts/copias-config.sh)) | Con eso se reconstruye un nodo: instalar Proxmox y volver a ponerlo |
| **No** copio el sistema de los nodos | — | — | Proxmox se reinstala desde la ISO en unos 10 minutos (estimado); lo que vale es la configuración y las VMs |

Copia manual de prueba ([proxmox-copias-vzdump.txt](../../evidencias/tasca5/proxmox-copias-vzdump.txt)):

| Máquina | Datos leídos | Fichero en el NAS | Tiempo |
|---|---|---|---|
| CT 130 | 558 MiB | **159 MB** (`.tar.zst`) | 14 s |
| VM 122 (encendida) | 7 GiB, de los que 5,5 GiB eran ceros (78 %) | **747 MB** (`.vma.zst`) | 22 s |

Aquí vzdump sí se salta los ceros: por eso la copia de la VM ocupa 747 MB y no 7 GB.
