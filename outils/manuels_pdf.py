#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generation des manuels en PDF A4 (utilise par l'action GitHub "Manuels PDF").

Le Markdown est rendu en HTML (marked + feuille de style GitHub), puis imprime
en PDF par un navigateur Chromium sans interface (Chrome, Chromium ou Edge).

Usage : python3 outils/manuels_pdf.py README.md impression/Manuel.pdf
Variable d'environnement facultative : CHROME = chemin du navigateur.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

MARKED = "https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"
GITHUB_CSS = "https://cdn.jsdelivr.net/npm/github-markdown-css@5.5.1/github-markdown-light.css"

BROWSERS = [
    "google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "msedge",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
]


def find_browser():
    if os.environ.get("CHROME"):
        return os.environ["CHROME"]
    for name in BROWSERS:
        path = shutil.which(name) or (name if os.path.isfile(name) else None)
        if path:
            return path
    sys.exit("Aucun navigateur Chromium trouve (definissez la variable CHROME).")


def build_html(md_path):
    md = md_path.read_text(encoding="utf-8")
    # Les images du manuel sont relatives au dossier du fichier Markdown
    base = md_path.resolve().parent.as_uri() + "/"
    return f"""<!doctype html><html><head><meta charset="utf-8"><base href="{base}">
<link rel="stylesheet" href="{GITHUB_CSS}">
<style>
 body {{ margin: 0; }}
 .markdown-body {{ max-width: 860px; margin: 0 auto; padding: 24px; }}
 @page {{ size: A4; margin: 14mm 12mm; }}
 @media print {{
   .markdown-body {{ padding: 0; }}
   pre, table, img, p {{ break-inside: avoid; }}
   h2, h3 {{ break-after: avoid; }}
 }}
</style>
<script src="{MARKED}"></script>
</head><body><article class="markdown-body" id="c"></article>
<script>document.getElementById('c').innerHTML = marked.parse({json.dumps(md)});</script>
</body></html>"""


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    md_path, pdf_path = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
    pdf_path.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        html_path = Path(tmp) / "manuel.html"
        html_path.write_text(build_html(md_path), encoding="utf-8")
        cmd = [
            find_browser(), "--headless=new", "--disable-gpu", "--no-sandbox",
            "--allow-file-access-from-files", "--virtual-time-budget=15000",
            "--no-pdf-header-footer", f"--print-to-pdf={pdf_path}", html_path.as_uri(),
        ]
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)

    if not pdf_path.is_file() or pdf_path.stat().st_size < 10000:
        sys.exit(f"Echec de la generation de {pdf_path}")
    print(f"{pdf_path} : {pdf_path.stat().st_size // 1024} Ko")


if __name__ == "__main__":
    main()
