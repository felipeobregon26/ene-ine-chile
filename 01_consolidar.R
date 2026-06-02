# =============================================================================
# 01_consolidar.R
# Consolida todos los archivos trimestrales ENE 2010-2026 en un único RDS
# con las variables comparables entre épocas.
#
# Fuente: INE Chile - Encuesta Nacional de Empleo
# Épocas del cuestionario:
#   1 = 2010-2012       ENE clásica (CIUO-88, CIIU Rev.3)
#   2 = 2013-2016       + rama CAENES
#   3 = 2017-2019       Nueva ENE (CIUO-08, nuevo marco muestral)
#   4 = 2020 - feb/2022 COVID (migración, plataformas, turnos)
#   5 = mar/2022 - 2026 Estructura estable actual
# =============================================================================

library(data.table)

# --- Configuración -----------------------------------------------------------

BASE_DIR  <- "C:/Users/psfel/descargas-ine"
SALIDA    <- file.path(BASE_DIR, "ene_consolidado.rds")

# Variables a extraer. fact_cal está presente en todos los períodos.
VARS_KEEP <- c("region", "sexo", "edad", "activ", "fact_cal")

setwd(BASE_DIR)

# --- Funciones auxiliares ----------------------------------------------------

asignar_epoca <- function(ano, mes) {
  fifelse(ano <= 2012, 1L,
  fifelse(ano <= 2016, 2L,
  fifelse(ano <= 2019, 3L,
  fifelse(ano < 2022 | (ano == 2022L & mes <= 2L), 4L, 5L))))
}

leer_ene <- function(ruta) {
  # Extraer año, mes y trimestre del nombre del archivo
  # Ejemplo: ene-2024-12-nde.csv → 2024, 12, "nde"
  partes <- strsplit(tools::file_path_sans_ext(basename(ruta)), "-")[[1]]
  ano_v  <- as.integer(partes[2])
  mes_v  <- as.integer(partes[3])
  trim_v <- partes[4]

  # Detectar qué variables de interés existen en este archivo
  # (lectura de 0 filas para obtener solo el header)
  cols_header   <- names(fread(ruta, sep = ";", nrows = 0L, encoding = "UTF-8",
                               showProgress = FALSE))
  cols_leer     <- intersect(VARS_KEEP, cols_header)
  cols_ausentes <- setdiff(VARS_KEEP, cols_header)

  # Leer solo las columnas necesarias
  dt <- fread(ruta, sep = ";", encoding = "UTF-8",
              select = cols_leer, showProgress = FALSE)

  # Rellenar con NA las variables ausentes en esta época
  for (v in cols_ausentes) set(dt, j = v, value = NA_real_)

  # Añadir columnas de identificación temporal y época
  dt[, `:=`(
    ano       = ano_v,
    mes       = mes_v,
    trimestre = trim_v,
    epoca     = asignar_epoca(ano_v, mes_v)
  )]

  dt
}

# --- Listar archivos ---------------------------------------------------------

archivos <- list.files(
  path       = as.character(2010:2026),
  pattern    = "^ene-\\d{4}-\\d{2}-[a-z]+\\.csv$",
  full.names = TRUE
)

cat(sprintf("Archivos mensuales encontrados: %d\n\n", length(archivos)))

# --- Leer y consolidar -------------------------------------------------------

cat("Leyendo archivos...\n")
t_inicio <- proc.time()

lista <- vector("list", length(archivos))

for (i in seq_along(archivos)) {
  lista[[i]] <- leer_ene(archivos[i])
  if (i %% 25 == 0 || i == length(archivos)) {
    cat(sprintf("  [%d/%d] %s\n", i, length(archivos), basename(archivos[i])))
  }
}

cat("\nConsolidando en un único data.table...\n")
ene <- rbindlist(lista, fill = TRUE)

# Orden lógico de columnas
setcolorder(ene, c("ano", "mes", "trimestre", "epoca",
                   "region", "sexo", "edad", "activ", "fact_cal"))

# Tipos correctos
ene[, `:=`(
  region = as.integer(region),
  sexo   = as.integer(sexo),
  edad   = as.integer(edad),
  activ  = as.integer(activ),
  epoca  = as.integer(epoca)
)]

# --- Guardar -----------------------------------------------------------------

cat(sprintf("Guardando en: %s\n", SALIDA))
saveRDS(ene, SALIDA)

t_total <- proc.time() - t_inicio
cat(sprintf("Tiempo total: %.1f segundos\n", t_total["elapsed"]))

# --- Resumen -----------------------------------------------------------------

ETIQ_EPOCA <- c(
  "1" = "Época 1 (2010-2012): ENE clásica, CIUO-88",
  "2" = "Época 2 (2013-2016): + rama CAENES",
  "3" = "Época 3 (2017-2019): Nueva ENE, CIUO-08",
  "4" = "Época 4 (2020-feb/2022): COVID",
  "5" = "Época 5 (mar/2022-2026): Estructura estable"
)

cat("\n")
cat("================================================================\n")
cat("                        RESUMEN FINAL\n")
cat("================================================================\n")
cat(sprintf("Total de filas:     %s\n",   format(nrow(ene), big.mark = ",")))
cat(sprintf("Total de columnas:  %d\n",   ncol(ene)))
cat(sprintf("Archivos leídos:    %d\n",   length(archivos)))
cat(sprintf("Período:            %d-%d\n", min(ene$ano), max(ene$ano)))
cat(sprintf("fact_cal completo:  %.1f%%\n",
            100 * mean(!is.na(ene$fact_cal))))
cat(sprintf("activ sin NA:       %.1f%%\n",
            100 * mean(!is.na(ene$activ))))

cat("\n--- Distribución por época ---\n")
por_epoca <- ene[, .(
  trimestres = uniqueN(paste(ano, mes)),
  filas      = .N,
  pct        = round(100 * .N / nrow(ene), 1)
), by = epoca][order(epoca)]
por_epoca[, etiqueta := ETIQ_EPOCA[as.character(epoca)]]
print(por_epoca[, .(etiqueta, trimestres, filas, pct)], row.names = FALSE)

cat("\n--- Distribución por año ---\n")
por_anio <- ene[, .(
  trimestres = uniqueN(mes),
  filas      = .N,
  epoca      = as.integer(median(epoca))
), by = ano][order(ano)]
print(por_anio, row.names = FALSE)

cat("\n--- Distribución de activ (global) ---\n")
por_activ <- ene[!is.na(activ), .(
  n     = .N,
  exp   = round(sum(fact_cal, na.rm = TRUE) / 1e6, 1)
), by = activ][order(activ)]
por_activ[, etiq := c("1" = "Ocupado", "2" = "Desocupado", "3" = "Inactivo")[as.character(activ)]]
por_activ[, pct_n := round(100 * n / sum(n), 1)]
print(por_activ[, .(etiq, n, pct_n, exp_millones = exp)], row.names = FALSE)

cat("\n¡Consolidación completada!\n")
cat(sprintf("RDS guardado en: %s\n", SALIDA))
