# MikroTik (RouterOS) · router principal

## Instalación y versión

- Imagen: `mikrotik-7.24.6.iso` (RouterOS x86, canal *long-term*). MikroTik no publica un fichero de sumas para esta ISO que pudiera descargar, así que su integridad queda como **N/C**: la forma de comprobarla sería bajarla otra vez de `download.mikrotik.com` y comparar el SHA-256 (ver [01-imagenes](01-imagenes-y-requisitos.md)).
- VM: 2 vCPU, disco IDE de 10 GB, dos tarjetas: `ether1` en NAT (WAN) y `ether2` en `lan_grupo3` (LAN).
- Versión comprobada: `/system resource print` → `version: 7.24.6 (long-term)`, arquitectura x86_64.
- Actualizaciones: en el canal *stable* había una 7.25.1, pero para un router prefiero *long-term* (menos cambios, más probado). En ese canal `check-for-updates` dice **System is already up to date**.
- Licencia: es la ISO x86 sin clave, que funciona en modo demo (en la consola avisa *ROUTER HAS NO SOFTWARE KEY, you have 16h49m*). El contador solo corre con el router encendido. Para el laboratorio vale; para algo permanente usaría CHR con licencia gratuita (limitada a 1 Mbit/s) o compraría una licencia nivel 4.

## Usuarios de administración

| Usuario | Grupo | Para qué |
|---|---|---|
| `admin` | full | El de fábrica, con contraseña. Lo dejo por si hay que entrar por consola |
| `alexsoler` | full | Mi cuenta personal para administrar |
| `copias` | `copias` (ssh, read, sensitive, ftp, test) | Solo lo usa el NAS para llevarse las copias; únicamente puede conectar desde 192.168.30.20 y entra con clave SSH, no con contraseña |

```
/user group add name=copias policy=ssh,read,sensitive,ftp,test
/user add name=copias group=copias address=192.168.30.20/32
/user ssh-keys import user=copias public-key-file=copias.pub
```

Además desactivé los servicios que no uso: `/ip service disable telnet,ftp,api,api-ssl`.

## Red

| Interfaz | Uso | Configuración |
|---|---|---|
| ether1 | WAN | Cliente DHCP del NAT de VirtualBox → 10.0.2.15/24, puerta 10.0.2.2 |
| ether2 | LAN | 192.168.30.1/24 estática |

- **DHCP** en la LAN: rango 192.168.30.100–200, puerta 192.168.30.1, **DNS 192.168.30.21 (el DC) y 192.168.30.1**, dominio `alexsoler.lan`. Así los clientes encuentran el dominio sin tocar nada a mano (en el grupo nos pasó lo contrario: el cliente usaba el DNS del router y no veía el dominio).
- Reserva para el cliente Linux: MAC 08:00:27:AA:51:50 → 192.168.30.150 (el NAS necesita una IP fija para hacerle copias).
- **NAT**: `chain=srcnat action=masquerade out-interface=ether1`.
- **DNS** propio: reenvía a 1.1.1.1 y 8.8.8.8 y responde a la LAN.

## Cortafuegos

Antes no tenía ninguna regla de filtrado (solo NAT). Lo dejé así:

```
input:   establecidas/relacionadas → aceptar; inválidas → descartar; ping → aceptar
         DHCP cliente en ether1 → aceptar
         todo lo que entra por ether2 (LAN) → aceptar (gestión, DNS)
         SSH por ether1 solo desde 10.0.2.2 (el anfitrión) → aceptar
         resto → descartar con log "MK-IN-DROP"
forward: establecidas → aceptar; inválidas → descartar
         LAN→WAN TCP 23 y 445 → descartar con log "MK-BLOQ"     ← prueba de bloqueo
         LAN→WAN → aceptar
         resto → descartar con log "MK-FWD-DROP"
```

La configuración completa exportada (sin contraseñas) está en [configs/mikrotik/mikrotik-export.rsc](../../configs/mikrotik/mikrotik-export.rsc).

## Prueba: una conexión permitida y otra bloqueada

Cliente de prueba: TrueNAS (192.168.30.20) con puerta de enlace .1. Destino `portquiz.net` (13.216.200.40), un servidor que responde en cualquier puerto, así que si algo no conecta es por el cortafuegos y no porque el destino no escuche.

```
HTTP 80 (permitida):      HTTP 200 en 0.208837s
TCP 23 telnet (bloqueada): no conecta (descartado)
TCP 445 SMB (bloqueada):   no conecta (descartado)
traceroute -n -m 3 1.1.1.1:
 1  192.168.30.1   2  10.0.2.2   3  * * *
```

Registro (`/log print where message~"MK-BLOQ"`):

```
22:19:45 firewall,info MK-BLOQ forward: in:ether2 out:ether1, connection-state:new
         src-mac 08:00:27:E1:B1:FA, proto TCP (SYN), 192.168.30.20:36022->13.216.200.40:445, len 60
```

Cómo lo leo: entra por `ether2` (la LAN), saldría por `ether1`, es un paquete nuevo (SYN), lo manda la MAC del TrueNAS y va al puerto 445. Lo descarta la regla 9 y por eso el cliente no recibe respuesta y espera hasta el timeout. Los contadores confirman 12 paquetes descartados en esa regla mientras la de "LAN a Internet" sigue sumando.

Evidencias completas: [cortafuegos-prueba-permitida-bloqueada.txt](../../evidencias/tasca5/cortafuegos-prueba-permitida-bloqueada.txt) y [cortafuegos-registros.txt](../../evidencias/tasca5/cortafuegos-registros.txt).

## Copia de seguridad

Dos formatos, porque sirven para cosas distintas:

- `/system backup save` → fichero **binario**. Restaura todo, usuarios incluidos, pero solo en el mismo modelo/versión.
- `/export` → **texto** con los comandos. Se lee, se puede comparar entre fechas y sirve para otro router, pero no lleva los usuarios.

Un *scheduler* del MikroTik genera los dos cada día a las 22:30 y el NAS se los lleva a las 23:00 con su script (ver [10-copias-automatizadas](10-copias-automatizadas.md)).

## Prueba de fallo y recuperación

Simulé el peor caso razonable: el router pierde toda la configuración.

| Hora | Paso |
|---|---|
| 22:57:23 | `/system reset-configuration no-defaults=yes skip-backup=yes` |
| 22:57:28 | Desde la LAN: sin ping al .1 y sin salida a Internet (HTTP 000) |
| entre medias | Entro por **consola** (sin IP ya no hay SSH). Me pide cambiar la contraseña de `admin`; con `/file print` veo que `mikrotik-diario.backup` sigue en el disco |
| 22:58:21 | `/system backup load name=mikrotik-diario.backup` |
| 22:58:30 | *Restore and reboot? y* → reinicia |
| 22:58:52 | Vuelve a responder por SSH con su contraseña original, IPs, NAT y usuarios |
| 22:58:54 | Prueba final desde la LAN: HTTP 200 |

**Tiempo sin servicio: 1 min 31 s.** Si el disco del router también se hubiera perdido, el paso extra sería darle una IP a `ether2` desde consola, subir el `.backup` del NAS por Winbox/SFTP y cargarlo; calculo unos 5 minutos más. Capturas: [tras el reset](../../evidencias/tasca5/mikrotik-tras-reset.png), [aviso de licencia](../../evidencias/tasca5/mikrotik-aviso-licencia.png), [restaurando](../../evidencias/tasca5/mikrotik-restaurar-backup.png). Registro: [recuperacion-mikrotik.txt](../../evidencias/tasca5/recuperacion-mikrotik.txt).

## Optimización aplicada

Tenía 4 GB de RAM asignados y RouterOS usaba unos 350 MB. Lo bajé a **256 MB**: arranca y enruta igual, y el proceso de VirtualBox pasa a ocupar 135 MB en el anfitrión. Detalle en la [Tarea 7](../tarea7-rendimiento.md).
