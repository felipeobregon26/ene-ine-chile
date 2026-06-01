"""
Analiza la estructura del sitio INE para encontrar los endpoints reales de los CSVs.
"""

import re
import json
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "es-CL,es;q=0.9",
}

SESSION = requests.Session()
SESSION.headers.update(HEADERS)

BASE = "https://www.ine.gob.cl"
PAGE = f"{BASE}/estadisticas-por-tema/mercado-laboral/ocupacion-y-desocupacion"


def fetch(url, **kw):
    try:
        r = SESSION.get(url, timeout=30, **kw)
        return r
    except Exception as e:
        print(f"  ERROR fetching {url}: {e}")
        return None


# -------------------------------------------------------------------
# 1. Examinar HTML completo de la página principal
# -------------------------------------------------------------------
print("=" * 70)
print("1. Descargando HTML de la página principal...")
r = fetch(PAGE)
if r:
    print(f"   Status: {r.status_code}  Content-Length: {len(r.text)}")
    soup = BeautifulSoup(r.text, "html.parser")

    # Todos los links
    all_hrefs = [a["href"] for a in soup.find_all("a", href=True)]
    print(f"   Total <a> tags: {len(all_hrefs)}")

    # Links que mencionen ENE, bbdd, csv, descargar
    keywords = ["ene", "bbdd", "csv", "descarg", "base", "empleo", "ocupac"]
    relevant = [h for h in all_hrefs if any(k in h.lower() for k in keywords)]
    print(f"   Links relevantes: {len(relevant)}")
    for h in relevant[:30]:
        print(f"     {h}")

    # Scripts externos
    scripts = [s["src"] for s in soup.find_all("script", src=True)]
    print(f"\n   Scripts externos: {len(scripts)}")
    for s in scripts[:20]:
        print(f"     {s}")

    # Buscar JSON embebido en <script> inline
    inline_scripts = [s.string for s in soup.find_all("script") if s.string]
    print(f"\n   Scripts inline: {len(inline_scripts)}")
    api_hits = []
    for sc in inline_scripts:
        hits = re.findall(r'["\']([^"\']*(?:api|bbdd|csv|document|library)[^"\']*)["\']',
                          sc, re.IGNORECASE)
        api_hits.extend(hits)
    if api_hits:
        print("   Strings con 'api/bbdd/csv/document/library' en scripts inline:")
        for h in sorted(set(api_hits))[:50]:
            print(f"     {h}")

    # Guardar HTML para inspección manual
    with open("pagina_principal.html", "w", encoding="utf-8") as f:
        f.write(r.text)
    print("\n   HTML guardado en pagina_principal.html")


# -------------------------------------------------------------------
# 2. Probar robots.txt y sitemap
# -------------------------------------------------------------------
print("\n" + "=" * 70)
print("2. robots.txt y sitemap...")

r2 = fetch(f"{BASE}/robots.txt")
if r2 and r2.ok:
    print(r2.text[:2000])

for sm in ["/sitemap.xml", "/sitemap_index.xml", "/sitemap.aspx"]:
    r3 = fetch(f"{BASE}{sm}")
    if r3 and r3.ok and "xml" in r3.headers.get("Content-Type", ""):
        print(f"\n   Sitemap encontrado: {BASE}{sm}  ({len(r3.text)} bytes)")
        # Buscar URLs con csv o bbdd
        hits = re.findall(r'<loc>([^<]*(?:csv|bbdd|empleo|ene)[^<]*)</loc>',
                          r3.text, re.IGNORECASE)
        print(f"   URLs relevantes en sitemap: {len(hits)}")
        for h in hits[:30]:
            print(f"     {h}")


# -------------------------------------------------------------------
# 3. Sitefinity REST API – enumerar librería de documentos
# -------------------------------------------------------------------
print("\n" + "=" * 70)
print("3. Probando Sitefinity REST API...")

sf_endpoints = [
    f"{BASE}/api/default/documents?$top=100&$filter=contains(UrlName,'ene')",
    f"{BASE}/api/default/documents?$top=100",
    f"{BASE}/api/default/libraries",
    f"{BASE}/api/default/contentitems?$top=50",
    f"{BASE}/api/default/documents?$top=100&$select=Title,Url,UrlName,Extension"
    "&$filter=Extension eq 'csv'",
]

for ep in sf_endpoints:
    r4 = fetch(ep, headers={**HEADERS, "Accept": "application/json"})
    if r4:
        ct = r4.headers.get("Content-Type", "")
        print(f"\n   {ep}")
        print(f"   -> {r4.status_code}  CT={ct[:60]}")
        if r4.ok and ("json" in ct or r4.text.strip().startswith("{")):
            try:
                data = r4.json()
                print(f"   -> JSON keys: {list(data.keys()) if isinstance(data, dict) else type(data)}")
                snippet = json.dumps(data, ensure_ascii=False)[:800]
                print(f"   -> {snippet}")
            except Exception:
                print(f"   -> {r4.text[:300]}")


# -------------------------------------------------------------------
# 4. Probar rutas alternativas de BBDD con GET (no HEAD)
# -------------------------------------------------------------------
print("\n" + "=" * 70)
print("4. Probando rutas bbdd con GET...")

paths = [
    "/docs/default-source/ocupacion-y-desocupacion/bbdd/",
    "/docs/default-source/ocupacion-y-desocupacion/bases-de-datos/",
    "/docs/default-source/mercado-laboral/bbdd/",
    "/docs/default-source/encuesta-empleo/bbdd/",
    "/docs/default-source/ene/bbdd/",
    "/docs/default-source/estadisticas/mercado-laboral/ocupacion-y-desocupacion/bbdd/",
    "/estadisticas/mercado-laboral/ocupacion-y-desocupacion/bbdd/",
]

for p in paths:
    r5 = fetch(f"{BASE}{p}")
    if r5:
        ct = r5.headers.get("Content-Type", "")
        print(f"   {p} -> {r5.status_code}  CT={ct[:40]}  len={len(r5.text)}")
        if r5.ok:
            soup5 = BeautifulSoup(r5.text, "html.parser")
            csvlinks = [a["href"] for a in soup5.find_all("a", href=True)
                        if ".csv" in a["href"].lower()]
            print(f"     CSV links: {csvlinks[:10]}")


# -------------------------------------------------------------------
# 5. Probar archivos individuales conocidos (patrones reales INE)
# -------------------------------------------------------------------
print("\n" + "=" * 70)
print("5. Probando archivos individuales con patrones conocidos...")

# Patrones reales observados en repositorios públicos / papers
test_urls = [
    # Formato moderno (desde ~2016): ene-YYYY-tri.csv en ruta directa
    "https://www.ine.gob.cl/docs/default-source/ocupacion-y-desocupacion/bbdd/2023/ene-2023-ond.csv",
    "https://www.ine.gob.cl/docs/default-source/ocupacion-y-desocupacion/bbdd/2023/ene-2023-son.csv",
    "https://www.ine.gob.cl/docs/default-source/ocupacion-y-desocupacion/bbdd/ene-2023-ond.csv",
    # Sin subcarpeta de año
    "https://www.ine.gob.cl/docs/default-source/ocupacion-y-desocupacion/bbdd/ene-2022-ond.csv",
    # Formato alternativo
    "https://www.ine.gob.cl/docs/default-source/ocupacion-y-desocupacion/bbdd/ene2023ond.csv",
    # Con guión bajo
    "https://www.ine.gob.cl/docs/default-source/ocupacion-y-desocupacion/bbdd/ene_2023_ond.csv",
]

for url in test_urls:
    r6 = SESSION.head(url, timeout=10, allow_redirects=True)
    ct = r6.headers.get("Content-Type", "")
    cl = r6.headers.get("Content-Length", "?")
    print(f"   {r6.status_code}  {ct[:30]}  size={cl}  {url.split('bbdd/')[-1]}")


# -------------------------------------------------------------------
# 6. Verificar qué devuelve exactamente la URL bbdd con HEAD
# -------------------------------------------------------------------
print("\n" + "=" * 70)
print("6. Headers completos de /docs/default-source/ocupacion-y-desocupacion/bbdd/")
r7 = fetch("https://www.ine.gob.cl/docs/default-source/ocupacion-y-desocupacion/bbdd/")
if r7:
    print(f"   Status: {r7.status_code}")
    for k, v in r7.headers.items():
        print(f"   {k}: {v}")
    print(f"\n   Body (primeros 500 chars):\n{r7.text[:500]}")
