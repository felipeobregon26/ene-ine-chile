#!/usr/bin/env python3
"""Descarga archivos de la carpeta 'Formato CSV' del manifest, organizados por año."""

import json
import os
import re
import sys
import time
import urllib.request
from urllib.parse import urlparse
from pathlib import Path

MANIFEST = "manifest_completo.json"
BASE_DIR = Path(".")
FOLDER_FILTRO = "Formato CSV"

def extraer_año(url):
    path = urlparse(url).path
    fname = os.path.basename(path)
    m = re.search(r"(19|20)\d{2}", fname)
    return m.group() if m else "general"

def formato_bytes(b):
    if b < 1024:
        return f"{b} B"
    elif b < 1024**2:
        return f"{b/1024:.1f} KB"
    elif b < 1024**3:
        return f"{b/1024**2:.1f} MB"
    else:
        return f"{b/1024**3:.2f} GB"

def descargar(url, dest_path):
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=120) as resp:
        total = int(resp.headers.get("Content-Length", 0))
        descargado = 0
        chunk = 65536
        with open(dest_path, "wb") as f:
            while True:
                data = resp.read(chunk)
                if not data:
                    break
                f.write(data)
                descargado += len(data)
                if total:
                    pct = descargado * 100 // total
                    bar = "#" * (pct // 5) + "-" * (20 - pct // 5)
                    print(f"\r    [{bar}] {pct:3d}% {formato_bytes(descargado)}/{formato_bytes(total)}", end="", flush=True)
        print()
    return descargado

def main():
    with open(MANIFEST, encoding="utf-8") as f:
        data = json.load(f)

    archivos = [d for d in data if d.get("folder", "") == FOLDER_FILTRO]
    print(f"Archivos encontrados en '{FOLDER_FILTRO}': {len(archivos)}")

    total_peso = sum(int(d.get("peso", 0)) for d in archivos if d.get("peso"))
    print(f"Tamaño total estimado: {formato_bytes(total_peso)}\n")

    exitos = 0
    fallos = []
    bytes_descargados = 0
    t_inicio = time.time()

    for i, archivo in enumerate(archivos, 1):
        url = archivo["url"]
        titulo = archivo.get("titulo", "sin_titulo")
        año = extraer_año(url)

        # Nombre de archivo desde la URL (sin query string)
        url_path = urlparse(url).path
        nombre = os.path.basename(url_path)
        if not nombre:
            nombre = re.sub(r"[^\w\-.]", "_", titulo) + archivo.get("tipo", ".csv")

        carpeta = BASE_DIR / año
        carpeta.mkdir(parents=True, exist_ok=True)
        dest = carpeta / nombre

        print(f"[{i:3d}/{len(archivos)}] {año}/{nombre}  ({formato_bytes(int(archivo.get('peso', 0)))})")

        if dest.exists() and dest.stat().st_size > 0:
            print("    Ya existe, omitiendo.")
            exitos += 1
            bytes_descargados += dest.stat().st_size
            continue

        intentos = 3
        for intento in range(1, intentos + 1):
            try:
                n = descargar(url, dest)
                bytes_descargados += n
                exitos += 1
                break
            except Exception as e:
                print(f"    Error intento {intento}/{intentos}: {e}")
                if dest.exists():
                    dest.unlink()
                if intento < intentos:
                    time.sleep(5)
                else:
                    fallos.append({"url": url, "error": str(e)})

    elapsed = time.time() - t_inicio
    print("\n" + "="*60)
    print(f"  DESCARGA COMPLETADA")
    print(f"  Archivos exitosos : {exitos}/{len(archivos)}")
    print(f"  Archivos fallidos : {len(fallos)}")
    print(f"  Total descargado  : {formato_bytes(bytes_descargados)}")
    print(f"  Tiempo total      : {elapsed/60:.1f} min")
    print("="*60)

    if fallos:
        print("\nFallidos:")
        for f in fallos:
            print(f"  {f['url']}  -> {f['error']}")

if __name__ == "__main__":
    main()
