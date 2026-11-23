# Windows Server 2025 · controlador de dominio DC01-ALEX

## Instalación y versión

- ISO de evaluación en español (`26100.32230...SERVER_EVAL_x64FRE_es-es.iso`), descargada del *Evaluation Center* de Microsoft. Microsoft enseña el hash en la página de descarga y no lo guardé: integridad **N/C**. La forma de comprobarlo sería `Get-FileHash` y compararlo con el que muestra esa página.
- Requisitos: x64 con SLAT, 2 GB de RAM mínimo para la versión con escritorio y 32 GB de disco. La VM tiene 2 vCPU, 4 GB (bajados desde 8) y 50 GB.
- La VM estaba creada pero **vacía** (el disco ocupaba 404 KB). La instalé de forma desatendida con `VBoxManage unattended install` (imagen 2: Standard con experiencia de escritorio).
- Versión comprobada: **Windows Server 2025 Standard Evaluation, 10.0.26100**, idioma es-ES.
- **Actualización** con [windows-actualizar.ps1](../../scripts/windows-actualizar.ps1) (API de Windows Update, como tarea de SYSTEM): actualización de seguridad de noviembre de 2026 **KB5131080**, .NET **KB5127690**, plataforma y firmas de Defender. 21 minutos de instalación y un reinicio de unos 4 minutos. Compilación **26100.32230 → 26100.33822**, y una nueva búsqueda da **0 pendientes**. Después del reinicio comprobé que NTDS, DNS, Netlogon, KDC y DFSR están en marcha y que `dcdiag` (servicios, anuncio, netlogons y roles FSMO) no da errores ([dc-actualizacion.txt](../../evidencias/tasca5/dc-actualizacion.txt)).

### Problemas al instalar

| Problema | Causa | Solución |
|---|---|---|
| *No bootable option or device was found* | Con EFI, el DVD de Windows pide "pulsa una tecla para arrancar desde el CD"; sin pantalla nadie la pulsa | Reiniciar y mandar pulsaciones de teclado con `keyboardputscancode` |
| `alexadmin` no podía ejecutar nada como administrador desde el anfitrión | UAC filtra el token de las cuentas administradoras que no son la integrada | Usar la cuenta `Administrador` integrada para la configuración inicial |
| Los nombres con tilde (Martí, Administración) salían rotos | PowerShell 5.1 lee los `.ps1` en UTF-8 sin BOM como ANSI | Guardar los scripts con BOM y recrear esos usuarios |
| `Add-ADGroupMember 'Domain Admins'` fallaba | En un Windows en español el grupo se llama "Admins. del dominio" | Buscar el grupo por su SID (termina en `-512`), que no cambia con el idioma |

## Usuarios de administración

- `Administrador`: la cuenta integrada. Solo para la promoción y emergencias.
- `adm.alex`: mi cuenta de administración del dominio (OU Informática, en "Admins. del dominio"). En el día a día no se trabaja con `Administrador`.
- Usuarios de prueba, uno por departamento, ficticios: `l.marti` (Dirección), `administracion`, `p.ferrer` (Comercial), `j.navarro` (Producción) y `a.soler` (Informática), cada uno en su grupo `G_<departamento>`.

Las contraseñas no están en los scripts: se pasan con las variables de entorno `CLAVE` y `CLAVE_INICIAL`.

## Red

| Parámetro | Valor |
|---|---|
| Adaptador | Intel PRO/1000 MT, renombrado a `LAN`, en `lan_grupo3` |
| IP | **192.168.36.21/24 estática** (un DC nunca por DHCP: los clientes lo buscan por DNS) |
| Puerta de enlace | 192.168.36.1 |
| DNS | 127.0.0.1 (él mismo) y 192.168.36.1 |
| Reenviadores DNS | 192.168.36.1 y 1.1.1.1 |

Script: [dc-01-red-y-dominio.ps1](../../scripts/dc-01-red-y-dominio.ps1). Pruebas de ping, rutas y tracert: [red-por-maquina.txt](../../evidencias/tasca4/red-por-maquina.txt).

## Dominio alexsoler.lan

- Roles AD DS y DNS. Nombre NetBIOS `ALEXSOLER`, nivel funcional de bosque y dominio 2016.
- OUs: `Empresa` › Dirección, Administración, Comercial, Producción, Informática, Equipos, Servidores. Con `redircmp` los equipos nuevos caen en `OU=Equipos` en vez de en `Computers`, así se les pueden aplicar directivas.
- Zona inversa 192.168.36.0/24 y registros A de todos los equipos con IP fija (routers, NAS, nodos, serveis, dades).
- Script: [dc-02-estructura.ps1](../../scripts/dc-02-estructura.ps1).

`dcdiag /q` da dos avisos que revisé ([dc-estado.txt](../../evidencias/tasca5/dc-estado.txt)):

- *DFSREvent* y *SystemLog*: errores de las primeras horas, mientras se promocionaba (registro DNS dinámico antes de que el DNS estuviera listo) y avisos de "no se pudo actualizar DBX/SBAT" porque la VM no tiene **arranque seguro**. No afectan al dominio; en un servidor físico activaría Secure Boot.

### Qué es un dominio y qué aporta

Un dominio es una base de datos central (Active Directory) con los usuarios, los equipos y las reglas de la empresa, guardada en el controlador de dominio. Lo que aporta frente a equipos sueltos:

- **Una sola cuenta por persona** para entrar en cualquier equipo del dominio. Si alguien se va, se desactiva una cuenta y no hay que ir equipo por equipo.
- **Permisos por grupos**: doy acceso a la carpeta de Comercial al grupo `G_Comercial`, no a cada persona.
- **Directivas de grupo (GPO)**: configuración aplicada a todos los equipos a la vez (contraseñas, bloqueo de pantalla, mapeo de unidades…).
- **DNS integrado**: los equipos se encuentran por nombre.
- El inconveniente: si el DC cae, nadie nuevo puede iniciar sesión. Por eso en la empresa habría **dos DC** y las copias del estado del sistema son lo más importante de este servidor.

Lo comprobé con los dos clientes: el Windows 11 inicia sesión con un usuario del dominio y el Debian deja entrar a `a.soler` (Informática) pero no a `p.ferrer` (Comercial) ([09-clientes](09-clientes.md)).

## Copias: qué sí y qué no

| Qué | Cómo | Por qué |
|---|---|---|
| **Estado del sistema** (AD, SYSVOL, registro, arranque) | `wbadmin start systemstatebackup` a un disco local dedicado `E:` (50 GB, ver abajo por qué) y después `robocopy` al NAS | Es lo que hace falta para recuperar el dominio |
| Exportaciones legibles: todas las GPO (`Backup-GPO`), usuarios y OUs (CSV), zona DNS | Directamente al recurso SMB del NAS | Para recuperar un objeto suelto sin restaurar el DC entero |
| **No** hago imagen completa de C: | — | 24 GB que se tarda más en restaurar por USB que en reinstalar Windows; lo valioso es el estado del sistema |

Tarea programada `Copia DC al NAS` todas las noches a las 21:30 como SYSTEM, con último resultado 0 ([windows-tareas-copia.txt](../../evidencias/tasca5/windows-tareas-copia.txt)) ([dc-03-copias.ps1](../../scripts/dc-03-copias.ps1), [dc-04-tarea-programada.ps1](../../scripts/dc-04-tarea-programada.ps1)).

### La copia de estado del sistema: lenta, pero funciona

Directamente contra el recurso SMB del NAS no avanzaba (1,6 MB en 30 minutos). Le añadí un disco local `E:` solo para copias (empezó con 25 GB) ([dc-05-disco-copias.ps1](../../scripts/dc-05-disco-copias.ps1)), y la copia se hace ahí y luego se replica al NAS.

Resultado de la ejecución del 23/11 ([dc-copia-estado-sistema.txt](../../evidencias/tasca5/dc-copia-estado-sistema.txt)):

| Hora | Qué pasa |
|---|---|
| 01:48:32 | Empieza (evento 1). Primero copia la partición EFI (46 MB, en 1 minuto) y hace la instantánea VSS de C: |
| 01:49 → ~02:15 | **Enumera los ficheros** del estado del sistema: `wbadmin get status` iba por 182.820 a las 02:11 y por 184.791 un minuto después (unos 25–30 por segundo). No escribe nada |
| ~02:15 → 02:29 | Copia (`wbadmin get status`: *haciendo copia de los archivos notificados por 'System Writer'*, 85 % a las 02:25): imagen de C: de **13,2 GB** |
| 02:29:29 | **Evento 4: "La operación de copia de seguridad finalizó correctamente"** |
| 02:30:51 | robocopy al NAS terminado: 13 GB que en el NAS ocupan 8 GB (compresión LZ4, 1,61×) |

`wbadmin get versions` → *Se puede recuperar: Volúmenes, Archivos, Aplicaciones, Estado del sistema*. **41 minutos en total.**

Por qué es tan lenta la enumeración ([dc-copia-diagnostico-lentitud.txt](../../evidencias/tasca5/dc-copia-diagnostico-lentitud.txt)):

- El disco del anfitrión estaba casi ocioso: 13 % de ocupación media, medido en el primer intento (que cancelé), en esta misma fase. En el intento bueno, wbengine tenía 0 MB leídos y escritos en sus contadores, y casi no gastaba CPU (de 235 a 239 s en dos minutos).
- El proceso que más CPU gasta en el DC es **MsMpEng (Defender)**: 1.311 s de CPU frente a 240 s de wbengine. Analiza cada fichero que la copia toca.
- **Solución aplicada (23/11)**: una exclusión de Defender **acotada**, solo para el motor de copia `wbengine.exe` y la carpeta donde escribe (`E:\WindowsImageBackup`) ([dc-05-exclusion-defender.ps1](../../scripts/dc-05-exclusion-defender.ps1)). No excluyo C: ni las carpetas del sistema: si un fichero malicioso llega al servidor, Defender lo sigue viendo cuando lo usa cualquier otro proceso. La protección en tiempo real sigue activa.

| | Sin exclusión (22/11, PC de casa) | Con exclusión (23/11, portátil de clase) |
|---|---|---|
| Copia del estado del sistema | ~41 min | **10 min 32 s** (09:46:52 → 09:57:24) |
| Total con la réplica al NAS | 42 min | **12 min 26 s** |
| CPU de Defender (MsMpEng) durante la copia | 1.311 s | **~11 s** |

Tengo que ser honesto con la comparación: la segunda medida es en otro equipo (el portátil de clase tiene 32 GB y su USB rinde algo más, ver [Tarea 2](../tarea2-equipos.md)), así que no todo el ahorro es de la exclusión. Lo que sí es de la exclusión es que Defender pasa de gastar 1.311 s de CPU a 11 s: deja de analizar cada fichero que lee la copia ([dc-copia-diagnostico-lentitud.txt](../../evidencias/tasca5/dc-copia-diagnostico-lentitud.txt)).

### Cambio de red del DC (23/11)

Al pasar la LAN a 192.168.36.0/24 el DC fue el equipo más delicado: es el DNS de todos. Lo cambié con [dc-06-cambio-red.ps1](../../scripts/dc-06-cambio-red.ps1), lanzado con `VBoxManage guestcontrol` para no depender de la red mientras la cambiaba:

- IP .36.21, puerta .36.1 y DNS él mismo + MikroTik.
- El servidor DNS **escuchaba solo en la IP vieja** (`ListeningIPAddress`): si no lo cambio, el DC tiene IP nueva pero no contesta consultas.
- Zona inversa nueva `36.168.192.in-addr.arpa`, registros A de los equipos con IP fija (con su PTR) y fuera la zona vieja.
- Los scripts de `C:\scripts` apuntaban al NAS por IP.
- `ipconfig /registerdns` y reiniciar Netlogon, para que el DC vuelva a registrar sus registros SRV: `_ldap._tcp.dc._msdcs.alexsoler.lan → dc01-alex.alexsoler.lan`.

El primer intento falló con el error 9607 al crear el primer registro justo después de reiniciar el servicio DNS; con una espera de 20 s, bien.

Después lancé la copia nocturna a mano para comprobar que llega al NAS en su IP nueva ([dc-copia-red-nueva.txt](../../evidencias/tasca5/dc-copia-red-nueva.txt)). Las exportaciones llegaron bien a `\\192.168.36.20`, pero **la copia del estado del sistema falló** (código -4, evento 7) y mi script no la replicó al NAS, como debe. El fichero de errores que indica wbadmin estaba vacío, así que fui a mirar el disco: a `E:` le quedaban **1,4 GB libres** de 25. La copia de la mañana ocupa 19,7 GB y wbadmin conserva la versión anterior mientras escribe la nueva, además de 3,6 GB de instantáneas VSS: no cabían dos copias. Con el DC apagado amplié el disco a 50 GB (`VBoxManage modifymedium --resize`) y extendí la partición (`Resize-Partition`). La segunda vez salió bien:

| | Resultado |
|---|---|
| 12:10:12 | Empieza. Evento 24: copia completa, porque el volumen ha cambiado de tamaño |
| 12:22:18 | **Evento 4, correcta**; `wbadmin get versions` muestra la de las 12:10 |
| 12:24:45 | robocopy al NAS terminado. **14 min 33 s** en total; quedan 29,9 GB libres en `E:` |

La lección es dimensionar el disco de copias para **dos copias más las instantáneas**, no para una. Con 50 GB caben con margen; si las copias crecen, la siguiente medida sería limitar el espacio de VSS en `E:` (`vssadmin resize shadowstorage`).

### Un error en mi script que encontré gracias a esto

Al cancelar una copia a medias, mi log decía *"wbadmin: La operación se completó correctamente"*: el visor de eventos, en cambio, decía **evento 8, cancelada**. Mi script buscaba la palabra "correctamente" en la salida de wbadmin, y esa frase la escribe también cuando la orden termina aunque la copia no se haya hecho. Lo corregí: ahora se fía del **código de salida** de wbadmin y, si no es 0, lo apunta como fallo y **no** replica al NAS una copia incompleta. Lección: comprobar una copia mirando el resultado real (versiones y eventos), no el texto del log.
