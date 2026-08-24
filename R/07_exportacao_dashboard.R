# =============================================================================
# 07_exportacao_dashboard.R
# Health Inequality Explorer — Exportação para o dashboard
#
# Converte os dados processados (CSV) em arquivos JSON que o front-end
# HTML/CSS/JS vai consumir via fetch(), sem precisar de nenhum servidor
# R rodando (arquitetura confirmada: R processa, HTML/JS estático
# renderiza — compatível com GitHub Pages).
#
# Cada bloco abaixo gera um arquivo JSON específico para uma seção do
# dashboard (ver Seção 11 do escopo do projeto):
#   - countries.json      -> Global Overview, Interactive Map, Country Explorer
#   - kpis_globais.json   -> Global Overview (cards)
#   - clusters.json       -> Health Profiles
#   - regressao.json      -> What Drives Health
#   - pca.json            -> What Drives Health / Health Profiles
#   - serie_temporal.json -> Country Explorer (evolução temporal)
# =============================================================================

source("R/funcoes.R")
library(jsonlite)

dir.create("dashboard/data", showWarnings = FALSE, recursive = TRUE)

# -----------------------------------------------------------------------
# A. countries.json — um objeto por país (núcleo, N=159, ano de referência)
# -----------------------------------------------------------------------
# Junta o perfil de indicadores (Fase 5/7) com a classificação
# esperado/observado (Fase 8) num único registro por país — é a peça
# central que alimenta o mapa, os cards de país e as comparações.

dados_com_cluster <- read_csv("data/processed/dados_com_cluster.csv", show_col_types = FALSE)
esperado_observado <- read_csv("outputs/tables/esperado_vs_observado.csv", show_col_types = FALSE)

countries <- dados_com_cluster |>
  left_join(
    esperado_observado |> select(pais_iso3, expectativa_esperada, residuo_studentizado, classificacao),
    by = "pais_iso3"
  ) |>
  transmute(
    iso3 = pais_iso3,
    nome = pais_nome,
    regiao = regiao,
    nivel_renda = nivel_renda,
    ano = ano,
    expectativa_vida = round(expectativa_vida, 1),
    mortalidade_infantil = round(mortalidade_infantil, 1),
    prevalencia_obesidade = round(prevalencia_obesidade, 1),
    pib_per_capita_ppp = round(pib_per_capita_ppp, 0),
    populacao = round(populacao, 0),
    gasto_saude_pc_ppp = round(gasto_saude_pc_ppp, 0),
    prevalencia_tabagismo = round(prevalencia_tabagismo, 1),
    escolaridade_esperada = round(escolaridade_esperada, 1),  # pode ser NA (secundário)
    medicos_per_10k = round(medicos_per_10k, 2),               # pode ser NA (secundário)
    cluster = as.integer(as.character(cluster)),
    nome_cluster = nome_cluster,
    pc1 = round(pc1, 3),
    pc2 = round(pc2, 3),
    expectativa_esperada = round(expectativa_esperada, 1),
    residuo_studentizado = round(residuo_studentizado, 2),
    classificacao = classificacao
  )

write_json(countries, "dashboard/data/countries.json", pretty = TRUE, na = "null", auto_unbox = TRUE)
message(sprintf("countries.json salvo — %d países.", nrow(countries)))

# -----------------------------------------------------------------------
# B. kpis_globais.json — cards da seção Global Overview
# -----------------------------------------------------------------------

kpis_globais <- list(
  ano_referencia = 2015,
  n_paises = nrow(countries),
  expectativa_vida_media = round(mean(countries$expectativa_vida, na.rm = TRUE), 1),
  mortalidade_infantil_media = round(mean(countries$mortalidade_infantil, na.rm = TRUE), 1),
  gasto_saude_medio = round(mean(countries$gasto_saude_pc_ppp, na.rm = TRUE), 0),
  pib_per_capita_mediano = round(median(countries$pib_per_capita_ppp, na.rm = TRUE), 0)
)

write_json(kpis_globais, "dashboard/data/kpis_globais.json", pretty = TRUE, auto_unbox = TRUE)
message("kpis_globais.json salvo.")

# -----------------------------------------------------------------------
# C. clusters.json — perfil de cada cluster + países representativos
# -----------------------------------------------------------------------

perfil_clusters <- read_csv("outputs/tables/perfil_clusters.csv", show_col_types = FALSE)
paises_representativos <- read_csv("outputs/tables/paises_representativos_clusters.csv", show_col_types = FALSE)

clusters_lista <- lapply(seq_len(nrow(perfil_clusters)), function(i) {
  linha <- perfil_clusters[i, ]
  cluster_id <- as.integer(as.character(linha$cluster))
  list(
    cluster = cluster_id,
    nome_cluster = linha$nome_cluster,
    n_paises = linha$n_paises,
    expectativa_vida_media = round(linha$expectativa_vida_media, 1),
    mortalidade_infantil_media = round(linha$mortalidade_infantil_media, 1),
    obesidade_media = round(linha$obesidade_media, 1),
    pib_per_capita_medio = round(linha$pib_per_capita_medio, 0),
    gasto_saude_medio = round(linha$gasto_saude_medio, 0),
    tabagismo_medio = round(linha$tabagismo_medio, 1),
    paises_representativos = paises_representativos |>
      filter(as.integer(as.character(cluster)) == cluster_id) |>
      pull(pais_nome)
  )
})

write_json(clusters_lista, "dashboard/data/clusters.json", pretty = TRUE, auto_unbox = TRUE)
message(sprintf("clusters.json salvo — %d clusters.", length(clusters_lista)))

# -----------------------------------------------------------------------
# D. regressao.json — coeficientes e diagnóstico do modelo (Fase 6)
# -----------------------------------------------------------------------

coef_robusto <- read_csv("outputs/tables/regressao_modelo2_robusto_hc3.csv", show_col_types = FALSE)

regressao_export <- list(
  n_paises = 159,
  r_quadrado = 0.737,
  r_quadrado_ajustado = 0.728,
  coeficientes = lapply(seq_len(nrow(coef_robusto)), function(i) {
    linha <- coef_robusto[i, ]
    list(
      variavel = linha$term,
      estimativa = round(linha$estimate, 3),
      erro_padrao = round(linha$std.error, 3),
      p_valor = round(linha$p.value, 4),
      significativo_5pct = linha$p.value < 0.05
    )
  }),
  nota_metodologica = "Erros-padrao robustos a heterocedasticidade (HC3). Ver METODOLOGIA.md secao 7 para detalhes sobre VIF, diagnosticos e a especificacao alternativa residualizada."
)

write_json(regressao_export, "dashboard/data/regressao.json", pretty = TRUE, auto_unbox = TRUE)
message("regressao.json salvo.")

# -----------------------------------------------------------------------
# E. pca.json — variância explicada e loadings (Fase 7)
# -----------------------------------------------------------------------

variancia_pca <- read_csv("outputs/tables/pca_variancia_explicada.csv", show_col_types = FALSE)
loadings_pca <- read_csv("outputs/tables/pca_loadings.csv", show_col_types = FALSE)

pca_export <- list(
  variancia_explicada = lapply(seq_len(nrow(variancia_pca)), function(i) {
    linha <- variancia_pca[i, ]
    list(
      componente = linha$componente,
      proporcao = round(linha$proporcao, 3),
      proporcao_acumulada = round(linha$proporcao_acumulada, 3)
    )
  }),
  loadings = lapply(seq_len(nrow(loadings_pca)), function(i) {
    linha <- loadings_pca[i, ]
    list(
      variavel = linha$variavel,
      pc1 = round(linha$PC1, 3),
      pc2 = round(linha$PC2, 3)
    )
  })
)

write_json(pca_export, "dashboard/data/pca.json", pretty = TRUE, auto_unbox = TRUE)
message("pca.json salvo.")

# -----------------------------------------------------------------------
# F. serie_temporal.json — evolução por país, indicadores do núcleo
# -----------------------------------------------------------------------
# PERGUNTA: como cada indicador evoluiu ao longo do tempo, por país —
# alimenta os gráficos de evolução temporal do Country Explorer.
# Restrito aos 159 países do núcleo (para manter o arquivo com tamanho
# razoável) e aos 7 indicadores do núcleo (não inclui os secundários,
# que têm cobertura temporal irregular demais para gráficos de linha
# confiáveis).

dados_longos <- read_csv("data/processed/dados_longos.csv", show_col_types = FALSE)
paises_nucleo_iso3 <- countries$iso3

INDICADORES_NUCLEO <- c("expectativa_vida", "mortalidade_infantil", "prevalencia_obesidade",
                         "pib_per_capita_ppp", "populacao", "gasto_saude_pc_ppp",
                         "prevalencia_tabagismo")

serie_temporal <- dados_longos |>
  filter(pais_iso3 %in% paises_nucleo_iso3, indicador %in% INDICADORES_NUCLEO) |>
  select(iso3 = pais_iso3, ano, indicador, valor)

# Formato: agrupado por país, cada um com um objeto por indicador
# contendo a série de anos/valores — mais fácil de consumir no JS do
# que uma lista "achatada" de milhares de linhas.
serie_temporal_final <- list()
for (pais in paises_nucleo_iso3) {
  dados_pais <- serie_temporal |> filter(iso3 == pais)
  indicadores_pais <- list()
  for (ind in INDICADORES_NUCLEO) {
    sub <- dados_pais |> filter(indicador == ind) |> arrange(ano)
    if (nrow(sub) > 0) {
      indicadores_pais[[ind]] <- list(anos = sub$ano, valores = round(sub$valor, 2))
    }
  }
  serie_temporal_final[[pais]] <- indicadores_pais
}

write_json(serie_temporal_final, "dashboard/data/serie_temporal.json", pretty = FALSE, auto_unbox = TRUE)
message(sprintf("serie_temporal.json salvo — %d países.", length(serie_temporal_final)))

# -----------------------------------------------------------------------
# Resumo final
# -----------------------------------------------------------------------

arquivos_gerados <- list.files("dashboard/data", full.names = TRUE)
tamanhos <- file.info(arquivos_gerados)$size / 1024

message("\n=== Arquivos JSON gerados em dashboard/data/ ===")
for (i in seq_along(arquivos_gerados)) {
  message(sprintf("  %s — %.1f KB", basename(arquivos_gerados[i]), tamanhos[i]))
}

message("\nExportação concluída. Dados prontos para o front-end HTML/CSS/JS (Fase 10).")
