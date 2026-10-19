# =============================================================================
# 08_sensibilidade_ano.R
# Health Inequality Explorer — Análise de sensibilidade do ano de referência
#
# PERGUNTA: os resultados do Modelo 2 (regressão) e da clusterização (Fases
# 6-7) são um acidente do ano escolhido (2015), ou se mantêm em outro corte
# transversal? Essa é uma pergunta padrão de robustez em qualquer artigo que
# usa dados de um único ano — e é diferente de reanalisar os MESMOS dados de
# formas diferentes: aqui trocamos a amostra inteira (outro ano, portanto
# outros países presentes/ausentes por cobertura).
#
# POR QUE 2010: é o ano mais distante de 2015 que ainda tem cobertura
# comparável nos indicadores do núcleo (evitamos 2020+ pelos mesmos motivos
# que evitamos na Fase 4 — distorção da pandemia). Cinco anos de distância
# é suficiente para não ser "quase a mesma amostra", sem cair numa década
# tão diferente que mudanças estruturais reais (não ruído de amostragem)
# expliquem toda a diferença.
#
# O QUE ESTE SCRIPT NÃO FAZ: não é um modelo de painel (não usa a variação
# dentro-do-país ao longo do tempo). Cada ano continua sendo tratado como um
# corte transversal independente — a comparação é "os achados de 2015
# aparecem de novo, de forma qualitativamente parecida, em 2010?", não uma
# estimativa conjunta com efeitos fixos.
#
# SAÍDA: outputs/tables/sensibilidade_ano.csv (coeficientes lado a lado) e
# um resumo impresso no console para citar na seção de Resultados do artigo.
# =============================================================================

source("R/funcoes.R")
library(broom)
library(sandwich)
library(lmtest)
library(factoextra)
library(cluster)

ANOS_COMPARADOS <- c(2015, 2010)

INDICADORES_NUCLEO <- c("expectativa_vida", "mortalidade_infantil", "prevalencia_obesidade",
                         "pib_per_capita_ppp", "populacao", "gasto_saude_pc_ppp",
                         "prevalencia_tabagismo")

VARS_PERFIL <- c("expectativa_vida", "mortalidade_infantil", "prevalencia_obesidade",
                  "pib_per_capita_ppp", "gasto_saude_pc_ppp", "prevalencia_tabagismo")

dados_largos <- read_csv("data/processed/dados_largos.csv", show_col_types = FALSE)

# -----------------------------------------------------------------------
# Função: monta o corte transversal "núcleo" para um ano específico —
# mesma lógica de elegibilidade usada na Fase 4 (linhas completas nos 7
# indicadores do núcleo), só que parametrizada por ano em vez de fixa em
# 2015.
# -----------------------------------------------------------------------
montar_corte_nucleo <- function(ano_ref) {
  dados_largos |>
    filter(ano == ano_ref) |>
    select(pais_iso3, pais_nome, regiao, nivel_renda, ano, all_of(INDICADORES_NUCLEO)) |>
    drop_na(all_of(INDICADORES_NUCLEO))
}

# -----------------------------------------------------------------------
# Função: reajusta o Modelo 2 (mesma especificação da Fase 6) com erros-
# padrão robustos HC3, para uma amostra qualquer.
# -----------------------------------------------------------------------
ajustar_modelo2 <- function(dados) {
  modelo <- lm(
    expectativa_vida ~ log(pib_per_capita_ppp) + prevalencia_obesidade +
      prevalencia_tabagismo + log(populacao) + log(gasto_saude_pc_ppp),
    data = dados
  )
  coef_robusto <- coeftest(modelo, vcov = vcovHC(modelo, type = "HC3"))
  list(
    modelo = modelo,
    r2 = summary(modelo)$r.squared,
    r2_ajustado = summary(modelo)$adj.r.squared,
    coeficientes = broom::tidy(coef_robusto)
  )
}

# -----------------------------------------------------------------------
# Função: PCA + K-Means (K=4, mesma especificação da Fase 7), para uma
# amostra qualquer. Retorna variância explicada e perfil médio de cada
# cluster nas variáveis originais.
# -----------------------------------------------------------------------
ajustar_pca_cluster <- function(dados) {
  dados_pca <- dados |>
    mutate(
      mortalidade_infantil = log(mortalidade_infantil),
      pib_per_capita_ppp = log(pib_per_capita_ppp),
      gasto_saude_pc_ppp = log(gasto_saude_pc_ppp)
    ) |>
    select(all_of(VARS_PERFIL))

  matriz_padronizada <- scale(dados_pca)
  pca <- prcomp(matriz_padronizada, center = FALSE, scale. = FALSE)

  variancia_explicada <- summary(pca)$importance[2, 1:2]

  set.seed(42)
  km <- kmeans(pca$x[, 1:2], centers = 4, nstart = 25)

  sil <- silhouette(km$cluster, dist(pca$x[, 1:2]))
  silhueta_media <- mean(sil[, 3])

  perfil <- dados |>
    mutate(cluster = km$cluster) |>
    group_by(cluster) |>
    summarise(
      n_paises = n(),
      expectativa_vida_media = mean(expectativa_vida, na.rm = TRUE),
      mortalidade_infantil_media = mean(mortalidade_infantil, na.rm = TRUE),
      .groups = "drop"
    )

  list(
    variancia_pc1 = unname(variancia_explicada[1]),
    variancia_pc2 = unname(variancia_explicada[2]),
    silhueta_media = silhueta_media,
    perfil = perfil
  )
}

# -----------------------------------------------------------------------
# Rodar para cada ano e comparar
# -----------------------------------------------------------------------

resultados <- list()

for (ano in ANOS_COMPARADOS) {
  corte <- montar_corte_nucleo(ano)
  message(sprintf("\n=== Ano %d: %d países no núcleo ===", ano, nrow(corte)))

  reg <- ajustar_modelo2(corte)
  message(sprintf("  R² = %.3f | R² ajustado = %.3f", reg$r2, reg$r2_ajustado))

  pca_cl <- ajustar_pca_cluster(corte)
  message(sprintf("  PCA: PC1 = %.1f%%, PC2 = %.1f%% da variância | Silhueta média (K=4) = %.3f",
                   pca_cl$variancia_pc1 * 100, pca_cl$variancia_pc2 * 100, pca_cl$silhueta_media))

  resultados[[as.character(ano)]] <- list(
    n = nrow(corte), regressao = reg, pca_cluster = pca_cl
  )
}

# -----------------------------------------------------------------------
# Tabela comparativa de coeficientes (lado a lado, para a seção de
# Resultados do artigo)
# -----------------------------------------------------------------------

tabela_coeficientes <- purrr::map_dfr(names(resultados), function(ano) {
  resultados[[ano]]$regressao$coeficientes |>
    mutate(ano = as.integer(ano)) |>
    select(ano, variavel = term, estimativa = estimate, erro_padrao = std.error, p_valor = p.value)
})

tabela_comparativa <- tabela_coeficientes |>
  pivot_wider(names_from = ano, values_from = c(estimativa, erro_padrao, p_valor))

write_csv(tabela_comparativa, "outputs/tables/sensibilidade_ano.csv")

# -----------------------------------------------------------------------
# Resumo interpretativo
# -----------------------------------------------------------------------
# COMO LER: se o sinal e a significância (p<0.05 ou não) dos coeficientes
# de log(pib) e log(gasto_saude) se mantiverem parecidos entre 2010 e
# 2015 — mesmo que os valores exatos mudem um pouco — isso é evidência de
# que o achado não é um acidente da escolha do ano de referência. O
# mesmo vale para a variância explicada pelo PC1/PC2 e para o número
# efetivo de países por cluster: clusters de tamanho muito diferente ou
# uma queda grande na variância explicada sinalizariam que a estrutura
# de 4 perfis é sensível ao corte temporal, não um padrão estável.

message("\n=== Resumo comparativo ===")
message("Tabela completa salva em outputs/tables/sensibilidade_ano.csv")
message("\nUse esta tabela na seção de Resultados do artigo como checagem de robustez:")
message("cite o R² ajustado e o sinal/significância de log(pib) e log(gasto_saude) em ambos os anos.")
