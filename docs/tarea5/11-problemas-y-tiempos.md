# Problemas detectados, configuraciones críticas y tiempos de respuesta

## Configuraciones críticas de cada sistema

Son las que, si se pierden o se tocan mal, dejan a la empresa sin servicio. Todas están en las copias del NAS.

| Sistema | Configuración crítica | Si falla… |
|---|---|---|
| MikroTik | NAT (`masquerade`), IP de ether2, DHCP con DNS del DC | Nadie sale a Internet ni recibe IP |
| OPNsense | `/conf/config.xml` entero (reglas, alias, interfaces) | Igual que arriba si es la puerta de enlace |
| Router Debian | `/etc/nftables.conf`, `ip_forward`, `/etc/network/interfaces` | Igual que arriba |
| TrueNAS | Pool `copias`, recursos NFS/SMB, clave SSH de copias, cron | No se hacen copias (y no se nota hasta que se necesitan) |
| Proxmox | `/etc/pve` (corosync, almacenamientos, VMs), quórum | Sin quórum no se puede arrancar ni cambiar nada |
| DC | AD DS + DNS (estado del sistema), IP fija | Nadie inicia sesión, los clientes no resuelven nombres internos |
| serveis / dades | `/etc/drbd.d`, `/etc/mdadm/mdadm.conf`, `/etc/fstab` | Los datos no se montan al arrancar |
| Clientes | DNS apuntando al DC, hora sincronizada | No encuentran el dominio / Kerberos rechaza el inicio de sesión |

## Problemas que me he encontrado (instalación, arranque y actualización)

| Sistema | Problema | Tiempo hasta resolverlo* |
|---|---|---|
| DC | Sin sistema instalado (disco de 404 KB) | Instalación desatendida: ~15 min |
| DC | No arrancaba desde el DVD con EFI (pide pulsar una tecla) | ~5 min |
| Cliente Debian | La ISO auxiliar de VirtualBox no arranca con EFI | ~5 min (pasar a BIOS) |
| Cliente Debian | El *preseed* no instaló SSH ni SSSD | ~5 min |
| TrueNAS | Arrancaba siempre el instalador (ISO montada) | ~2 min |
| TrueNAS | Disco ampliado que no crecía (imagen diferencial del snapshot) | ~5 min |
| OPNsense | Hora adelantada una hora (RTC en hora local) | ~2 min |
| Proxmox | `apt update` con error 401 (repositorio *enterprise*) | ~2 min |
| Proxmox pve2/pve3 | `grub-pc` no se configuraba: apuntaba al número de serie de un disco que ya no existe (clon o snapshot) | ~10 min. Lo añadí al script de actualización |
| Proxmox | Actualización parada esperando: sin quórum `/etc/pve` es de solo lectura | Se resolvió sola al arrancar el segundo nodo (~5 min) |
| Proxmox | VMs anidadas sin red fuera del nodo (modo promiscuo) | ~15 min de diagnóstico |
| Proxmox | Thin pool lleno → VM en `io-error` | ~3 min (mover 7 discos al NFS, 5–7 s cada uno) |
| serveis/dades | cloud-init en error (consecuencia de lo anterior) | ~3 min |
| Anfitrión | El PC se colgó entero con DC copiando + TrueNAS + routers + Proxmox arrancando | Reinicio del PC y reconstrucción de la sesión: ~20 min |
| DC | Copia de estado del sistema bloqueada en "enumerar ficheros" | Sin resolver del todo (ver [07-windows-server](07-windows-server.md)) |

\* Medido aproximadamente con la hora de los registros y de las evidencias; incluye diagnóstico.

## Tiempos de respuesta ante una incidencia

Lo que tardaría hoy, con los procedimientos y las copias que tengo:

| Incidencia | Qué haría | Tiempo medido o estimado |
|---|---|---|
| Router pierde la configuración | Restaurar el `.backup` (o el `.rsc`) desde el NAS | **1 min 31 s** medido (MikroTik); 8 s medido en OPNsense y Debian |
| Router no arranca (disco roto) | Reinstalar desde la ISO + restaurar la copia | ~15 min (estimado) |
| Nodo Proxmox caído | Arrancar sus VMs en otro nodo desde la copia `vzdump` del NAS | Copia de 747 MB: restauración de pocos minutos (estimado) |
| Servidor de datos caído | Promocionar el otro lado del espejo DRBD | **21 s** medido |
| Disco de un RAID roto | Sustituir y reconstruir | 0 s de corte; 5–11 s de reconstrucción con discos de 1 GB |
| DC caído | Restaurar estado del sistema o reinstalar y recuperar con las exportaciones | Es el punto débil: ver [07-windows-server](07-windows-server.md). En la empresa pondría un segundo DC |
