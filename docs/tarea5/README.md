# Tarea 5 · Instalación y comunicaciones

Cada sistema tiene su documento con lo mismo: imagen y versión, actualización, usuarios de administración, red, copias (qué sí y qué no) y, en los equipos de comunicaciones, prueba de conexión permitida/bloqueada y prueba de fallo con recuperación.

| # | Documento | Sistema |
|---|---|---|
| 01 | [Imágenes y requisitos](01-imagenes-y-requisitos.md) | Origen, arquitectura y SHA-256 de todas las ISOs |
| 02 | [MikroTik](02-mikrotik.md) | Router principal, DHCP y NAT |
| 03 | [OPNsense](03-opnsense.md) | Cortafuegos alternativo |
| 04 | [Debian con nftables](04-debian-nftables.md) | Router GNU/Linux |
| 05 | [TrueNAS](05-truenas.md) | Servidor de copias |
| 06 | [Proxmox](06-proxmox.md) | Clúster de 3 nodos, migraciones medidas |
| 07 | [Windows Server 2025](07-windows-server.md) | Controlador de dominio |
| 08 | [Servidores Linux](08-servidores-linux.md) | serveis y dades |
| 09 | [Clientes](09-clientes.md) | Windows 11 y Debian unidos al dominio |
| 10 | [Copias automatizadas](10-copias-automatizadas.md) | Calendario, script del NAS y recuperaciones probadas |
| 11 | [Problemas y tiempos](11-problemas-y-tiempos.md) | Configuraciones críticas, incidencias y tiempos de respuesta |

## Resumen por sistema

| Sistema | Versión final | Actualizado | Usuarios admin | Red | Copia al NAS | Fallo y recuperación |
|---|---|---|---|---|---|---|
| MikroTik | RouterOS 7.24.6 *long-term* | Al día en su canal | `alexsoler` + `copias` (solo lectura) | WAN DHCP / LAN .1 | `.backup` + `.rsc` diario | Reset de fábrica → 1 min 31 s |
| OPNsense | 26.7.9_3 | 26.7 → 26.7.9_3 | `root` + `alexsoler` | WAN DHCP / LAN .2 | `config.xml` diario | Regla borrada → 8 s |
| Debian nftables | 13.8 | 13.7 → 13.8 | `alexsoler` + `root` (solo clave) | WAN DHCP / LAN .3 | `/etc` diario | `masquerade` borrado → 8 s |
| TrueNAS | 24.04.2.5 | 24.04.0 → 24.04.2.5 | `admin`, `alexsoler`, `copias` | .20 fija | Es el destino (+ snapshots) | — |
| Proxmox ×3 | 9.2.32, kernel 7.0.14 | 9.2.2 → 9.2.32 | `alexsoler@pve` | .32–.34 en vmbr0 | `vzdump` diario + `/etc/pve` | Migraciones medidas |
| Windows Server | 2025, 10.0.26100 | ver doc. 07 | `adm.alex` | .21 fija | Exportaciones + estado del sistema | — |
| serveis / dades | Debian 13.8 | 13.7 → 13.8 | `alexsoler` (sudo) | .22 / .23 fijas | `/etc` + `vzdump` | Caída de serveis → 21 s con DRBD |
| Windows 11 | 23H2 | ver doc. 09 | Admins. del dominio | DHCP .198 | Perfiles por SMB | — |
| Debian cliente | 13.8 | 13.1 → 13.8 | `alexsoler`, G_Informatica | DHCP reservado .150 | `/etc` | — |
