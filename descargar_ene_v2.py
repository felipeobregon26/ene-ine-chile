"""
Descarga todos los archivos CSV de la sección BASES DE DATOS de la ENE
usando los endpoints AJAX reales del sitio INE (Sitefinity CMS).
"""

import os
import re
import time
import json
import requests
from pathlib import Path
from urllib.parse import urljoin

BASE_DIR = Path(__file__).parent
BASE_URL = "https://www.ine.gob.cl"
PAGE_URL = f"{BASE_URL}/estadisticas-por-tema/mercado-laboral/ocupacion-y-desocupacion"

# Folder IDs extraídos del HTML
FOLDER_IDS = {
    "CUADROS ESTADÍSTICOS":    "0aa7885f-6806-4ddc-a6b5-77bd3b2e0257",
    "BOLETINES":               "7279c0d2-8140-4937-be75-5a53661b3813",
    "PUBLICACIONES Y ANUARIOS":"f0d3f858-3487-4b08-97eb-4b32427d2944",
    "DOCUMENTOS DE TRABAJO":   "a208c4fa-caca-42de-8119-182456e04149",
    "INFOGRAFÍAS":             "95c67971-73ac-4897-8a83-b1d198dbddbe",
    "METODOLOGÍAS":            "bff0a195-70c9-4bd4-98c4-c10ade024862",
    "COMITÉS Y NOTAS TÉCNICAS":"12ba987a-9881-4495-9e44-fa98e858b282",
    "BASES DE DATOS":          "83b8e18c-5d25-4229-8289-8882d4f21478",
    "FORMULARIOS":             "04669e9f-f1a0-4b64-8e0f-66db32278b4d",
    "METADATOS":               "725d91aa-5ab6-443d-935c-1bce1743d81d",
}

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Referer": PAGE_URL,
    "X-Requested-With": "XMLHttpRequest",
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
}

SESSION = requests.Session()
SESSION.headers.update(HEADERS)

HIJOS_URL    = f"{PAGE_URL}/hijosCarpeta/"
ARCHIVOS_URL = f"{PAGE_URL}/getArchivos/"


# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

def get_subfolders(folder_id: str) -> list[dict]:
    try:
        r = SESSION.post(HIJOS_URL, data={"idFolder": folder_id}, timeout=30)
        r.raise_for_status()
        data = r.json()
        return data.get("folder", []) if isinstance(data, dict) else []
    except Exception as e:
        print(f"    [warn] hijosCarpeta({folder_id}): {e}")
        return []


def get_files(folder_id: str) -> list[dict]:
    try:
        r = SESSION.post(ARCHIVOS_URL, data={"idFolder": folder_id}, timeout=30)
        r.raise_for_status()
        data = r.json()
        return data.get("documento", []) if isinstance(data, dict) else []
    except Exception as e:
        print(f"    [warn] getArchivos({folder_id}): {e}")
        return []


# ---------------------------------------------------------------------------
# Year extraction
# ---------------------------------------------------------------------------

def year_from_text(*texts) -> str:
    for t in texts:
        if not t:
            continue
        m = re.search(r"(20\d{2})", str(t))
        if m:
            return m.group(1)
    return "sin_año"


# ---------------------------------------------------------------------------
# Recursive folder walker
# ---------------------------------------------------------------------------

def walk_folder(folder_id: str, folder_name: str, depth: int = 0) -> list[dict]:
    indent = "  " * depth
    print(f"{indent}[dir] {folder_name}")

    results = []

    # Files in this folder
    files = get_files(folder_id)
    for f in files:
        url  = f.get("Url") or f.get("url") or ""
        tipo = (f.get("Tipo") or "").lower()
        titulo = f.get("Titulo") or f.get("titulo") or ""
        desc   = f.get("Descripcion") or ""
        peso   = f.get("Peso") or ""
        if not url:
            continue
        full_url = url if url.startswith("http") else BASE_URL + url
        results.append({
            "url": full_url,
            "tipo": tipo,
            "titulo": titulo,
            "descripcion": desc,
            "peso": peso,
            "folder": folder_name,
        })
        print(f"{indent}  [file] [{tipo}] {titulo}  ({peso})")

    # Subfolders
    subs = get_subfolders(folder_id)
    for sub in subs:
        sub_id    = sub.get("Id") or sub.get("id") or ""
        sub_title = sub.get("Titulo") or sub.get("titulo") or sub_id
        if sub_id:
            results.extend(walk_folder(sub_id, sub_title, depth + 1))
        time.sleep(0.15)

    return results


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

def download_file(url: str, dest: Path) -> bool:
    if dest.exists():
        print(f"    [skip]  {dest.name}")
        return True
    try:
        r = SESSION.get(url, timeout=120, stream=True)
        r.raise_for_status()
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "wb") as fh:
            for chunk in r.iter_content(chunk_size=131072):
                fh.write(chunk)
        size_kb = dest.stat().st_size // 1024
        print(f"    [ok]    {dest.parent.name}/{dest.name}  ({size_kb} KB)")
        return True
    except Exception as e:
        print(f"    [error] {url}  -> {e}")
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 70)
    print("  Descargador ENE v2 – INE Chile (endpoints AJAX reales)")
    print("=" * 70)

    # Walk BASES DE DATOS (and all its subfolders recursively)
    bbdd_id = FOLDER_IDS["BASES DE DATOS"]
    print(f"\nExplorando árbol de BASES DE DATOS (id={bbdd_id})...\n")
    all_items = walk_folder(bbdd_id, "BASES DE DATOS")

    print(f"\nTotal de archivos encontrados: {len(all_items)}")

    # Show all types found
    tipos = {}
    for item in all_items:
        t = item["tipo"] or "desconocido"
        tipos[t] = tipos.get(t, 0) + 1
    print("Tipos encontrados:", tipos)

    # Save full manifest
    with open(BASE_DIR / "manifest_completo.json", "w", encoding="utf-8") as f:
        json.dump(all_items, f, ensure_ascii=False, indent=2)
    print(f"Manifiesto guardado en manifest_completo.json")

    # Filter CSVs
    csv_items = [i for i in all_items if ".csv" in i["url"].lower() or
                 i["tipo"] in (".csv", "csv")]

    # If no CSV filter found, try by tipo containing 'csv'
    if not csv_items:
        csv_items = [i for i in all_items if "csv" in i["tipo"].lower()]

    # If still nothing, download everything (maybe all are CSV under a different Tipo label)
    if not csv_items:
        print("\nNo se detectaron CSVs por extensión/tipo; descargando todo...")
        csv_items = all_items

    print(f"\nArchivos CSV a descargar: {len(csv_items)}\n")

    ok = fail = 0
    for item in csv_items:
        url    = item["url"]
        titulo = item["titulo"]
        desc   = item["descripcion"]
        year   = year_from_text(titulo, desc, url)
        # Build filename from URL tail, fallback to titulo
        from urllib.parse import urlparse, unquote
        path_part = urlparse(url).path
        filename  = unquote(Path(path_part).name) or re.sub(r'[\\/:*?"<>|]', "_", titulo) + ".csv"
        dest = BASE_DIR / year / filename
        if download_file(url, dest):
            ok += 1
        else:
            fail += 1
        time.sleep(0.2)

    print("\n" + "=" * 70)
    print(f"  Descarga completa:")
    print(f"    Exitosos : {ok}")
    print(f"    Fallidos : {fail}")
    print(f"    Total    : {ok + fail}")
    print("=" * 70)

    print("\nArchivos por año:")
    for d in sorted(BASE_DIR.glob("*/")):
        if d.is_dir() and d.name not in ("__pycache__",):
            files = list(d.glob("*"))
            if files:
                print(f"  {d.name}: {len(files)} archivo(s)")


if __name__ == "__main__":
    main()
