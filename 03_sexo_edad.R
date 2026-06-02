# =============================================================================
# 03_sexo_edad.R
# Análisis por sexo y grupos de edad — ENE Chile 2010-2026
# Gráficos 04-07 y tabla_sexo_anual.csv
# =============================================================================

library(data.table)
library(ggplot2)
library(scales)
if (!requireNamespace("patchwork", quietly = TRUE)) install.packages("patchwork")
library(patchwork)

BASE_DIR <- "C:/Users/psfel/descargas-ine"
setwd(BASE_DIR)
dir.create("graficos",   showWarnings = FALSE)
dir.create("resultados", showWarnings = FALSE)

AZUL    <- "#2166AC"
ROJO    <- "#D6604D"
NARANJA <- "#E07B00"
VERDE   <- "#4DAC26"
ROSA    <- "#E7298A"
GRIS    <- "gray45"

tema_ene <- theme_minimal(base_size = 11) + theme(
  plot.title       = element_text(face = "bold", size = 12),
  plot.subtitle    = element_text(color = "gray40", size = 9),
  plot.caption     = element_text(color = "gray55", size = 8),
  panel.grid.minor = element_blank(),
  axis.text.x      = element_text(angle = 45, hjust = 1, size = 8),
  legend.position  = "top",
  legend.title     = element_blank(),
  plot.margin      = margin(8, 16, 8, 8)
)

# --- Carga y preparación -----------------------------------------------------
cat("Cargando ene_consolidado.rds...\n")
ene <- readRDS("ene_consolidado.rds")

pet <- ene[edad >= 15 & !is.na(activ) & !is.na(fact_cal) & fact_cal > 0]
pet[, fecha      := as.IDate(paste(ano, mes, "01", sep = "-"))]
pet[, sexo_label := fifelse(sexo == 1L, "Hombre", "Mujer")]
pet[, grupo3     := fcase(
  edad >= 15L & edad <= 24L, "15-24",
  edad >= 25L & edad <= 54L, "25-54",
  edad >= 55L,                "55+",
  default = NA_character_
)]
pet[, grupo3 := factor(grupo3, levels = c("15-24", "25-54", "55+"))]

cat(sprintf("PET válida: %s filas\n\n", format(nrow(pet), big.mark = ",")))

# --- Tasas por sexo ----------------------------------------------------------
calc_sexo <- function(dt) {
  r <- dt[, .(
    w_ocup  = sum(fact_cal[activ == 1L]),
    w_desoc = sum(fact_cal[activ == 2L]),
    w_pea   = sum(fact_cal[activ %in% c(1L, 2L)]),
    w_pet   = sum(fact_cal)
  ), by = .(fecha, ano, mes, sexo_label)][order(fecha, sexo_label)]
  r[, `:=`(td = w_desoc / w_pea, tp = w_pea / w_pet)]
  r
}

nac_sexo   <- calc_sexo(pet)
antof_sexo <- calc_sexo(pet[region == 2L])

# Brecha trimestral (Mujer - Hombre)
calc_brecha <- function(dt) {
  w <- dcast(dt, fecha + ano + mes ~ sexo_label, value.var = "td")
  w[, brecha := Mujer - Hombre]
  w
}

brecha_nac   <- calc_brecha(nac_sexo)
brecha_antof <- calc_brecha(antof_sexo)

# Elementos comunes de los gráficos
hitos3 <- data.table(
  fecha = as.IDate(c("2017-08-01", "2019-10-01", "2020-03-01")),
  label = c("Nueva ENE", "Estallido social", "COVID-19")
)

sombra_covid <- data.frame(
  xmin = as.IDate("2020-03-01"), xmax = as.IDate("2021-12-01"),
  ymin = -Inf, ymax = Inf
)

# =============================================================================
# 1. BRECHA DE GÉNERO NACIONAL
# =============================================================================
cat("Generando graficos/04_desocupacion_sexo_nacional.png...\n")

p_td_nac <- ggplot(nac_sexo,
                   aes(x = as.Date(fecha), y = td, color = sexo_label,
                       fill = sexo_label)) +
  geom_rect(data = sombra_covid,
            aes(xmin = as.Date(xmin), xmax = as.Date(xmax),
                ymin = ymin, ymax = ymax),
            inherit.aes = FALSE, fill = "#BDD7EE", alpha = 0.35) +
  geom_vline(data = hitos3, aes(xintercept = as.Date(fecha)),
             inherit.aes = FALSE, linetype = "dashed",
             color = GRIS, linewidth = 0.35) +
  geom_text(data = hitos3,
            aes(x = as.Date(fecha), y = 0.185, label = label),
            inherit.aes = FALSE, hjust = -0.05, size = 2.3, color = "gray35") +
  geom_line(linewidth = 0.45, alpha = 0.22) +
  geom_smooth(method = "loess", span = 0.30, se = FALSE, linewidth = 1.1) +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     limits = c(0, 0.20), breaks = seq(0, 0.20, 0.02)) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y",
               expand = expansion(mult = c(0.01, 0.09))) +
  scale_color_manual(values = c("Hombre" = AZUL, "Mujer" = ROJO)) +
  scale_fill_manual(values  = c("Hombre" = AZUL, "Mujer" = ROJO)) +
  labs(title    = "Tasa de desocupación por sexo — Nacional ENE Chile 2010-2026",
       subtitle = "LOESS span = 0.30 · Población 15 años y más",
       x = NULL, y = "Tasa de desocupación") +
  tema_ene

p_brecha_nac <- ggplot(brecha_nac, aes(x = as.Date(fecha), y = brecha)) +
  geom_rect(data = sombra_covid,
            aes(xmin = as.Date(xmin), xmax = as.Date(xmax),
                ymin = ymin, ymax = ymax),
            inherit.aes = FALSE, fill = "#BDD7EE", alpha = 0.35) +
  geom_vline(data = hitos3, aes(xintercept = as.Date(fecha)),
             inherit.aes = FALSE, linetype = "dashed",
             color = GRIS, linewidth = 0.35) +
  geom_hline(yintercept = 0, color = "gray50", linewidth = 0.6,
             linetype = "solid") +
  geom_line(linewidth = 0.45, alpha = 0.22, color = VERDE) +
  geom_smooth(method = "loess", span = 0.30, se = TRUE, linewidth = 1.0,
              color = VERDE, fill = VERDE, alpha = 0.18) +
  scale_y_continuous(
    labels = function(x) sprintf("%+.1f pp", x * 100),
    breaks = seq(-0.04, 0.08, 0.01)
  ) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y",
               expand = expansion(mult = c(0.01, 0.09))) +
  labs(x = NULL, y = "Brecha (Mujer − Hombre)",
       caption = "Fuente: INE Chile — Encuesta Nacional de Empleo (ENE)") +
  tema_ene + theme(legend.position = "none")

p4 <- p_td_nac / p_brecha_nac + plot_layout(heights = c(3, 1.8))

ggsave("graficos/04_desocupacion_sexo_nacional.png", p4,
       width = 13, height = 9, dpi = 150, bg = "white")

# =============================================================================
# 2. BRECHA ANTOFAGASTA
# =============================================================================
cat("Generando graficos/05_desocupacion_sexo_antofagasta.png...\n")

p_td_antof <- ggplot(antof_sexo,
                     aes(x = as.Date(fecha), y = td, color = sexo_label,
                         fill = sexo_label)) +
  geom_rect(data = sombra_covid,
            aes(xmin = as.Date(xmin), xmax = as.Date(xmax),
                ymin = ymin, ymax = ymax),
            inherit.aes = FALSE, fill = "#BDD7EE", alpha = 0.35) +
  geom_vline(data = hitos3, aes(xintercept = as.Date(fecha)),
             inherit.aes = FALSE, linetype = "dashed",
             color = GRIS, linewidth = 0.35) +
  geom_text(data = hitos3,
            aes(x = as.Date(fecha), y = 0.205, label = label),
            inherit.aes = FALSE, hjust = -0.05, size = 2.3, color = "gray35") +
  geom_line(linewidth = 0.45, alpha = 0.18) +
  geom_smooth(method = "loess", span = 0.30, se = TRUE,
              linewidth = 1.1, alpha = 0.15) +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     limits = c(0, 0.22), breaks = seq(0, 0.22, 0.02)) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y",
               expand = expansion(mult = c(0.01, 0.09))) +
  scale_color_manual(values = c("Hombre" = AZUL, "Mujer" = ROJO)) +
  scale_fill_manual(values  = c("Hombre" = AZUL, "Mujer" = ROJO)) +
  labs(title    = "Tasa de desocupación por sexo — Antofagasta (Región 2) ENE 2010-2026",
       subtitle = "LOESS span = 0.30 · Banda = IC 95% · Población 15 años y más",
       x = NULL, y = "Tasa de desocupación") +
  tema_ene

p_brecha_antof <- ggplot(brecha_antof, aes(x = as.Date(fecha), y = brecha)) +
  geom_rect(data = sombra_covid,
            aes(xmin = as.Date(xmin), xmax = as.Date(xmax),
                ymin = ymin, ymax = ymax),
            inherit.aes = FALSE, fill = "#BDD7EE", alpha = 0.35) +
  geom_vline(data = hitos3, aes(xintercept = as.Date(fecha)),
             inherit.aes = FALSE, linetype = "dashed",
             color = GRIS, linewidth = 0.35) +
  geom_hline(yintercept = 0, color = "gray50", linewidth = 0.6) +
  geom_line(linewidth = 0.45, alpha = 0.18, color = NARANJA) +
  geom_smooth(method = "loess", span = 0.30, se = TRUE, linewidth = 1.0,
              color = NARANJA, fill = NARANJA, alpha = 0.18) +
  scale_y_continuous(
    labels = function(x) sprintf("%+.1f pp", x * 100)
  ) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y",
               expand = expansion(mult = c(0.01, 0.09))) +
  labs(x = NULL, y = "Brecha (Mujer − Hombre)",
       caption = "Fuente: INE Chile — Encuesta Nacional de Empleo (ENE)") +
  tema_ene + theme(legend.position = "none")

p5 <- p_td_antof / p_brecha_antof + plot_layout(heights = c(3, 1.8))

ggsave("graficos/05_desocupacion_sexo_antofagasta.png", p5,
       width = 13, height = 9, dpi = 150, bg = "white")

# =============================================================================
# 3. DESOCUPACIÓN JUVENIL (15-24 / 25-54 / 55+)
# =============================================================================
cat("Generando graficos/06_desocupacion_grupos_edad.png...\n")

por_g3 <- pet[!is.na(grupo3), .(
  w_desoc = sum(fact_cal[activ == 2L]),
  w_pea   = sum(fact_cal[activ %in% c(1L, 2L)])
), by = .(fecha, grupo3)][order(fecha, grupo3)]
por_g3[, td := w_desoc / w_pea]

COLS_G3 <- c("15-24" = ROSA, "25-54" = AZUL, "55+" = VERDE)

p6 <- ggplot(por_g3, aes(x = as.Date(fecha), y = td,
                          color = grupo3, fill = grupo3)) +
  geom_rect(data = sombra_covid,
            aes(xmin = as.Date(xmin), xmax = as.Date(xmax),
                ymin = ymin, ymax = ymax),
            inherit.aes = FALSE, fill = "#BDD7EE", alpha = 0.35) +
  geom_vline(data = hitos3, aes(xintercept = as.Date(fecha)),
             inherit.aes = FALSE, linetype = "dashed",
             color = GRIS, linewidth = 0.35) +
  geom_text(data = hitos3,
            aes(x = as.Date(fecha), y = 0.325, label = label),
            inherit.aes = FALSE, hjust = -0.05, size = 2.3, color = "gray35") +
  geom_line(linewidth = 0.45, alpha = 0.20) +
  geom_smooth(method = "loess", span = 0.30, se = TRUE,
              linewidth = 1.1, alpha = 0.12) +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     limits = c(0, 0.36), breaks = seq(0, 0.35, 0.05)) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y",
               expand = expansion(mult = c(0.01, 0.09))) +
  scale_color_manual(values = COLS_G3) +
  scale_fill_manual(values  = COLS_G3) +
  labs(title    = "Desocupación juvenil vs. adulta — Nacional ENE Chile 2010-2026",
       subtitle = "LOESS span = 0.30 · Banda = IC 95% · Población 15 años y más",
       x = NULL, y = "Tasa de desocupación",
       color = "Grupo de edad", fill = "Grupo de edad",
       caption = "Fuente: INE Chile — Encuesta Nacional de Empleo (ENE)") +
  tema_ene + theme(legend.position = "right")

ggsave("graficos/06_desocupacion_grupos_edad.png", p6,
       width = 13, height = 6.5, dpi = 150, bg = "white")

# =============================================================================
# 4. COVID POR SEXO — zoom ene-2019 a dic-2022
# =============================================================================
cat("Generando graficos/07_covid_por_sexo.png...\n")

zoom <- nac_sexo[fecha >= as.IDate("2019-01-01") &
                 fecha <= as.IDate("2022-12-01")]

sombra_zoom <- data.frame(
  xmin = as.IDate("2020-03-01"), xmax = as.IDate("2021-12-01"),
  ymin = -Inf, ymax = Inf
)

p_td_covid <- ggplot(zoom, aes(x = as.Date(fecha), y = td,
                                color = sexo_label, fill = sexo_label)) +
  geom_rect(data = sombra_zoom,
            aes(xmin = as.Date(xmin), xmax = as.Date(xmax),
                ymin = ymin, ymax = ymax),
            inherit.aes = FALSE, fill = "#BDD7EE", alpha = 0.45) +
  annotate("text", x = as.Date("2020-10-01"), y = 0.005,
           label = "Período COVID", size = 2.8,
           color = "#2E6DA4", fontface = "italic") +
  geom_line(linewidth = 0.5, alpha = 0.25) +
  geom_smooth(method = "loess", span = 0.40, se = FALSE, linewidth = 1.2) +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     limits = c(0, 0.22), breaks = seq(0, 0.22, 0.02)) +
  scale_x_date(date_breaks = "3 months", date_labels = "%b\n%Y",
               expand = expansion(mult = c(0.01, 0.01))) +
  scale_color_manual(values = c("Hombre" = AZUL, "Mujer" = ROJO)) +
  scale_fill_manual(values  = c("Hombre" = AZUL, "Mujer" = ROJO)) +
  labs(title    = "Impacto COVID en el mercado laboral por sexo — Nacional 2019-2022",
       subtitle = "Tasa de desocupación · LOESS span = 0.40",
       x = NULL, y = "Tasa de desocupación") +
  tema_ene

p_tp_covid <- ggplot(zoom, aes(x = as.Date(fecha), y = tp,
                                color = sexo_label, fill = sexo_label)) +
  geom_rect(data = sombra_zoom,
            aes(xmin = as.Date(xmin), xmax = as.Date(xmax),
                ymin = ymin, ymax = ymax),
            inherit.aes = FALSE, fill = "#BDD7EE", alpha = 0.45) +
  geom_line(linewidth = 0.5, alpha = 0.25) +
  geom_smooth(method = "loess", span = 0.40, se = FALSE, linewidth = 1.2) +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     breaks = seq(0.30, 0.80, 0.05)) +
  scale_x_date(date_breaks = "3 months", date_labels = "%b\n%Y",
               expand = expansion(mult = c(0.01, 0.01))) +
  scale_color_manual(values = c("Hombre" = AZUL, "Mujer" = ROJO)) +
  scale_fill_manual(values  = c("Hombre" = AZUL, "Mujer" = ROJO)) +
  labs(subtitle = "Tasa de participación laboral · LOESS span = 0.40",
       x = NULL, y = "Tasa de participación",
       caption = "Fuente: INE Chile — Encuesta Nacional de Empleo (ENE)") +
  tema_ene

p7 <- p_td_covid / p_tp_covid +
  plot_layout(guides = "collect") &
  theme(legend.position = "top")

ggsave("graficos/07_covid_por_sexo.png", p7,
       width = 13, height = 9, dpi = 150, bg = "white")

# =============================================================================
# 5. TABLA SEXO ANUAL
# =============================================================================
cat("Generando resultados/tabla_sexo_anual.csv...\n")

nac_anual <- dcast(
  nac_sexo[, .(td_pct = round(weighted.mean(td, w = w_pea) * 100, 2)),
           by = .(ano, sexo_label)],
  ano ~ sexo_label, value.var = "td_pct"
)
setnames(nac_anual, c("Hombre", "Mujer"),
         c("TD_Hombre_Nac_%", "TD_Mujer_Nac_%"))
nac_anual[, Brecha_Nac_pp := round(`TD_Mujer_Nac_%` - `TD_Hombre_Nac_%`, 2)]

antof_anual <- dcast(
  antof_sexo[, .(td_pct = round(weighted.mean(td, w = w_pea) * 100, 2)),
             by = .(ano, sexo_label)],
  ano ~ sexo_label, value.var = "td_pct"
)
setnames(antof_anual, c("Hombre", "Mujer"),
         c("TD_Hombre_Antof_%", "TD_Mujer_Antof_%"))
antof_anual[, Brecha_Antof_pp := round(`TD_Mujer_Antof_%` - `TD_Hombre_Antof_%`, 2)]

tabla_sexo <- merge(nac_anual, antof_anual, by = "ano", all.x = TRUE)
setorder(tabla_sexo, ano)
fwrite(tabla_sexo, "resultados/tabla_sexo_anual.csv")

cat("\nTabla por sexo y año:\n")
print(tabla_sexo)

# =============================================================================
cat("\n================================================================\n")
cat("              SCRIPT 03_sexo_edad.R COMPLETADO\n")
cat("================================================================\n")
cat("Gráficos:\n")
cat("  graficos/04_desocupacion_sexo_nacional.png\n")
cat("  graficos/05_desocupacion_sexo_antofagasta.png\n")
cat("  graficos/06_desocupacion_grupos_edad.png\n")
cat("  graficos/07_covid_por_sexo.png\n")
cat("Tabla:\n")
cat("  resultados/tabla_sexo_anual.csv\n")
