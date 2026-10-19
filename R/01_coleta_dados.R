# =============================================================================
# 01_coleta_dados.R
# Health Inequality Explorer — Coleta de dados brutos
#
# O que este script faz:
#   1. Busca e resolve os códigos de indicador da WHO GHO por nome (evita
#      hardcode "cego" de códigos que podem mudar).
#   2. Coleta os 8 indicadores centrais definidos na Fase 1/2, via WHO GHO,
#      World Bank e OWID.
#   3. Salva cada indicador BRUTO (sem nenhuma limpeza) em data/raw/,
#      separado por fonte.
#   4. Gera um manifesto de coleta (data/raw/manifesto_coleta.csv) para
#      rastreabilidade e para alimentar a seção de Metodologia do dashboard.
#
# Importante: nenhum dado bruto é alterado manualmente. Qualquer limpeza,
# renomeação de país ou tratamento de missing acontece em 02_limpeza_dados.R.
#
# Janela de anos: 2000–2022. O ano/período de referência final para as
# análises transversais (PCA, cluster, regressão) só será decidido na
# Fase 4, depois de inspecionarmos a cobertura real por ano e por país.
# =============================================================================

source("R/funcoes.R")

ANO_INICIO <- 2000
ANO_FIM <- 2022

manifesto <- tibble(
  fonte = character(),
  codigo_indicador = character(),
  nome_legivel = character(),
  n_linhas = integer(),
  coletado_em = character()
)

# -----------------------------------------------------------------------
# 1. Resolver códigos de indicador da WHO GHO por busca (não hardcode cego)
# -----------------------------------------------------------------------
# Cada busca abaixo deve ser conferida manualmente na primeira execução:
# o pesquisador confirma visualmente que o IndicatorCode retornado
# corresponde ao indicador pretendido antes de seguir para a coleta.
# Isso é documentado no console e pode ser revisado em
# data/external/gho_codigos_resolvidos.csv.

candidatos_expectativa_vida   <- gho_buscar_indicador("life expectancy at birth")
candidatos_mortalidade_infantil <- gho_buscar_indicador("under-five mortality rate")
candidatos_gasto_saude        <- gho_buscar_indicador("current health expenditure")
candidatos_medicos            <- gho_buscar_indicador("medical doctors")
candidatos_obesidade          <- gho_buscar_indicador("prevalence of obesity")
candidatos_tabagismo          <- gho_buscar_indicador("prevalence of current tobacco use")

# Exibe os candidatos encontrados para conferência manual antes de fixar
# os códigos definitivos usados na coleta.
print(candidatos_expectativa_vida)
print(candidatos_mortalidade_infantil)
print(candidatos_gasto_saude)
print(candidatos_medicos)
print(candidatos_obesidade)
print(candidatos_tabagismo)

# -----------------------------------------------------------------------
# IMPORTANTE — passo manual necessário:
# Depois de rodar o bloco acima e conferir os resultados impressos,
# preencha os códigos abaixo com o IndicatorCode correto de cada
# candidato_* (o primeiro resultado nem sempre é o indicador certo —
# por exemplo, a busca por "life expectancy" pode retornar variantes
# como "at age 60" que não são o que queremos).
#
# Os valores abaixo são os códigos historicamente estáveis da GHO no
# momento da escrita deste script; foram incluídos como ponto de
# partida, mas DEVEM ser confirmados contra a impressão acima antes de
# rodar a coleta em produção.
# -----------------------------------------------------------------------

codigo_expectativa_vida     <- "WHOSIS_000001"        # Life expectancy at birth (years)
codigo_mortalidade_infantil <- "MDG_0000000007"       # Under-five mortality rate (probabilidade por 1000 nasc. vivos)
codigo_medicos              <- "HWF_0001"             # Medical doctors (per 10,000) — nota: por 10.000, não por 1.000
codigo_obesidade            <- "NCD_BMI_30A"          # Obesity among adults, BMI ≥30 (age-standardized %)

# Gasto em saúde e tabagismo NÃO ficam mais aqui — ver seção World Bank
# abaixo. Motivo: a base GHED (gasto em saúde) da WHO vive em portais
# regionais separados, não no endpoint global ghoapi.azureedge.net, e o
# indicador SDGTOBACCO retornou 0 registros mesmo sem filtro de data —
# ambos não são consultáveis por este endpoint. O World Bank expõe os
# mesmos dados (originalmente da própria WHO) de forma mais estável.

# -----------------------------------------------------------------------
# 1b. Resolver códigos do World Bank por busca (mesma lógica da WHO acima)
# -----------------------------------------------------------------------
# Tentativas anteriores com códigos copiados de documentação externa
# (SH.XPD.PCAP.PP.KD, SH.PRV.SMOK.TO) falharam — provavelmente séries
# descontinuadas ou codificadas de forma diferente da documentada.
# Buscar programaticamente evita esse tipo de erro silencioso.

candidatos_gasto_saude_wb <- wb_buscar_indicador("current health expenditure per capita")
candidatos_tabagismo_wb   <- wb_buscar_indicador("tobacco use")

print(candidatos_gasto_saude_wb)
print(candidatos_tabagismo_wb)

# -----------------------------------------------------------------------
# 2. Coleta WHO GHO
# -----------------------------------------------------------------------

coletar_e_salvar_gho <- function(codigo, nome_arquivo, nome_legivel, manifesto) {
  if (is.null(codigo)) {
    message(sprintf("[PULADO] '%s' — código ainda não confirmado manualmente.", nome_legivel))
    return(manifesto)
  }

  dados <- gho_obter_dados(codigo, ANO_INICIO, ANO_FIM)

  if (nrow(dados) == 0) {
    message(sprintf("[AVISO] '%s' (%s) retornou 0 linhas.", nome_legivel, codigo))
    return(manifesto)
  }

  caminho <- sprintf("data/raw/who/%s.csv", nome_arquivo)
  write_csv(dados, caminho)
  message(sprintf("[OK] '%s' salvo em %s (%d linhas)", nome_legivel, caminho, nrow(dados)))

  registrar_manifesto(manifesto, "WHO GHO", codigo, nome_legivel, nrow(dados))
}

manifesto <- coletar_e_salvar_gho(codigo_expectativa_vida, "expectativa_vida",
                                   "Expectativa de vida ao nascer", manifesto)
manifesto <- coletar_e_salvar_gho(codigo_mortalidade_infantil, "mortalidade_infantil",
                                   "Mortalidade infantil (<5 anos)", manifesto)
manifesto <- coletar_e_salvar_gho(codigo_medicos, "medicos_per_capita",
                                   "Médicos por 1.000 habitantes", manifesto)
manifesto <- coletar_e_salvar_gho(codigo_obesidade, "obesidade",
                                   "Prevalência de obesidade", manifesto)

# -----------------------------------------------------------------------
# 3. Coleta World Bank
# -----------------------------------------------------------------------

coletar_e_salvar_wb <- function(codigo, nome_arquivo, nome_legivel, manifesto) {
  dados <- wb_obter_dados(codigo, ANO_INICIO, ANO_FIM)

  if (nrow(dados) == 0) {
    message(sprintf("[AVISO] '%s' (%s) retornou 0 linhas.", nome_legivel, codigo))
    return(manifesto)
  }

  caminho <- sprintf("data/raw/worldbank/%s.csv", nome_arquivo)
  write_csv(dados, caminho)
  message(sprintf("[OK] '%s' salvo em %s (%d linhas)", nome_legivel, caminho, nrow(dados)))

  registrar_manifesto(manifesto, "World Bank", codigo, nome_legivel, nrow(dados))
}

manifesto <- coletar_e_salvar_wb("NY.GDP.PCAP.PP.KD", "pib_per_capita",
                                  "PIB per capita (PPP, US$ 2017)", manifesto)
manifesto <- coletar_e_salvar_wb("SE.SCH.LIFE", "escolaridade_esperada",
                                  "Anos esperados de escolaridade", manifesto)
manifesto <- coletar_e_salvar_wb("SP.POP.TOTL", "populacao",
                                  "População total", manifesto)

# -----------------------------------------------------------------------
# IMPORTANTE — passo manual necessário:
# Confira os candidatos impressos em candidatos_gasto_saude_wb e
# candidatos_tabagismo_wb (rodados na Seção 1b) e preencha os dois
# códigos abaixo antes de rodar a coleta completa.
# -----------------------------------------------------------------------
codigo_gasto_saude_wb <- "SH.XPD.CHEX.PP.CD"  # Current health expenditure per capita, PPP (current international $)
codigo_tabagismo_wb   <- "SH.PRV.SMOK"        # Prevalence of current tobacco use (% of adults), total

if (!is.null(codigo_gasto_saude_wb)) {
  manifesto <- coletar_e_salvar_wb(codigo_gasto_saude_wb, "gasto_saude",
                                    "Gasto em saúde per capita", manifesto)
} else {
  message("[PULADO] 'Gasto em saúde' — código do World Bank ainda não confirmado.")
}

if (!is.null(codigo_tabagismo_wb)) {
  manifesto <- coletar_e_salvar_wb(codigo_tabagismo_wb, "tabagismo",
                                    "Prevalência de tabagismo", manifesto)
} else {
  message("[PULADO] 'Tabagismo' — código do World Bank ainda não confirmado.")
}

# -----------------------------------------------------------------------
# 4. Salvar manifesto de coleta
# -----------------------------------------------------------------------

write_csv(manifesto, "data/raw/manifesto_coleta.csv")
message(sprintf("\nColeta concluída. Manifesto salvo com %d indicadores coletados com sucesso.",
                 nrow(manifesto)))
