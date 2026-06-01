# ENE - INE Chile (2010-2026)

Scripts para descargar las bases de datos de la Encuesta Nacional de Empleo (ENE)
del Instituto Nacional de Estadísticas de Chile.

## Contenido
- `descargar_ene_v2.py` — descarga el manifest completo desde el sitio INE
- `descarga_csv.py` — descarga todos los CSV organizados por año
- `manifest_completo.json` — índice de 1.270 archivos disponibles

## Uso
`ash
pip install requests beautifulsoup4
python descargar_ene_v2.py
python descarga_csv.py
`

## Fuente
https://www.ine.gob.cl/estadisticas-por-tema/mercado-laboral/ocupacion-y-desocupacion

210 archivos CSV | 2010-2026 | ~7.3 GB
