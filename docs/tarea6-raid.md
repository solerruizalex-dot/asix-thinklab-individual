# Tarea 6 · RAID y espejo entre dos equipos

Todo con discos virtuales y datos ficticios, en las VMs `dades` (pve3) y `serveis` (pve1) del clúster Proxmox.

## 1. Qué aporta cada RAID

| RAID | Discos mín. | Capacidad útil | Aguanta | Lectura | Escritura | Para qué lo usaría |
|---|---|---|---|---|---|---|
| **0** (reparto) | 2 | 100 % | **0 discos** | Rápida | Rápida | Datos temporales o fáciles de regenerar (caché, renders) |
| **1** (espejo) | 2 | 50 % | 1 disco | Rápida | Como un disco (escribe en los dos) | Sistema operativo y datos importantes pequeños |
| **5** (paridad repartida) | 3 | (n−1)/n | 1 disco | Rápida | Más lenta (calcula paridad) | Carpetas compartidas: buen equilibrio entre espacio y seguridad |

Un RAID **no es una copia de seguridad**: si borro un fichero o entra un ransomware, el cambio se aplica a todos los discos a la vez. Por eso las copias van aparte, al NAS.

## 2. Los tres RAID en dades (mdadm)

dades tiene un disco de sistema (`sda`) y 8 discos de 1 GB. Con [dades-raid.sh](../scripts/dades-raid.sh):

```
md0  RAID 0  sdb + sdc          → 2,0 GB   /srv/md0
md1  RAID 1  sdd + sde          → 1,0 GB   /srv/md1
md5  RAID 5  sdf + sdg + sdh    → 2,0 GB   /srv/md5
sdi  (libre para el espejo DRBD del apartado 3)
```

Los tamaños confirman la teoría: RAID 0 suma los dos discos, RAID 1 se queda con uno y RAID 5 con tres discos da dos de espacio útil. Los arrays quedan en `/etc/mdadm/mdadm.conf` y `/etc/fstab`; tras reiniciar dades se montan solos. Salida completa: [raid-creacion.txt](../evidencias/tasca6/raid-creacion.txt).

### Pruebas ([dades-raid-pruebas.sh](../scripts/dades-raid-pruebas.sh), salida en [raid-pruebas-fallo.txt](../evidencias/tasca6/raid-pruebas-fallo.txt))

En cada array escribí 100 MB aleatorios y guardé su SHA-256 para comprobar después que no se pierde nada.

| Prueba | RAID 0 | RAID 1 | RAID 5 |
|---|---|---|---|
| Marcar un disco como fallado | `mdadm` **no lo permite**: *Cannot remove /dev/sdc from /dev/md0, array will be failed* | Estado `clean, degraded`, 1 disco activo | Estado `clean, degraded`, 2 discos activos |
| ¿Se leen los datos con un disco menos? | Al intentar montarlo solo con sdb: *assembled from 1 drive - not enough to start the array* → **datos perdidos** | **Sí**, SHA-256 OK | **Sí**, SHA-256 OK |
| Disco nuevo y reconstrucción | — | **5 s** hasta volver a `[UU]` | **11 s** hasta volver a `[UUU]` |
| Datos al final | OK (al volver a conectar sdc) | OK | OK |

Velocidad orientativa con `dd` de 200 MB (escritura directa):

| | Disco simple | RAID 0 | RAID 1 | RAID 5 |
|---|---|---|---|---|
| Escritura | 880 MB/s | 1,1 GB/s | 529 MB/s | 632 MB/s |
| Lectura | — | 1,4 GB/s | 1,5 GB/s | 1,0 GB/s |

Las cifras absolutas no son reales: por debajo hay tres capas de caché (VM → Proxmox → VirtualBox → SSD USB). Lo que sí se ve es la tendencia: RAID 0 es el que más escribe, y RAID 1 y RAID 5 escriben más despacio porque tienen que escribir la copia o calcular la paridad.

### Lo que aprendí con los fallos

- La reconstrucción tardó segundos porque los discos son de 1 GB. Con discos de 4 TB serían horas, y durante ese tiempo un RAID 5 no aguanta otro fallo: por eso en discos grandes se usa RAID 6 o RAID 10.
- Al mover los discos de almacenamiento (ver incidencia), Linux les cambió el nombre (`sdg` pasó a estar en md1). mdadm no se inmutó porque reconoce cada disco por su **superbloque**, no por el nombre.

### Incidencia: thin pool lleno

En mitad de las pruebas dades se quedó en `io-error`. El almacenamiento `local-lvm` de pve3 es *thin* (6,78 GB reales) y yo le había asignado 6 GB + 8 × 1 GB. Las reconstrucciones de RAID y la sincronización de DRBD escriben los discos enteros y lo llenaron (`switching pool to out-of-data-space (error IO) mode`). Lo resolví moviendo los 7 discos de RAID al NFS de TrueNAS con `qm disk move` (5–7 s cada uno): el pool bajó del 100 % al 36 % y los tres RAID volvieron con los datos intactos (SHA-256 OK). Evidencia: [incidencia-thin-pool.txt](../evidencias/tasca6/incidencia-thin-pool.txt).

## 3. Espejo entre discos de dos equipos distintos

### Opciones que estudié

Un RAID 1 normal protege de que se rompa un **disco**, pero no de que se caiga el **equipo** entero (fuente de alimentación, placa, el nodo de Proxmox…). Para eso el espejo tiene que hacerse por red:

| Opción | Cómo funciona | A favor | En contra |
|---|---|---|---|
| **DRBD** | Replica un dispositivo de bloques por red. Uno es primario (lee y escribe) y el otro secundario (recibe cada escritura) | Es literalmente un RAID 1 por red; síncrono; está en el kernel de Debian | Solo un nodo usa los datos a la vez; el cambio de primario es manual (o con Pacemaker) |
| GlusterFS réplica 2 | Sistema de ficheros distribuido entre servidores | Los dos nodos sirven ficheros | Con 2 nodos hay riesgo de *split-brain*; necesita un árbitro |
| Ceph | Almacenamiento distribuido integrado en Proxmox | Alta disponibilidad real | Mínimo 3 nodos y mucha RAM por disco: imposible con 16 GB |
| ZFS replication | Envía snapshots cada X minutos | Muy fácil en Proxmox | No es un espejo: se pueden perder los últimos minutos |

**Elegí DRBD**: es lo que pide el enunciado (un espejo entre dos discos de dos equipos), funciona con 384 MB de RAM y se ve muy claro qué pasa en cada momento.

### Montaje

- `serveis` (en pve1): disco `scsi1` de 1 GB · `dades` (en pve3): disco `scsi8` de 1 GB. Son discos de **nodos físicos (VMs) distintos**.
- Protocolo **C** (síncrono): una escritura no se da por terminada hasta que está en los dos discos.
- Configuración [drbd-espejo.sh](../scripts/drbd-espejo.sh): recurso `espejo`, `/dev/drbd0`, puerto 7789. Uso las rutas `/dev/disk/by-id/...drive-scsiN` porque los nombres `sdX` cambian de orden (me pasó, ver arriba).
- Versión: módulo DRBD 8.4.11 del kernel de Debian con `drbd-utils` 9.22.

### Caso de uso

La **carpeta compartida de la empresa** (`/srv/compartida`, con una carpeta por departamento y sus permisos). Si se cae el servidor donde está, no quiero esperar a restaurar la copia de la noche anterior (perdería el trabajo del día): quiero levantar la carpeta en el otro servidor con los datos al día.

### Prueba ([drbd-espejo.txt](../evidencias/tasca6/drbd-espejo.txt))

| Hora | Paso | Resultado |
|---|---|---|
| 01:02:15 | serveis primario: creo `/srv/compartida` con carpetas por departamento (Comercial con permisos 750) y un fichero de 50 MB; guardo su SHA-256 | `Connected Primary/Secondary UpToDate/UpToDate` |
| 01:02:16 | Intento montar el disco en dades | No deja: *Can't open blockdev*. El secundario solo recibe |
| 01:02:17 | **Fallo**: `qm stop 122` (como quitar la corriente a serveis) | dades ve `WFConnection Primary/Unknown` |
| 01:02:22 | En dades: `drbdadm primary` + `mount` | Monta |
| 01:02:38 | Compruebo | **4 de 4 ficheros con SHA-256 OK** y la carpeta Comercial sigue siendo `drwxr-x--- root`: un usuario normal no puede leerla |
| 01:02:55 | Se sigue trabajando en dades: creo `durante-la-caida.txt` | |
| 01:03:28 | Vuelvo a encender serveis y levanto DRBD | Resincroniza solo en **64 s** |
| 01:04:33 | Vuelta a la normalidad: dades secundario, serveis primario | serveis tiene el fichero creado durante la caída |

**Tiempo desde el fallo hasta tener los datos en el otro equipo: 21 s**, con cero pérdida (protocolo síncrono).

Cosas que vi y que no esperaba:

- Al volver, serveis copió el disco **entero** (1 GB) y no solo lo cambiado: como se cayó siendo primario, DRBD no se fía de su registro de actividad (*Marked additional 1024 MB as out-of-sync based on AL*).
- `drbd.service` viene deshabilitado: el nodo que vuelve **no se conecta solo**. Lo dejé así a propósito: si los dos arrancaran solos como primarios, tendría un *split-brain* (dos versiones distintas de los datos). Prefiero que volver a conectar sea un paso consciente del procedimiento.
- El cambio de primario es manual. Para hacerlo automático haría falta un gestor de clúster (Pacemaker/Corosync) y un tercer voto para evitar el *split-brain*.

También probé el **cambio planificado** (mantenimiento): antes de migrar serveis entre nodos pasé el primario a dades, migré y lo devolví. La resincronización tardó 1 s porque esta vez el apagado fue limpio ([Tarea 5 · Proxmox](tarea5/06-proxmox.md)).
