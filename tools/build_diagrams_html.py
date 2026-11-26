"""Builds docs/diagrams/diyagramlar.html from the Mermaid sources (*.mmd).

    python tools/build_diagrams_html.py

Open the HTML file in a browser (internet needed for the Mermaid library),
then print it (Ctrl+P -> "Save as PDF" or a printer). Every diagram starts on
a new page; each one also has a button to download it as SVG.
"""
import html
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIAGRAM_DIR = os.path.join(ROOT, "docs", "diagrams")
OUT = os.path.join(DIAGRAM_DIR, "diyagramlar.html")
MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"

# (file, title, description, page orientation for printing)
DIAGRAMS = [
    ("01-genel-mimari.mmd", "1. Genel mimari",
     "Katmanlar ve aralarındaki bağımlılıklar. «...» işaretleri kullanılan tasarım desenini gösterir.", "landscape"),
    ("02-algoritma.mmd", "2. ATLAS algoritması",
     "Hocanın Java ATLAS kodunun Lua portu ve maliyet stratejileri (Strategy + Factory Method).", "landscape"),
    ("03-rota-planlama.mmd", "3. Rota planlama",
     "Görevleri ATLAS grafına çeviren ve rotayı üreten sınıflar (Strategy, Factory Method).", "portrait"),
    ("04-servisler-ve-model.mmd", "4. Servisler ve alan modeli",
     "Oyun API'sine erişim (Adapter), görev veritabanı (Repository), görev nesneleri (Factory Method).", "portrait"),
    ("05-takip-ve-arayuz.mmd", "5. Takip ve arayüz",
     "Facade, Observer (EventBus), MVP (Presenter/View), Factory Method (WidgetFactory), Composition Root.", "landscape"),
    ("06-komutlar.mmd", "6. Slash komutları",
     "Chain of Responsibility + Template Method: her /qa komutu ayrı bir sınıf.", "portrait"),
    ("07-sade-diyagram.mmd", "7. Sadeleştirilmiş sınıf diyagramı (ezber için)",
     "Elle çizilecekse bu yeterli: ana sınıflar, desenler ve en önemli metotlar.", "portrait"),
    ("08-akis-gorev-guncelleme.mmd", "8. Sıralı diyagram: görev günlüğü değişince ne olur?",
     "Bir oyun olayından ekrandaki rotaya kadar çağrı sırası.", "landscape"),
]

PAGE = """<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>QuestAtlas Diyagramları</title>
<style>
  :root {{ --ink: #1d2433; --muted: #5b6478; --line: #d9dde6; --bg: #ffffff; --accent: #2f5aa8; }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: var(--bg); color: var(--ink);
         font: 15px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }}
  header {{ padding: 24px 16px 8px; max-width: 1200px; margin: 0 auto; }}
  h1 {{ font-size: 24px; margin: 0 0 4px; }}
  header p {{ color: var(--muted); margin: 4px 0; }}
  .toolbar {{ display: flex; gap: 8px; flex-wrap: wrap; margin-top: 12px; }}
  button {{ font: inherit; border: 1px solid var(--line); background: #f5f7fb; color: var(--ink);
           padding: 6px 12px; border-radius: 6px; cursor: pointer; }}
  button:hover {{ border-color: var(--accent); }}
  section {{ max-width: 1200px; margin: 0 auto; padding: 16px; border-top: 1px solid var(--line); }}
  section h2 {{ font-size: 19px; margin: 8px 0 2px; }}
  section p {{ color: var(--muted); margin: 0 0 12px; }}
  .diagram {{ overflow-x: auto; }}
  .diagram svg {{ max-width: 100%; height: auto; }}
  .legend {{ font-size: 13px; color: var(--muted); }}
  .legend code {{ background: #f1f3f8; padding: 1px 4px; border-radius: 4px; }}
  @media print {{
    @page {{ size: A4 landscape; margin: 10mm; }}
    @page portrait {{ size: A4 portrait; margin: 10mm; }}
    header .toolbar, section button {{ display: none; }}
    section {{ page-break-before: always; border: 0; max-width: none; }}
    section.portrait {{ page: portrait; }}
    .diagram {{ overflow: visible; }}
  }}
</style>
</head>
<body>
<header>
  <h1>QuestAtlas: Sınıf ve akış diyagramları</h1>
  <p>WoW: Forever için görev takipçisi ve ATLAS tabanlı en kısa görev rotası eklentisi.</p>
  <p class="legend">Okların anlamı: <code>&lt;|..</code> arayüzü uygular,
     <code>&lt;|--</code> kalıtım, <code>*--</code> bileşim (composition),
     <code>o--</code> toplama (aggregation), <code>--&gt;</code> ilişki / kullanır,
     <code>..&gt;</code> bağımlılık / oluşturur. <code>$</code> statik, <code>*</code> soyut metot.</p>
  <div class="toolbar">
    <button onclick="window.print()">Yazdır / PDF olarak kaydet</button>
  </div>
</header>
{sections}
<script src="{mermaid_url}"></script>
<script>
  mermaid.initialize({{ startOnLoad: true, theme: "default", securityLevel: "strict",
                        classDiagram: {{ useMaxWidth: true }}, flowchart: {{ useMaxWidth: true }} }});
  function downloadSvg(id, name) {{
    var svg = document.querySelector("#" + id + " svg");
    if (!svg) {{ alert("Diyagram henüz çizilmedi."); return; }}
    var data = new XMLSerializer().serializeToString(svg);
    var blob = new Blob([data], {{ type: "image/svg+xml" }});
    var link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = name + ".svg";
    link.click();
  }}
</script>
</body>
</html>
"""

SECTION = """<section class="{orientation}">
  <h2>{title}</h2>
  <p>{description}</p>
  <div class="diagram" id="{id}"><pre class="mermaid">
{source}
</pre></div>
  <button onclick="downloadSvg('{id}', '{name}')">SVG indir</button>
</section>"""


def main():
    sections = []
    for index, (file_name, title, description, orientation) in enumerate(DIAGRAMS, 1):
        with open(os.path.join(DIAGRAM_DIR, file_name), encoding="utf-8") as f:
            source = f.read().rstrip()
        sections.append(SECTION.format(title=html.escape(title), description=html.escape(description),
                                       id="d%d" % index, name=file_name[:-4], source=html.escape(source),
                                       orientation=orientation))
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(PAGE.format(sections="\n".join(sections), mermaid_url=MERMAID_URL))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
