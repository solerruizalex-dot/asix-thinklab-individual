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
| Proxmox | Thin pool lleno → VM en `io-error` | ~3 min (mover 7 discos al NFS, 5–7 s cada uno). Fue lo que me decidió a sacar serveis y dades de Proxmox |
| serveis/dades (1.ª versión, dentro de Proxmox) | cloud-init en error (consecuencia del modo promiscuo) | ~3 min |
| serveis/dades (VMs de VirtualBox) | Pantalla negra: `unattended install` deja el disco vacío primero en el orden de arranque | ~10 min |
| serveis/dades | El instalador se colgaba descargando por `lan_grupo3` | Rodeado instalando por NAT (~1 h entre intentos). La causa real, la tarjeta virtio, la encontré después: ~15 min de diagnóstico |
| serveis/dades | Un script mío expulsó el CD a mitad de instalación | Reinstalar (~30 min) y que el preseed apague la VM al terminar |
| serveis/dades | Tras poner la IP fija, `resolv.conf` vacío | ~5 min |
| dades | En el primer cambio de disco en caliente, el disco nuevo no aparecía (*serial number mismatch*) | ~15 min: hay que hacer que el kernel olvide el disco viejo antes |
| serveis/dades | DRBD no aceptaba la ruta `by-path` (*Parse error*) | ~5 min: ponerla entre comillas |
| Toda la red | Montada en 192.168.30.0/24 en lugar de la 192.168.36.0/24 que me corresponde | ~25 min cambiar los 12 equipos sin reinstalar ([Tarea 4](../tarea4-red.md)) |
| DC | La copia del estado del sistema falló con código -4 al repetirla en la red nueva | ~15 min: ver que a `E:` le quedaban 1,4 GB (no caben dos versiones + VSS), ampliar el disco a 50 GB y repetir: correcta en 14 min 33 s |
| Anfitrión | El PC se colgó entero con DC copiando + TrueNAS + routers + Proxmox arrancando | Reinicio del PC y reconstrucción de la sesión: ~20 min |
| DC | La copia de estado del sistema parecía colgada en "enumerar ficheros" | No estaba colgada: Defender la frena. Tardaba 41 min; con una exclusión acotada, 10 min 32 s ([07-windows-server](07-windows-server.md)) |
| DC | Mi script daba por buena una copia cancelada | Comprobar el código de salida de wbadmin, no el texto (~10 min) |

\* Medido aproximadamente con la hora de los registros y de las evidencias; incluye diagnóstico.

## Tiempos de respuesta ante una incidencia

Lo que tardaría hoy, con los procedimientos y las copias que tengo:

| Incidencia | Qué haría | Tiempo medido o estimado |
|---|---|---|
| Router pierde la configuración | Restaurar el `.backup` (o el `.rsc`) desde el NAS | **1 min 31 s** medido (MikroTik); 8 s medido en OPNsense y Debian |
| Router no arranca (disco roto) | Reinstalar desde la ISO + restaurar la copia | ~15 min (estimado) |
| Nodo Proxmox caído | Arrancar sus VMs en otro nodo desde la copia `vzdump` del NAS | Restaurar la VM de prueba (4 GiB): **9,6 s** medido, y respondía al ping a los 16 s |
| Servidor de datos caído | Promocionar el otro lado del espejo DRBD | **2,7 s** medido con los pasos ya preparados; en la realidad, lo que tarde alguien en notarlo y ejecutar dos comandos |
| Disco de un RAID roto | Sustituir y reconstruir | 0 s de corte; 6–7 s de reconstrucción con discos de 1 GB (quitando el disco de verdad) |
| DC caído | Arrancar desde la ISO en modo recuperación y restaurar el estado del sistema desde E: o desde la copia del NAS | Sin probar: la copia tarda 10–12 min en hacerse, la restauración sería del mismo orden (estimado). Es el punto débil; en la empresa pondría un segundo DC |
