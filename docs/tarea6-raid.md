# Tarea 6 · RAID y espejo entre dos equipos

Todo con discos virtuales y datos ficticios, en las VMs `dades` y `serveis`, que son **VMs independientes de VirtualBox** (ver [08-servidores-linux](tarea5/08-servidores-linux.md)). Hice estas pruebas dos veces: la primera, la noche del 22 al 23, con las dos máquinas dentro del clúster Proxmox, y se me llenó el disco de los nodos (lo cuento al final). Lo que hay aquí es la segunda, del 23/11, con las máquinas ya en VirtualBox.

## 1. Qué aporta cada RAID

| RAID | Discos mín. | Capacidad útil | Aguanta | Lectura | Escritura | Para qué lo usaría |
|---|---|---|---|---|---|---|
| **0** (reparto) | 2 | 100 % | **0 discos** | Rápida | Rápida | Datos temporales o fáciles de regenerar (caché, renders) |
| **1** (espejo) | 2 | 50 % | 1 disco | Rápida | Como un disco (escribe en los dos) | Sistema operativo y datos importantes pequeños |
| **5** (paridad repartida) | 3 | (n−1)/n | 1 disco | Rápida | Más lenta (calcula paridad) | Carpetas compartidas: buen equilibrio entre espacio y seguridad |

Un RAID **no es una copia de seguridad**: si borro un fichero o entra un ransomware, el cambio se aplica a todos los discos a la vez. Por eso las copias van aparte, al NAS.

## 2. Los tres RAID en dades (mdadm)

dades tiene un disco de sistema (puerto SATA 0) y 8 discos de 1 GB en los puertos 1 a 8. Con [dades-raid.sh](../scripts/dades-raid.sh):

```
md0  RAID 0  puertos 1 + 2        (sdb + sdc)        → 2,0 GB   /srv/md0
md1  RAID 1  puertos 3 + 4        (sdi + sdd)        → 1,0 GB   /srv/md1
md5  RAID 5  puertos 5 + 6 + 7    (sde + sdf + sdg)  → 2,0 GB   /srv/md5
puerto 8 (sdh): libre para el espejo DRBD del apartado 3
```

Los tamaños confirman la teoría: RAID 0 suma los dos discos, RAID 1 se queda con uno y RAID 5 con tres discos da dos de espacio útil. Los arrays quedan en `/etc/mdadm/mdadm.conf` (por UUID) y en `/etc/fstab` (por etiqueta); **reinicié dades y se montaron solos**. Salida completa: [raid-creacion.txt](../evidencias/tasca6/raid-creacion.txt).

Dos cosas que me encontré al crearlos:

- **El disco del puerto 3 arrancó como `sdi` y no como `sdd`.** Linux pone los nombres según el orden en que detecta los discos, no según el puerto. Si hubiera escrito `sdb sdc sdd…` a mano, habría metido en el RAID 1 un disco que no tocaba. Por eso el script elige los discos por su ruta física (`/dev/disk/by-path/…-ata-N`, controlador + puerto).
- La primera vez guardé `mdadm.conf` mientras el RAID 5 aún se estaba sincronizando, y quedó apuntado con `spares=1`. Lo regeneré con el array ya sincronizado y el script ahora espera a que termine.

### Pruebas de fallo quitando el disco de verdad

En lugar de marcar un disco como fallado con `mdadm --fail` (que es una simulación), **arranqué el disco virtual con la máquina encendida**, como quien saca un disco de una bahía. En VirtualBox los puertos SATA se pueden marcar como extraíbles en caliente (`--hotpluggable on`, con la VM apagada) y desde el anfitrión se quita el disco con `VBoxManage storageattach … --medium none`. Después puse en el mismo puerto un **disco nuevo y vacío**, como haría con un disco de repuesto.

Script: [dades-raid-fallo-real.sh](../scripts/dades-raid-fallo-real.sh) · salida completa: [raid-pruebas-fallo.txt](../evidencias/tasca6/raid-pruebas-fallo.txt). Antes de empezar escribí 100 MB aleatorios en cada array y guardé su SHA-256.

| | RAID 0 (md0) | RAID 1 (md1) | RAID 5 (md5) |
|---|---|---|---|
| Disco arrancado | puerto 2 | puerto 4 | puerto 6 |
| Justo después | — | Sigue en `[UU]`: mdadm aún no se ha enterado | Sigue en `[UUU]` |
| Al escribir en el array | `State : broken, FAILED`, *Buffer I/O error* y el sistema de ficheros aborta el diario | `clean, degraded`, `[U_]`, 1 disco fallado | `clean, degraded`, `[U_U]` |
| ¿Se leen los datos con un disco menos? | **No**: *FAILED open or read* → **datos perdidos** | **Sí**, SHA-256 OK | **Sí**, SHA-256 OK |
| Disco nuevo y vacío en el mismo puerto | — (no hay de dónde reconstruir) | Reconstruido en **6 s** → `[UU]` | Reconstruido en **7 s** → `[UUU]` |
| Datos al final | Solo al volver a poner el disco **original**: `e2fsck` reparó el diario y SHA-256 OK | SHA-256 OK | SHA-256 OK |

Los números de serie del final confirman que en los puertos 4 y 6 hay discos distintos de los del principio (`VBc579a959…` y `VBbc362347…`).

**Cambiar un disco en caliente en Linux tiene su procedimiento**, y lo aprendí porque el primer intento me salió mal:

1. Al desaparecer el disco, mdadm **no lo marca como fallado hasta que intenta escribir en él**. Un servidor con poco movimiento podría estar horas degradado sin avisar: por eso el aviso por correo de `mdadm` (o una comprobación periódica) es importante.
2. Hay que sacar el disco del array (`mdadm --fail` + `--remove`) y que **el kernel lo olvide** (`echo 1 > /sys/block/sdX/device/delete`). En el primer intento no lo hice: al llegar el disco nuevo al mismo puerto, el kernel esperaba el número de serie del viejo (*serial number mismatch*), la revalidación falló y el disco nuevo no apareció.
3. Con el disco nuevo puesto, se vuelve a escanear el controlador (`echo '- - -' > /sys/class/scsi_host/hostN/scan`) y se añade al array con `mdadm --add`.

### Velocidad

`dd` de 200 MB saltándose la caché de la VM (`oflag=direct` / `iflag=direct`):

| | Disco simple | RAID 0 | RAID 1 | RAID 5 |
|---|---|---|---|---|
| Escritura | 3,1 GB/s | 3,0 GB/s | 2,9 GB/s | **1,1 GB/s** |
| Lectura | — | 7,0 GB/s | 8,2 GB/s | 2,9 GB/s |

Estas cifras **no son velocidades reales de disco**: mi SSD USB da unos 400 MB/s ([Tarea 2](tarea2-equipos.md)). Los discos de las VMs tienen activada la caché de E/S del anfitrión, así que lo que mido es sobre todo la RAM del portátil. Además, los ocho discos virtuales son ficheros del mismo SSD, así que un RAID 0 no puede repartir el trabajo entre discos físicos distintos. Lo que sí se ve, porque es trabajo de CPU, es que **el RAID 5 escribe a un tercio**: por cada escritura calcula la paridad y, si no escribe la franja entera, tiene que leer antes para recalcularla.

### Lo que saco de las pruebas

- La reconstrucción tardó segundos porque los discos son de 1 GB. Con discos de 4 TB serían horas, y durante ese tiempo un RAID 5 no aguanta otro fallo: por eso con discos grandes se usa RAID 6 o RAID 10.
- mdadm reconoce cada disco por su **superbloque**, no por el nombre: después de reiniciar y de cambiar discos, los nombres `sdX` ya no siguen el orden de los puertos y los arrays siguen bien.
- RAID 0 solo para lo que me da igual perder: con quitar un disco de dos se pierde todo.

## 3. Espejo entre discos de dos equipos distintos

### Opciones que estudié

Un RAID 1 normal protege de que se rompa un **disco**, pero no de que se caiga el **equipo** entero (fuente de alimentación, placa, el nodo de Proxmox…). Para eso el espejo tiene que hacerse por red:

| Opción | Cómo funciona | A favor | En contra |
|---|---|---|---|
| **DRBD** | Replica un dispositivo de bloques por red. Uno es primario (lee y escribe) y el otro secundario (recibe cada escritura) | Es literalmente un RAID 1 por red; síncrono; está en el kernel de Debian | Solo un nodo usa los datos a la vez; el cambio de primario es manual (o con Pacemaker) |
| GlusterFS réplica 2 | Sistema de ficheros distribuido entre servidores | Los dos nodos sirven ficheros | Con 2 nodos hay riesgo de *split-brain*; necesita un árbitro |
| Ceph | Almacenamiento distribuido integrado en Proxmox | Alta disponibilidad real | Mínimo 3 nodos y mucha RAM por disco: no cabe en mi entorno |
| ZFS replication | Envía snapshots cada X minutos | Muy fácil en Proxmox | No es un espejo: se pueden perder los últimos minutos |

**Elegí DRBD**: es lo que pide el enunciado (un espejo entre dos discos de dos equipos), gasta muy poca RAM y se ve muy claro qué pasa en cada momento.

### Montaje

- `serveis`: disco de 1 GB del puerto SATA 1 · `dades`: disco de 1 GB del puerto SATA 8. Cada uno es un disco de **una VM distinta**: si cae una máquina entera, el otro disco sigue vivo.
- Protocolo **C** (síncrono): una escritura no se da por terminada hasta que está en los dos discos.
- Configuración [drbd-espejo.sh](../scripts/drbd-espejo.sh): recurso `espejo`, `/dev/drbd0`, puerto 7789. Los discos van por su ruta física (`/dev/disk/by-path/…-ata-N`) porque los nombres `sdX` cambian de orden (ver el apartado 2). Esa ruta tiene `:` y **hay que ponerla entre comillas**: la primera vez `drbdadm` dio *Parse error: ';' expected* y no creó el recurso.
- Versión: módulo DRBD 8.4.11 del kernel de Debian con `drbd-utils` 9.22.

### Caso de uso

La **carpeta compartida de la empresa** (`/srv/compartida`, con una carpeta por departamento y sus permisos). Si se cae el servidor donde está, no quiero esperar a restaurar la copia de la noche anterior (perdería el trabajo del día): quiero levantar la carpeta en el otro servidor con los datos al día.

### Prueba ([drbd-prueba-fallo.sh](../scripts/drbd-prueba-fallo.sh), salida en [drbd-espejo.txt](../evidencias/tasca6/drbd-espejo.txt))

La hice dos veces: a las 11:07, con la LAN todavía en 192.168.30.0/24, y a las 11:52, después de pasar todo a 192.168.36.0/24 (ver [Tarea 4](tarea4-red.md)). Los resultados son iguales; la tabla es la segunda.

| Hora | Paso | Resultado |
|---|---|---|
| 11:52:50 | serveis pasa a primario | `Connected Primary/Secondary UpToDate/UpToDate`. La sincronización inicial de 1 GB la medí la primera vez: **53,5 s** |
| 11:52:51 | En serveis creo `/srv/compartida` con una carpeta por departamento (Comercial con permisos 750) y un fichero de 50 MB; guardo los SHA-256 | |
| 11:52:52 | Intento montar el disco en dades | No deja: *Can't open blockdev*. El secundario solo recibe |
| 11:52:53 | **Fallo**: `VBoxManage controlvm serveis-AlexSoler poweroff` (como quitar la corriente) | |
| 11:52:54 | En dades: `drbdadm primary` + `mount` + comprobar | **4 de 4 ficheros con SHA-256 OK**. Comercial sigue siendo `drwxr-x--- root`: un usuario sin permisos recibe *Permiso denegado* |
| 11:52:56 | Se sigue trabajando en dades: creo `durante-la-caida.txt` | dades queda `WFConnection Primary/Unknown` (esperando al otro) |
| 11:52:56 | Vuelvo a encender serveis | Arranca, pero DRBD no se levanta solo (`drbd.service` deshabilitado) |
| 11:53:15 | Lo levanto a mano (`drbdadm up espejo`) | Resincroniza **108 MB en 18,4 s** (la primera vez, 96 MB en 18,5 s) |
| 11:53:33 | Vuelta a la normalidad: dades suelta el recurso, serveis vuelve a ser primario | serveis tiene el fichero creado durante la caída |

**Desde el fallo hasta tener los datos comprobados en el otro equipo: 2,7 s, sin perder nada** (protocolo síncrono). Hay que leer bien esa cifra: los pasos los da mi script en cuanto serveis cae. En la realidad alguien tiene que darse cuenta de la caída y ejecutar los dos comandos, así que lo que cuenta es el tiempo de reacción de la persona; lo que demuestra la prueba es que los datos están completos y al día en dades.

Cosas que vi y que no esperaba:

- Al volver, serveis no copia el disco entero, sino lo que su registro de actividad (*activity log*) marca como posiblemente cambiado: *Marked additional 108 MB as out-of-sync based on AL* (96 MB la primera vez). Como se cayó siendo primario, DRBD no se fía de las últimas zonas en las que escribía y las vuelve a copiar.
- `drbd.service` viene deshabilitado: el nodo que vuelve **no se conecta solo**. Lo dejo así a propósito: si los dos arrancaran solos como primarios, tendría un *split-brain* (dos versiones distintas de los datos). Prefiero que volver a conectar sea un paso consciente del procedimiento.
- El cambio de primario es manual. Para hacerlo automático haría falta un gestor de clúster (Pacemaker/Corosync) y un tercer voto para evitar el *split-brain*.

## 4. La primera vez, dentro de Proxmox (historia)

La noche del 22 al 23 hice todo esto con serveis y dades como VMs **dentro del clúster Proxmox** (cada una en un nodo). Los RAID y el espejo funcionaron, pero en mitad de las pruebas dades se quedó en `io-error`: el almacenamiento `local-lvm` del nodo es *thin* (6,78 GB reales) y yo le había asignado 6 GB + 8 × 1 GB. Las reconstrucciones de RAID y la sincronización de DRBD escriben los discos enteros y lo llenaron (`switching pool to out-of-data-space (error IO) mode`). Lo salvé moviendo los discos de RAID al NFS de TrueNAS, sin perder datos ([incidencia-thin-pool.txt](../evidencias/tasca6/incidencia-thin-pool.txt)).

Eso, sumado a que los nodos tienen 2 GB de RAM, es lo que me hizo sacar serveis y dades a VMs independientes de VirtualBox y repetir aquí las pruebas. Esta vez, además, los fallos de disco son **reales** (quitando el disco con la máquina encendida) y no simulados con `mdadm --fail`, como hice aquella noche.
