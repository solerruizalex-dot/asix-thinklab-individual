#!/usr/bin/env python3
"""generar-diagrama.py - Álex Soler Ruiz

Esquema de red del entorno individual. Una sola descripción (cajas y conexiones) genera:
  red-individual.drawio  -> se abre y se edita en draw.io / app.diagrams.net
  red-individual.svg     -> la misma geometría, para convertirla a PNG
uso: python3 generar-diagrama.py   (en la carpeta diagramas/)
"""
from xml.sax.saxutils import escape, quoteattr

# colores: (relleno, borde)
ROJO = ("#fde2df", "#c0392b"); AZUL = ("#dbe9f7", "#2c6e9b"); NAR = ("#fdebd3", "#e67e22")
VERDE = ("#dcf3e3", "#27ae60"); GRIS = ("#f4f6f8", "#5b6770"); AMAR = ("#fff6db", "#b7950b")
CIAN = ("#e3f1f3", "#2a7f8f"); LILA = ("#efe3f6", "#8e44ad")

# grupos (contenedores): id, x, y, w, h, título, (relleno, borde), discontinuo
GRUPOS = [
    ("host", 30, 170, 1640, 880, "Anfitrión · VirtualBox 7.0.20 · grupo «ASIX-ThinkLAB Individual»", ("#ffffff", "#888888"), True),
    ("g_com", 110, 320, 1480, 150, "Servidores de comunicaciones (WAN en NAT de VirtualBox, IP por DHCP)", ("#fffafa", "#c0392b"), False),
    ("g_srv", 110, 610, 840, 270, "Servidores (IP fija · puerta 192.168.36.1 · DNS 192.168.36.21) · VMs independientes", ("#f8fbff", "#2c6e9b"), False),
    ("g_pve", 970, 610, 620, 140, "Clúster Proxmox VE 9.2.32 «grupo3-cluster» · 3 nodos, quórum 2/3 · sin VMs (solo demostración)", ("#fffaf3", "#e67e22"), False),
    ("g_cli", 970, 770, 620, 150, "Clientes (DHCP del MikroTik · DNS → DC) · unidos a alexsoler.lan", ("#f7fdf9", "#27ae60"), False),
]
# cajas: id, x, y, w, h, líneas (la primera en negrita), colores, forma
CAJAS = [
    ("inet", 735, 20, 230, 50, ["Internet"], CIAN, "ellipse"),
    ("aula", 660, 95, 380, 55, ["Red del instituto (172.16.222.0/24) o de casa", "salida del anfitrión"], GRIS, "rect"),
    ("nat", 690, 225, 320, 70, ["NAT de VirtualBox (uno por VM)", "10.0.2.0/24 · puerta 10.0.2.2"], AMAR, "rect"),
    ("mk", 140, 360, 440, 95, ["MikroTik-AlexSoler · RouterOS 7.24.6", "ether1 WAN 10.0.2.15 (DHCP)", "ether2 LAN 192.168.36.1/24",
                                "PUERTA DE ENLACE + DHCP .100–.200"], ROJO, "rect"),
    ("opn", 630, 360, 440, 95, ["OPNsense-AlexSoler · 26.7.9", "em0 WAN 10.0.2.15 (DHCP)", "em1 LAN 192.168.36.2/24",
                                 "router alternativo"], ROJO, "rect"),
    ("nft", 1120, 360, 440, 95, ["nftables-AlexSoler · Debian 13.8", "enp0s3 WAN 10.0.2.15 (DHCP)", "enp0s8 LAN 192.168.36.3/24",
                                  "router alternativo · salto SSH de administración"], ROJO, "rect"),
    ("sw", 110, 505, 1480, 60, ["Switch virtual · red interna de VirtualBox «lan_grupo3»", "LAN 192.168.36.0/24 · dominio alexsoler.lan"], CIAN, "rect"),
    ("dc", 130, 650, 390, 95, ["DC01-ALEX · Windows Server 2025", "192.168.36.21/24", "AD DS + DNS alexsoler.lan",
                                "copia nocturna del estado del sistema al NAS"], AZUL, "rect"),
    ("tn", 540, 650, 390, 95, ["truenas-alex · TrueNAS SCALE 24.04.2.5", "192.168.36.20/24", "pool «copias» (60 GB) · SMB + NFS",
                                "se lleva por SSH la configuración de todos (23:00)"], AZUL, "rect"),
    ("serveis", 130, 770, 360, 95, ["serveis · Debian 13.8 (sin entorno gráfico)", "192.168.36.22/24",
                                     "servidor de infraestructura", "disco de 1 GB para el espejo DRBD"], AZUL, "rect"),
    ("dades", 570, 770, 360, 95, ["dades · Debian 13.8 (sin entorno gráfico)", "192.168.36.23/24",
                                   "RAID 0, 1 y 5 con mdadm (7 discos de 1 GB)", "disco de 1 GB para el espejo DRBD"], AZUL, "rect"),
    ("pve1", 990, 660, 180, 70, ["pve1", "vmbr0 192.168.36.32/24"], NAR, "rect"),
    ("pve2", 1190, 660, 180, 70, ["pve2", "vmbr0 192.168.36.33/24"], NAR, "rect"),
    ("pve3", 1390, 660, 180, 70, ["pve3", "vmbr0 192.168.36.34/24"], NAR, "rect"),
    ("w11", 990, 815, 285, 90, ["administracion-AlexSoler", "Windows 11 Pro · PC-ADMIN01", "DHCP → 192.168.36.200"], VERDE, "rect"),
    ("lx", 1290, 815, 280, 90, ["informatica-linux-AlexSoler", "Debian 13.8 · pc-informatica (SSSD)", "reserva DHCP 192.168.36.150"], VERDE, "rect"),
    ("ley", 110, 935, 1480, 100, ["Leyenda", "Línea continua: camino normal de la LAN (puerta de enlace .1)  ·  Discontinua roja: routers alternativos "
                                  "(se prueban cambiando la puerta de enlace de un cliente)", "Morada: espejo DRBD por red entre serveis y dades "
                                  "(protocolo C, síncrono)  ·  Todas las IPs fijas por debajo de .100; DHCP .100–.200",
                                  "Anfitrión: SSD de clase por USB, arrancado en el PC de casa (i5-10400F, 16 GB) o en el portátil de clase (Core Ultra 5 125H, 32 GB)"], GRIS, "rect"),
]
# conexiones: origen, destino, texto, estilo (normal / alterno / drbd)
CONEX = [
    ("inet", "aula", "", "normal"), ("aula", "nat", "", "normal"),
    ("nat", "mk", "WAN", "normal"), ("nat", "opn", "WAN", "normal"), ("nat", "nft", "WAN", "normal"),
    ("mk", "sw", "LAN · puerta de enlace", "normal"), ("opn", "sw", "LAN", "alterno"), ("nft", "sw", "LAN", "alterno"),
    ("sw", "dc", "", "normal"), ("sw", "tn", "", "normal"), ("sw", "pve1", "", "normal"), ("sw", "pve2", "", "normal"),
    ("sw", "pve3", "", "normal"),
    ("sw", "w11", "", "normal"), ("sw", "lx", "", "normal"),
    ("serveis", "dades", "DRBD", "drbd"),
]
TITULO = ("Entorno individual ASIX ThinkLab — Álex Soler Ruiz", "LAN 192.168.36.0/24 · red interna «lan_grupo3» · dominio alexsoler.lan")
ANCHO, ALTO = 1700, 1060
CONEX += [("sw", "serveis", "", "normal"), ("sw", "dades", "", "normal")]
# Rutas ortogonales para las cajas de la segunda fila: bajan por el lateral del grupo o por el hueco entre cajas,
# para no atravesar las de arriba. Coordenada x del carril vertical (y de entrada, si llega por un lado).
CARRIL = {"serveis": (120, "izq"), "dades": (940, "der"), "w11": (1180, "arriba"), "lx": (1380, "arriba")}

ESTILO_LINEA = {"normal": ("#2a7f8f", ""), "alterno": ("#c0392b", "8 6"), "drbd": ("#8e44ad", "10 5")}


def caja(i):
    return next(c for c in CAJAS if c[0] == i)


def centro(c):
    return c[1] + c[3] / 2, c[2] + c[4] / 2


# ---------- SVG con la misma geometría ----------
def punto_borde(c, hacia):
    """Punto del borde de la caja c en dirección al punto 'hacia' (para que las líneas no entren en las cajas)."""
    cx, cy = centro(c); hx, hy = hacia
    dx, dy = hx - cx, hy - cy
    if dx == 0 and dy == 0:
        return cx, cy
    sx = (c[3] / 2) / abs(dx) if dx else 1e9
    sy = (c[4] / 2) / abs(dy) if dy else 1e9
    s = min(sx, sy)
    return cx + dx * s, cy + dy * s



def ruta(a, b, e):
    """Lista de puntos de una conexión (inicio, codos, fin). La usan el .drawio y el SVG."""
    ca, cb = caja(a), caja(b)
    if a == "sw" and b in CARRIL:
        x, lado = CARRIL[b]
        if lado == "arriba":
            return [(x, ca[2] + ca[4]), (x, cb[2])]
        ym = cb[2] + cb[4] / 2
        return [(x, ca[2] + ca[4]), (x, ym), (cb[1] if lado == "izq" else cb[1] + cb[3], ym)]
    if a == "sw":
        bx = centro(cb)[0]
        return [(bx, ca[2] + ca[4]), (bx, cb[2])]
    if b == "sw":
        ax = centro(ca)[0]
        return [(ax, ca[2] + ca[4]), (ax, cb[2])]
    return [punto_borde(ca, centro(cb)), punto_borde(cb, centro(ca))]

# ---------- draw.io ----------
def drawio():
    celdas = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>']
    for gid, x, y, w, h, t, (f, b), disc in GRUPOS:
        st = (f"rounded=1;arcSize=3;whiteSpace=wrap;html=1;verticalAlign=top;align=left;spacingLeft=10;spacingTop=4;"
              f"fillColor={f};strokeColor={b};fontSize=12;fontStyle=1;fontColor={b};" + ("dashed=1;" if disc else ""))
        celdas.append(f'<mxCell id="{gid}" value={quoteattr(escape(t))} style="{st}" vertex="1" parent="1">'
                      f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
    for cid, x, y, w, h, lin, (f, b), forma in CAJAS:
        html = "<b>" + escape(lin[0]) + "</b>" + "".join("<br>" + escape(l) for l in lin[1:])
        st = ("ellipse;" if forma == "ellipse" else "rounded=1;arcSize=8;") + \
             f"whiteSpace=wrap;html=1;fillColor={f};strokeColor={b};fontSize=12;"
        if cid == "ley":
            st += "align=left;spacingLeft=10;"
        celdas.append(f'<mxCell id="{cid}" value={quoteattr(html)} style="{st}" vertex="1" parent="1">'
                      f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
    for n, (a, b, t, e) in enumerate(CONEX):
        col, dash = ESTILO_LINEA[e]
        pts = ruta(a, b, e); ca, cb = caja(a), caja(b)
        # puntos de salida y llegada relativos a cada caja (0..1), para que draw.io dibuje lo mismo que el SVG
        ex, ey = (pts[0][0] - ca[1]) / ca[3], (pts[0][1] - ca[2]) / ca[4]
        nx, ny = (pts[-1][0] - cb[1]) / cb[3], (pts[-1][1] - cb[2]) / cb[4]
        st = (f"endArrow=none;html=1;rounded=0;strokeColor={col};strokeWidth=2;fontSize=11;labelBackgroundColor=#ffffff;"
              f"exitX={ex:.4f};exitY={ey:.4f};exitDx=0;exitDy=0;entryX={nx:.4f};entryY={ny:.4f};entryDx=0;entryDy=0;")
        if dash:
            st += f"dashed=1;dashPattern={dash};"
        if e == "drbd":
            st += "startArrow=classic;endArrow=classic;"
        medio = pts[1:-1]
        geo = ('<mxGeometry relative="1" as="geometry">' +
               ('<Array as="points">' + "".join(f'<mxPoint x="{x:.0f}" y="{y:.0f}"/>' for x, y in medio) + '</Array>' if medio else '') +
               '</mxGeometry>')
        celdas.append(f'<mxCell id="e{n}" value={quoteattr(escape(t))} style="{st}" edge="1" parent="1" source="{a}" target="{b}">'
                      f'{geo}</mxCell>')
    celdas.append(f'<mxCell id="titulo" value={quoteattr("<b>" + escape(TITULO[0]) + "</b><br>" + escape(TITULO[1]))} '
                  f'style="text;html=1;align=left;verticalAlign=top;fontSize=14;" vertex="1" parent="1">'
                  f'<mxGeometry x="30" y="20" width="600" height="50" as="geometry"/></mxCell>')
    return ('<mxfile host="generar-diagrama.py" agent="Álex Soler Ruiz">\n<diagram id="red" name="Red individual">\n'
            f'<mxGraphModel dx="{ANCHO}" dy="{ALTO}" grid="1" gridSize="10" guides="1" page="1" pageWidth="{ANCHO}" '
            f'pageHeight="{ALTO}" math="0" shadow="0">\n<root>\n' + "\n".join(celdas) +
            '\n</root>\n</mxGraphModel>\n</diagram>\n</mxfile>\n')


def svg():
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{ANCHO}" height="{ALTO}" viewBox="0 0 {ANCHO} {ALTO}" '
         f'font-family="Helvetica, Arial, sans-serif">', f'<rect width="{ANCHO}" height="{ALTO}" fill="#ffffff"/>']
    for gid, x, y, w, h, t, (f, b), disc in GRUPOS:
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{f}" stroke="{b}" stroke-width="1.5"'
                 + (' stroke-dasharray="6 4"' if disc else '') + '/>')
    for a, b, t, e in CONEX:
        col, dash = ESTILO_LINEA[e]
        pts = ruta(a, b, e); p1, p2 = pts[0], pts[-1]
        extra = f' stroke-dasharray="{dash}"' if dash else ''
        mk = ' marker-start="url(#f)" marker-end="url(#f)"' if e == "drbd" else ''
        o.append(f'<polyline points="{" ".join(f"{x:.0f},{y:.0f}" for x, y in pts)}" fill="none" stroke="{col}" stroke-width="2"{extra}{mk}/>')
        if t:
            mx, my = (p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2
            ancho = 7.2 * len(t) + 10
            o.append(f'<rect x="{mx - ancho / 2:.0f}" y="{my - 10:.0f}" width="{ancho:.0f}" height="18" fill="#ffffff"/>')
            o.append(f'<text x="{mx:.0f}" y="{my + 4:.0f}" font-size="11.5" text-anchor="middle" fill="{col}">{escape(t)}</text>')
    o.insert(2, '<defs><marker id="f" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
                '<path d="M0,0 L10,5 L0,10 z" fill="#8e44ad"/></marker></defs>')
    for gid, x, y, w, h, t, (f, b), disc in GRUPOS:   # títulos de grupo por encima de las líneas
        o.append(f'<text x="{x + 10}" y="{y + 18}" font-size="12.5" font-weight="bold" fill="{b}" stroke="#ffffff" '
                 f'stroke-width="4" paint-order="stroke">{escape(t)}</text>')
    for cid, x, y, w, h, lin, (f, b), forma in CAJAS:
        if forma == "ellipse":
            o.append(f'<ellipse cx="{x + w / 2}" cy="{y + h / 2}" rx="{w / 2}" ry="{h / 2}" fill="{f}" stroke="{b}" stroke-width="1.5"/>')
        else:
            o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{f}" stroke="{b}" stroke-width="1.5"/>')
        izq = cid == "ley"
        tx = x + 12 if izq else x + w / 2
        alto_l = 17
        y0 = y + h / 2 - (len(lin) - 1) * alto_l / 2 + 4
        for k, l in enumerate(lin):
            o.append(f'<text x="{tx:.0f}" y="{y0 + k * alto_l:.0f}" font-size="{13 if k == 0 else 12}" '
                     f'{"" if izq else "text-anchor=\"middle\" "}{"font-weight=\"bold\" " if k == 0 else ""}fill="#1f2a30">{escape(l)}</text>')
    o.append(f'<text x="30" y="38" font-size="18" font-weight="bold" fill="#1d4a3c">{escape(TITULO[0])}</text>')
    o.append(f'<text x="30" y="60" font-size="13" fill="#1d4a3c">{escape(TITULO[1])}</text>')
    o.append('</svg>')
    return "\n".join(o)


if __name__ == "__main__":
    open("red-individual.drawio", "w", encoding="utf-8").write(drawio())
    open("red-individual.svg", "w", encoding="utf-8").write(svg())
    print("red-individual.drawio y red-individual.svg generados")
