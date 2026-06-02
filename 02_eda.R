# =============================================================================
# 02_eda.R
# Análisis exploratorio ENE Chile 2010-2026
# Tasas laborales nacionales, por edad y Región de Antofagasta
# =============================================================================

library(data.table)
library(ggplot2)
library(scales)

BASE_DIR <- "C:/Users/psfel/descargas-ine"
setwd(BASE_DIR)

dir.create("graficos",   showWarnings = FALSE, recursive = TRUE)
dir.create("resultados", showWarnings = FALSE, recursive = TRUE)

# --- Paleta y tema base -------------------------------------------------------
AZUL   <- "#2166AC"
ROJO   <- "#D6604D"
NARANJA <- "#E07B00"
GRIS   <- "gray45"

tema_ene <- theme_minimal(base_size = 11) +
  theme(
    plot.title       = element_text(face = "bold", size = 12),
    plot.subtitle    = element_text(color = "gray40", size = 9),
    plot.caption     = element_text(color = "gray55", size = 8),
    panel.grid.minor = element_blank(),
    axis.text.x      = element_text(angle = 45, hjust = 1, size = 8),
    legend.position  = "top",
    legend.title     = element_blank(),
    plot.margin      = margin(8, 16, 8, 8)
  )

# --- Carga de datos -----------------------------------------------------------
cat("Cargando ene_consolidado.rds...\n")
ene <- readRDS("ene_consolidado.rds")

# Población en Edad de Trabajar: 15+ años, activ conocido
pet <- ene[edad >= 15 & !is.na(activ) & !is.na(fact_cal) & fact_cal > 0]
cat(sprintf("PET (edad>=15, activ y fact_cal válidos): %s filas\n\n",
            format(nrow(pet), big.mark = ",")))

# Fecha del trimestre = 1° del mes central
pet[, fecha := as.IDate(paste(ano, mes, "01", sep = "-"))]

# Grupos de edad
pet[, grupo_edad := fcase(
  edad >= 15 & edad <= 24, "15-24",
  edad >= 25 & edad <= 34, "25-34",
  edad >= 35 & edad <= 44, "35-44",
  edad >= 45 & edad <= 54, "45-54",
  edad >= 55 & edad <= 64, "55-64",
  edad >= 65,               "65+",
  default = NA_character_
)]
pet[, grupo_edad := factor(grupo_edad,
  levels = c("15-24", "25-34", "35-44", "45-54", "55-64", "65+"))]

# Etiqueta de sexo
pet[, sexo_label := fifelse(sexo == 1, "Hombre", "Mujer")]

# =============================================================================
# 1. TASAS NACIONALES POR TRIMESTRE
# =============================================================================
cat("Calculando tasas nacionales...\n")

# -- Total nacional ------------------------------------------------------------
nac <- pet[, .(
  w_ocup  = sum(fact_cal[activ == 1]),
  w_desoc = sum(fact_cal[activ == 2]),
  w_inact = sum(fact_cal[activ == 3]),
  w_pea   = sum(fact_cal[activ %in% c(1, 2)]),
  w_pet   = sum(fact_cal)
), by = .(fecha, ano, mes)][order(fecha)]

nac[, `:=`(
  td = w_desoc / w_pea,
  to = w_ocup  / w_pet,
  tp = w_pea   / w_pet
)]

cat("Tasas nacionales (primeros y últimos trimestres):\n")
print(nac[c(1:4, (.N - 3):.N),
          .(fecha, td = percent(td, 0.1), to = percent(to, 0.1), tp = percent(tp, 0.1))])

# -- Por sexo ------------------------------------------------------------------
nac_sexo <- pet[, .(
  w_ocup  = sum(fact_cal[activ == 1]),
  w_desoc = sum(fact_cal[activ == 2]),
  w_pea   = sum(fact_cal[activ %in% c(1, 2)]),
  w_pet   = sum(fact_cal)
), by = .(fecha, ano, mes, sexo_label)][order(fecha, sexo_label)]

nac_sexo[, `:=`(
  td = w_desoc / w_pea,
  to = w_ocup  / w_pet,
  tp = w_pea   / w_pet
)]

# =============================================================================
# 2. GRÁFICO SERIE DE TIEMPO NACIONAL (con hitos y sombreado COVID)
# =============================================================================
cat("\nGenerando graficos/01_desocupacion_nacional.png...\n")

# Hitos metodológicos e históricos
hitos <- data.table(
  fecha  = as.IDate(c("2017-08-01", "2019-10-01", "2020-03-01",
                       "2021-11-01", "2024-04-01")),
  label  = c("Nueva ENE\n(quiebre)", "Estallido\nsocial",
              "COVID-19", "Elecciones\npresidenciales", "Censo\n2024"),
  y_lbl  = c(0.235, 0.175, 0.265, 0.245, 0.195)  # posición vertical etiquetas
)

covid_shade <- data.frame(
  xmin = as.IDate("2020-03-01"), xmax = as.IDate("2021-12-01"),
  ymin = -Inf, ymax = Inf
)

p1 <- ggplot(nac_sexo, aes(x = as.Date(fecha), y = td,
                            color = sexo_label, linetype = sexo_label)) +
  # Sombreado COVID
  geom_rect(data = covid_shade,
            aes(xmin = as.Date(xmin), xmax = as.Date(xmax),
                ymin = ymin, ymax = ymax),
            inherit.aes = FALSE, fill = "#BDD7EE", alpha = 0.45) +
  annotate("text", x = as.Date("2020-11-15"), y = 0.028,
           label = "Período COVID", size = 2.8, color = "#2E6DA4",
           fontface = "italic") +
  # Líneas de hitos
  geom_vline(data = hitos,
             aes(xintercept = as.Date(fecha)),
             linetype = "dashed", color = GRIS, linewidth = 0.35,
             inherit.aes = FALSE) +
  # Etiquetas de hitos (escaladas)
  geom_text(data = hitos,
            aes(x = as.Date(fecha), y = y_lbl, label = label),
            inherit.aes = FALSE, hjust = -0.07, size = 2.4,
            color = "gray30", lineheight = 0.85) +
  # Series: cruda fada + tendencia LOESS encima
  geom_line(linewidth = 0.5, alpha = 0.25) +
  geom_smooth(method = "loess", span = 0.30, se = FALSE,
              linewidth = 1.1, alpha = 0.9) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    limits = c(0, 0.30),
    breaks = seq(0, 0.30, 0.04)
  ) +
  scale_x_date(
    date_breaks  = "1 year",
    date_labels  = "%Y",
    expand       = expansion(mult = c(0.01, 0.12))  # espacio para etiquetas
  ) +
  scale_color_manual(values   = c("Hombre" = AZUL, "Mujer" = ROJO)) +
  scale_linetype_manual(values = c("Hombre" = "solid", "Mujer" = "dashed")) +
  labs(
    title    = "Tasa de desocupación nacional — ENE Chile 2010-2026",
    subtitle = "Trimestres móviles · Población 15 años y más · Suavizado LOESS por sexo (span = 0.30)",
    x        = NULL,
    y        = "Tasa de desocupación",
    caption  = "Fuente: INE Chile — Encuesta Nacional de Empleo (ENE)"
  ) +
  tema_ene

ggsave("graficos/01_desocupacion_nacional.png", p1,
       width = 13, height = 6.5, dpi = 150, bg = "white")

# =============================================================================
# 3. TASA DE DESOCUPACIÓN POR GRUPO DE EDAD
# =============================================================================
cat("Generando graficos/02_desocupacion_edad.png...\n")

por_edad <- pet[!is.na(grupo_edad), .(
  w_desoc = sum(fact_cal[activ == 2]),
  w_pea   = sum(fact_cal[activ %in% c(1, 2)])
), by = .(fecha, grupo_edad)][order(fecha, grupo_edad)]

por_edad[, td := w_desoc / w_pea]

p2 <- ggplot(por_edad, aes(x = as.Date(fecha), y = td, color = grupo_edad)) +
  geom_rect(data = covid_shade,
            aes(xmin = as.Date(xmin), xmax = as.Date(xmax),
                ymin = ymin, ymax = ymax),
            inherit.aes = FALSE, fill = "#BDD7EE", alpha = 0.40) +
  geom_vline(xintercept = as.Date("2017-08-01"),
             linetype = "dashed", color = GRIS, linewidth = 0.4) +
  annotate("text", x = as.Date("2017-08-01"), y = 0.52,
           label = "Nueva ENE", hjust = -0.08, size = 2.6, color = GRIS) +
  geom_line(linewidth = 0.5, alpha = 0.25) +
  geom_smooth(method = "loess", span = 0.30, se = FALSE,
              linewidth = 1.0, alpha = 0.9) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    breaks = seq(0, 0.55, 0.05),
    limits = c(0, 0.56)
  ) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y",
               expand = expansion(mult = c(0.01, 0.02))) +
  scale_color_brewer(palette = "Set2") +
  labs(
    title    = "Tasa de desocupación por grupo de edad — ENE Chile 2010-2026",
    subtitle = "Trimestres móviles · Población 15 años y más · Suavizado LOESS por grupo (span = 0.30)",
    x        = NULL,
    y        = "Tasa de desocupación",
    color    = "Grupo de edad",
    caption  = "Fuente: INE Chile — Encuesta Nacional de Empleo (ENE)"
  ) +
  tema_ene +
  theme(legend.position = "right")

ggsave("graficos/02_desocupacion_edad.png", p2,
       width = 13, height = 6.5, dpi = 150, bg = "white")

# =============================================================================
# 4. ANTOFAGASTA vs NACIONAL
# =============================================================================
cat("Generando graficos/03_antofagasta_vs_nacional.png...\n")

antof <- pet[region == 2, .(
  w_desoc = sum(fact_cal[activ == 2]),
  w_pea   = sum(fact_cal[activ %in% c(1, 2)])
), by = .(fecha, ano, mes)][order(fecha)]

antof[, `:=`(td = w_desoc / w_pea, zona = "Antofagasta (Región 2)")]
nac_line <- nac[, .(fecha, td, zona = "Nacional")]

comparacion <- rbindlist(
  list(antof[, .(fecha, td, zona)], nac_line)
)

p3 <- ggplot(comparacion,
             aes(x = as.Date(fecha), y = td, color = zona, linewidth = zona)) +
  geom_rect(data = covid_shade,
            aes(xmin = as.Date(xmin), xmax = as.Date(xmax),
                ymin = ymin, ymax = ymax),
            inherit.aes = FALSE, fill = "#BDD7EE", alpha = 0.40) +
  geom_vline(xintercept = as.Date("2017-08-01"),
             linetype = "dashed", color = GRIS, linewidth = 0.4) +
  annotate("text", x = as.Date("2017-08-01"), y = 0.285,
           label = "Nueva ENE", hjust = -0.07, size = 2.6, color = GRIS) +
  # Serie Nacional: línea sólida
  geom_line(data = comparacion[zona == "Nacional"], alpha = 0.90) +
  # Serie Antofagasta: cruda fada + tendencia LOESS encima
  geom_line(data = comparacion[zona == "Antofagasta (Región 2)"], alpha = 0.25) +
  geom_smooth(
    data        = comparacion[zona == "Antofagasta (Región 2)"],
    aes(x = as.Date(fecha), y = td),
    inherit.aes = FALSE,
    method      = "loess", span = 0.30, se = TRUE,
    color       = NARANJA, fill = NARANJA,
    linewidth   = 1.2, alpha = 0.18
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    breaks = seq(0, 0.30, 0.02),
    limits = c(0, 0.30)
  ) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y",
               expand = expansion(mult = c(0.01, 0.04))) +
  scale_color_manual(values = c(
    "Antofagasta (Región 2)" = NARANJA,
    "Nacional"               = AZUL
  )) +
  scale_linewidth_manual(values = c(
    "Antofagasta (Región 2)" = 0.75,
    "Nacional"               = 1.10
  )) +
  labs(
    title    = "Tasa de desocupación: Antofagasta vs. Nacional — ENE Chile 2010-2026",
    subtitle = "Trimestres móviles · Población 15 años y más · Antofagasta con suavizado LOESS (span = 0.30)",
    x        = NULL,
    y        = "Tasa de desocupación",
    caption  = "Fuente: INE Chile — Encuesta Nacional de Empleo (ENE)"
  ) +
  tema_ene +
  guides(linewidth = "none")   # oculta leyenda de linewidth, queda solo color

ggsave("graficos/03_antofagasta_vs_nacional.png", p3,
       width = 13, height = 6.5, dpi = 150, bg = "white")

# =============================================================================
# 5. TABLA RESUMEN ANUAL
# =============================================================================
cat("Generando resultados/tabla_resumen_anual.csv...\n")

nac_anual <- nac[, .(
  td_nac_pct = round(weighted.mean(td, w = w_pea) * 100, 2),
  to_nac_pct = round(weighted.mean(to, w = w_pet) * 100, 2),
  tp_nac_pct = round(weighted.mean(tp, w = w_pet) * 100, 2)
), by = ano]

antof_anual <- antof[, .(
  td_antof_pct = round(weighted.mean(td, w = w_pea) * 100, 2)
), by = ano]

tabla <- merge(nac_anual, antof_anual, by = "ano", all.x = TRUE)
tabla[, brecha_pp := round(td_antof_pct - td_nac_pct, 2)]
setorder(tabla, ano)

setnames(tabla,
  old = c("ano", "td_nac_pct", "to_nac_pct", "tp_nac_pct",
          "td_antof_pct", "brecha_pp"),
  new = c("Ano", "TD_Nacional_%", "TO_Nacional_%", "TP_Nacional_%",
          "TD_Antofagasta_%", "Brecha_pp"))

fwrite(tabla, "resultados/tabla_resumen_anual.csv")

cat("\nTabla resumen anual:\n")
print(tabla, digits = 4)

# =============================================================================
# RESUMEN FINAL
# =============================================================================
cat("\n================================================================\n")
cat("                  SCRIPT 02_eda.R COMPLETADO\n")
cat("================================================================\n")
cat("Gráficos generados:\n")
cat("  graficos/01_desocupacion_nacional.png\n")
cat("  graficos/02_desocupacion_edad.png\n")
cat("  graficos/03_antofagasta_vs_nacional.png\n")
cat("Tabla guardada:\n")
cat("  resultados/tabla_resumen_anual.csv\n")
