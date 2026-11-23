#!/usr/bin/env python3
# generar-pdf.py - Álex Soler Ruiz
# Genera un PDF por tarea a partir de los Markdown de docs/.
#   uso: python3 pdf/generar-pdf.py CARPETA_DESTINO
# Necesita: python3-markdown, python3-websockets, pdfunite (poppler-utils) y Google Chrome (lo usa en modo headless
# por DevTools para poder poner pie de página con número de página).
import asyncio, base64, json, pathlib, re, shutil, subprocess, sys, tempfile, time, urllib.request
import markdown, websockets

BASE = pathlib.Path(__file__).resolve().parent.parent
OUT = pathlib.Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
REPO_WEB = "https://github.com/solerruizalex-dot/asix-thinklab-individual"
REPO = REPO_WEB + "/blob/main"
TAREAS = [
 ("Tarea0_Entorno", "Tarea 0", "Entorno de pruebas", ["docs/tarea0-entorno.md"]),
 ("Tarea2_Equipos", "Tarea 2", "Equipos y periféricos", ["docs/tarea2-equipos.md"]),
 ("Tarea4_Red", "Tarea 4", "Diseño físico y lógico de la red", ["docs/tarea4-red.md"]),
 ("Tarea5_Instalacion", "Tarea 5", "Instalación y comunicaciones",
  ["docs/tarea5/README.md", "docs/tarea5/01-imagenes-y-requisitos.md", "docs/tarea5/02-mikrotik.md",
   "docs/tarea5/03-opnsense.md", "docs/tarea5/04-debian-nftables.md", "docs/tarea5/05-truenas.md",
   "docs/tarea5/06-proxmox.md", "docs/tarea5/07-windows-server.md", "docs/tarea5/08-servidores-linux.md",
   "docs/tarea5/09-clientes.md", "docs/tarea5/10-copias-automatizadas.md", "docs/tarea5/11-problemas-y-tiempos.md"]),
 ("Tarea6_RAID", "Tarea 6", "Almacenamiento: RAID y espejo entre equipos", ["docs/tarea6-raid.md"]),
 ("Tarea7_Rendimiento", "Tarea 7", "Rendimiento y diagnóstico", ["docs/tarea7-rendimiento.md"]),
]

# Paleta: verde pino + terracota sobre papel cálido
PINO, PINO_CLARO, TERRA, PAPEL, TINTA = "#1d4a3c", "#e6efe9", "#b5562b", "#fbf8f3", "#2a2724"
CSS = f"""
@page {{ size: A4; margin: 17mm 17mm 19mm 17mm; }}
@page :first {{ margin: 0; }}
html {{ -webkit-print-color-adjust: exact; print-color-adjust: exact; }}
body {{ font-family: 'Noto Sans', 'DejaVu Sans', sans-serif; font-size: 10.2pt; line-height: 1.5; color: {TINTA}; margin: 0; }}
h1, h2, h3 {{ font-family: Georgia, 'DejaVu Serif', serif; font-weight: normal; break-after: avoid; }}
h1 {{ font-size: 21pt; color: {PINO}; page-break-before: always; margin: 0 0 14px; padding: 0 0 8px;
      border-bottom: 1px solid {PINO}; }}
h1::before {{ content: ""; display: block; width: 46px; height: 5px; background: {TERRA}; margin-bottom: 10px; }}
h2 {{ font-size: 14pt; color: {PINO}; margin: 22px 0 8px; }}
h2::before {{ content: "▍"; color: {TERRA}; margin-right: 4px; }}
h3 {{ font-size: 11.5pt; color: {TERRA}; margin: 16px 0 6px; font-style: italic; }}
p {{ margin: 6px 0 8px; }}
strong {{ color: #1a1a1a; }}
a {{ color: {TERRA}; text-decoration: none; border-bottom: 1px dotted {TERRA}; }}
table {{ border-collapse: collapse; width: 100%; margin: 10px 0 12px; font-size: 9pt; }}
thead {{ display: table-header-group; }} tr {{ break-inside: avoid; }}
th {{ background: {PINO}; color: #fff; font-weight: 600; text-align: left; padding: 5px 7px; }}
td {{ padding: 4px 7px; border-bottom: 1px solid #d9d3c7; vertical-align: top; }}
tbody tr:nth-child(even) td {{ background: {PAPEL}; }}
code {{ font-family: 'DejaVu Sans Mono', monospace; font-size: 8.6pt; background: {PINO_CLARO}; color: #183d31; padding: 0 3px; border-radius: 2px; }}
pre {{ background: #24302b; color: #e8efe9; padding: 9px 11px; border-radius: 4px; font-size: 8.3pt; line-height: 1.4;
       white-space: pre-wrap; break-inside: avoid; border-left: 4px solid {TERRA}; }}
pre code {{ background: none; color: inherit; padding: 0; }}
blockquote {{ margin: 10px 0; padding: 6px 12px; background: {PAPEL}; border-left: 4px solid {TERRA}; color: #4a4540; }}
ul, ol {{ padding-left: 20px; }} li {{ margin: 2px 0; }}
img {{ max-width: 100%; display: block; margin: 8px auto 4px; border: 1px solid #cfc8bb; border-radius: 3px; break-inside: avoid; }}
img + em, p > em:only-child {{ display: block; text-align: center; font-size: 8.6pt; color: #6b655c; }}
/* portada */
.portada {{ width: 210mm; height: 296mm; display: flex; overflow: hidden; break-after: page; }}
.franja {{ width: 62mm; background: {PINO}; color: #fff; padding: 26mm 11mm; box-sizing: border-box;
           display: flex; flex-direction: column; justify-content: space-between; }}
.franja .num {{ font-family: Georgia, serif; font-size: 46pt; line-height: 1; }}
.franja .num span {{ display: block; font-size: 11pt; letter-spacing: 3px; text-transform: uppercase; color: #f0c9a8; margin-bottom: 6px; }}
.franja .pie {{ font-size: 9pt; color: #cfe0d7; line-height: 1.6; }}
.cuerpo-portada {{ flex: 1; padding: 42mm 18mm 30mm 18mm; display: flex; flex-direction: column; background: {PAPEL}; }}
.cuerpo-portada .proy {{ font-size: 10pt; letter-spacing: 2px; text-transform: uppercase; color: {TERRA}; }}
.cuerpo-portada .titulo {{ font-family: Georgia, serif; font-size: 30pt; color: {PINO}; line-height: 1.15; margin: 10px 0 18px; }}
.cuerpo-portada .raya {{ width: 60px; height: 4px; background: {TERRA}; margin-bottom: 22px; }}
.cuerpo-portada .autor {{ font-size: 15pt; color: {TINTA}; }} .cuerpo-portada .curso {{ font-size: 11pt; color: #6b655c; margin-top: 4px; }}
.repo {{ margin-top: auto; background: #fff; border: 1px solid #d9d3c7; border-left: 5px solid {PINO}; padding: 10px 14px; font-size: 9.5pt; }}
.repo b {{ display: block; font-family: Georgia, serif; font-weight: normal; color: {PINO}; font-size: 11pt; margin-bottom: 3px; }}
.repo a {{ font-family: 'DejaVu Sans Mono', monospace; font-size: 9pt; }}
.aviso-repo {{ font-size: 9pt; background: {PINO_CLARO}; border-radius: 3px; padding: 7px 10px; margin: 0 0 14px; }}
"""

def a_html(md_path):
    p = BASE / md_path
    h = markdown.markdown(p.read_text(encoding="utf-8"), extensions=["tables", "fenced_code"])
    h = re.sub(r'src="(?!http)([^"]+)"', lambda m: 'src="%s"' % (p.parent / m.group(1)).resolve().as_uri(), h)
    def enlace(m):  # los enlaces a ficheros del repo apuntan a GitHub, donde están scripts y evidencias
        destino = (p.parent / m.group(1)).resolve()
        try: rel = destino.relative_to(BASE).as_posix()
        except ValueError: return m.group(0)
        return 'href="%s/%s"' % (REPO, rel)
    return re.sub(r'href="(?!http|#|mailto)([^"#]+)"', enlace, h)

def portada(num, nombre, docs):
    carpeta = REPO + "/" + (docs[0].rsplit("/", 1)[0] if len(docs) > 1 else docs[0])
    return f"""<div class="portada"><div class="franja">
  <div class="num"><span>{num.split()[0]}</span>{num.split()[1]}</div>
  <div class="pie">ASIX ThinkLab<br>Parte individual<br>Noviembre de 2026</div></div>
 <div class="cuerpo-portada"><div class="proy">ASIX ThinkLab · parte individual</div>
  <div class="titulo">{nombre}</div><div class="raya"></div>
  <div class="autor">Álex Soler Ruiz</div><div class="curso">1º ASIX · Implantación de sistemas operativos</div>
  <div class="repo"><b>Repositorio en GitHub</b>Todo lo que cuento aquí (scripts, evidencias y capturas) está en:<br>
   <a href="{REPO_WEB}">{REPO_WEB.replace('https://','')}</a><br>
   Esta tarea: <a href="{carpeta}">{carpeta.replace('https://github.com/solerruizalex-dot/asix-thinklab-individual/blob/main/','…/')}</a></div>
 </div></div>"""

PIE = ("<div style=\"font-family:'Noto Sans',sans-serif;font-size:7.5pt;color:#6b655c;width:100%;padding:0 17mm;"
       "display:flex;justify-content:space-between\"><span>Álex Soler Ruiz · {num} · {nombre}</span>"
       "<span>github.com/solerruizalex-dot/asix-thinklab-individual</span>"
       "<span><span class='pageNumber'></span> / <span class='totalPages'></span></span></div>")

async def imprimir(puerto, html_uri, pdf, pie):
    req = urllib.request.Request(f"http://127.0.0.1:{puerto}/json/new?{html_uri}", method="PUT")
    t = json.load(urllib.request.urlopen(req))
    async with websockets.connect(t["webSocketDebuggerUrl"], max_size=200_000_000) as ws:
        n = 0
        async def call(m, prm={}):
            nonlocal n; n += 1; await ws.send(json.dumps({"id": n, "method": m, "params": prm}))
            while True:
                r = json.loads(await ws.recv())
                if r.get("id") == n: return r
        await asyncio.sleep(2.5)  # imágenes y fuentes
        opciones = {"printBackground": True, "preferCSSPageSize": True, "displayHeaderFooter": bool(pie)}
        if pie: opciones.update(headerTemplate="<span></span>", footerTemplate=pie)
        r = await call("Page.printToPDF", opciones)
        pdf.write_bytes(base64.b64decode(r["result"]["data"]))
    urllib.request.urlopen(f"http://127.0.0.1:{puerto}/json/close/{t['id']}")

def main():
    perfil = tempfile.mkdtemp(prefix="pdf-chrome-"); puerto = 9555
    chrome = subprocess.Popen(["google-chrome", "--headless=new", f"--remote-debugging-port={puerto}",
        f"--user-data-dir={perfil}", "--no-first-run", "--allow-file-access-from-files", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try: urllib.request.urlopen(f"http://127.0.0.1:{puerto}/json/version"); break
            except OSError: time.sleep(0.2)
        for fich, num, nombre, docs in TAREAS:
            cuerpo = "".join(a_html(d) for d in docs)
            # la primera página después de la portada no necesita salto extra
            cuerpo = cuerpo.replace("<h1>", "<h1 style='page-break-before:avoid'>", 1)
            cab = f"<!DOCTYPE html><html lang='es'><head><meta charset='utf-8'><title>{num} · {nombre} · Álex Soler Ruiz</title><style>{CSS}</style></head><body>"
            pdf = OUT / f"{fich}_AlexSolerRuiz.pdf"
            partes = []
            # la portada se imprime sin pie de página y el resto con él; luego se unen
            for sufijo, html, pie in (("portada", portada(num, nombre, docs), None),
                                      ("cuerpo", cuerpo, PIE.format(num=num, nombre=nombre))):
                css_extra = "" if sufijo == "portada" else "<style>@page :first { margin: 17mm 17mm 19mm 17mm; }</style>"
                tmp = OUT / f".{fich}.{sufijo}.html"; tmp.write_text(cab + css_extra + html + "</body></html>", encoding="utf-8")
                parte = OUT / f".{fich}.{sufijo}.pdf"
                asyncio.run(imprimir(puerto, tmp.as_uri(), parte, pie)); tmp.unlink(); partes.append(parte)
            subprocess.run(["pdfunite", *map(str, partes), str(pdf)], check=True)
            for parte in partes: parte.unlink()
            print(pdf.name, pdf.stat().st_size)
    finally:
        chrome.terminate(); chrome.wait(); shutil.rmtree(perfil, ignore_errors=True)

main()
