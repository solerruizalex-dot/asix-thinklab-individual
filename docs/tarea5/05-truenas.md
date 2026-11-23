# TrueNAS SCALE · servidor de copias

## Instalación, versión y estado

- Imagen `TrueNAS-SCALE-24.04.0.iso`, **SHA-256 verificado** (coincide con el publicado junto a la ISO).
- La VM estaba creada pero sin configurar: ya tenía el sistema instalado en el disco de 16 GB (`boot-pool`), pero arrancaba siempre el instalador porque la ISO seguía montada y el DVD iba antes en el orden de arranque. La expulsé.
- Versión inicial comprobada por la API: `TrueNAS-SCALE-24.04.0`, nombre `truenas-alex`, zona horaria Europe/Madrid.
- **Actualización**: dentro de su tren (*Dragonfish* 24.04) había una actualización, la **24.04.2.5** (1,3 GB según la propia API). La apliqué por la API: 3 min 36 s de descarga e instalación y 67 s de reinicio. Después el pool sigue `ONLINE`, SMB, NFS y SSH funcionan y ya no hay más actualizaciones en el tren ([truenas-actualizacion.txt](../../evidencias/tasca5/truenas-actualizacion.txt)). TrueNAS guarda el sistema anterior como **entorno de arranque** (`24.04.0`), así que si algo fallara se vuelve a él desde el menú de arranque. No salté a 24.10/25.04: es cambiar de versión mayor y prefiero probarlo antes en otra VM.
- RAM: al empezar tenía 8 GB asignados; el 22/11 la bajé a 4 GB y el 23/11 a 2,5 GB (TrueNAS ve 2.477 MiB). Con un único pool pequeño y sin aplicaciones funciona (ZFS usa menos caché ARC, pero aquí casi todo son escrituras de copias).

## Usuarios

| Usuario | Para qué | Notas |
|---|---|---|
| `admin` | Administración por web, API y SSH | El que crea el instalador |
| `alexsoler` | Mi cuenta personal | Grupo `builtin_administrators` |
| `copias` | Cuenta de servicio con la que los Windows escriben en SMB | Sin acceso SSH con contraseña, solo SMB |

## Red

| Interfaz | Configuración |
|---|---|
| enp0s3 (`lan_grupo3`) | **192.168.36.20/24 estática** (al principio tenía la .200 por DHCP del MikroTik) |
| Puerta de enlace | 192.168.36.1 |
| DNS | 192.168.36.1, 1.1.1.1 · dominio `alexsoler.lan` |

Un NAS de copias necesita IP fija: todos los equipos y scripts apuntan a ella.

## Disco adicional para las copias

- Segundo disco virtual solo para datos: lo amplié de 20 GB a **60 GB**. Me pasó una cosa: lo amplié y TrueNAS seguía viendo 20 GB. La VM tenía un snapshot de VirtualBox, así que trabajaba sobre una imagen **diferencial** y yo había ampliado la imagen base. Hay que redimensionar el fichero que sale en `showvminfo`.
- Pool `copias` sobre ese disco (un solo disco: en el laboratorio no hay redundancia; en la empresa serían dos discos en espejo).
- Datasets, todos con compresión LZ4:

| Dataset | Para qué | Acceso |
|---|---|---|
| `copias/configs` | Configuración de routers, nodos y servidores Linux | Solo el propio NAS (las va a buscar él) |
| `copias/windows` | Estado del sistema del DC y perfiles del Windows 11 | SMB `\\truenas\copias-windows`, usuario `copias`, **cuota de 30 GB** |
| `copias/proxmox` | Almacenamiento compartido del clúster: lo usé en la prueba de migración (disco de la VM de prueba, copias `vzdump` y su restauración). Al terminar lo vacié | NFS solo para 192.168.36.0/24 |
| `copias/linux` | Reservado a datos de clientes Linux | — |
| `copias/scripts` | El script de copias, su clave SSH y el log | Solo root |

- Red: 192.168.36.20/24, puerta .1, DNS el DC (.21), el MikroTik (.1) y 1.1.1.1. La cambié desde la API (`interface.update` + `interface.commit` sin *rollback*, porque la confirmación no podía llegar desde la IP vieja).
- **Snapshots** del pool todos los días a las 23:00 con retención de 14 días: si un fichero copiado se estropea o se sobrescribe, tengo las versiones de los días anteriores.

Estado completo sacado de la API: [truenas-estado.txt](../../evidencias/tasca5/truenas-estado.txt).

## Qué es copia, cómo y dónde

El detalle de qué se copia de cada equipo está en [10-copias-automatizadas](10-copias-automatizadas.md). Resumen de la idea:

- **Configuración** (pequeña, cambia poco, es lo que de verdad cuesta rehacer): el NAS **se la lleva** cada noche por SSH. Los equipos no guardan ninguna contraseña del NAS.
- **Imágenes** (grandes): el DC deja el estado del sistema por SMB. El clúster Proxmox las dejaría por NFS (probado con las máquinas de prueba).
- **No se copia** lo que se reinstala más rápido de lo que se restaura (los sistemas operativos de routers, nodos y clientes).
