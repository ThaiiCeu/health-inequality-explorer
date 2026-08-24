# =============================================================================
# funcoes.R
# Funções reutilizáveis para coleta de dados do projeto Health Inequality Explorer
#
# Fontes cobertas:
#   - WHO Global Health Observatory (GHO) OData API
#   - World Bank Indicators API (v2)
#   - Our World in Data (OWID) - CSVs versionados por gráfico
#
# Nota sobre robustez: a API OData da WHO está em transição (a WHO já
# anunciou depreciação da versão atual). Por isso, em vez de fixar códigos
# de indicador "no escuro", oferecemos uma função de BUSCA por nome
# (gho_buscar_indicador) que deve ser rodada antes de fixar os códigos
# definitivos no script de coleta. Os códigos resolvidos ficam registrados
# em um manifesto (ver 01_coleta_dados.R) para que a coleta seja
# reprodutível mesmo se a API mudar de estrutura no futuro.
# =============================================================================

library(httr2)
library(jsonlite)
library(dplyr)
library(readr)
library(purrr)
library(stringr)
library(tidyr)

# -----------------------------------------------------------------------
# 1. WHO Global Health Observatory (GHO)
# -----------------------------------------------------------------------

#' Busca indicadores da WHO GHO por padrão de texto no nome
#'
#' @param padrao Texto (ou regex simples) a procurar no nome do indicador.
#'   A busca não diferencia maiúsculas/minúsculas.
#' @return Um tibble com IndicatorCode e IndicatorName dos indicadores
#'   que contêm o padrão buscado.
#'
#' Por que essa função existe: os códigos de indicador da WHO (ex.:
#' "WHOSIS_000001") não são intuitivos e podem mudar na migração de API
#' anunciada pela WHO. Buscar por nome deixa o pipeline mais robusto a
#' essa mudança e documenta explicitamente qual indicador foi escolhido
#' e por quê.
gho_buscar_indicador <- function(padrao) {
  url_base <- "https://ghoapi.azureedge.net/api/Indicator"

  resp <- request(url_base) |>
    req_url_query(`$filter` = sprintf("contains(tolower(IndicatorName),'%s')",
                                       tolower(padrao))) |>
    req_perform()

  if (resp_status(resp) != 200) {
    warning(sprintf("Falha ao buscar indicador '%s': HTTP %s", padrao, resp_status(resp)))
    return(tibble(IndicatorCode = character(), IndicatorName = character()))
  }

  conteudo <- resp_body_json(resp, simplifyVector = TRUE)

  if (is.null(conteudo$value) || length(conteudo$value) == 0) {
    message(sprintf("Nenhum indicador encontrado para o padrão: '%s'", padrao))
    return(tibble(IndicatorCode = character(), IndicatorName = character()))
  }

  as_tibble(conteudo$value) |>
    select(IndicatorCode, IndicatorName)
}

#' Obtém os dados de um indicador específico da WHO GHO
#'
#' @param codigo_indicador Código do indicador (ex.: "WHOSIS_000001").
#' @param ano_inicio Ano inicial (inclusive). Default 2000.
#' @param ano_fim Ano final (inclusive). Default 2022.
#' @return Um tibble com os dados brutos retornados pela API (sem nenhuma
#'   transformação — a limpeza acontece em 02_limpeza_dados.R).
#'
#' Nota sobre o filtro de datas: usamos o campo 'TimeDim' (o ano como
#' número inteiro) em vez de 'TimeDimensionBegin' (uma data completa).
#' Alguns indicadores — sobretudo os que vêm de bases secundárias, como
#' o Global Health Expenditure Database (GHED) — não preenchem
#' TimeDimensionBegin de forma consistente, o que fazia o filtro
#' descartar silenciosamente todos os registros (retornando 0 linhas
#' mesmo para indicadores válidos). TimeDim é o campo mais universal
#' entre os indicadores da GHO para dados anuais.
gho_obter_dados <- function(codigo_indicador, ano_inicio = 2000, ano_fim = 2022) {
  url_base <- paste0("https://ghoapi.azureedge.net/api/", codigo_indicador)

  filtro <- sprintf("TimeDim ge %d and TimeDim le %d", ano_inicio, ano_fim)

  resp <- tryCatch(
    request(url_base) |>
      req_url_query(`$filter` = filtro) |>
      req_perform(),
    error = function(e) {
      warning(sprintf("Erro ao requisitar indicador '%s': %s", codigo_indicador, e$message))
      NULL
    }
  )

  if (is.null(resp) || resp_status(resp) != 200) {
    warning(sprintf("Falha ao obter dados do indicador '%s'", codigo_indicador))
    return(tibble())
  }

  conteudo <- resp_body_json(resp, simplifyVector = TRUE)

  if (is.null(conteudo$value) || length(conteudo$value) == 0) {
    # Rede de segurança: se o filtro por TimeDim não retornou nada
    # (pode acontecer se esse campo também estiver ausente para este
    # indicador específico), tenta buscar tudo sem filtro e filtrar
    # os anos depois, em R.
    message(sprintf(
      "Indicador '%s' retornou 0 registros com filtro; tentando sem filtro...",
      codigo_indicador
    ))

    resp_sem_filtro <- tryCatch(
      request(url_base) |> req_perform(),
      error = function(e) NULL
    )

    if (is.null(resp_sem_filtro) || resp_status(resp_sem_filtro) != 200) {
      warning(sprintf("Falha ao obter dados (sem filtro) do indicador '%s'", codigo_indicador))
      return(tibble())
    }

    conteudo_sf <- resp_body_json(resp_sem_filtro, simplifyVector = TRUE)

    if (is.null(conteudo_sf$value) || length(conteudo_sf$value) == 0) {
      message(sprintf("Indicador '%s' realmente não tem dados disponíveis.", codigo_indicador))
      return(tibble())
    }

    dados_completos <- as_tibble(conteudo_sf$value)

    if ("TimeDim" %in% names(dados_completos)) {
      dados_completos <- dados_completos |>
        filter(TimeDim >= ano_inicio, TimeDim <= ano_fim)
    } else {
      warning(sprintf(
        "Indicador '%s' não tem campo TimeDim — retornando todos os dados sem filtrar por ano.",
        codigo_indicador
      ))
    }

    return(dados_completos)
  }

  as_tibble(conteudo$value)
}

# -----------------------------------------------------------------------
# 2. World Bank Indicators API (v2)
# -----------------------------------------------------------------------

#' Busca indicadores do World Bank (WDI) por padrão de texto no nome
#'
#' @param padrao Texto a procurar no nome do indicador (não diferencia
#'   maiúsculas/minúsculas).
#' @return Um tibble com id e name dos indicadores que contêm o padrão.
#'
#' Por que essa função existe: assim como na WHO, adivinhar códigos do
#' World Bank a partir de documentação externa é frágil — códigos podem
#' estar desatualizados, ser de séries descontinuadas, ou simplesmente
#' errados. Esta função consulta a lista oficial da base WDI (source=2,
#' ~1500 indicadores) diretamente na API e filtra localmente, o que é
#' muito mais confiável do que confiar em um código copiado de algum
#' lugar.
wb_buscar_indicador <- function(padrao) {
  url <- "https://api.worldbank.org/v2/indicator"

  resp <- tryCatch(
    request(url) |>
      req_url_query(format = "json", source = 2, per_page = 20000) |>
      req_perform(),
    error = function(e) {
      warning(sprintf("Erro ao buscar indicadores do World Bank: %s", e$message))
      NULL
    }
  )

  if (is.null(resp) || resp_status(resp) != 200) {
    warning("Falha ao buscar lista de indicadores do World Bank.")
    return(tibble(id = character(), name = character()))
  }

  conteudo <- resp_body_json(resp, simplifyVector = TRUE)

  if (length(conteudo) < 2 || is.null(conteudo[[2]])) {
    warning("Resposta inesperada ao buscar indicadores do World Bank.")
    return(tibble(id = character(), name = character()))
  }

  lista <- as_tibble(conteudo[[2]]) |>
    select(id, name)

  lista |>
    filter(str_detect(tolower(name), tolower(padrao)))
}

#' Obtém os dados de um indicador do World Bank para todos os países
#'
#' @param codigo_indicador Código do indicador (ex.: "NY.GDP.PCAP.PP.KD").
#' @param ano_inicio Ano inicial (inclusive).
#' @param ano_fim Ano final (inclusive).
#' @return Um tibble com os dados brutos (todas as páginas já concatenadas).
#'
#' A API do World Bank pagina os resultados; por isso a função consulta
#' primeiro para descobrir o total de páginas e depois itera até coletar
#' tudo. Isso evita perder países por causa do limite padrão de itens
#' por página.
wb_obter_dados <- function(codigo_indicador, ano_inicio = 2000, ano_fim = 2022) {
  url_base <- sprintf("https://api.worldbank.org/v2/country/all/indicator/%s",
                       codigo_indicador)

  # Primeira requisição: descobrir número total de páginas
  resp1 <- tryCatch(
    request(url_base) |>
      req_url_query(
        format = "json",
        date = sprintf("%d:%d", ano_inicio, ano_fim),
        per_page = 1000,
        page = 1
      ) |>
      req_perform(),
    error = function(e) {
      warning(sprintf("Erro ao requisitar indicador WB '%s': %s", codigo_indicador, e$message))
      NULL
    }
  )

  if (is.null(resp1) || resp_status(resp1) != 200) {
    warning(sprintf("Falha ao obter dados do World Bank para '%s'", codigo_indicador))
    return(tibble())
  }

  conteudo1 <- resp_body_json(resp1, simplifyVector = TRUE)

  # O World Bank normalmente retorna uma lista de 2 elementos:
  # [1] metadados, [2] dados. Mas se o código do indicador for inválido
  # ou a API retornar uma mensagem de erro, essa lista pode vir com
  # apenas 1 elemento (ou nenhum) — sem essa checagem, acessar
  # conteudo1[[2]] direto quebra o script inteiro com um erro genérico
  # de "índice fora dos limites" em vez de avisar e seguir em frente.
  if (length(conteudo1) < 2) {
    warning(sprintf(
      "Indicador World Bank '%s' retornou uma resposta inesperada (código inválido?). Pulando.",
      codigo_indicador
    ))
    return(tibble())
  }

  meta <- conteudo1[[1]]
  dados <- conteudo1[[2]]

  if (is.null(dados) || length(dados) == 0) {
    message(sprintf("Indicador World Bank '%s' retornou 0 registros", codigo_indicador))
    return(tibble())
  }

  total_paginas <- meta$pages

  # As colunas 'country' e 'indicator' vêm da API como sub-objetos
  # {id, value} aninhados. jsonlite::flatten() as transforma em colunas
  # simples (country.id, country.value, indicator.id, indicator.value),
  # o que é necessário porque write_csv() não aceita list-columns.
  lista_dados <- list(as_tibble(jsonlite::flatten(as.data.frame(dados))))

  if (!is.null(total_paginas) && total_paginas > 1) {
    for (pg in 2:total_paginas) {
      resp_pg <- tryCatch(
        request(url_base) |>
          req_url_query(
            format = "json",
            date = sprintf("%d:%d", ano_inicio, ano_fim),
            per_page = 1000,
            page = pg
          ) |>
          req_perform(),
        error = function(e) NULL
      )

      if (is.null(resp_pg) || resp_status(resp_pg) != 200) {
        warning(sprintf("Falha ao obter página %d do indicador World Bank '%s'. Pulando essa página.",
                         pg, codigo_indicador))
        next
      }

      conteudo_pg <- resp_body_json(resp_pg, simplifyVector = TRUE)

      if (length(conteudo_pg) < 2) next

      dados_pg <- conteudo_pg[[2]]

      if (!is.null(dados_pg) && length(dados_pg) > 0) {
        lista_dados[[length(lista_dados) + 1]] <-
          as_tibble(jsonlite::flatten(as.data.frame(dados_pg)))
      }
    }
  }

  bind_rows(lista_dados)
}

# -----------------------------------------------------------------------
# 3. Our World in Data (OWID)
# -----------------------------------------------------------------------

#' Baixa um dataset da OWID a partir do slug do gráfico
#'
#' @param slug Nome do gráfico na URL da OWID
#'   (ex.: "life-expectancy" para ourworldindata.org/grapher/life-expectancy).
#' @return Um tibble com os dados brutos do CSV.
#'
#' Por que usar o CSV do grapher em vez de baixar um "dataset explorer"
#' inteiro: o CSV por gráfico já vem filtrado para a variável específica
#' que precisamos, é versionado automaticamente pela OWID (sempre aponta
#' para a versão mais recente daquele indicador) e evita que a gente
#' dependa de um arquivo estático baixado manualmente.
owid_obter_csv <- function(slug) {
  url <- sprintf("https://ourworldindata.org/grapher/%s.csv", slug)

  dados <- tryCatch(
    read_csv(url, show_col_types = FALSE),
    error = function(e) {
      warning(sprintf("Erro ao baixar dataset OWID '%s': %s", slug, e$message))
      NULL
    }
  )

  if (is.null(dados)) return(tibble())

  dados
}

# -----------------------------------------------------------------------
# 4. Utilitário de log / manifesto de coleta
# -----------------------------------------------------------------------

#' Registra uma linha no manifesto de coleta
#'
#' O manifesto documenta, para cada indicador coletado: fonte, código,
#' nome legível, número de linhas obtidas e timestamp da coleta. Isso é
#' essencial para reprodutibilidade (Seção 2 do prompt original) e para
#' a seção de Metodologia do dashboard.
registrar_manifesto <- function(manifesto, fonte, codigo, nome_legivel, n_linhas) {
  nova_linha <- tibble(
    fonte = fonte,
    codigo_indicador = codigo,
    nome_legivel = nome_legivel,
    n_linhas = n_linhas,
    coletado_em = as.character(Sys.time())
  )
  bind_rows(manifesto, nova_linha)
}

# -----------------------------------------------------------------------
# 5. Referência de países (World Bank Country API)
# -----------------------------------------------------------------------

#' Obtém a lista oficial de países do World Bank, com região e renda
#'
#' @return Um tibble com pais_iso3, pais_nome, regiao, nivel_renda —
#'   apenas países de verdade (agregados como "World", "European Union",
#'   "Low income" etc. são excluídos via region.value != "Aggregates").
#'
#' Por que essa função existe: WHO e World Bank não usam exatamente os
#' mesmos nomes de país em texto livre (ex.: "Russian Federation" vs
#' "Russia", "Viet Nam" vs "Vietnam", "Korea, Rep." vs "South Korea").
#' Em vez de tentar casar strings entre as duas fontes — frágil e
#' propenso a erro silencioso — usamos o código ISO3 como chave única
#' de junção, e esta lista do World Bank como árbitro de quais
#' entidades são países de fato (a API do WB mistura países reais com
#' agregados regionais e por nível de renda na mesma lista de
#' "countries", então é preciso filtrar isso explicitamente).
wb_obter_paises <- function() {
  url <- "https://api.worldbank.org/v2/country"

  resp <- tryCatch(
    request(url) |>
      req_url_query(format = "json", per_page = 400) |>
      req_perform(),
    error = function(e) {
      warning(sprintf("Erro ao buscar lista de países do World Bank: %s", e$message))
      NULL
    }
  )

  if (is.null(resp) || resp_status(resp) != 200) {
    warning("Falha ao buscar lista de países do World Bank.")
    return(tibble())
  }

  conteudo <- resp_body_json(resp, simplifyVector = TRUE)

  if (length(conteudo) < 2 || is.null(conteudo[[2]])) {
    warning("Resposta inesperada ao buscar países do World Bank.")
    return(tibble())
  }

  bruto <- as_tibble(jsonlite::flatten(as.data.frame(conteudo[[2]])))

  bruto |>
    filter(region.value != "Aggregates") |>
    transmute(
      pais_iso3 = id,
      pais_nome = name,
      regiao = region.value,
      nivel_renda = incomeLevel.value
    )
}
