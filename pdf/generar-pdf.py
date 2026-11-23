#!/usr/bin/env python3
# Genera un PDF por tarea a partir de los Markdown de docs/ (Álex Soler Ruiz)
import markdown, re, subprocess, sys, pathlib, html
BASE = pathlib.Path(__file__).resolve().parent.parent
OUT = pathlib.Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
TAREAS = [
 ("Tarea0_Entorno", "Tarea 0", "Entorno de pruebas", ["docs/tarea0-entorno.md"]),
 ("Tarea2_Equipos", "Tarea 2", "Equipos y periféricos", ["docs/tarea2-equipos.md"]),
 ("Tarea4_Red", "Tarea 4", "Diseño físico y lógico de la red", ["docs/tarea4-red.md"]),
 ("Tarea5_Instalacion", "Tarea 5", "Instalación y comunicaciones",
  ["docs/tarea5/01-imagenes-y-requisitos.md", "docs/tarea5/02-mikrotik.md", "docs/tarea5/03-opnsense.md",
   "docs/tarea5/04-debian-nftables.md", "docs/tarea5/05-servidores-y-clientes.md"]),
 ("Tarea6_RAID", "Tarea 6", "Almacenamiento: RAID y espejo entre equipos", ["docs/tarea6-raid.md"]),
 ("Tarea7_Rendimiento", "Tarea 7", "Rendimiento y diagnóstico", ["docs/tarea7-rendimiento.md"]),
]
CSS = """
@page { size: A4; margin: 18mm 16mm; }
body { font-family: 'DejaVu Sans', Arial, sans-serif; font-size: 10.5pt; line-height: 1.45; color:#222; }
h1 { font-size: 18pt; border-bottom: 2px solid #2b5797; padding-bottom: 4px; color:#2b5797; page-break-before: always; }
h2 { font-size: 13.5pt; color:#2b5797; margin-top: 18px; } h3 { font-size: 11.5pt; }
table { border-collapse: collapse; width: 100%; margin: 8px 0; font-size: 9.3pt; page-break-inside: avoid; }
th, td { border: 1px solid #bbb; padding: 4px 6px; vertical-align: top; } th { background: #e8eef7; }
code { background:#f2f2f2; padding: 1px 3px; font-size: 9pt; }
pre { background:#f5f5f5; border:1px solid #ddd; padding: 8px; font-size: 8.5pt; white-space: pre-wrap; page-break-inside: avoid; }
img { max-width: 100%; } a { color:#2b5797; text-decoration:none; }
.portada { height: 250mm; display:flex; flex-direction:column; justify-content:center; text-align:center; }
.portada .t { font-size: 30pt; color:#2b5797; font-weight:bold; margin: 10px 0; }
.portada .s { font-size: 20pt; margin-bottom: 40px; } .portada .n { font-size: 16pt; }
"""
for fich, num, nombre, docs in TAREAS:
    cuerpo = ""
    for d in docs:
        p = BASE / d
        md = p.read_text(encoding="utf-8")
        h = markdown.markdown(md, extensions=["tables", "fenced_code"])
        # rutas relativas de imágenes -> absolutas
        h = re.sub(r'src="(?!http)([^"]+)"', lambda m: 'src="%s"' % (p.parent / m.group(1)).resolve().as_uri(), h)
        cuerpo += h
    portada = f"""<div class="portada"><div class="n">Álex Soler Ruiz · 1º ASIX</div>
<div class="t">ASIX ThinkLab (parte individual)</div><div class="s">{num} · {nombre}</div>
<div class="n">Noviembre de 2026</div></div>"""
    doc = f"<!DOCTYPE html><html lang='es'><head><meta charset='utf-8'><title>{num} - Álex Soler Ruiz</title><style>{CSS}</style></head><body>{portada}{cuerpo}</body></html>"
    tmp = OUT / f".{fich}.html"; tmp.write_text(doc, encoding="utf-8")
    pdf = OUT / f"{fich}_AlexSolerRuiz.pdf"
    subprocess.run(["google-chrome", "--headless", "--disable-gpu", "--no-pdf-header-footer",
                    f"--print-to-pdf={pdf}", tmp.as_uri()], check=True, capture_output=True)
    tmp.unlink()
    print(pdf.name, pdf.stat().st_size)
