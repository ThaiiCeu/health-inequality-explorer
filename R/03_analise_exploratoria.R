# =============================================================================
# 03_analise_exploratoria.R
# Health Inequality Explorer — Análise exploratória
#
# Para cada análise abaixo, seguimos a estrutura pedida no escopo do
# projeto: (1) qual pergunta ela responde, (2) por que essa técnica é
# adequada, (3) como interpretar o resultado, (4) quais as limitações.
# Isso é documentado em comentários acima de cada bloco — não é só
# estética, cada gráfico existe para responder algo específico.
#
# Este script cobre o núcleo da Fase 5. Análises adicionais (evolução
# temporal detalhada por indicador, scatter de mortalidade infantil)
# ficam para depois de validarmos que esta primeira rodada está
# correta — construir tudo de uma vez dificulta revisar cada peça.
# =============================================================================

source("R/funcoes.R")
library(ggplot2)
library(corrplot)
library(scales)

dados_longos <- read_csv("data/processed/dados_longos.csv", show_col_types = FALSE)
dados_largos <- read_csv("data/processed/dados_largos.csv", show_col_types = FALSE)

# -----------------------------------------------------------------------
# Núcleo vs. secundários
# -----------------------------------------------------------------------
# medicos_per_10k e escolaridade_esperada têm cobertura bem mais fraca
# que os outros 7 indicadores (visto no gráfico de cobertura da
# primeira rodada). Em vez de forçar os 9 juntos — o que reduz a
# amostra para ~74 países mesmo no melhor ano — tratamos esses dois
# como SECUNDÁRIOS: o núcleo de 7 indicadores define o país-ano válido
# para as análises principais (PCA, cluster, regressão base); os dois
# secundários entram só em análises específicas que os exijam,
# aceitando ali uma amostra menor, com essa limitação sempre
# documentada nos resultados que os usarem.

NUCLEO <- c("expectativa_vida", "mortalidade_infantil", "prevalencia_obesidade",
            "pib_per_capita_ppp", "populacao", "gasto_saude_pc_ppp",
            "prevalencia_tabagismo")
SECUNDARIOS <- c("medicos_per_10k", "escolaridade_esperada")

# -----------------------------------------------------------------------
# A. Diagnóstico de cobertura por ano (decisão do ano de referência)
# -----------------------------------------------------------------------
# PERGUNTA: em qual ano temos o maior número de países com dado
# disponível simultaneamente nos 7 indicadores do núcleo? Essa é a
# pergunta que ficou em aberto desde a Fase 2 — agora refeita já
# considerando a decisão de tratar 2 indicadores como secundários.
# POR QUE ESSE GRÁFICO: uma linha por indicador, ao longo dos anos,
# deixa visualmente óbvio onde a cobertura cai.
# COMO INTERPRETAR: procure o platô mais alto e mais recente onde todas
# as linhas do núcleo estão próximas do teto. Anos muito recentes
# (2021-2022) costumam cair por atraso de publicação — não é ausência
# real, é só que a estimativa ainda não saiu.
# LIMITAÇÃO: esse gráfico mostra quantos países têm QUALQUER dado no
# ano, não necessariamente os MESMOS países em todos os indicadores
# simultaneamente — a interseção exata só é confirmada depois de
# filtrar o ano escolhido e checar quantas linhas sobram sem NA.

cobertura_longa <- dados_longos |>
  count(ano, indicador) |>
  mutate(grupo = if_else(indicador %in% NUCLEO, "núcleo", "secundário"))

grafico_cobertura <- ggplot(cobertura_longa, aes(x = ano, y = n, color = indicador, linetype = grupo)) +
  geom_line(linewidth = 0.8) +
  labs(
    title = "Cobertura de países por indicador e ano",
    x = "Ano", y = "Número de países com dado disponível",
    color = "Indicador", linetype = "Grupo"
  ) +
  theme_minimal()

ggsave("outputs/figures/cobertura_por_ano.png", grafico_cobertura, width = 10, height = 6, bg = "white")
message("Gráfico de cobertura salvo em outputs/figures/cobertura_por_ano.png")

# Sugestão automática: ano com maior número de países tendo os 7
# indicadores do NÚCLEO simultaneamente presentes.
cobertura_simultanea_nucleo <- dados_largos |>
  filter(if_all(all_of(NUCLEO), ~ !is.na(.x))) |>
  count(ano, sort = TRUE)

message("\nAnos com mais países tendo os 7 indicadores do NÚCLEO simultaneamente:")
print(head(cobertura_simultanea_nucleo, 10))
message("\n=> Use essa lista + o gráfico salvo para decidir ANO_REFERENCIA abaixo.")

# -----------------------------------------------------------------------
# IMPORTANTE — decisão manual:
# Preencha o ano de referência depois de olhar o gráfico e a tabela
# acima. Deixamos 2019 como valor inicial sugerido (pré-pandemia,
# evita distorção do COVID nos indicadores de mortalidade), mas troque
# se a cobertura simultânea do núcleo apontar para outro ano melhor.
# -----------------------------------------------------------------------
ANO_REFERENCIA <- 2015

dados_corte <- dados_largos |> filter(ano == ANO_REFERENCIA)

message(sprintf(
  "\nCorte transversal em %d: %d países.",
  ANO_REFERENCIA, nrow(dados_corte)
))
message(sprintf(
  "Países com o NÚCLEO (7 indicadores) completo nesse ano: %d",
  dados_corte |> filter(if_all(all_of(NUCLEO), ~ !is.na(.x))) |> nrow()
))
message(sprintf(
  "Países com os 2 SECUNDÁRIOS também completos nesse ano: %d",
  dados_corte |> filter(if_all(c(all_of(NUCLEO), all_of(SECUNDARIOS)), ~ !is.na(.x))) |> nrow()
))

# Salva o corte transversal para reuso nas próximas fases (regressão,
# PCA, clusterização) — evita recalcular a decisão de ano/núcleo toda
# vez. Guardamos também a versão restrita ao núcleo completo (usada
# como amostra principal de PCA/cluster/regressão) e a versão restrita
# aos 9 indicadores completos (usada em análises de robustez).
write_csv(dados_corte, "data/processed/dados_corte.csv")

dados_corte_nucleo <- dados_corte |> filter(if_all(all_of(NUCLEO), ~ !is.na(.x)))
write_csv(dados_corte_nucleo, "data/processed/dados_corte_nucleo.csv")

dados_corte_completo <- dados_corte |> filter(if_all(c(all_of(NUCLEO), all_of(SECUNDARIOS)), ~ !is.na(.x)))
write_csv(dados_corte_completo, "data/processed/dados_corte_completo.csv")

message("Cortes transversais salvos em data/processed/ (dados_corte.csv, dados_corte_nucleo.csv, dados_corte_completo.csv)")

# -----------------------------------------------------------------------
# B. Estatísticas descritivas
# -----------------------------------------------------------------------
# PERGUNTA: qual a distribuição típica (centro, dispersão, amplitude)
# de cada indicador no ano de referência?
# POR QUE: é o ponto de partida obrigatório antes de qualquer modelo —
# sem isso não sabemos se as variáveis têm escalas muito diferentes
# (o que pediria padronização antes do PCA) ou assimetrias fortes (o
# que pediria log-transformação antes da regressão).
# LIMITAÇÃO: médias e desvios-padrão escondem multimodalidade — países
# muito ricos e muito pobres podem gerar uma distribuição bimodal que
# a média sozinha não revela. Os histogramas da seção C complementam isso.

variaveis_numericas <- dados_corte |>
  select(expectativa_vida, mortalidade_infantil, medicos_per_10k,
         prevalencia_obesidade, pib_per_capita_ppp, escolaridade_esperada,
         gasto_saude_pc_ppp, prevalencia_tabagismo)

descritivas <- variaveis_numericas |>
  pivot_longer(everything(), names_to = "indicador", values_to = "valor") |>
  filter(!is.na(valor)) |>
  group_by(indicador) |>
  summarise(
    n = n(),
    media = mean(valor),
    mediana = median(valor),
    desvio_padrao = sd(valor),
    minimo = min(valor),
    maximo = max(valor),
    .groups = "drop"
  )

write_csv(descritivas, "outputs/tables/estatisticas_descritivas.csv")
message("\nEstatísticas descritivas salvas em outputs/tables/estatisticas_descritivas.csv")
print(descritivas)

# -----------------------------------------------------------------------
# C. Distribuições (histogramas)
# -----------------------------------------------------------------------
# PERGUNTA: as variáveis-chave (expectativa de vida e PIB per capita)
# são simétricas ou enviesadas?
# POR QUE HISTOGRAMA: é a forma mais direta de ver assimetria, e
# assimetria importa diretamente para decisões metodológicas — PIB per
# capita é classicamente enviesado à direita (poucos países muito
# ricos puxando a cauda), o que geralmente pede transformação log
# antes de usá-lo em regressão ou PCA.
# COMO INTERPRETAR: cauda longa à direita = enviesado à direita
# (poucos valores muito altos). Dois picos = possível heterogeneidade
# de grupo (ex.: países desenvolvidos vs. em desenvolvimento).
# LIMITAÇÃO: o número de faixas (bins) do histograma pode exagerar ou
# esconder padrões — sempre olhar com mais de uma largura de faixa
# antes de tirar conclusões fortes.

grafico_hist_expectativa <- ggplot(dados_corte, aes(x = expectativa_vida)) +
  geom_histogram(bins = 30, fill = "#1D9E75", color = "white") +
  labs(title = "Distribuição da expectativa de vida ao nascer",
       x = "Expectativa de vida (anos)", y = "Número de países") +
  theme_minimal()
ggsave("outputs/figures/hist_expectativa_vida.png", grafico_hist_expectativa, width = 8, height = 5, bg = "white")

grafico_hist_pib <- ggplot(dados_corte, aes(x = pib_per_capita_ppp)) +
  geom_histogram(bins = 30, fill = "#378ADD", color = "white") +
  scale_x_continuous(labels = label_dollar(prefix = "$")) +
  labs(title = "Distribuição do PIB per capita (PPP)",
       x = "PIB per capita (US$ PPP)", y = "Número de países") +
  theme_minimal()
ggsave("outputs/figures/hist_pib_per_capita.png", grafico_hist_pib, width = 8, height = 5, bg = "white")

message("Histogramas salvos em outputs/figures/hist_expectativa_vida.png e hist_pib_per_capita.png")

# -----------------------------------------------------------------------
# D. Dispersão: expectativa de vida vs. PIB per capita
# -----------------------------------------------------------------------
# PERGUNTA: existe relação entre desenvolvimento econômico e
# expectativa de vida, e ela parece linear ou de retornos decrescentes?
# POR QUE SCATTER: é a forma padrão de inspecionar visualmente a forma
# de uma relação bivariada antes de assumir um modelo linear na etapa
# de regressão.
# COMO INTERPRETAR: se a nuvem de pontos parece uma curva que achata
# (não uma reta), isso sugere retornos decrescentes — o que justifica
# usar log(PIB per capita) na regressão em vez do valor bruto (H1 da
# Fase 1). A cor por região ajuda a ver se a relação é consistente
# entre grupos ou se há padrões regionais distintos.
# LIMITAÇÃO: correlação (mesmo visual) não implica causalidade — países
# ricos também tendem a ter mais anos de escolaridade e melhor acesso
# à saúde, então o efeito "puro" do PIB só pode ser isolado com
# regressão múltipla (Fase 6), não com este gráfico sozinho.

grafico_dispersao <- ggplot(dados_corte, aes(x = pib_per_capita_ppp, y = expectativa_vida, color = regiao)) +
  geom_point(alpha = 0.7, size = 2) +
  scale_x_log10(labels = label_dollar(prefix = "$")) +
  labs(
    title = "Expectativa de vida vs. PIB per capita (escala log)",
    x = "PIB per capita, PPP (escala log)", y = "Expectativa de vida (anos)",
    color = "Região"
  ) +
  theme_minimal()

ggsave("outputs/figures/dispersao_expectativa_pib.png", grafico_dispersao, width = 10, height = 6, bg = "white")
message("Gráfico de dispersão salvo em outputs/figures/dispersao_expectativa_pib.png")

# -----------------------------------------------------------------------
# E. Matriz de correlação
# -----------------------------------------------------------------------
# PERGUNTA: quais pares de indicadores estão mais fortemente
# associados entre si, e existe risco de multicolinearidade para a
# regressão da Fase 6?
# POR QUE CORRELAÇÃO (Pearson): estamos avaliando relações lineares
# aproximadas entre variáveis contínuas; Pearson é o padrão para essa
# checagem inicial, com a ressalva de que só captura relação linear.
# COMO INTERPRETAR: valores próximos de +1/-1 entre DUAS VARIÁVEIS
# EXPLICATIVAS (não a variável resposta) são um alerta de
# multicolinearidade — ex.: se PIB per capita e gasto em saúde tiverem
# correlação muito alta, a regressão terá dificuldade de separar o
# efeito de cada um.
# LIMITAÇÃO: correlação de Pearson não captura relações não-lineares
# (como a de retornos decrescentes vista no scatter acima) e é
# sensível a outliers — não interpretar como causalidade em nenhuma
# hipótese.

matriz_correlacao <- variaveis_numericas |>
  cor(use = "pairwise.complete.obs", method = "pearson")

# Diagnóstico: se alguma coluna ficar inteiramente NA na matriz (ex.:
# 'prevalencia_tabagismo' apareceu com '?' em todas as células na
# primeira rodada), a causa mais provável é essa variável não ter
# NENHUMA observação não-NA no ano de referência escolhido — o que
# aconteceria se ANO_REFERENCIA cair fora do período coberto por ela.
# Reportamos isso explicitamente em vez de deixar o gráfico mostrar um
# símbolo ambíguo sem explicação.
colunas_totalmente_na <- names(which(colSums(!is.na(matriz_correlacao)) <= 1))
if (length(colunas_totalmente_na) > 0) {
  message(sprintf(
    "[ATENÇÃO] Correlação não pôde ser calculada para: %s — provavelmente sem dado no ano %d. Verifique cobertura_por_ano.csv.",
    paste(colunas_totalmente_na, collapse = ", "), ANO_REFERENCIA
  ))
}

message("\nMatriz de correlação (valores exatos, para conferir contra o gráfico):")
print(round(matriz_correlacao, 2))

png("outputs/figures/matriz_correlacao.png", width = 1100, height = 1100, res = 130)
corrplot(matriz_correlacao, method = "color", type = "upper",
         addCoef.col = "black", number.cex = 0.65,
         tl.col = "black", tl.srt = 45, tl.cex = 0.8,
         na.label = "NA",
         title = "Matriz de correlação (Pearson) — indicadores no ano de referência",
         mar = c(0, 0, 2, 0))
dev.off()

message("Matriz de correlação salva em outputs/figures/matriz_correlacao.png")

# -----------------------------------------------------------------------
# F. Comparação entre regiões (boxplot)
# -----------------------------------------------------------------------
# PERGUNTA: a expectativa de vida varia sistematicamente entre as
# regiões do mundo, e essa variação é maior entre regiões ou dentro de
# cada região?
# POR QUE BOXPLOT: resume distribuição inteira (mediana, quartis,
# outliers) por grupo em um único gráfico, permitindo comparar
# variabilidade ENTRE grupos e DENTRO de cada grupo ao mesmo tempo.
# COMO INTERPRETAR: caixas com pouca sobreposição entre regiões
# indicam diferença regional consistente; caixas altas (longo
# intervalo interquartil) indicam heterogeneidade forte dentro da
# própria região — nesse caso, "região" sozinha não é um bom preditor,
# reforçando por que olhamos clusters na Fase 7 em vez de só a divisão
# geográfica oficial (H5 da Fase 1).
# LIMITAÇÃO: boxplot não mostra o tamanho da amostra por região —
# regiões com poucos países podem parecer mais "compactas" só por
# terem menos observações, não por serem de fato mais homogêneas.

grafico_boxplot_regiao <- ggplot(dados_corte |> filter(!is.na(expectativa_vida)),
                                  aes(x = reorder(regiao, expectativa_vida, FUN = median),
                                      y = expectativa_vida, fill = regiao)) +
  geom_boxplot(show.legend = FALSE) +
  coord_flip() +
  labs(
    title = "Expectativa de vida por região",
    x = NULL, y = "Expectativa de vida (anos)"
  ) +
  theme_minimal()

ggsave("outputs/figures/boxplot_expectativa_regiao.png", grafico_boxplot_regiao, width = 9, height = 6, bg = "white")
message("Boxplot por região salvo em outputs/figures/boxplot_expectativa_regiao.png")

# -----------------------------------------------------------------------
# G. Evolução temporal: expectativa de vida por região (2000-2022)
# -----------------------------------------------------------------------
# PERGUNTA: como a expectativa de vida média evoluiu ao longo do tempo
# em cada região, e existem choques visíveis (quedas abruptas que
# sinalizam crises, conflitos ou eventos específicos)?
# POR QUE LINHA TEMPORAL: é a forma padrão de visualizar tendência ao
# longo de um período contínuo; usar a MÉDIA REGIONAL (não os 217
# países individuais) evita poluição visual e deixa o padrão principal
# — convergência ou divergência entre regiões — visível.
# COMO INTERPRETAR: linhas subindo de forma consistente indicam
# progresso sustentado. Quedas abruptas e localizadas (um único ano)
# geralmente indicam eventos específicos (conflito, epidemia) — não
# uma reversão estrutural de tendência. Linhas que se aproximam ao
# longo do tempo sugerem convergência entre regiões mais e menos
# desenvolvidas; linhas que se afastam sugerem divergência.
# LIMITAÇÃO: a média regional esconde heterogeneidade interna — uma
# região "estável" na média pode ter países individuais em trajetórias
# opostas (alguns subindo, outros caindo) que se cancelam na agregação.

evolucao_regional <- dados_longos |>
  filter(indicador == "expectativa_vida") |>
  group_by(ano, regiao) |>
  summarise(media_regional = mean(valor, na.rm = TRUE), .groups = "drop")

grafico_evolucao <- ggplot(evolucao_regional, aes(x = ano, y = media_regional, color = regiao)) +
  geom_line(linewidth = 0.9) +
  labs(
    title = "Evolução da expectativa de vida média por região (2000-2022)",
    x = "Ano", y = "Expectativa de vida média (anos)",
    color = "Região"
  ) +
  theme_minimal()

ggsave("outputs/figures/evolucao_expectativa_regiao.png", grafico_evolucao, width = 10, height = 6, bg = "white")
message("Gráfico de evolução temporal salvo em outputs/figures/evolucao_expectativa_regiao.png")

# -----------------------------------------------------------------------
# H. Dispersão: mortalidade infantil vs. PIB per capita
# -----------------------------------------------------------------------
# PERGUNTA: mortalidade infantil segue o mesmo padrão de retornos
# decrescentes visto na expectativa de vida (Seção D), ou a relação com
# renda tem formato diferente? Essa é a pergunta secundária 4 da Fase 1
# — testar se os fatores associados à mortalidade infantil são
# distintos dos associados à expectativa de vida geral.
# POR QUE ESCALA LOG NOS DOIS EIXOS: mortalidade infantil também é
# fortemente enviesada à direita (poucos países com valores muito
# altos) — usar log em ambos os eixos costuma linearizar melhor esse
# tipo de relação do que log só no eixo x, o que ajuda a comparar
# visualmente com o gráfico da Seção D.
# COMO INTERPRETAR: se a relação parecer mais "íngreme" ou mais abrupta
# que a da expectativa de vida (queda rápida de mortalidade já em
# níveis baixos de renda, depois estabilização), isso sugere que
# mortalidade infantil é mais sensível a acesso básico a saúde do que
# a riqueza em si — consistente com a H3 da Fase 1.
# LIMITAÇÃO: mesma ressalva de causalidade da Seção D — países mais
# ricos também têm melhor cobertura vacinal e acesso a saneamento, que
# não estão isolados aqui.

grafico_dispersao_mortalidade <- ggplot(dados_corte, aes(x = pib_per_capita_ppp, y = mortalidade_infantil, color = regiao)) +
  geom_point(alpha = 0.7, size = 2) +
  scale_x_log10(labels = label_dollar(prefix = "$")) +
  scale_y_log10() +
  labs(
    title = "Mortalidade infantil vs. PIB per capita (escala log-log)",
    x = "PIB per capita, PPP (escala log)", y = "Mortalidade infantil, <5 anos (escala log)",
    color = "Região"
  ) +
  theme_minimal()

ggsave("outputs/figures/dispersao_mortalidade_pib.png", grafico_dispersao_mortalidade, width = 10, height = 6, bg = "white")
message("Gráfico de dispersão (mortalidade infantil) salvo em outputs/figures/dispersao_mortalidade_pib.png")

message("\nAnálise exploratória (completa) concluída. Reveja os gráficos em outputs/figures/ antes de seguirmos para a Fase 6 (análise estatística).")
