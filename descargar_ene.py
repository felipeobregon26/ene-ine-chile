"""
Descarga todos los archivos CSV de la ENE (Encuesta Nacional de Empleo)
desde el sitio del INE de Chile.
"""

import os
import re
import time
import requests
from pathlib import Path
from urllib.parse import urljoin, urlparse
from bs4 import BeautifulSoup

BASE_DIR = Path(__file__).parent
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    )
}
SESSION = requests.Session()
SESSION.headers.update(HEADERS)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def year_from_url(url: str) -> str | None:
    m = re.search(r"(20\d{2})", url)
    return m.group(1) if m else None


def year_from_filename(name: str) -> str | None:
    m = re.search(r"(20\d{2})", name)
    return m.group(1) if m else None


def download_file(url: str, dest: Path) -> bool:
    """Download a single file; return True on success."""
    if dest.exists():
        print(f"  [skip]  {dest.name} (ya existe)")
        return True
    try:
        r = SESSION.get(url, timeout=60, stream=True)
        r.raise_for_status()
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "wb") as fh:
            for chunk in r.iter_content(chunk_size=65536):
                fh.write(chunk)
        print(f"  [ok]    {dest.parent.name}/{dest.name}")
        return True
    except Exception as exc:
        print(f"  [error] {url} -> {exc}")
        return False


# ---------------------------------------------------------------------------
# Strategy 1: scrape the main page
# ---------------------------------------------------------------------------

def scrape_main_page() -> list[str]:
    url = (
        "https://www.ine.gob.cl/estadisticas-por-tema/"
        "mercado-laboral/ocupacion-y-desocupacion"
    )
    print(f"\n[1] Scrapeando página principal:\n    {url}")
    try:
        r = SESSION.get(url, timeout=30)
        r.raise_for_status()
    except Exception as exc:
        print(f"    Error: {exc}")
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    links = []
    for a in soup.find_all("a", href=True):
        href = a["href"].strip()
        if href.lower().endswith(".csv"):
            full = urljoin(url, href)
            links.append(full)
    print(f"    Links CSV encontrados en HTML: {len(links)}")
    return links


# ---------------------------------------------------------------------------
# Strategy 2: brute-force directory listing en bbdd/
# ---------------------------------------------------------------------------

BBDD_BASES = [
    "https://www.ine.gob.cl/docs/default-source/ocupacion-y-desocupacion/bbdd/",
    "https://www.ine.gob.cl/docs/default-source/mercado-laboral/ocupacion-y-desocupacion/bbdd/",
    "https://www.ine.gob.cl/docs/default-source/encuesta-nacional-de-empleo/bbdd/",
]

# Typical filename patterns observed in INE ENE datasets
FILE_PATTERNS = [
    # ene-{YYYY}-{trimester}.csv  (e.g. ene-2023-ond.csv)
    # ene-{YYYY}{MM}.csv
    # ene_{YYYY}_{MM}.csv
    # Various names — we'll try the directory listing first and fall back
]

TRIMESTRES = ["efs", "fma", "mam", "amj", "mjj", "jja", "jas", "aso",
              "son", "ond", "nde", "def",
              # older 2-letter codes
              "ef", "fm", "ma", "am", "mj", "jj", "ja", "as", "so", "on", "nd", "de"]
MESES = [f"{m:02d}" for m in range(1, 13)]


def try_directory_listing(base_url: str) -> list[str]:
    """Try to get an Apache/IIS-style directory listing."""
    try:
        r = SESSION.get(base_url, timeout=20)
        if r.status_code != 200:
            return []
        soup = BeautifulSoup(r.text, "html.parser")
        links = []
        for a in soup.find_all("a", href=True):
            href = a["href"].strip()
            if href.lower().endswith(".csv"):
                links.append(urljoin(base_url, href))
        return links
    except Exception:
        return []


def probe_urls_for_year(base: str, year: int) -> list[str]:
    """
    Probe common URL patterns for a given year and return those that exist (HTTP 200).
    """
    candidates = []

    # Pattern: base{year}/ene-{year}-{trimestre}.csv
    year_dirs = [
        f"{base}{year}/",
        f"{base}{year}-{year+1}/",  # sometimes academic years
        base,  # flat structure
    ]

    for ydir in year_dirs:
        # by trimester
        for tri in TRIMESTRES:
            candidates.append(f"{ydir}ene-{year}-{tri}.csv")
            candidates.append(f"{ydir}ene_{year}_{tri}.csv")
            candidates.append(f"{ydir}ENE-{year}-{tri}.csv")
        # by month (YYYYMM)
        for mes in MESES:
            candidates.append(f"{ydir}ene-{year}{mes}.csv")
            candidates.append(f"{ydir}ene_{year}{mes}.csv")
            candidates.append(f"{ydir}ene-{year}-{mes}.csv")

    found = []
    for url in candidates:
        try:
            r = SESSION.head(url, timeout=10, allow_redirects=True)
            if r.status_code == 200:
                ct = r.headers.get("Content-Type", "")
                if "html" not in ct.lower():
                    found.append(url)
        except Exception:
            pass

    return found


# ---------------------------------------------------------------------------
# Strategy 3: search INE sitemap / API endpoints used by the SPA
# ---------------------------------------------------------------------------

def scrape_spa_api() -> list[str]:
    """
    INE uses Sitefinity CMS. Try known API endpoints that return JSON
    lists of documents.
    """
    api_urls = [
        (
            "https://www.ine.gob.cl/api/estadisticas/mercado-laboral/"
            "ocupacion-y-desocupacion/bbdd"
        ),
        (
            "https://www.ine.gob.cl/docs/default-source/"
            "ocupacion-y-desocupacion/bbdd"
        ),
    ]
    links = []
    for api in api_urls:
        try:
            r = SESSION.get(api, timeout=20)
            if "application/json" in r.headers.get("Content-Type", ""):
                data = r.json()
                # Navigate typical structures
                for item in (data if isinstance(data, list) else []):
                    u = item.get("url") or item.get("Url") or ""
                    if u.lower().endswith(".csv"):
                        links.append(u)
        except Exception:
            pass
    return links


# ---------------------------------------------------------------------------
# Strategy 4: Scrape the INE document list via Sitefinity REST
# ---------------------------------------------------------------------------

def scrape_sitefinity_docs() -> list[str]:
    """
    Sitefinity (INE's CMS) exposes a REST endpoint for documents.
    Try to enumerate all CSVs in the ocupacion-y-desocupacion library.
    """
    endpoint = (
        "https://www.ine.gob.cl/api/default/documents"
        "?$filter=contains(UrlName,'ene') and contains(UrlName,'csv')"
        "&$select=Url,Title&$top=1000"
    )
    links = []
    try:
        r = SESSION.get(endpoint, timeout=20)
        if r.ok:
            data = r.json()
            items = data.get("value", data) if isinstance(data, dict) else data
            for item in (items if isinstance(items, list) else []):
                u = item.get("Url") or item.get("url") or ""
                if u:
                    links.append("https://www.ine.gob.cl" + u if u.startswith("/") else u)
    except Exception:
        pass
    return links


# ---------------------------------------------------------------------------
# Strategy 5: follow known INE document share links
# ---------------------------------------------------------------------------

def scrape_known_share_pages() -> list[str]:
    """
    Some INE pages list direct download links inside iframes or
    embedded document viewers — probe those.
    """
    share_urls = [
        "https://www.ine.gob.cl/estadisticas-por-tema/mercado-laboral/"
        "ocupacion-y-desocupacion#bases-de-datos",
    ]
    links = []
    for url in share_urls:
        try:
            r = SESSION.get(url, timeout=30)
            soup = BeautifulSoup(r.text, "html.parser")
            # look for any href containing .csv (case-insensitive) in full page
            for a in soup.find_all("a", href=True):
                href = a["href"]
                if ".csv" in href.lower():
                    links.append(urljoin(url, href))
            # look inside script tags for JSON-embedded document lists
            for script in soup.find_all("script"):
                text = script.string or ""
                urls_in_js = re.findall(
                    r'https?://[^\s\'"<>]+\.csv', text, re.IGNORECASE
                )
                links.extend(urls_in_js)
        except Exception:
            pass
    return links


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def collect_all_links() -> list[str]:
    all_links: set[str] = set()

    # 1. Main page scrape
    all_links.update(scrape_main_page())

    # 2. SPA / CMS API
    all_links.update(scrape_spa_api())
    all_links.update(scrape_sitefinity_docs())
    all_links.update(scrape_known_share_pages())

    # 3. Directory listing on known bbdd paths
    print("\n[2] Probando directory listing en rutas bbdd conocidas...")
    for base in BBDD_BASES:
        found = try_directory_listing(base)
        print(f"    {base} -> {len(found)} links")
        all_links.update(found)

    # 4. Brute-force by year if still nothing
    if not all_links:
        print("\n[3] No se encontraron links. Iniciando sondeo por año (2010-2025)...")
        for base in BBDD_BASES:
            for year in range(2010, 2026):
                found = probe_urls_for_year(base, year)
                if found:
                    print(f"    {year}: {len(found)} archivo(s) en {base}")
                all_links.update(found)
                time.sleep(0.3)

    return sorted(all_links)


def main():
    print("=" * 60)
    print("  Descargador ENE - INE Chile")
    print("=" * 60)

    links = collect_all_links()

    # Filter to ine.gob.cl only, just in case
    links = [l for l in links if "ine.gob.cl" in l]

    print(f"\nTotal de links CSV únicos encontrados: {len(links)}")

    if not links:
        print("\nNo se encontraron archivos CSV.\n")
        print("Sugerencias:")
        print("  - El sitio puede requerir JavaScript para cargar la lista.")
        print("  - Intenta con Selenium/Playwright para renderizar el JS.")
        return

    ok = 0
    fail = 0
    print("\nDescargando archivos...")
    for url in links:
        filename = Path(urlparse(url).path).name
        year = year_from_url(url) or year_from_filename(filename) or "sin_año"
        dest = BASE_DIR / year / filename
        if download_file(url, dest):
            ok += 1
        else:
            fail += 1
        time.sleep(0.2)  # polite crawl

    print("\n" + "=" * 60)
    print(f"  Descarga completa:")
    print(f"    Exitosos : {ok}")
    print(f"    Fallidos : {fail}")
    print(f"    Total    : {ok + fail}")
    print("=" * 60)

    # Summary by year
    print("\nArchivos por año:")
    year_dirs = sorted(BASE_DIR.glob("*/"))
    for d in year_dirs:
        if d.is_dir() and d.name != "__pycache__":
            csvs = list(d.glob("*.csv"))
            if csvs:
                print(f"  {d.name}: {len(csvs)} archivo(s)")


if __name__ == "__main__":
    main()
