# OPNsense · cortafuegos alternativo

## Instalación y versión

- Imagen: `OPNsense-26.7-dvd-amd64.iso`. OPNsense publica el SHA-256 del fichero **comprimido** (`.iso.bz2`), no de la ISO. Para verificarla bajé el `.bz2` oficial, comprobé que su suma coincide con la publicada (`95cafedd…186bfb`) y que, al descomprimirlo, sale exactamente mi ISO (`1efd5dc9…`): **integridad verificada** ([isos-sha256.txt](../../evidencias/tasca5/isos-sha256.txt)).
- VM: FreeBSD 64 bits, 2 vCPU, disco de 10 GB con UFS (en el arranque monta `/dev/gpt/rootfs`), `em0` en NAT (WAN) y `em1` en `lan_grupo3` (LAN).
- Versión de partida: `opnsense-version` → **OPNsense 26.7 (amd64)** sobre FreeBSD 15.1-RELEASE-p1.
- **Actualización**: tenía unos 90 paquetes pendientes. Guardé antes `config.xml` en `/conf/backup/` y lancé `configctl firmware update` (lo mismo que el botón de la web): algo menos de minuto y medio y reinicio automático. Queda en **OPNsense 26.7.9_3** con FreeBSD 15.1-RELEASE-p6 y, contándolo bien, 0 paquetes pendientes (al principio conté mal: ver la aclaración en la evidencia). Después comprobé que la regla de bloqueo sigue cargada, que HTTP sale (200) y que el 445 sigue bloqueado ([opnsense-actualizacion.txt](../../evidencias/tasca5/opnsense-actualizacion.txt)).
- La RAM la bajé de 4 GB a 2 GB: sin plugins (ni IDS ni proxy) no necesita más para enrutar y filtrar una LAN pequeña.

Al revisarla vi que el **asistente inicial nunca se había completado** (`<trigger_initial_wizard/>` seguía en `config.xml`), el nombre era el de fábrica (`OPNsense.internal`) y la zona horaria UTC.

## Lo que cambié

Lo hice editando `/conf/config.xml` con un pequeño script PHP y recargando servicios, siempre guardando antes una copia en `/conf/backup/`. Es lo mismo que haría desde la web, pero así queda escrito y se puede repetir.

| Qué | Antes | Después |
|---|---|---|
| Nombre / dominio | OPNsense.internal | OPNsense-AlexSoler.alexsoler.lan |
| Zona horaria | Etc/UTC | Europe/Madrid |
| Usuarios | solo `root` | `root` + `alexsoler` (grupo *admins*) |
| SSH | desactivado | activo **solo en LAN**, para administración y copias |
| DHCP (dnsmasq) | activo en LAN | desactivado (lo da el MikroTik) |
| Reglas | permitir LAN→cualquiera | + bloqueo TCP 23/445 con registro, por delante |

Para activar el SSH la primera vez tuve que usar la consola de la VM. Ahí me encontré con que el teclado estaba en español y lo que escribía desde el anfitrión salía cambiado (`/` → `-`). Lo arreglé con `kbdcontrol -l us`.

## Red

| Interfaz | Uso | Configuración |
|---|---|---|
| em0 | WAN | DHCP del NAT → 10.0.2.15/24, puerta 10.0.2.2 |
| em1 | LAN | 192.168.30.2/24 estática |

NAT de salida en modo **automático** (crea solo el *masquerade* de la LAN hacia la WAN).

## La regla de bloqueo

La primera vez puse los puertos como `23,445` directamente en la regla y no hacía nada. Mirando `/tmp/rules.debug` vi que OPNsense la había generado **comentada** con `#`: ese campo no acepta listas. La solución correcta es un **alias de puertos**:

```
alias  puertos_bloqueados (port): 23, 445
regla  LAN · in · TCP · origen LAN · destino any · puerto puertos_bloqueados · BLOCK · log
```

Con el alias, `pfctl -sr` ya muestra:

```
block drop in log quick on em1 inet proto tcp from (em1:network) to any port = telnet
block drop in log quick on em1 inet proto tcp from (em1:network) to any port = microsoft-ds
```

## Prueba: permitida y bloqueada

Mismo cliente (TrueNAS) y destino que en el MikroTik, con la puerta de enlace cambiada a .2:

```
HTTP 80 (permitida):      HTTP 200 en 0.211502s
TCP 23 telnet (bloqueada): no conecta (descartado)
TCP 445 SMB (bloqueada):   no conecta (descartado)
traceroute: 1 192.168.30.2 · 2 10.0.2.2
```

Registro en `/var/log/filter/`:

```
2026-11-22T23:19:53+01:00 OPNsense-AlexSoler filterlog ... b10c0b10-...,em1,match,block,in,4,...,tcp,60,
192.168.30.20,13.216.200.40,59562,445,0,S,...
```

Se lee por campos separados por comas: identificador de la regla (`b10c0b10…`, la mía), interfaz `em1`, `match,block,in`, IPv4, TCP, origen 192.168.30.20, destino 13.216.200.40, puerto 445, flag `S` (intento de conexión). La hora del registro iba **una hora adelantada**: VirtualBox le pasa el reloj en hora local y FreeBSD lo interpreta como UTC. Lo corregí con `VBoxManage modifyvm OPNsense-AlexSoler --rtc-use-utc on`.

## Copia de seguridad

Todo OPNsense está en un único fichero: `/conf/config.xml`. Es lo único que hay que guardar; el sistema se reinstala desde la ISO en unos 10 minutos (estimado, no lo he cronometrado) y, al importar ese fichero (opción 13 de la consola o *System › Configuration › Backups*), queda igual. El NAS lo copia cada noche por SSH con su clave (ver [10-copias-automatizadas](10-copias-automatizadas.md)). La clave está en el usuario `root` limitada con `from="192.168.30.20"`.

Además OPNsense guarda solo sus versiones anteriores en `/conf/backup/` (el 23/11 había 20, ver [opnsense-actualizacion.txt](../../evidencias/tasca5/opnsense-actualizacion.txt)).

## Prueba de fallo y recuperación

Simulé un error típico desde la web: borrar sin querer la regla que deja salir a la LAN.

| Hora | Paso |
|---|---|
| 22:21:29 | Se borra la regla *Default allow LAN to any rule* y se recarga el filtro |
| 22:21:29 | Cliente con puerta .2: **SIN SALIDA A INTERNET** |
| 22:21:36 | Desde el NAS: `scp` de la última copia a `/conf/config.xml` + `configctl filter reload` |
| 22:21:37 | Prueba final: HTTP 200, y la regla de bloqueo sigue cargada |

**Tiempo sin servicio: 8 s** con el procedimiento ya preparado y una copia del NAS hecha 3 minutos antes (la de las 22:18), así que no se perdió ningún cambio. Con la copia de la noche anterior se perderían los cambios del día. Haciéndolo a mano (darse cuenta, entrar, buscar la copia) serían unos minutos. Registro: [recuperacion-opnsense.txt](../../evidencias/tasca5/recuperacion-opnsense.txt).
