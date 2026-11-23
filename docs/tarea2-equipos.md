# Tarea 2 · Equipos: inventario de clase y de casa

## Cómo lo he hecho

Llevo el proyecto en un SSD (Kingston SA400 de 480 GB) que conecto por USB **al portátil de clase y al PC de casa**: es el mismo sistema (Linux Mint 22.3) arrancando en dos equipos distintos. Eso me ha permitido algo útil: cada vez que arranca, el kernel apunta en su registro el hardware que encuentra, así que tengo datos del portátil de clase aunque no lo tenga en casa.

- **PC de casa**: `inxi -Fxz`, `lscpu`, `lsblk`, `/sys` y los tests de este documento ([inventario-pc-casa-inxi.txt](../evidencias/tasca2/inventario-pc-casa-inxi.txt)).
- **Portátil de clase**: el registro del kernel de los arranques en el aula (`journalctl -k -b N`) ([inventario-portatil-clase-journal.txt](../evidencias/tasca2/inventario-portatil-clase-journal.txt)) y el historial de **33 arranques** entre el 19/10 y el 23/11 ([historial-arranques-hardware.txt](../evidencias/tasca2/historial-arranques-hardware.txt)).

## Inventario

| | Portátil de clase | PC de casa |
|---|---|---|
| Modelo | ASUS ExpertBook B3605CCA (portátil 16") | Torre con placa Gigabyte H470M DS3H |
| Firmware | BIOS B3605CCA.303 (06/2025), UEFI | AMI UEFI F3 (05/2020) |
| CPU | Intel Core Ultra 5 125H · **18 hilos** (el kernel activa 18 procesadores; según la ficha de Intel son 14 núcleos: 4P + 8E + 2LP) | Intel Core i5-10400F · 6 núcleos / **12 hilos**, 2,9–4,3 GHz |
| Virtualización | VT-x + VT-d (el kernel activa VT-d para la gráfica) | VT-x con EPT (`vmx` en los flags) |
| RAM | **32 GB** (31,6 GB útiles) | **16 GB** DDR4 (15,5 GiB útiles) + 8 GB de swap + zram |
| Disco interno | NVMe con 7 particiones (el sistema del instituto) | SSD SATA Kingston SA400 480 GB (el de casa) |
| Disco del proyecto | Mi SSD por USB | Mi SSD por USB |
| Caja USB del SSD | Ugreen (ASMedia, USB 3.2 Gen2, 10 Gbit/s) hasta el 10/11; **JMicron JMS578 (USB 3.0, 5 Gbit/s)** desde el 12/11 | JMicron JMS578 (USB 3.0, 5 Gbit/s), UAS |
| Red | Intel PRO/1000 (`eno1`, e1000e), **1000 Mbit/s full dúplex** en todos los arranques + Wi-Fi/Bluetooth Realtek | Ethernet integrada (`eno1`), 1000 Mbit/s full dúplex |
| Gráfica | Intel integrada (driver i915) | NVIDIA GeForce RTX 5060 |
| Periféricos | Webcam FHD, lector de tarjetas Realtek, ratón Dell MS116 USB | Teclado, ratón, adaptador PlayStation Link (audio) |
| Alimentación | Batería + adaptador AC | Fuente ATX |
| Sistema | Linux Mint 22.3, kernel 6.8 (el mismo SSD) | Igual |

Dos arranques del registro (23/10 y 2/11, a primera hora) son de un tercer equipo que se identifica como **APD ALDA+** (placa B85M-DS3H-A): por la hora, un ordenador del aula.

## Comparación y cuellos de botella previstos

| Recurso | Clase | Casa | Cuello de botella previsto |
|---|---|---|---|
| RAM | 32 GB | 16 GB | **En casa**: las VMs piden 36 GB tal como estaban |
| CPU | 18 hilos | 12 hilos | Ninguno: 2 vCPU por VM caben en los dos |
| Disco | SSD por USB | El mismo SSD por USB 3.0 | **En los dos**: todas las VMs leen y escriben en un único SSD SATA a través de un puente USB |
| Red | 1 Gbit/s | 1 Gbit/s | Ninguno para el laboratorio (las VMs salen por NAT) |

## Tests de diagnóstico

El script [tests-equipo.sh](../scripts/tests-equipo.sh) hace los tres tests con herramientas que ya trae el sistema (sin instalar nada ni ser root), para poder repetirlo igual en los dos equipos. Siempre con **todas las VMs apagadas**, para tener una línea base limpia.

| Test | Herramienta | Qué mide |
|---|---|---|
| Memoria | Registro del kernel (errores MCE/EDAC) + escritura y verificación de 4 patrones (00, FF, 55, AA) sobre 2 GB con Python | Errores de memoria y ancho de banda aproximado |
| Disco | `dd` con `oflag=direct` / `iflag=direct` (sin caché): 1 GB secuencial y 4000 bloques de 4 KB con `dsync` | Velocidad secuencial y de escrituras pequeñas, que es lo que hacen las VMs |
| Red | `ping` (20 a la puerta de enlace y 20 a 1.1.1.1), descarga de 100 MB con `curl`, contadores de errores de la tarjeta | Latencia, pérdida, velocidad real y errores |

### Resultados en el PC de casa

Condiciones: 23/11/2026 a las 03:39, **ninguna VM encendida**, carga del sistema 0,17, 13 GB de RAM disponibles. Salida completa: [tests-pc-casa.txt](../evidencias/tasca2/tests-pc-casa.txt).

| Test | Resultado | Cómo lo interpreto |
|---|---|---|
| Errores de memoria en el kernel (MCE/EDAC) | **Ninguno** en este arranque ni en los 33 del historial | Sin indicios de RAM defectuosa |
| Patrones 00/FF/55/AA sobre 2 GB | **0 bloques con error**, 3,4 GB/s escribiendo y verificando | Correcto. No sustituye a memtest86+, que no está instalado y necesita reiniciar; lo haría si apareciera algún error |
| Disco: escritura secuencial 1 GB sin caché | **312 MB/s** | Cerca del máximo práctico de USB 3.0 (unos 400–450 MB/s) |
| Disco: lectura secuencial 1 GB sin caché | **387 MB/s** | El SSD SATA podría dar ~500 MB/s: el límite es el USB 3.0 |
| Disco: 4000 escrituras de 4 KB con sincronización | **2,5 MB/s (~620 operaciones/s)** | **Muy bajo.** Es lo que hacen las VMs (sistemas de ficheros, bases de datos, Windows Update): muchas escrituras pequeñas que esperan confirmación. El puente USB + un SSD SATA de gama baja sin DRAM (el SA400) lo hacen mal |
| Errores de disco/USB en el registro | **Ninguno** | La caja JMicron funciona bien |
| Red: enlace | 1000 Mbit/s full dúplex, 0 errores en la tarjeta | Correcto |
| Red: latencia | 0,60 ms a la puerta de enlace, 10,2 ms a 1.1.1.1, 0 % de pérdida | Correcto y muy estable (desviación 0,02 ms y 0,15 ms) |
| Red: descarga de 100 MB | **38,1 MB/s (305 Mbit/s)** en 2,7 s | Es la velocidad de la conexión a Internet de casa, no de la tarjeta (1 Gbit/s) |

### Portátil de clase

No he podido pasar el script en el portátil esta noche porque está en el instituto: lo ejecutaré en la próxima clase con el mismo comando (`bash scripts/tests-equipo.sh > evidencias/tasca2/tests-portatil-clase.txt`). Lo que sí puedo dar con datos del portátil son los diagnósticos que quedaron en el registro:

- **Red**: en los 26 arranques en el portátil, el enlace sube siempre a **1000 Mbit/s full dúplex**. Ningún problema de cable ni de negociación.
- **Memoria**: **0 errores de hardware** (MCE) en todos los arranques.
- **Disco**: aquí sí apareció una avería (siguiente apartado).

## Avería detectada: errores de disco el 10/11

En el historial de arranques, el 10/11 a las 12:19 y a las 12:24 el kernel registró **72 y 11 errores** del disco: `uas_eh_abort_handler … CMD IN` sobre lecturas (`Read(10)`). Es decir, el sistema pedía datos al SSD y no llegaban a tiempo, así que el kernel abortaba la orden y la repetía.

**Causas posibles:**

1. El SSD se está estropeando.
2. La caja USB (Ugreen, chip ASMedia) o su cable fallan, o el modo UAS a 10 Gbit/s es inestable con este chip.

**Prueba que las distingue:** usar **el mismo SSD** con **otra caja**. Desde el 12/11 lo conecto siempre con una caja JMicron JMS578 (que ya había usado dos días en un PC del aula) y el resultado ha sido:

| | Caja Ugreen (ASMedia) | Caja JMicron JMS578 |
|---|---|---|
| Arranques | 21 (todos en el portátil de clase) | 12 (portátil de clase, PC de casa y un PC del aula) |
| Errores de E/S | **83** (todos el 10/11) | **0**, también esta noche con hasta 9 VMs y picos de 124 MB/s de escritura |

Si el problema fuera el SSD, seguiría dando errores en la otra caja. **Conclusión: la avería está en la caja o en su cable, no en el SSD.** La confirmaría del todo leyendo el SMART del SSD (`smartctl -a`, que necesita root) para ver que no tiene sectores reasignados, y probando la caja Ugreen con otro disco.

El precio de la solución es velocidad: la caja nueva es USB 3.0 (5 Gbit/s) en vez de 10 Gbit/s. Para un SSD SATA (máximo unos 550 MB/s) no se nota mucho: 5 Gbit/s dan unos 400–450 MB/s reales, y aquí he medido 387 MB/s leyendo.

## ¿Se confirman los cuellos de botella?

| Cuello de botella previsto | ¿Se confirma? | Dato que lo demuestra |
|---|---|---|
| **Disco** por USB | **Sí, y es el principal** | 312/387 MB/s en secuencial está bien, pero las escrituras pequeñas sincronizadas caen a **2,5 MB/s**. Con VMs, el disco llega al **81 %** de ocupación con picos de 124 MB/s (Tarea 7). El único bloqueo total del PC coincidió con dos VMs escribiendo a la vez (sin error en el registro, así que es una hipótesis) |
| **RAM** en casa | **Sí** | 13,4 GB usados de 15,5 con el bloque Proxmox; el DC y el Windows 11 no caben a la vez que ese bloque |
| CPU | **No** | La CPU libre media nunca ha bajado del 79 %, ni con dos VMs al 100 % |
| Red del equipo | **No** | Enlace de 1 Gbit/s sin errores; el límite es la conexión de casa (305 Mbit/s). El cuello de botella de red que sí apareció estaba **dentro** del laboratorio: la tarjeta emulada del MikroTik (Tarea 7) |
| Disco en clase | Previsto igual que en casa (mismo SSD y misma caja) | Lo confirmaré con el script en clase. Lo que sí está demostrado con el registro es que la **caja Ugreen** daba errores |

## Soluciones con el material que tengo

| Problema | Solución sin comprar nada | Solución con coste |
|---|---|---|
| RAM de casa (16 GB) | Ajustar la RAM de cada VM a lo que usa y trabajar por bloques (ver Tarea 7): de 36 GB asignados a un máximo de 10–11 GB por bloque | Ampliar a 32 GB (la placa tiene 4 ranuras) |
| Disco USB | No encender a la vez dos VMs que escriban mucho; discos thin pero vigilados | SSD NVMe en una caja USB 3.2 Gen2 **de calidad**, o llevar las VMs a un disco interno |
| Caja USB que falla | Cambiada por la JMicron | Caja nueva con buen chip y cable corto |
