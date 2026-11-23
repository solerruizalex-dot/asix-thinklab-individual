# Copias automatizadas: qué, cómo, dónde y cuándo

Todas las copias acaban en el pool `copias` de TrueNAS (disco propio de 60 GB, distinto del del sistema). Nada se hace a mano.

## Calendario de cada noche

| Hora | Quién | Qué |
|---|---|---|
| 21:30 | DC (tarea programada `Copia DC al NAS`, SYSTEM) | Exportaciones (GPO, usuarios, OUs, DNS) al NAS + estado del sistema a E: y réplica al NAS |
| 22:00 | Clúster Proxmox (`copia-diaria`) | `vzdump` de todas las VMs y contenedores, modo *snapshot*, zstd, se guardan 3 |
| 22:30 | MikroTik (*scheduler*) | Genera `mikrotik-diario.backup` (binario) y `mikrotik-diario.rsc` (texto) en su disco |
| 23:00 | TrueNAS (cron, [copias-config.sh](../../scripts/copias-config.sh)) | Va a buscar por SSH la configuración de cada equipo |
| 23:00 | TrueNAS (tarea de snapshots) | Snapshot recursivo del pool, retención 14 días |
| 21:00 | Windows 11 (tarea programada `Copia datos al NAS`, SYSTEM) | Escritorio, Documentos y Descargas de cada perfil al SMB del NAS |

El orden importa: el MikroTik genera su copia a las 22:30 para que el NAS se la lleve fresca a las 23:00.

## El script del NAS (modelo *pull*)

El NAS entra con **su** clave SSH en cada equipo y se trae lo que necesita. Lo elegí así porque:

- Los equipos no guardan ninguna contraseña del NAS. Si alguien entra en un router, no puede borrar las copias.
- En cada equipo la clave del NAS solo se acepta si viene de 192.168.30.20 (`from="192.168.30.20"` en `authorized_keys`); en el MikroTik, el usuario `copias` tiene `address=192.168.30.20/32` y solo permisos de lectura.
- Si un equipo está apagado, lo apunta como fallo en el log y sigue con el siguiente. Las carpetas vacías se borran y se guardan 30 días.

| Equipo | Qué se trae |
|---|---|
| MikroTik | `/export show-sensitive` (texto) + el `.backup` binario |
| OPNsense | `/conf/config.xml` (todo el sistema está ahí) |
| Router Debian | `/etc/nftables.conf`, `/etc/network`, dnsmasq, sysctl, sshd + lista de paquetes |
| pve1, pve2, pve3 | `/etc/pve`, `/etc/network/interfaces`, `/etc/corosync`, `config.db` |
| serveis, dades, cliente Linux | `/etc` completo + lista de paquetes |

Ejecución real de esta noche ([copias-config-ejecucion.txt](../../evidencias/tasca5/copias-config-ejecucion.txt)), con OPNsense y el cliente Linux apagados:

```
OK    mikrotik · FALLO opnsense · OK debian-nft · OK proxmox-pve1/2/3 · OK serveis · OK dades · FALLO cliente-linux
---- fin: 7 correctas, 2 con fallo ----
```

Los dos fallos son los equipos apagados, y quedan registrados: es justo lo que quiero ver por la mañana. En la tercera ejecución, con OPNsense encendido, su `config.xml` también se copia bien (`OK opnsense`). Las tareas programadas de los dos Windows, con su hora y su último resultado (0), están en [windows-tareas-copia.txt](../../evidencias/tasca5/windows-tareas-copia.txt).

## Lo que no se copia y por qué

| No se copia | Por qué |
|---|---|
| El sistema operativo de routers, nodos Proxmox y clientes | Se reinstala desde la ISO en 10–20 minutos; restaurar una imagen por USB tarda más |
| Imagen completa del DC | 24 GB. Lo que hace falta para recuperar el dominio es el **estado del sistema** |
| Programas de los clientes | Se reinstalan; la configuración llega por el dominio |
| Los datos de prueba de los RAID | Son ficticios. Con datos reales irían al NAS, porque un RAID no es una copia |

## Recuperaciones probadas

| Equipo | Fallo provocado | Recuperación | Tiempo sin servicio |
|---|---|---|---|
| MikroTik | Reset de fábrica sin configuración | Consola + `/system backup load` | **1 min 31 s** |
| OPNsense | Borrar la regla que deja salir a la LAN | Restaurar `config.xml` desde TrueNAS | **8 s** ([03-opnsense](03-opnsense.md)) |
| Router Debian | Borrar el *masquerade* de `nftables.conf` | Restaurar el fichero desde TrueNAS | **8 s** ([04-debian-nftables](04-debian-nftables.md)) |
| serveis (servidor entero) | Apagado brusco (`qm stop`) | Los datos del espejo DRBD se levantan en dades | **21 s** hasta tener los datos ([Tarea 6](../tarea6-raid.md)) |
| Disco de RAID 1 / RAID 5 | Disco marcado como fallado | Cambio de disco y reconstrucción | 0 s de corte; reconstrucción en 5 s / 11 s |
| Windows 11 | Documento del usuario borrado | Copiarlo desde la copia del NAS | 0,1 s, mismo SHA-256 |
