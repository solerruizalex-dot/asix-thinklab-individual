# Clientes: Windows 11 (Administración) y Debian (Informática)

El enunciado pide los cinco departamentos; con uno de cada sistema unido al dominio basta para el entorno individual. Los demás serían iguales cambiando el nombre y el grupo.

## Windows 11 · PC-ADMIN01

| | |
|---|---|
| VM | `administracion-AlexSoler`: 2 vCPU, 4 GB, 80 GB, `lan_grupo3` |
| SO | Windows 11 Pro 23H2, compilación **22631.2861** (de diciembre de 2023) |
| Origen | `w11.iso` (SHA-256 calculado; integridad N/C, ver [01-imagenes](01-imagenes-y-requisitos.md)) |
| Requisitos | TPM 2.0, arranque seguro, 4 GB, 64 GB: la VM los cumple con el TPM virtual y EFI de VirtualBox 7 |

### Usuarios

- `Administracion-AlexS`: la cuenta local que se creó al instalar, **sin contraseña**. La dejé deshabilitada para que nadie entre al equipo sin autenticarse en el dominio.
- `Administrador` local: habilitado y con contraseña, para emergencias si se pierde la relación con el dominio.
- Usuarios del dominio: `ALEXSOLER\administracion` (grupo `G_Administracion`) es el usuario de trabajo. `adm.alex` es administrador del equipo porque está en "Admins. del dominio".

### Red

| Parámetro | Valor |
|---|---|
| IP | 192.168.30.198/24 por **DHCP** del MikroTik (un puesto de usuario no necesita IP fija) |
| Puerta | 192.168.30.1 |
| DNS | **192.168.30.21 (DC)** y 192.168.30.1: los reparte el DHCP, por eso encuentra el dominio sin tocar nada |

### Unión al dominio

[w11-unir-dominio.ps1](../../scripts/w11-unir-dominio.ps1): comprueba que resuelve `alexsoler.lan` y el registro SRV `_ldap._tcp.dc._msdcs`, y después `Add-Computer`. Tras reiniciar:

```
usuario: alexsoler\administracion     grupos: ALEXSOLER\G_Administracion
equipo: PC-ADMIN01  dominio: alexsoler.lan  parte del dominio: True
nltest /dsgetdc:alexsoler.lan  →  DC: \\DC01-ALEX.alexsoler.lan  (192.168.30.21)
```

Desde el DC el equipo aparece en `OU=Equipos,OU=Empresa` (gracias a `redircmp`). Evidencias: [w11-union-dominio.txt](../../evidencias/tasca5/w11-union-dominio.txt), [w11-dominio-verificacion.txt](../../evidencias/tasca5/w11-dominio-verificacion.txt).

### Copias: qué sí y qué no

- **Sí**: Escritorio, Documentos y Descargas de cada perfil, con `robocopy /MIR` al recurso SMB del NAS (`\\truenas\copias-windows\PC-ADMIN01`) cada día ([w11-copias.ps1](../../scripts/w11-copias.ps1)).
- **No**: Windows ni los programas. Un puesto se reinstala o se clona en menos tiempo del que se tarda en restaurar 80 GB, y la configuración le llega del dominio. Lo único irrecuperable son los ficheros del usuario.

## Debian 13 · pc-informatica

| | |
|---|---|
| VM | `informatica-linux-AlexSoler`: 2 vCPU, 2 GB, 20 GB, `lan_grupo3`, firmware BIOS |
| SO | Debian 13 con GNOME, actualizado de 13.1 a **13.8** |
| Origen | `debian-13.1.0-amd64-netinst.iso`, **SHA-256 verificado** |

Instalación desatendida con `VBoxManage unattended`. Me dio dos problemas: con EFI la ISO auxiliar que genera VirtualBox (basada en isolinux) no arranca, así que la pasé a BIOS; y el *preseed* no aplicó mi selección de paquetes (instaló GNOME, pero no SSH ni SSSD). Los instalé después y actualicé el sistema.

### Usuarios

- `alexsoler`: el local que crea la instalación. Administra con `su -`.
- Usuarios del dominio: solo pueden entrar los del grupo **G_Informatica** y `adm.alex` (`realm permit`), y G_Informatica tiene `sudo`.

### Red

IP por DHCP con **reserva** en el MikroTik (MAC 08:00:27:AA:51:50 → 192.168.30.150), porque el NAS tiene que encontrarlo para hacerle copias. DNS 192.168.30.21 y 192.168.30.1, búsqueda `alexsoler.lan` (todo por DHCP).

### Unión al dominio

[linux-unir-dominio.sh](../../scripts/linux-unir-dominio.sh): hora sincronizada con el DC (Kerberos no admite más de 5 minutos de diferencia), `realm join` con realmd + SSSD, nombres de usuario sin `@dominio` y carpeta personal automática.

```
$ ssh a.soler@pc-informatica       (Informática)  → entra, ticket Kerberos krbtgt/ALEXSOLER.LAN
$ ssh p.ferrer@pc-informatica      (Comercial)    → Permission denied
```

Un fallo que tuve: `sssd` se quedó en *start-limit-hit* porque cada `realm permit` lo reinicia y al tercero systemd lo bloquea. Se arregla con `systemctl reset-failed sssd`. Evidencias: [linux-union-dominio.txt](../../evidencias/tasca5/linux-union-dominio.txt), [linux-login-usuario-dominio.txt](../../evidencias/tasca5/linux-login-usuario-dominio.txt).

### Copias: qué sí y qué no

- **Sí**: `/etc` y la lista de paquetes, que se lleva el NAS cada noche (2047 ficheros en la primera copia).
- **No**: el `/home` de los usuarios del dominio en local. En la empresa iría en una carpeta de red del servidor de datos, que es la que se copia.
