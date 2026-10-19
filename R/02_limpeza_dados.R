# =============================================================================
# 02_limpeza_dados.R
# Health Inequality Explorer — Limpeza e padronização
#
# O que este script faz:
#   1. Carrega os 9 indicadores brutos (data/raw/) e os padroniza para um
#      formato comum: pais_iso3 | ano | indicador | valor.
#   2. Resolve duplicidade de país-ano na WHO causada por desagregação por
#      sexo (mantém apenas "ambos os sexos" quando essa dimensão existe).
#   3. Usa a lista oficial de países do World Bank como árbitro de "o que é
#      um país de verdade" e como fonte única de nomes de país — evita
#      o problema clássico de nomes divergentes entre WHO e World Bank
#      (ex.: "Russian Federation" vs "Russia").
#   4. Junta os 9 indicadores em uma única tabela larga (pais-ano-indicadores)
#      e salva o resultado em data/processed/.
#
# O que este script NÃO faz (fica para 03_analise_exploratoria.R):
#   - Remoção de outliers: decisão que exige inspeção visual, não deve ser
#     automatizada às cegas (ver regra do prompt original: "não elimine
#     dados automaticamente sem justificar").
#   - Análise de correlação entre indicadores / multicolinearidade.
#   - Decisão do ano/período de referência para o corte transversal —
#     esse script preserva TODOS os anos disponíveis; a escolha do ano
#     de referência acontece depois de vermos a cobertura real (gráfico
#     de linhas por indicador na Fase 4).
# =============================================================================

source("R/funcoes.R")

# -----------------------------------------------------------------------
# 1. Referência de países
# -----------------------------------------------------------------------
# Cacheamos essa lista em disco porque ela muda raramente e evita uma
# chamada de API extra toda vez que este script roda.

caminho_paises_ref <- "data/external/paises_referencia.csv"

if (file.exists(caminho_paises_ref)) {
  paises_ref <- read_csv(caminho_paises_ref, show_col_types = FALSE)
  message(sprintf("Lista de países carregada do cache (%d países).", nrow(paises_ref)))
} else {
  paises_ref <- wb_obter_paises()
  write_csv(paises_ref, caminho_paises_ref)
  message(sprintf("Lista de países obtida da API e salva em cache (%d países).", nrow(paises_ref)))
}

if (nrow(paises_ref) == 0) {
  stop("Não foi possível obter a lista de referência de países. Abortando limpeza.")
}

# -----------------------------------------------------------------------
# 2. Funções de extração — padronizam cada fonte para pais_iso3 | ano | valor
# -----------------------------------------------------------------------

#' Extrai um indicador bruto da WHO GHO para o formato padronizado
#'
#' @param caminho_csv Caminho do CSV bruto em data/raw/who/.
#' @param nome_indicador Nome legível a atribuir a este indicador na
#'   coluna 'indicador' da tabela final.
#' @return Tibble com pais_iso3, ano, valor, indicador — uma linha por
#'   país-ano (sem duplicidade).
#'
#' Tratamento de duplicidade: vários indicadores da WHO são desagregados
#' por sexo (Dim1 = SEX_MLE / SEX_FMLE / SEX_BTSX). Sem filtrar isso,
#' cada país-ano apareceria até 3 vezes. Damos preferência a "ambos os
#' sexos" (BTSX) quando essa categoria existe. Se depois de filtrar
#' ainda sobrar duplicidade (situação inesperada), o script AVISA
#' explicitamente em vez de descartar dados silenciosamente — isso
#' segue a regra de não eliminar dados sem justificar.
extrair_who <- function(caminho_csv, nome_indicador) {
  bruto <- read_csv(caminho_csv, show_col_types = FALSE)

  # Mantém apenas linhas de país (descarta agregados regionais/globais
  # que a própria WHO inclui na mesma tabela).
  if ("SpatialDimType" %in% names(bruto)) {
    bruto <- bruto |> filter(SpatialDimType == "COUNTRY")
  }

  # Resolve a dimensão de sexo, se existir.
  if ("Dim1" %in% names(bruto) && any(!is.na(bruto$Dim1))) {
    valores_dim1 <- unique(bruto$Dim1)
    codigo_ambos_sexos <- intersect(c("BTSX", "SEX_BTSX"), valores_dim1)

    if (length(codigo_ambos_sexos) > 0) {
      bruto <- bruto |> filter(Dim1 == codigo_ambos_sexos[1])
    } else {
      message(sprintf(
        "[ATENÇÃO] '%s': indicador tem dimensão Dim1 (%s) sem categoria 'ambos os sexos' reconhecida. Mantendo todas as categorias — revisar manualmente.",
        nome_indicador, paste(valores_dim1, collapse = ", ")
      ))
    }
  }

  padronizado <- bruto |>
    transmute(
      pais_iso3 = SpatialDim,
      ano = as.integer(TimeDim),
      valor = NumericValue,
      indicador = nome_indicador,
      data_publicacao = if ("Date" %in% names(bruto)) bruto$Date else NA_character_
    ) |>
    filter(!is.na(valor))

  # Checagem de duplicidade remanescente (país-ano repetido). Causa mais
  # comum: a WHO mantém múltiplas revisões/vintages da mesma estimativa
  # ao longo do tempo (ex.: mortalidade infantil é frequentemente
  # reestimada conforme novos dados chegam). Nesses casos, o critério de
  # desempate correto é manter a publicação mais recente (campo 'Date'),
  # não "a primeira linha" arbitrária.
  duplicados <- padronizado |>
    count(pais_iso3, ano) |>
    filter(n > 1)

  if (nrow(duplicados) > 0) {
    if (all(!is.na(padronizado$data_publicacao))) {
      message(sprintf(
        "[INFO] '%s': %d combinações país-ano com múltiplas revisões da WHO. Mantendo a estimativa mais recente (campo Date).",
        nome_indicador, nrow(duplicados)
      ))
      padronizado <- padronizado |>
        arrange(pais_iso3, ano, desc(data_publicacao)) |>
        distinct(pais_iso3, ano, .keep_all = TRUE)
    } else {
      message(sprintf(
        "[ATENÇÃO] '%s': %d combinações país-ano duplicadas e sem campo 'Date' para desempate. Mantendo a primeira ocorrência — revisar manualmente.",
        nome_indicador, nrow(duplicados)
      ))
      padronizado <- padronizado |> distinct(pais_iso3, ano, .keep_all = TRUE)
    }
  }

  padronizado |> select(-data_publicacao)
}

#' Extrai um indicador bruto do World Bank para o formato padronizado
#'
#' @param caminho_csv Caminho do CSV bruto em data/raw/worldbank/.
#' @param nome_indicador Nome legível a atribuir a este indicador.
#' @return Tibble com pais_iso3, ano, valor, indicador.
#'
#' O World Bank já vem sem desagregação por sexo/idade nesses
#' indicadores, então a extração é mais direta. O principal cuidado é
#' descartar linhas com valor ausente (o próprio World Bank retorna
#' 'value: null' para país-ano sem dado coletado) e usar
#' 'countryiso3code' — não 'country.id', que no World Bank é o código
#' ISO2, não ISO3 — para casar com a lista de referência de países.
extrair_wb <- function(caminho_csv, nome_indicador) {
  bruto <- read_csv(caminho_csv, show_col_types = FALSE)

  padronizado <- bruto |>
    transmute(
      pais_iso3 = countryiso3code,
      ano = as.integer(date),
      valor = as.numeric(value),
      indicador = nome_indicador
    ) |>
    filter(!is.na(valor), !is.na(pais_iso3), pais_iso3 != "")

  duplicados <- padronizado |>
    count(pais_iso3, ano) |>
    filter(n > 1)

  if (nrow(duplicados) > 0) {
    message(sprintf(
      "[ATENÇÃO] '%s': %d combinações país-ano duplicadas no World Bank (inesperado). Mantendo a primeira ocorrência — revisar manualmente.",
      nome_indicador, nrow(duplicados)
    ))
    padronizado <- padronizado |> distinct(pais_iso3, ano, .keep_all = TRUE)
  }

  padronizado
}

# -----------------------------------------------------------------------
# 3. Extrair os 9 indicadores
# -----------------------------------------------------------------------

lista_indicadores <- list(
  extrair_who("data/raw/who/expectativa_vida.csv", "expectativa_vida"),
  extrair_who("data/raw/who/mortalidade_infantil.csv", "mortalidade_infantil"),
  extrair_who("data/raw/who/medicos_per_capita.csv", "medicos_per_10k"),
  extrair_who("data/raw/who/obesidade.csv", "prevalencia_obesidade"),
  extrair_wb("data/raw/worldbank/pib_per_capita.csv", "pib_per_capita_ppp"),
  extrair_wb("data/raw/worldbank/escolaridade_esperada.csv", "escolaridade_esperada"),
  extrair_wb("data/raw/worldbank/populacao.csv", "populacao"),
  extrair_wb("data/raw/worldbank/gasto_saude.csv", "gasto_saude_pc_ppp"),
  extrair_wb("data/raw/worldbank/tabagismo.csv", "prevalencia_tabagismo")
)

dados_longos <- bind_rows(lista_indicadores)

message(sprintf("\nTotal de observações (país-ano-indicador) após extração: %d", nrow(dados_longos)))

# -----------------------------------------------------------------------
# 4. Filtrar para países de verdade e anexar nome/região/renda
# -----------------------------------------------------------------------
# Países presentes nos dados brutos mas ausentes na lista de referência
# do World Bank são descartados aqui — normalmente são territórios,
# códigos agregados residuais, ou entidades que não são países
# soberanos reconhecidos pelo World Bank. Reportamos quantos foram
# descartados para transparência (não eliminamos silenciosamente).

paises_nos_dados <- unique(dados_longos$pais_iso3)
paises_nao_reconhecidos <- setdiff(paises_nos_dados, paises_ref$pais_iso3)

if (length(paises_nao_reconhecidos) > 0) {
  message(sprintf(
    "\n[INFO] %d códigos de país/território nos dados brutos não estão na lista de referência do World Bank e serão descartados:\n%s",
    length(paises_nao_reconhecidos),
    paste(paises_nao_reconhecidos, collapse = ", ")
  ))
}

dados_longos <- dados_longos |>
  inner_join(paises_ref, by = "pais_iso3")

# -----------------------------------------------------------------------
# 5. Pivotar para formato largo (uma linha por país-ano)
# -----------------------------------------------------------------------

dados_largos <- dados_longos |>
  select(pais_iso3, pais_nome, regiao, nivel_renda, ano, indicador, valor) |>
  pivot_wider(names_from = indicador, values_from = valor)

message(sprintf(
  "\nTabela final: %d linhas (país-ano), %d países únicos, anos de %d a %d.",
  nrow(dados_largos),
  n_distinct(dados_largos$pais_iso3),
  min(dados_largos$ano, na.rm = TRUE),
  max(dados_largos$ano, na.rm = TRUE)
))

# -----------------------------------------------------------------------
# 6. Diagnóstico de cobertura por ano e por indicador
# -----------------------------------------------------------------------
# Esse diagnóstico é justamente o que vai informar a decisão pendente
# do ano/período de referência para o corte transversal (deixada em
# aberto na Fase 2). Não decidimos aqui — só reportamos.

cobertura_por_ano <- dados_longos |>
  count(ano, indicador) |>
  pivot_wider(names_from = indicador, values_from = n, values_fill = 0)

write_csv(cobertura_por_ano, "outputs/tables/cobertura_por_ano.csv")
message("\nTabela de cobertura por ano/indicador salva em outputs/tables/cobertura_por_ano.csv")
message("Use essa tabela para decidir o ano de referência do corte transversal na Fase 4.")

# -----------------------------------------------------------------------
# 7. Salvar dados processados
# -----------------------------------------------------------------------

write_csv(dados_longos, "data/processed/dados_longos.csv")
write_csv(dados_largos, "data/processed/dados_largos.csv")

message("\nLimpeza concluída.")
message("  - Formato longo salvo em data/processed/dados_longos.csv")
message("  - Formato largo salvo em data/processed/dados_largos.csv")
