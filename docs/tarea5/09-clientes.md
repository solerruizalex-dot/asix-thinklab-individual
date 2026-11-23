# Clientes: Windows 11 (Administración) y Debian (Informática)

El enunciado pide los cinco departamentos; con uno de cada sistema unido al dominio basta para el entorno individual. Los demás serían iguales cambiando el nombre y el grupo.

## Windows 11 · PC-ADMIN01

| | |
|---|---|
| VM | `administracion-AlexSoler`: 2 vCPU, 4 GB, 80 GB, `lan_grupo3` |
| SO | Windows 11 Pro 23H2: estaba en la compilación 22631.2861 (diciembre de 2023), **actualizado a 22631.6199** |
| Origen | `w11.iso` (SHA-256 calculado; integridad N/C, ver [01-imagenes](01-imagenes-y-requisitos.md)) |
| Requisitos | TPM 2.0, arranque seguro, 4 GB, 64 GB: la VM los cumple con el TPM virtual y EFI de VirtualBox 7 (`Get-Tpm` → presente y listo; `Confirm-SecureBootUEFI` → True; [w11-usuarios-requisitos.txt](../../evidencias/tasca5/w11-usuarios-requisitos.txt)) |

### Actualización

Estaba casi dos años sin parches. Lo actualicé con [windows-actualizar.ps1](../../scripts/windows-actualizar.ps1), que usa la API de Windows Update que trae el propio sistema (sin módulos externos) y se lanza como tarea programada de SYSTEM ([w11-actualizacion.txt](../../evidencias/tasca5/w11-actualizacion.txt)):

| Pasada | Qué instaló | Tiempo |
|---|---|---|
| 1 | Acumulativa **KB5068865** (2025-11, la última de 23H2), plataforma de seguridad, firmas de Defender y la herramienta de software malintencionado | 12 min + reinicio (unos 5 minutos hasta volver a responder) |
| 2 | Acumulativa de .NET Framework **KB5066133** | 1 min + reinicio |

Resultado: **22631.2861 → 22631.6199**, y el equipo sigue en el dominio (`Test-ComputerSecureChannel` → True; `nltest /sc_query` → `NERR_Success`).

Lo único que queda pendiente es **Windows 11 25H2**, y el script lo omite a propósito: es un cambio de versión, no un parche. Hay que tenerlo en cuenta porque la 23H2 Pro dejó de recibir actualizaciones en noviembre de 2025 (la KB5068865 es la última). Antes de pasar los puestos a 25H2 lo probaría en una VM clonada, comprobando el dominio y las aplicaciones.

### Usuarios

Comprobado con `Get-LocalUser` y `Get-LocalGroupMember Administradores`:

| Cuenta | Estado | Administrador del equipo |
|---|---|---|
| `Administracion-AlexS` (local, la de la instalación) | Habilitada; **sin contraseña hasta el 23/11**, ahora con contraseña obligatoria | Sí |
| `Administrador` (local integrada) | Habilitada, con contraseña. La activé para administrar el equipo desde el anfitrión | Sí |
| `ALEXSOLER\Admins. del dominio` (grupo, incluye `adm.alex`) | Del dominio | Sí: es lo que se usa para administrar |
| `ALEXSOLER\administracion` (G_Administracion) | Del dominio | No: es el usuario de trabajo |

**Riesgo que encontré y corregí**: `Administracion-AlexS` era administradora y **no tenía contraseña**, así que cualquiera con acceso físico entraba como administrador sin pasar por el dominio. Dudé entre deshabilitarla o ponerle contraseña. Elegí la contraseña porque es la cuenta con la que se instaló el equipo y es la puerta de entrada si un día el equipo pierde la relación de confianza con el dominio (sin red, sin DC). La puse desde el anfitrión con el administrador del dominio y obligué a que la cuenta la exija (`net user … /passwordreq:yes`); caduca a los 42 días como marca la directiva del dominio ([w11-cuenta-local-contrasena.txt](../../evidencias/tasca5/w11-cuenta-local-contrasena.txt)):

```
Set-LocalUser -Name 'Administracion-AlexS' -Password (ConvertTo-SecureString '…' -AsPlainText -Force)
net user Administracion-AlexS /passwordreq:yes
→ PasswordRequired: True · último cambio 23/11/2026 9:47 · expira 04/01/2027
```

### Red

| Parámetro | Valor |
|---|---|
| IP | 192.168.36.200/24 por **DHCP** del MikroTik (un puesto de usuario no necesita IP fija). Con la red anterior tenía la .30.198; al cambiar de red recibió la .36.200 y sigue unido al dominio |
| Puerta | 192.168.36.1 |
| DNS | **192.168.36.21 (DC)** y 192.168.36.1: los reparte el DHCP, por eso encuentra el dominio sin tocar nada |

### Unión al dominio

[w11-unir-dominio.ps1](../../scripts/w11-unir-dominio.ps1): comprueba que resuelve `alexsoler.lan` y el registro SRV `_ldap._tcp.dc._msdcs`, y después `Add-Computer`. Tras reiniciar:

```
usuario: alexsoler\administracion     grupos: ALEXSOLER\G_Administracion
equipo: PC-ADMIN01  dominio: alexsoler.lan  parte del dominio: True
nltest /dsgetdc:alexsoler.lan  →  DC: \\DC01-ALEX.alexsoler.lan  (192.168.36.21)
```

Desde el DC el equipo aparece en `OU=Equipos,OU=Empresa` (gracias a `redircmp`). Evidencias: [w11-union-dominio.txt](../../evidencias/tasca5/w11-union-dominio.txt), [w11-dominio-verificacion.txt](../../evidencias/tasca5/w11-dominio-verificacion.txt).

### Copias: qué sí y qué no

- **Sí**: Escritorio, Documentos y Descargas de cada perfil, con `robocopy /MIR` al recurso SMB del NAS (`\\truenas\copias-windows\PC-ADMIN01`) todos los días a las 21:00 con la tarea programada `Copia datos al NAS` como SYSTEM ([w11-copias.ps1](../../scripts/w11-copias.ps1)).
- Lo probé el 23/11 ([windows-tareas-copia.txt](../../evidencias/tasca5/windows-tareas-copia.txt)): creé un documento en Documentos del usuario de dominio `administracion`, lancé la tarea (7 s, resultado 0) y apareció en el NAS. Después **lo borré del equipo y lo recuperé** desde el NAS en 0,1 s, con el mismo SHA-256 que el original. El usuario conserva control total sobre él por herencia de la carpeta, aunque el propietario pasa a ser *Administradores* porque lo restauré como administrador.
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

IP por DHCP con **reserva** en el MikroTik (MAC 08:00:27:AA:51:50 → 192.168.36.150), porque el NAS tiene que encontrarlo para hacerle copias. DNS 192.168.36.21 y 192.168.36.1, búsqueda `alexsoler.lan` (todo por DHCP).

### Unión al dominio

[linux-unir-dominio.sh](../../scripts/linux-unir-dominio.sh): hora sincronizada con el DC (Kerberos no admite más de 5 minutos de diferencia), `realm join` con realmd + SSSD, nombres de usuario sin `@dominio` y carpeta personal automática.

```
$ ssh a.soler@pc-informatica       (Informática)  → entra, ticket Kerberos krbtgt/ALEXSOLER.LAN
$ ssh p.ferrer@pc-informatica      (Comercial)    → Permission denied
```

Un fallo que tuve: `sssd` se quedó en *start-limit-hit* porque cada `realm permit` lo reinicia y al tercero systemd lo bloquea. Se arregla con `systemctl reset-failed sssd`. Evidencias: [linux-union-dominio.txt](../../evidencias/tasca5/linux-union-dominio.txt), [linux-login-usuario-dominio.txt](../../evidencias/tasca5/linux-login-usuario-dominio.txt).

### Copias: qué sí y qué no

- **Sí**: `/etc` y la lista de paquetes, que se lleva el NAS cada noche (2047 ficheros en la primera copia, [linux-cliente-primera-copia.txt](../../evidencias/tasca5/linux-cliente-primera-copia.txt)).
- **No**: el `/home` de los usuarios del dominio en local. En la empresa iría en una carpeta de red del servidor de datos, que es la que se copia.
