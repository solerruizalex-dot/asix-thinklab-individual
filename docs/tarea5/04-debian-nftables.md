# GNU/Linux con nftables · router Debian

## Instalación y versión

- Imagen: `debian-13.1.0-amd64-netinst.iso`. **SHA-256 verificado** contra `SHA256SUMS` de cdimage.debian.org (`658b28e2…9c65568b3`, coincide).
- VM: Debian 64 bits, 2 vCPU, disco de 20 GB, `enp0s3` en NAT (WAN) y `enp0s8` en `lan_grupo3` (LAN). Firmware BIOS, tabla MBR, raíz ext4 de 19 GB y 1 GB de swap.
- Se instaló con escritorio GNOME. Para un router sobra: lo dejé arrancando en modo texto (`systemctl set-default multi-user.target`) y bajé la RAM de 2 GB a 1 GB. Detalle y medidas en la [Tarea 7](../tarea7-rendimiento.md).
- Actualizado antes de darlo por bueno: `apt update && apt upgrade` → 75 paquetes, Debian **13.7 → 13.8**, kernel 6.12.117. El 23/11 volví a comprobarlo y había un kernel nuevo de seguridad: **6.12.118**, aplicado y reiniciado (28 s sin servicio; nftables y dnsmasq arrancan solos). Punto de retorno: el snapshot `estado-inicial-22nov` de VirtualBox.

## Usuarios de administración

- `alexsoler`: usuario normal, no está en el grupo `sudo`; para administrar uso `su -`.
- `root`: con contraseña local. Por SSH solo entra con clave (lo que trae Debian por defecto, `PermitRootLogin prohibit-password`). La única clave autorizada es la del NAS, limitada con `from="192.168.30.20"`.

## Red

`/etc/network/interfaces`:

```
allow-hotplug enp0s3
iface enp0s3 inet dhcp          # WAN: NAT de VirtualBox → 10.0.2.15

auto enp0s8
iface enp0s8 inet static
    address 192.168.30.3/24      # LAN, sin gateway (la salida es por enp0s3)
```

Reenvío de paquetes activado en `/etc/sysctl.d/99-forward.conf` → `net.ipv4.ip_forward=1`.

## nftables

Partía de una configuración ya funcional (política *drop* en `input` y `forward`, NAT con *masquerade*). Le añadí tres cosas:

1. **SSH por la WAN solo desde 10.0.2.2.** En el NAT de VirtualBox esa dirección es el anfitrión, así que nadie más puede llegar. Lo necesitaba para usar este router como salto hacia la LAN.
2. **Bloqueo con registro** de telnet y SMB hacia Internet (la prueba de conexión bloqueada).
3. Un `log` al final de `input` limitado a 5 por minuto, para ver qué se descarta sin llenar el disco.

```nft
chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    iifname "enp0s8" oifname "enp0s3" tcp dport { 23, 445 } log prefix "NFT-BLOQ " drop
    iifname "enp0s8" oifname "enp0s3" accept
}
table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "enp0s3" masquerade
    }
}
```

Antes de aplicar cualquier cambio: `nft -c -f fichero` (comprueba sin cargar) y copia del anterior en `/root/nftables.conf.bak-FECHA`. Fichero completo en [configs/debian-nft/nftables.conf](../../configs/debian-nft/nftables.conf).

## dnsmasq

Al revisarlo me encontré la misma configuración (interfaz, rango DHCP, opciones) **repetida** en `/etc/dnsmasq.conf` y en `/etc/dnsmasq.d/lan.conf`. En el historial de root se ven varios `dnsmasq --test` seguidos, así que en su momento costó que arrancara. Además daba DHCP en la misma red que el MikroTik y el OPNsense.

Ahora `dnsmasq.conf` está como viene de serie y en `lan.conf` solo queda el DNS para la LAN; las líneas del DHCP están comentadas por si este router pasa a ser el principal. Ver [configs/debian-nft/dnsmasq-lan.conf](../../configs/debian-nft/dnsmasq-lan.conf).

## Prueba: permitida y bloqueada

Cliente TrueNAS con puerta de enlace .3:

```
HTTP 80 (permitida):      HTTP 200 en 0.213137s
TCP 23 telnet (bloqueada): no conecta (descartado)
TCP 445 SMB (bloqueada):   no conecta (descartado)
traceroute: 1 192.168.30.3 · 2 10.0.2.2
```

`journalctl -k | grep NFT-BLOQ`:

```
NFT-BLOQ IN=enp0s8 OUT=enp0s3 SRC=192.168.30.20 DST=13.216.200.40 LEN=60 TTL=63
         PROTO=TCP SPT=52294 DPT=445 WINDOW=32120 SYN
```

Entra por la LAN (`IN=enp0s8`), iba a salir por la WAN (`OUT=enp0s3`), es un SYN al 445: la regla lo registra y lo descarta. El TTL=63 indica que ya ha atravesado un salto (el propio router).

## Copia de seguridad

No tiene sentido guardar el disco entero (20 GB) para un router que se reinstala en unos 15 minutos (estimado). Lo que vale es lo que lo hace distinto de un Debian recién instalado:

- `/etc/nftables.conf`, `/etc/network/`, `/etc/dnsmasq*`, `/etc/sysctl.d/`, `/etc/ssh/sshd_config`, `/etc/hostname`, `/etc/hosts`
- la lista de paquetes (`dpkg --get-selections`) para reinstalar lo mismo.

El NAS se lo lleva cada noche (ver [10-copias-automatizadas](10-copias-automatizadas.md)).

## Prueba de fallo y recuperación

Simulé un error de edición: alguien borra por error la línea del *masquerade* y reinicia nftables.

| Hora | Paso |
|---|---|
| 22:21:01 | `sed -i "/masquerade/d" /etc/nftables.conf; systemctl restart nftables` |
| 22:21:01 | Cliente con puerta .3: **SIN SALIDA A INTERNET** |
| 22:21:08 | Diagnóstico: `nft list table ip nat` → la cadena `postrouting` está vacía |
| 22:21:08 | Desde el NAS: se extrae `etc/nftables.conf` de la última copia, `nft -c -f` y `systemctl restart nftables` |
| 22:21:09 | Prueba final: HTTP 200 |

**Tiempo sin servicio: 8 s**, con una copia del NAS hecha minutos antes (22:18). Registro: [recuperacion-debian-nft.txt](../../evidencias/tasca5/recuperacion-debian-nft.txt).
