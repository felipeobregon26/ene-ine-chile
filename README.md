# ENE — INE Chile (2010-2026)

Análisis del mercado laboral chileno con microdatos de la **Encuesta Nacional de Empleo (ENE)** del Instituto Nacional de Estadísticas (INE). Cubre 210 archivos CSV trimestrales (~7.3 GB) para el período 2010–2026, con foco en tasas de desocupación nacionales y de la **Región de Antofagasta**, desagregadas por sexo y grupo de edad.

## Estructura del repositorio

```
descargas-ine/
├── 2010/ … 2026/          # Microdatos CSV por año (no incluidos en git)
├── graficos/              # Gráficos PNG generados
├── resultados/            # Tablas CSV con resultados
├── investigar_ine.py      # Exploración inicial del sitio INE
├── descargar_ene_v2.py    # Descarga del manifest completo
├── descarga_csv.py        # Descarga masiva de CSV por año
├── 01_consolidar.R        # Consolida todos los CSV en un único RDS
├── 02_eda.R               # Análisis exploratorio y gráficos 01-03
├── 03_sexo_edad.R         # Análisis por sexo y edad, gráficos 04-07
├── ene_consolidado.rds    # Dataset consolidado (~152 MB, no en git)
├── manifest_completo.json # Índice de 1.270 archivos disponibles
├── reporte_estructura.md  # Inventario detallado de archivos por año
└── HALLAZGOS.md           # Hallazgos, interpretaciones y próximos pasos
```

## Pipeline de análisis

### Paso 1 — Descarga

```bash
pip install requests beautifulsoup4
python descargar_ene_v2.py   # genera manifest_completo.json
python descarga_csv.py       # descarga ~210 CSV en carpetas por año
```

### Paso 2 — Consolidación (R)

```r
# Requiere: data.table
source("01_consolidar.R")
# Salida: ene_consolidado.rds (~152 MB)
```

### Paso 3 — Análisis y gráficos (R)

```r
# Requiere: data.table, ggplot2, scales
source("02_eda.R")        # gráficos 01-03, tabla_resumen_anual.csv

# Requiere: data.table, ggplot2, scales, patchwork
source("03_sexo_edad.R")  # gráficos 04-07, tabla_sexo_anual.csv
```

## Gráficos generados

| Archivo | Descripción |
|---------|-------------|
| `01_desocupacion_nacional.png` | Serie de tiempo nacional por sexo con hitos (2010-2026) |
| `02_desocupacion_edad.png` | Desocupación por 6 grupos de edad (2010-2026) |
| `03_antofagasta_vs_nacional.png` | Antofagasta vs. Nacional (2010-2026) |
| `04_desocupacion_sexo_nacional.png` | Brecha de género nacional con panel de diferencia |
| `05_desocupacion_sexo_antofagasta.png` | Brecha de género en Antofagasta con IC 95% |
| `06_desocupacion_grupos_edad.png` | Desocupación juvenil (15-24) vs. adulta (25-54) y 55+ |
| `07_covid_por_sexo.png` | Zoom 2019-2022: TD y tasa de participación por sexo |

## Hallazgos principales

- Antofagasta pasó de estar **por debajo** de la media nacional hasta 2013 (auge minero) a **superar** el promedio hasta 2022 (contracción minera), y volvió a situarse por debajo en 2023-2026.
- El **COVID-19** elevó la TD nacional del ~7% al ~14% en 2020; la recuperación dejó un piso más alto (~8.5%) que persiste en 2025-2026.
- La **brecha de género** (Mujer − Hombre) se comprimió durante COVID porque las mujeres abandonaron la fuerza laboral (desaliento) en mayor proporción que los hombres.
- La **desocupación juvenil** (15-24) supera estructuralmente el doble de la tasa adulta y no ha retornado a los mínimos pre-COVID.

Ver `HALLAZGOS.md` para el análisis completo con tablas de datos e interpretación de cada gráfico.

## Épocas metodológicas ENE

| Época | Período | Nota |
|-------|---------|------|
| 1 | 2010-2012 | ENE clásica (CIUO-88) |
| 2 | 2013-2016 | + rama CAENES |
| 3 | 2017-2019 | Nueva ENE (nuevo marco muestral) |
| 4 | 2020-feb/2022 | Cuestionario COVID |
| 5 | mar/2022-2026 | Estructura estable actual |

Los quiebres entre épocas (especialmente 2016→2017) afectan la comparabilidad de largo plazo.

## Fuente

Instituto Nacional de Estadísticas de Chile — Encuesta Nacional de Empleo (ENE)  
https://www.ine.gob.cl/estadisticas-por-tema/mercado-laboral/ocupacion-y-desocupacion

210 archivos CSV | 2010-2026 | ~7.3 GB
