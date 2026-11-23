# Tarea 4 · Esquema y red individual

![Esquema de red](../diagramas/red-individual.png)

Fuente editable del esquema: [red-individual.drawio](../diagramas/red-individual.drawio) (se abre con draw.io / diagrams.net). El esquema del grupo, para comparar: [arquitectura-grupo3.png](../diagramas/arquitectura-grupo3.png).

## Montaje en VirtualBox

| En el aula | En mi entorno |
|---|---|
| Red del rack 172.16.222.0/24, IP de WAN que asigna el profesor | **NAT de VirtualBox**: cada router coge 10.0.2.15/24 por DHCP, con puerta 10.0.2.2. El enunciado lo permite ("la WAN pot obtindre la IP per DHCP… millor NAT") |
| Switch del grupo | **Red interna `lan_grupo3`**: solo la ven las VMs conectadas a ella, no sale a la red de casa |
| LAN del grupo 3 (192.168.30.0/24) | **192.168.36.0/24**, la red que me corresponde en la parte individual. Así mi laboratorio no se pisa con el del grupo aunque compartan la red interna |

¿Por qué NAT y no adaptador puente? Con un puente los routers estarían en la red de casa y su DHCP podría repartir IPs a otros dispositivos. Con NAT la LAN queda aislada: lo que sale lo hace a través del router y del NAT del anfitrión.

## Direccionamiento y método de asignación

| Equipo | Interfaz | IP / máscara | Puerta | DNS | Asignación |
|---|---|---|---|---|---|
| MikroTik | ether1 WAN | 10.0.2.15/24 | 10.0.2.2 | 1.1.1.1, 8.8.8.8 | DHCP (NAT) |
| | ether2 LAN | **192.168.36.1/24** | — | — | Estática |
| OPNsense | em0 WAN / em1 LAN | 10.0.2.15/24 / **192.168.36.2/24** | 10.0.2.2 | — | DHCP / estática |
| Debian nftables | enp0s3 WAN / enp0s8 LAN | 10.0.2.15/24 / **192.168.36.3/24** | 10.0.2.2 | — | DHCP / estática |
| TrueNAS | enp0s3 | 192.168.36.20/24 | .1 | .21, .1, 1.1.1.1 | Estática |
| DC01-ALEX | LAN | 192.168.36.21/24 | .1 | 127.0.0.1, .1 | Estática |
| serveis | enp0s3 | 192.168.36.22/24 | .1 | .21, .1 | Estática (`ifupdown`) |
| dades | enp0s3 | 192.168.36.23/24 | .1 | .21, .1 | Estática (`ifupdown`) |
| pve1 / pve2 / pve3 | vmbr0 | 192.168.36.32 / .33 / .34 /24 | .1 | .21, .1 | Estática |
| Máquinas de prueba de Proxmox (borradas) | eth0 | .30 (contenedor) y .40 (VM) | .1 | .1 | Estática, solo durante la prueba de migración |
| PC-ADMIN01 (Windows 11) | Ethernet | 192.168.36.200/24 | .1 | .21, .1 | DHCP |
| pc-informatica (Debian) | enp0s3 | 192.168.36.150/24 | .1 | .21, .1 | DHCP con reserva por MAC |

- **DHCP**: solo el MikroTik, rango .100–.200, entrega puerta .1, DNS .21 (DC) y .1, y el dominio `alexsoler.lan`. Las IPs fijas van por debajo de .100 para que no choquen.
- Al principio había **tres DHCP** en la misma LAN (MikroTik, dnsmasq del Debian y el de OPNsense), y cada uno daba una puerta de enlace distinta. Dejé solo el del MikroTik.
- **Separación**: la LAN solo sale por los routers, que hacen NAT y filtran (bloqueo de telnet y SMB hacia fuera, con registro). Desde fuera no se entra en la LAN salvo el SSH de administración por el router Debian, limitado a la IP del anfitrión (10.0.2.2).
- Los tres routers están en la misma LAN, pero solo el MikroTik es la puerta de enlace. Los otros dos los probé cambiando la puerta de enlace de un cliente (TrueNAS) a .2 o .3.

## Cambio de red: de 192.168.30.0/24 a 192.168.36.0/24

Al principio monté todo en la 192.168.30.0/24, que es la red del grupo. En la parte individual me corresponde la **192.168.36.0/24**, así que el 23/11 cambié todos los equipos sin reinstalar nada, manteniendo el último octeto de cada uno. Lo que hice y lo que salió está en [cambio-red-192.168.36.txt](../evidencias/tasca4/cambio-red-192.168.36.txt). La idea fue no quedarme nunca sin acceso:

1. **Routers primero, con las dos redes a la vez**: el MikroTik y el router Debian tuvieron .30 y .36 en la misma interfaz mientras duró el cambio. El DHCP ya repartía la red nueva.
2. **Cada equipo**, cambiando también lo que dependía de la IP: el script de copias y el NFS del NAS, la configuración de DRBD, los registros DNS del DC (y su zona inversa, y la IP en la que escucha el servidor DNS), la configuración de corosync del clúster Proxmox (y sus certificados), el `config.xml` de OPNsense y el `from="192.168.36.20"` que limita la clave del NAS en cada equipo.
3. **Al final**, quitar la red vieja de los dos routers.

Los puntos delicados:

- **El DC** se cambió con un script ([dc-06-cambio-red.ps1](../scripts/dc-06-cambio-red.ps1)) lanzado con `VBoxManage guestcontrol`, que no depende de la red. El primer intento falló al crear un registro justo después de reiniciar el servicio DNS (error 9607): las zonas aún se estaban cargando. Con una espera de 20 s funcionó.
- **El clúster Proxmox**: con los tres nodos encendidos y con quórum cambié las direcciones de `/etc/pve/corosync.conf` y subí `config_version`. Proxmox lo copia a los tres nodos. Luego cambié la IP de cada nodo y reinicié corosync. A los 45 s: `Quorate: Yes` con los tres nodos en .32, .33 y .34.
- **El W11** renovaba siempre la misma IP vieja: el MikroTik guardaba su concesión. La borré y con `ipconfig /release` + `/renew` recibió la .36.200. Sigue unido al dominio (`nltest /sc_query` → `NERR_Success`).

### Algo que descubrí con el cambio: tarjeta virtio en la red interna

Al repetir las pruebas, en serveis y dades `curl` recibía la cabecera (`200`) de una web y la descarga se quedaba parada a los pocos KB. El TrueNAS, por la misma red y la misma puerta de enlace, descargaba bien. Con MTU 1400 pasaba lo mismo, así que no era el MTU. La diferencia era la **tarjeta de red**: serveis y dades tenían **virtio** y todas las demás la Intel 82540EM. Con la VM apagada, `--nictype1 82540EM`, y la misma descarga tardó **1,7 s**. Esto explica también por qué el instalador de Debian se colgaba descargando por `lan_grupo3` ([08-servidores-linux](tarea5/08-servidores-linux.md)): no era culpa del MikroTik.

## Conectividad comprobada

Lo repetí todo en la red nueva el 23/11 entre las 11:44 y las 11:51. En cada máquina ejecuté lo mismo: interfaces, tabla de rutas, DNS, ping a la puerta de enlace, al NAS y al DC, resolución de nombres, una descarga HTTP de Internet y traceroute a 1.1.1.1. Todo en [red-por-maquina.txt](../evidencias/tasca4/red-por-maquina.txt) (las pruebas de la red anterior se quedan como historia en [red-por-maquina-red-anterior-192.168.30.txt](../evidencias/tasca4/red-por-maquina-red-anterior-192.168.30.txt)).

| Origen | Puerta (.1) | NAS (.20) | DC (.21) | Nombres del dominio | Internet (HTTP) | Traceroute |
|---|---|---|---|---|---|---|
| MikroTik | — | ✔ | ✔ | — | ✔ | 10.0.2.2 → 172.16.222.1 → 172.18.22.1 |
| OPNsense | ✔ | ✔ | ✔ | — | ✔ (`fetch`) | — |
| Router Debian | ✔ | ✔ | ✔ | (usa el DNS de la WAN) | ✔ 0,9 s | .1 → 10.0.2.2 → … |
| TrueNAS | ✔ | — | ✔ | ✔ | ✔ 0,9 s | .1 → 10.0.2.2 → … |
| serveis, dades | ✔ | ✔ | ✔ | ✔ | ✔ 1,7 / 2,6 s | .1 → 10.0.2.2 → * → 172.18.22.1 |
| pve1, pve2, pve3 | ✔ | ✔ | ✔ | ✔ | ✔ 0,1–0,3 s | .1 → 10.0.2.2 → … |
| pc-informatica (Debian) | ✔ | ✔ | ✔ | ✔ | ✔ 0,9 s | .1 → 10.0.2.2 → … |
| DC01-ALEX | ✔ | ✔ | ✔ | ✔ | ✔ 0,9 s | .1 → 10.0.2.2 → * → 172.18.22.1 |
| PC-ADMIN01 (Windows 11) | ✔ | ✔ | ✔ | ✔ | ✔ 1,3 s | .1 → 10.0.2.2 → * → 172.18.22.1 |

Por qué Internet se prueba con HTTP y no con ping: en el portátil de clase, la red del instituto corta el ICMP hacia fuera (un `ping 1.1.1.1` no vuelve ni desde el propio portátil, ver [Tarea 2](tarea2-equipos.md)), pero el tráfico web sí sale.

Cómo leo el traceroute: el primer salto es siempre la puerta de enlace de la LAN (192.168.36.1, el MikroTik); el segundo, 10.0.2.2, es el NAT de VirtualBox, o sea, el anfitrión. A partir de ahí ya es la red del instituto (172.16.222.1 es la del rack, la misma que usamos en clase) y su salida a Internet.

Tabla de rutas típica (pve1):

```
default via 192.168.36.1 dev vmbr0 proto kernel onlink
192.168.36.0/24 dev vmbr0 proto kernel scope link src 192.168.36.32
```

Y la del MikroTik, que es el que une las dos redes:

```
DAd  0.0.0.0/0        10.0.2.2       (ruta por defecto aprendida por DHCP en ether1)
DAc  10.0.2.0/24      ether1
DAc  192.168.36.0/24  ether2
```

Los clientes del dominio también resuelven `alexsoler.lan` y el registro SRV del DC y se unen al dominio ([Tarea 5 · clientes](tarea5/09-clientes.md)).

## Recursos simultáneos

La tabla de máquinas con vCPU, RAM, disco y host está en la [Tarea 0](tarea0-entorno.md). El cálculo de cuántas caben a la vez, en la [Tarea 7](tarea7-rendimiento.md): con 16 GB (PC de casa) no puedo tener todo encendido, así que trabajo por bloques y dejo unos 3 GB para el anfitrión; en el portátil de clase (32 GB) caben más a la vez.
