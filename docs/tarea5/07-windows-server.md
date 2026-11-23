# Windows Server 2025 · controlador de dominio DC01-ALEX

## Instalación y versión

- ISO de evaluación en español (`26100.32230...SERVER_EVAL_x64FRE_es-es.iso`), descargada del *Evaluation Center* de Microsoft. Microsoft enseña el hash en la página de descarga y no lo guardé: integridad **N/C**. La forma de comprobarlo sería `Get-FileHash` y compararlo con el que muestra esa página.
- Requisitos: x64 con SLAT, 2 GB de RAM mínimo para la versión con escritorio y 32 GB de disco. La VM tiene 2 vCPU, 4 GB (bajados desde 8) y 50 GB.
- La VM estaba creada pero **vacía** (el disco ocupaba 404 KB). La instalé de forma desatendida con `VBoxManage unattended install` (imagen 2: Standard con experiencia de escritorio).
- Versión comprobada: **Windows Server 2025 Standard Evaluation, 10.0.26100**, idioma es-ES.

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
| IP | **192.168.30.21/24 estática** (un DC nunca por DHCP: los clientes lo buscan por DNS) |
| Puerta de enlace | 192.168.30.1 |
| DNS | 127.0.0.1 (él mismo) y 192.168.30.1 |
| Reenviadores DNS | 192.168.30.1 y 1.1.1.1 |

Script: [dc-01-red-y-dominio.ps1](../../scripts/dc-01-red-y-dominio.ps1). Pruebas de ping, rutas y tracert: [red-por-maquina.txt](../../evidencias/tasca4/red-por-maquina.txt).

## Dominio alexsoler.lan

- Roles AD DS y DNS. Nombre NetBIOS `ALEXSOLER`, nivel funcional de bosque y dominio 2016.
- OUs: `Empresa` › Dirección, Administración, Comercial, Producción, Informática, Equipos, Servidores. Con `redircmp` los equipos nuevos caen en `OU=Equipos` en vez de en `Computers`, así se les pueden aplicar directivas.
- Zona inversa 192.168.30.0/24 y registros A de todos los equipos con IP fija (routers, NAS, nodos, serveis, dades).
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
| **Estado del sistema** (AD, SYSVOL, registro, arranque) | `wbadmin start systemstatebackup` a un disco local dedicado `E:` (25 GB) y después `robocopy` al NAS | Es lo que hace falta para recuperar el dominio |
| Exportaciones legibles: todas las GPO (`Backup-GPO`), usuarios y OUs (CSV), zona DNS | Directamente al recurso SMB del NAS | Para recuperar un objeto suelto sin restaurar el DC entero |
| **No** hago imagen completa de C: | — | 24 GB que se tarda más en restaurar por USB que en reinstalar Windows; lo valioso es el estado del sistema |

Tarea programada `Copia DC al NAS` todas las noches a las 21:30 como SYSTEM ([dc-03-copias.ps1](../../scripts/dc-03-copias.ps1), [dc-04-tarea-programada.ps1](../../scripts/dc-04-tarea-programada.ps1)).

### La copia de estado del sistema: lenta, pero funciona

Directamente contra el recurso SMB del NAS no avanzaba (1,6 MB en 30 minutos). Le añadí un disco local `E:` de 25 GB solo para copias ([dc-05-disco-copias.ps1](../../scripts/dc-05-disco-copias.ps1)), y la copia se hace ahí y luego se replica al NAS.

Resultado de la ejecución del 23/11 ([dc-copia-estado-sistema.txt](../../evidencias/tasca5/dc-copia-estado-sistema.txt)):

| Hora | Qué pasa |
|---|---|
| 01:48:32 | Empieza (evento 1). Primero copia la partición EFI (46 MB, en 1 minuto) y hace la instantánea VSS de C: |
| 01:49 → 02:15 | **Enumera los ficheros** del estado del sistema: unos 184.000, a ~25 ficheros por segundo. No escribe nada |
| 02:15 → 02:29 | Copia: imagen de C: de **13,2 GB** |
| 02:29:29 | **Evento 4: "La operación de copia de seguridad finalizó correctamente"** |
| 02:30:51 | robocopy al NAS terminado: 13 GB que en el NAS ocupan 8 GB (compresión LZ4, 1,61×) |

`wbadmin get versions` → *Se puede recuperar: Volúmenes, Archivos, Aplicaciones, Estado del sistema*. **41 minutos en total.**

Por qué es tan lenta la enumeración (lo medí durante la copia):

- El disco del anfitrión está casi ocioso (13 % de ocupación media) y wbengine apenas usa CPU.
- El proceso que más CPU gasta en el DC es **MsMpEng (Defender)**: 1.311 s de CPU frente a 240 s de wbengine. Analiza cada fichero que la copia toca.
- La solución sería una exclusión de Defender para el proceso de copia, pero eso reduce la protección del servidor y es una decisión que no tomo yo solo: la dejo propuesta. Como la copia es de noche, 41 minutos son aceptables.

### Un error en mi script que encontré gracias a esto

Al cancelar una copia a medias, mi log decía *"wbadmin: La operación se completó correctamente"*: el visor de eventos, en cambio, decía **evento 8, cancelada**. Mi script buscaba la palabra "correctamente" en la salida de wbadmin, y esa frase la escribe también cuando la orden termina aunque la copia no se haya hecho. Lo corregí: ahora se fía del **código de salida** de wbadmin y, si no es 0, lo apunta como fallo y **no** replica al NAS una copia incompleta. Lección: comprobar una copia mirando el resultado real (versiones y eventos), no el texto del log.
