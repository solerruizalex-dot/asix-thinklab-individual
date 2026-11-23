#!/usr/bin/env python3
"""medir-anfitrion.py - Álex Soler Ruiz

Mide el equipo anfitrión mientras trabajan las VMs, sin instalar nada (lee /proc):
CPU (usuario, sistema, espera de disco), memoria y swap, disco (MB/s y % de tiempo ocupado)
y red. Imprime una línea cada INTERVALO segundos y un resumen con medias y máximos.

uso: medir-anfitrion.py SEGUNDOS ETIQUETA [DISCO] [INTERVALO]
     medir-anfitrion.py 60 "bloque virtualizacion en reposo" sdb 5
"""
import sys, time

DUR = int(sys.argv[1]); ETIQ = sys.argv[2]
DISCO = sys.argv[3] if len(sys.argv) > 3 else "sdb"
INT = int(sys.argv[4]) if len(sys.argv) > 4 else 5


def cpu():
    v = list(map(int, open("/proc/stat").readline().split()[1:8]))
    return v  # user nice system idle iowait irq softirq


def mem():
    m = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo")}
    usada = (m["MemTotal"] - m["MemAvailable"]) / 1024
    swap = (m["SwapTotal"] - m["SwapFree"]) / 1024
    return usada, m["MemAvailable"] / 1024, swap


def disco():
    for l in open("/proc/diskstats"):
        p = l.split()
        if p[2] == DISCO:
            return int(p[5]), int(p[9]), int(p[12])  # sect leidos, sect escritos, ms ocupado
    raise SystemExit(f"no encuentro el disco {DISCO}")


def red():
    rx = tx = 0
    for l in open("/proc/net/dev").readlines()[2:]:
        nom, d = l.split(":", 1)
        if nom.strip() in ("lo",) or nom.strip().startswith(("docker", "vbox")):
            continue
        d = d.split(); rx += int(d[0]); tx += int(d[8])
    return rx, tx


def carga():
    return float(open("/proc/loadavg").read().split()[0])


print(f"### {ETIQ}  ({time.strftime('%F %T')}, {DUR} s, disco {DISCO})")
print(f"{'hora':8} {'us%':>5} {'sy%':>5} {'wa%':>5} {'id%':>5} {'RAM MB':>7} {'libre':>6} {'swap':>5} "
      f"{'lee MB/s':>8} {'esc MB/s':>8} {'disco%':>6} {'red Mb/s':>8} {'carga':>5}")
filas = []
c0, d0, r0, t0 = cpu(), disco(), red(), time.time()
for _ in range(DUR // INT):
    time.sleep(INT)
    c1, d1, r1, t1 = cpu(), disco(), red(), time.time()
    dc = [b - a for a, b in zip(c0, c1)]; tot = sum(dc) or 1
    us = 100 * (dc[0] + dc[1]) / tot; sy = 100 * (dc[2] + dc[5] + dc[6]) / tot
    wa = 100 * dc[4] / tot; idl = 100 * dc[3] / tot
    dt = t1 - t0
    lee = (d1[0] - d0[0]) * 512 / dt / 1e6; esc = (d1[1] - d0[1]) * 512 / dt / 1e6
    ocu = min(100, (d1[2] - d0[2]) / (dt * 10))
    net = ((r1[0] - r0[0]) + (r1[1] - r0[1])) * 8 / dt / 1e6
    u, libre, sw = mem(); ld = carga()
    f = (us, sy, wa, idl, u, libre, sw, lee, esc, ocu, net, ld); filas.append(f)
    print(f"{time.strftime('%T'):8} {us:5.1f} {sy:5.1f} {wa:5.1f} {idl:5.1f} {u:7.0f} {libre:6.0f} {sw:5.0f} "
          f"{lee:8.1f} {esc:8.1f} {ocu:6.1f} {net:8.2f} {ld:5.2f}", flush=True)
    c0, d0, r0, t0 = c1, d1, r1, t1

med = [sum(x) / len(filas) for x in zip(*filas)]; mx = [max(x) for x in zip(*filas)]
fmt = lambda v: (f"{v[0]:5.1f} {v[1]:5.1f} {v[2]:5.1f} {v[3]:5.1f} {v[4]:7.0f} {v[5]:6.0f} {v[6]:5.0f} "
                 f"{v[7]:8.1f} {v[8]:8.1f} {v[9]:6.1f} {v[10]:8.2f} {v[11]:5.2f}")
print(f"{'MEDIA':8} " + fmt(med))
print(f"{'MÁXIMO':8} " + fmt(mx))
print()
