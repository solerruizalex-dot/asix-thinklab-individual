# Tarea 2 · Equipos: inventario de clase y de casa

## Inventario

Uso el mismo SSD (Kingston SA400 480 GB) en clase y en casa. El inventario de casa lo saqué con `inxi`; el del portátil de clase, del registro del kernel del arranque que hizo este SSD en el aula el 19/11 (`journalctl -k -b -2`), porque el portátil no lo tengo en casa.

| | Portátil de clase | PC de casa |
|---|---|---|
| Modelo | ASUS ExpertBook B3605CCA (BIOS 303, 06/2025) | Gigabyte H470M DS3H (UEFI F3, 2020) |
| CPU | Intel Core Ultra 5 125H · 18 hilos | Intel Core i5-10400F · 6 núcleos / 12 hilos |
| Virtualización | VT-x | VT-x con EPT (flag `vmx`) |
| RAM | 32 GB (31,6 GB útiles) | 16 GB (15,5 GiB útiles) |
| Disco interno | NVMe (no lo uso para el proyecto) | — |
| Disco del proyecto | SSD por USB 3.0 (puente JMicron JMS578, UAS) | El mismo SSD por USB 3.0 (JMS578, UAS) |
| Red | Intel PRO/1000 (`eno1`) + Wi-Fi/Bluetooth Realtek | Ethernet integrada |
| Gráfica | Intel integrada (i915) | NVIDIA GeForce RTX 5060 |
| Alimentación | Batería + adaptador AC | Fuente ATX |

Evidencias: [inventario-pc-casa-inxi.txt](../evidencias/tasca2/inventario-pc-casa-inxi.txt) y [inventario-portatil-clase-journal.txt](../evidencias/tasca2/inventario-portatil-clase-journal.txt).

## Comparación y cuellos de botella

- **Disco**: en los dos equipos el sistema y las VMs van en un SSD SATA conectado por USB. Es el cuello de botella común: todas las VMs leen y escriben en el mismo disco a través de un puente USB. En casa se notó de verdad: el 22/11 a las 23:06, con el DC haciendo una copia `wbadmin`, TrueNAS, los routers y un nodo Proxmox arrancando, el PC se quedó congelado y no dejó ningún mensaje en el registro (ni falta de memoria ni error del kernel).
- **RAM**: en casa 16 GB para un entorno que pedía 36 GB tal como estaba asignado. En clase hay 32 GB, el doble de margen.
- **CPU**: el i5-10400F tiene 12 hilos; el Ultra 5 125H, 18. Ninguno de los dos ha sido el límite en lo que he medido.

## Soluciones según el material que tengo

- Trabajar por bloques de pocas VMs y no encender a la vez dos máquinas con mucha escritura (copia del DC + arranque de Proxmox).
- Ajustar la RAM de cada VM a lo que usa de verdad (ver Tarea 7).
- Mejora con coste: mover el disco de VMs a un SSD interno (SATA o NVMe) en lugar del USB.

## Tests de diagnóstico

Los tests de memoria, disco y red los dejé para hacerlos con todas las VMs apagadas, para tener una línea base limpia. **Están pendientes**; los añadiré en la versión v2 con la herramienta, las condiciones y el resultado de cada uno.
