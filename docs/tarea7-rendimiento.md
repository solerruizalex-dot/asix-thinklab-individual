# Tarea 7 · Rendimiento del equipo físico y optimizaciones

## Cómo he medido

- **Anfitrión**: un script propio, [medir-anfitrion.py](../scripts/medir-anfitrion.py), que lee `/proc` cada 5 s (en este equipo no tengo `sysstat` ni permisos para instalarlo) y saca lo mismo que `vmstat` + `iostat`: CPU (usuario, sistema, espera de disco, libre), RAM usada y disponible, swap, MB/s leídos y escritos en el SSD USB (`sdb`), **% de tiempo que el disco está ocupado** (como el `%util` de iostat) y tráfico de red. Al final, media y máximo.
- **Dentro de las VMs**: `dd`, `curl` (velocidad de descarga), `free`, `/proc/mdstat`, `/system resource` en el MikroTik, `top` en OPNsense, y en Windows `Get-Process` y el Visor de eventos.
- **Carga de prueba**: [carga-vm.sh](../scripts/carga-vm.sh), que pone una VM al 100 % de CPU, escribe 3 × 300 MB en disco y descarga 100 MB, todo a la vez.

Todas las salidas están en [evidencias/tasca7](../evidencias/tasca7/).

## Recursos del equipo y lo que piden las VMs

| | Disponible en el anfitrión | Pedido por las VMs al principio | Asignado ahora |
|---|---|---|---|
| RAM | 15,5 GiB | **36 GB** (DC 8, TrueNAS 8, MikroTik 4, OPNsense 4, Debian 2, Proxmox 3 × 2, Windows 11 4) | 22,3 GB en total, pero **nunca todo a la vez** |
| CPU | 6 núcleos / 12 hilos | 2 vCPU por VM | Igual |
| Disco | SSD SATA por **USB 3.0** (JMS578) | ~300 GB en discos dinámicos | Igual |

## Medidas por bloques de trabajo

| Bloque | VMs encendidas | RAM usada en el anfitrión | CPU libre (media) | Disco USB ocupado (media / máx.) | Observaciones |
|---|---|---|---|---|---|
| **Línea base: ninguna VM** | — | **2,9 GB** (13 GB disponibles) | 98,5 % | 0,4 % / 1 % | Lo que gasta el escritorio solo ([linea-base-sin-vms.txt](../evidencias/tasca7/linea-base-sin-vms.txt)) |
| Virtualización, en reposo | MikroTik, Debian, TrueNAS, pve1-3 (+ serveis, dades y un contenedor dentro) | **13,4 GB** (2,5 GB disponibles) | 91,8 % | 5 % / 21 % | Estable |
| Virtualización, **con carga** (serveis y dades al 100 % de CPU + escritura + descarga) | Igual | 13,4 GB | 81,0 % | 14 % / **81 %** | Picos de **124 MB/s de escritura**; carga media del sistema 1,8–2,3 |
| Dominio, en reposo | MikroTik, Debian, TrueNAS, DC | 10,9 GB | 90,2 % | 16 % / 46 % | El DC acababa de arrancar (picos de lectura de 88 MB/s) |
| Dominio, copia del DC (primer intento, en la fase de enumerar ficheros) | Igual | 10,9 GB | 90,4 % | 13 % / 57 % | El disco no se satura. Ese intento lo cancelé a las 01:47; el bueno (01:48–02:29) se comportó igual en esa fase: wbengine sin E/S y Defender con más CPU que él ([dc-copia-diagnostico-lentitud.txt](../evidencias/tasca5/dc-copia-diagnostico-lentitud.txt)) |
| Dominio + cliente: Windows 11 instalando la acumulativa | MikroTik, Debian, DC, Windows 11 | 12,8 GB (3 GB disponibles) | 79,6 % | 28 % / 49 % | Carga del sistema 2,8: la instalación de parches es la tarea más pesada del bloque |
| Comunicaciones (descarga por cada router) | MikroTik, OPNsense, Debian, TrueNAS y también el DC | 13,3 GB | máx. 83–85 % (solo guardé el máximo de cada ventana de 15 s) | máx. 32–37 % | La red llega a 178 Mb/s en el anfitrión |

Ficheros: [bloque-virtualizacion.txt](../evidencias/tasca7/bloque-virtualizacion.txt), [bloque-dominio.txt](../evidencias/tasca7/bloque-dominio.txt), [bloque-comunicaciones.txt](../evidencias/tasca7/bloque-comunicaciones.txt).

## Qué satura cada máquina

| VM | Recurso que más gasta | Dato |
|---|---|---|
| Windows Server (DC) | **RAM** (4 GB) y CPU por Defender | En la copia, MsMpEng gasta más CPU que el propio wbengine |
| Windows 11 | **RAM** (4 GB, el mínimo que pide) | No cabe a la vez que el DC y el bloque Proxmox |
| Nodos Proxmox | **RAM** y **espacio en disco** | Recién arrancado y sin VMs, pve2 usa 1,5 GB de 2 GB ([proxmox-ram-nodos.txt](../evidencias/tasca7/proxmox-ram-nodos.txt)); el thin pool de 6,8 GB se llenó dos veces |
| VMs dentro de Proxmox | **Disco** (escrituras) | Con carga, el SSD USB llega al 81 % de ocupación |
| TrueNAS | RAM (ZFS) | Funciona con 2,5 GB porque solo recibe copias |
| Routers | **Red** (la tarjeta emulada) | Ver la optimización 3: el MikroTik limitaba a toda la LAN |

## Límite real: el día que se colgó el PC

El 22/11 a las 23:06 el equipo se **congeló por completo** y tuve que reiniciarlo. Estaban encendidos el MikroTik, el router Debian, TrueNAS (4 GB), el DC haciendo la copia del estado del sistema, y acababa de arrancar pve1 con una actualización. El registro del sistema (`journalctl -b -1`) se corta a las 23:06:36 **sin ningún error**: 0 líneas de falta de memoria, errores de E/S, reinicios del USB o bloqueos de tareas ([cuelgue-22nov-registro.txt](../evidencias/tasca7/cuelgue-22nov-registro.txt)).

Mi **hipótesis** es que se atascó el puente USB del disco con varias VMs escribiendo a la vez, más que la RAM. La memoria iba justa (11,3 GB asignados más los 2,9 GB del escritorio, de 15,5), pero el kernel no registró ninguna falta de memoria y tenía 8 GB de swap disponibles. No lo puedo demostrar, porque un cuelgue así no deja rastro. Lo que sí hice fue no repetir esa combinación: desde entonces, con hasta 9 máquinas encendidas pero una sola escribiendo mucho, el equipo no ha vuelto a bloquearse.

## Cuántas VMs puedo usar sin bloquear el equipo

| Situación | Resultado |
|---|---|
| 6 VMs de VirtualBox (MikroTik 0,25 + Debian 1 + TrueNAS 2,5 + pve1 2 + pve2 2 + pve3 2,5 = **10,25 GB asignados**) + 3 VMs/contenedores anidados dentro, con carga | **Funciona**: el anfitrión usa 13,4 GB y quedan 2,4 GB; el disco con picos del 81 % |
| DC (4 GB, copiando) + TrueNAS (4 GB) + MikroTik + Debian + pve1 (2 GB) arrancando y actualizándose: ~11,3 GB asignados y **dos máquinas escribiendo mucho** | **Se colgó** |
| DC + Windows 11 + bloque Proxmox | No lo intento: pasaría de 16 GB |

**Conclusión:** en este PC puedo trabajar con **5–6 VMs a la vez** siempre que:

1. La RAM asignada sumada no pase de **unos 10–11 GB**. La cuenta sale de las medidas: el escritorio solo ya usa 2,9 GB (línea base), y con 10,25 GB asignados el anfitrión llega a 13,4 GB de 15,5 (VirtualBox añade su propio consumo).
2. **Solo una** de ellas haga escrituras pesadas a la vez (copias, actualizaciones, migraciones).

Por eso trabajo por bloques: comunicaciones, dominio y virtualización. En el portátil de clase (32 GB de RAM, ver Tarea 2) la RAM deja de ser el límite, pero el disco es el mismo SSD por USB, así que la regla 2 se mantiene.

## Optimizaciones aplicadas (antes y después)

### 1. Router Debian sin entorno gráfico

Tenía GNOME instalado y arrancaba en modo gráfico para no usarlo nunca.

```
systemctl set-default multi-user.target      y RAM de la VM de 2 GB a 1 GB
```

| | Antes | Después |
|---|---|---|
| RAM usada dentro de la VM | 646 MB | **301 MB** |
| Servicios en marcha | 33 | **20** |
| RAM reservada en el anfitrión | 2 GB | **1 GB** |

### 2. RAM ajustada a lo que se usa

| VM | Antes | Después | Comprobación |
|---|---|---|---|
| MikroTik | 4 GB | **256 MB** | Con 4 GB, RouterOS tenía 3.746 MB libres (usaba ~350 MB); con 256 MB le quedan 46–53 MB libres y enruta igual. En RAM **usada** del anfitrión casi no cambia (proceso de VirtualBox de 159 a 135 MiB): lo que se gana es la RAM **reservada**, que VirtualBox puede llegar a ocupar |
| OPNsense | 4 GB | **2 GB** | Sin plugins; en reposo 1,4 GB libres |
| TrueNAS | 8 GB → 4 GB (22/11) | **2,5 GB** | Ve 2.477 MiB; recibe las copias, se actualizó y sirve NFS/SMB sin problemas ([truenas-actualizacion.txt](../evidencias/tasca5/truenas-actualizacion.txt)) |
| DC | 8 GB | **4 GB** | Funciona; es el mínimo razonable con escritorio |

Total para el bloque de comunicaciones: de 18 GB a 5,8 GB. Evidencias: [optimizaciones-ram-antes-despues.txt](../evidencias/tasca7/optimizaciones-ram-antes-despues.txt) (salidas originales del antes y el después) y [ram-asignada-antes-despues.txt](../evidencias/tasca7/ram-asignada-antes-despues.txt). Esto es lo que me permite tener el bloque de virtualización entero encendido (13,4 GB usados) sin que el equipo se bloquee.

### 3. Tarjeta de red del MikroTik (la que más se nota)

Midiendo la red vi algo raro: el anfitrión descargaba a 37 MB/s, pero cualquier VM que saliera por el MikroTik iba a 1,4–4 MB/s. Fui descartando por partes:

| Prueba (descarga de 100 MB) | Velocidad |
|---|---|
| Anfitrión, sin VMs de por medio | 37,5 MB/s |
| Router Debian (sale por su propio NAT) | ~35 MB/s (100 MiB en 3,0 s) |
| TrueNAS **por el router Debian** | 36,3 MB/s |
| TrueNAS **por el MikroTik** | **1,4 MB/s** |
| serveis (anidada) por el MikroTik | 4,0 MB/s |

El problema no era la virtualización anidada, ni la CPU del MikroTik (7 %): era el MikroTik. Sus dos tarjetas eran **AMD PCnet-FAST III (Am79C973)**, una tarjeta antigua de 100 Mbit/s cuya emulación es muy costosa; el resto de VMs tenían Intel PRO/1000.

```
VBoxManage modifyvm Mikrotik-AlexSoler --nictype1 82540EM --nictype2 82540EM
```

Antes guardé un backup del router. Las interfaces mantienen nombre y MAC, así que la configuración no cambió.

| Descarga de 100 MB | Antes | Después | Mejora |
|---|---|---|---|
| TrueNAS por el MikroTik | 1,4 MB/s | **17,7–22,7 MB/s** | ×12–16 |
| serveis por el MikroTik | 4,0 MB/s | **35,8 MB/s** | ×9 |

Evidencia: [optimizacion-nic-mikrotik.txt](../evidencias/tasca7/optimizacion-nic-mikrotik.txt). Con la tarjeta corregida, los tres routers quedan parecidos: OPNsense 38,5 MB/s, Debian 36,2 MB/s y MikroTik 22,7 MB/s.

## Mejoras que no he podido aplicar

- **Mover las VMs a un disco interno.** El PC de casa tiene un SSD SATA interno (otro Kingston SA400), pero es el disco de casa, no el del proyecto. Sería la mejora más grande para el disco.
- **Discos de Proxmox en almacenamiento compartido**: las migraciones solo moverían la RAM (ver [Tarea 5 · Proxmox](tarea5/06-proxmox.md)).
- **Exclusión de Defender para la copia del DC**: es una decisión de seguridad, la dejo propuesta.
