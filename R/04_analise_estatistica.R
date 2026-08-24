# =============================================================================
# 04_analise_estatistica.R
# Health Inequality Explorer — Análise estatística (regressão)
#
# Testa a H1, H2 e H4 da Fase 1: PIB per capita e gasto em saúde
# explicam expectativa de vida (com retornos decrescentes / log), gasto
# em saúde tem efeito incremental além do PIB, e o resíduo do modelo
# nos dá os países "acima/abaixo do esperado" (isso é preparado aqui,
# mas a classificação final fica para a Fase 8).
#
# Decisão de amostra: usamos o núcleo de 7 indicadores (N=159, ano
# 2015) como amostra principal, e o conjunto completo de 9 indicadores
# (N=74) como checagem de robustez — não o contrário — porque perder
# 85 países só para incluir 2 variáveis secundárias arriscaria mudar
# os resultados por composição de amostra, não por efeito real.
# =============================================================================

source("R/funcoes.R")
library(broom)
library(performance)
library(ggplot2)
library(sandwich)
library(lmtest)

dados_nucleo <- read_csv("data/processed/dados_corte_nucleo.csv", show_col_types = FALSE)
dados_completo <- read_csv("data/processed/dados_corte_completo.csv", show_col_types = FALSE)

message(sprintf("Amostra principal (núcleo): %d países.", nrow(dados_nucleo)))
message(sprintf("Amostra de robustez (núcleo + secundários): %d países.", nrow(dados_completo)))

# -----------------------------------------------------------------------
# A. Correlação de Spearman vs. Pearson (checagem de linearidade)
# -----------------------------------------------------------------------
# PERGUNTA: as relações entre expectativa de vida e as explicativas são
# predominantemente lineares, ou existe não-linearidade monotônica que
# o Pearson (calculado na Fase 5) não captura bem?
# POR QUE SPEARMAN: mede associação monotônica (não exige relação
# linear) — comparar Spearman com Pearson é uma forma padrão de
# detectar não-linearidade: se Spearman for bem maior que Pearson para
# um par de variáveis, a relação existe mas não é linear (reforça a
# necessidade de log() que já aplicamos com base no exploratório).
# COMO INTERPRETAR: diferenças pequenas (< 0.05) indicam que a
# suposição de linearidade do modelo abaixo é razoável. Diferenças
# grandes indicam que talvez precisemos de outra transformação.
# LIMITAÇÃO: Spearman também não captura relações não-monotônicas
# (em U, por exemplo) — nenhuma das duas substitui inspeção visual.

vars_correlacao <- dados_nucleo |>
  select(expectativa_vida, pib_per_capita_ppp, gasto_saude_pc_ppp,
         prevalencia_obesidade, prevalencia_tabagismo, populacao)

pearson <- cor(vars_correlacao, use = "pairwise.complete.obs", method = "pearson")["expectativa_vida", ]
spearman <- cor(vars_correlacao, use = "pairwise.complete.obs", method = "spearman")["expectativa_vida", ]

comparacao_correlacao <- tibble(
  variavel = names(pearson),
  pearson = round(pearson, 3),
  spearman = round(spearman, 3),
  diferenca = round(spearman - pearson, 3)
) |>
  filter(variavel != "expectativa_vida")

message("\nComparação Pearson vs. Spearman (com expectativa_vida):")
print(comparacao_correlacao)
write_csv(comparacao_correlacao, "outputs/tables/comparacao_pearson_spearman.csv")

# -----------------------------------------------------------------------
# B. Modelo de regressão — abordagem hierárquica (em blocos)
# -----------------------------------------------------------------------
# PERGUNTA CENTRAL (H1 e H2 da Fase 1): PIB per capita explica
# expectativa de vida com retornos decrescentes, e gasto em saúde
# acrescenta poder explicativo ALÉM do que o PIB já explica sozinho?
# POR QUE ABORDAGEM HIERÁRQUICA (Modelo 1 sem gasto_saude, Modelo 2
# com gasto_saude) EM VEZ DE UM ÚNICO MODELO COM TUDO: a Fase 5 já
# mostrou PIB e gasto em saúde correlacionados em 0.86 — colocar os
# dois soltos num único modelo deixaria os coeficientes individuais
# instáveis (VIF alto) e difíceis de interpretar. Comparar os dois
# modelos em sequência isola exatamente a pergunta que queremos
# responder: "gasto em saúde adiciona algo além do PIB?" — sem
# precisar decidir arbitrariamente qual variável descartar.
# TRANSFORMAÇÕES: log(PIB), log(gasto em saúde) e log(população) —
# todas mostraram forte assimetria à direita na Fase 5 (Seção B/C).
# Obesidade e tabagismo entram sem transformação (são percentuais,
# sem assimetria extrema nas descritivas da Fase 5).
# COMO INTERPRETAR: se o R² do Modelo 2 for significativamente maior
# que o do Modelo 1 (teste F via anova()) E o coeficiente de
# log(gasto_saude) for significativo no Modelo 2, isso sustenta a H2.
# Coeficientes em variáveis logadas se leem como: "um aumento de 1% em
# X está associado a uma mudança de (coeficiente/100) anos na
# expectativa de vida" (aproximação padrão para log-nível).
# LIMITAÇÃO: mesmo com essa abordagem, a correlação residual entre as
# duas variáveis significa que parte do efeito atribuído a uma pode
# realmente pertencer à outra — isso é uma limitação de dados
# observacionais, não algo que a técnica resolve completamente.

modelo_1_base <- lm(
  expectativa_vida ~ log(pib_per_capita_ppp) + prevalencia_obesidade +
    prevalencia_tabagismo + log(populacao),
  data = dados_nucleo
)

modelo_2_com_saude <- lm(
  expectativa_vida ~ log(pib_per_capita_ppp) + prevalencia_obesidade +
    prevalencia_tabagismo + log(populacao) + log(gasto_saude_pc_ppp),
  data = dados_nucleo
)

message("\n=== Modelo 1 (base, sem gasto em saúde) ===")
print(summary(modelo_1_base))

message("\n=== Modelo 2 (com gasto em saúde) ===")
print(summary(modelo_2_com_saude))

message("\n=== Comparação Modelo 1 vs. Modelo 2 (teste F) ===")
comparacao_modelos <- anova(modelo_1_base, modelo_2_com_saude)
print(comparacao_modelos)

# O teste F clássico acima assume variância constante — dado que a
# Seção D detecta heterocedasticidade, complementamos com uma versão
# robusta do teste (Wald robusto a HC3), que não depende dessa
# suposição. Se as duas conclusões baterem, a comparação é confiável;
# se divergirem, prevalece a versão robusta.
message("\n=== Comparação Modelo 1 vs. Modelo 2 (teste robusto a heterocedasticidade) ===")
comparacao_robusta <- waldtest(modelo_1_base, modelo_2_com_saude, vcov = vcovHC(modelo_2_com_saude, type = "HC3"))
print(comparacao_robusta)

# Tabelas organizadas (coeficientes) salvas para uso no dashboard.
tidy_modelo_1 <- tidy(modelo_1_base, conf.int = TRUE)
tidy_modelo_2 <- tidy(modelo_2_com_saude, conf.int = TRUE)

write_csv(tidy_modelo_1, "outputs/tables/regressao_modelo1_base.csv")
write_csv(tidy_modelo_2, "outputs/tables/regressao_modelo2_com_saude.csv")

message(sprintf(
  "\nR² ajustado — Modelo 1: %.3f | Modelo 2: %.3f",
  summary(modelo_1_base)$adj.r.squared,
  summary(modelo_2_com_saude)$adj.r.squared
))

# -----------------------------------------------------------------------
# C. Multicolinearidade (VIF) no modelo final
# -----------------------------------------------------------------------
# PERGUNTA: mesmo com a abordagem hierárquica, o Modelo 2 tem
# multicolinearidade problemática entre as variáveis que sobraram
# juntas nele?
# POR QUE VIF: Variance Inflation Factor mede quanto a variância de
# cada coeficiente está inflada por correlação com as outras
# explicativas — é o diagnóstico padrão para multicolinearidade em
# regressão múltipla.
# COMO INTERPRETAR: VIF > 5 é motivo de atenção; VIF > 10 é
# problemático e exige ação (remover ou combinar variáveis).
# LIMITAÇÃO: VIF não diz QUAL variável remover, só que existe
# redundância — a decisão de qual manter é sempre teórica/metodológica,
# não puramente estatística.

vif_modelo2 <- check_collinearity(modelo_2_com_saude)
message("\nVIF do Modelo 2 (com gasto em saúde):")
print(vif_modelo2)

# -----------------------------------------------------------------------
# D. Diagnóstico de resíduos do modelo final
# -----------------------------------------------------------------------
# PERGUNTA: os pressupostos da regressão linear (normalidade dos
# resíduos, homocedasticidade, ausência de observações excessivamente
# influentes) são razoavelmente atendidos pelo Modelo 2?
# POR QUE ESSES TESTES: são os pressupostos que sustentam a validade
# dos p-valores e intervalos de confiança reportados acima — sem
# checá-los, os testes de significância podem estar enviesados.
# COMO INTERPRETAR: teste de Shapiro-Wilk com p > 0.05 não rejeita
# normalidade dos resíduos (bom sinal). Teste de heterocedasticidade
# (Breusch-Pagan) com p > 0.05 não rejeita homocedasticidade (bom
# sinal). Observações com distância de Cook muito acima das demais são
# candidatas a investigação individual (não remoção automática).
# LIMITAÇÃO: com N=159, esses testes têm razoável poder estatístico,
# mas ainda assim são sensíveis a poucos pontos extremos — sempre
# olhar os gráficos, não só o p-valor do teste.

teste_normalidade <- check_normality(modelo_2_com_saude)
message("\nTeste de normalidade dos resíduos (Shapiro-Wilk):")
print(teste_normalidade)

teste_heterocedasticidade <- check_heteroscedasticity(modelo_2_com_saude)
message("\nTeste de heterocedasticidade (Breusch-Pagan):")
print(teste_heterocedasticidade)

outliers_influentes <- check_outliers(modelo_2_com_saude)
message("\nObservações potencialmente influentes (distância de Cook):")
print(outliers_influentes)

# Gráficos de diagnóstico (resíduos vs. ajustados, QQ-plot, etc.)
png("outputs/figures/diagnostico_regressao.png", width = 1400, height = 1000, res = 130)
print(check_model(modelo_2_com_saude))
dev.off()
message("\nGráficos de diagnóstico salvos em outputs/figures/diagnostico_regressao.png")

# -----------------------------------------------------------------------
# D2. Correção: erros-padrão robustos a heterocedasticidade (HC3)
# -----------------------------------------------------------------------
# PERGUNTA: os p-valores do Modelo 2 continuam válidos depois de
# corrigir para a heterocedasticidade detectada acima?
# POR QUE HC3: os testes de Breusch-Pagan e Shapiro-Wilk rejeitaram os
# pressupostos de variância constante e normalidade dos resíduos — os
# erros-padrão "clássicos" do summary() acima podem estar sub ou
# superestimados. HC3 (Heteroscedasticity-Consistent, variante 3) é a
# correção padrão nesse cenário: recalcula os erros-padrão sem assumir
# variância constante, sem precisar re-especificar o modelo.
# COMO INTERPRETAR: comparar a coluna 'Pr(>|t|)' aqui com a do
# summary() original — se uma variável perde significância só com essa
# correção, sua significância original era artefato da heterocedasticidade,
# não um efeito robusto.
# LIMITAÇÃO: HC3 corrige o erro-padrão, não resolve a não-normalidade
# dos resíduos nem a multicolinearidade (VIF alto continua sendo um
# problema à parte, tratado na Seção C).

message("\n=== Modelo 2 com erros-padrão robustos (HC3) ===")
modelo_2_robusto <- coeftest(modelo_2_com_saude, vcov = vcovHC(modelo_2_com_saude, type = "HC3"))
print(modelo_2_robusto)

tidy_modelo_2_robusto <- broom::tidy(modelo_2_robusto)
write_csv(tidy_modelo_2_robusto, "outputs/tables/regressao_modelo2_robusto_hc3.csv")

# -----------------------------------------------------------------------
# E. Checagem de robustez: amostra completa (N=74) com secundários
# -----------------------------------------------------------------------
# PERGUNTA: os efeitos de PIB e gasto em saúde encontrados no núcleo
# (N=159) se mantêm quando adicionamos médicos per capita e
# escolaridade — mesmo com uma amostra bem menor e potencialmente
# enviesada para países de melhor cobertura estatística?
# POR QUE ISSO IMPORTA: um efeito que só aparece com N=159 mas some
# com N=74 pode ser fragilidade estatística, não um achado real. Um
# efeito que se mantém nas duas amostras é evidência bem mais forte.
# LIMITAÇÃO: a amostra de 74 países não é aleatória — são os países
# com melhor infraestrutura estatística (em geral, mais desenvolvidos),
# então qualquer diferença de resultado entre as duas amostras pode
# refletir esse viés de seleção, não necessariamente uma mudança real
# no efeito.

modelo_robustez <- lm(
  expectativa_vida ~ log(pib_per_capita_ppp) + prevalencia_obesidade +
    prevalencia_tabagismo + log(populacao) + log(gasto_saude_pc_ppp) +
    escolaridade_esperada + medicos_per_10k,
  data = dados_completo
)

message("\n=== Modelo de robustez (N=74, com secundários) ===")
print(summary(modelo_robustez))

tidy_robustez <- tidy(modelo_robustez, conf.int = TRUE)
write_csv(tidy_robustez, "outputs/tables/regressao_modelo_robustez.csv")

# -----------------------------------------------------------------------
# F. Especificação alternativa: gasto em saúde "residualizado" (ortogonal ao PIB)
# -----------------------------------------------------------------------
# PERGUNTA: entre países de renda parecida, gastar em saúde MAIS do que
# o esperado para aquele nível de renda está associado a maior
# expectativa de vida? Essa é uma versão mais limpa da H2 — em vez de
# perguntar "PIB e gasto em saúde, cada um, quanto explicam", perguntamos
# "gastar acima ou abaixo do que a renda prevê faz diferença?".
# POR QUE RESIDUALIZAR: regredimos log(gasto_saude) sobre log(PIB) e
# usamos o RESÍDUO dessa regressão como preditor. Por construção
# (propriedade algébrica de MQO), esse resíduo tem correlação ZERO com
# log(PIB) — o que elimina o VIF>10 sem descartar nenhuma informação:
# toda a variação de gasto em saúde que não é "só PIB" continua no
# modelo, isolada.
# COMO INTERPRETAR: um coeficiente positivo e significativo no resíduo
# significa que, mesmo COMPARANDO países de renda parecida, quem gasta
# mais que o esperado em saúde tem expectativa de vida
# sistematicamente maior — uma versão mais defensável da H2 do que a
# tentativa original com as duas variáveis brutas.
# LIMITAÇÃO: essa técnica resolve a colinearidade, mas não resolve
# causalidade — países que "gastam mais que o esperado" podem ter
# outras características não observadas (qualidade institucional,
# estabilidade política) que também afetam expectativa de vida.

modelo_residualizacao <- lm(log(gasto_saude_pc_ppp) ~ log(pib_per_capita_ppp), data = dados_nucleo)
dados_nucleo_resid <- dados_nucleo |>
  mutate(gasto_saude_residual = resid(modelo_residualizacao))

modelo_3_residualizado <- lm(
  expectativa_vida ~ log(pib_per_capita_ppp) + prevalencia_obesidade +
    prevalencia_tabagismo + log(populacao) + gasto_saude_residual,
  data = dados_nucleo_resid
)

message("\n=== Modelo 3 (gasto em saúde residualizado, ortogonal ao PIB) ===")
print(summary(modelo_3_residualizado))

message("\nVIF do Modelo 3 (deve estar baixo agora, sem o problema de colinearidade):")
print(check_collinearity(modelo_3_residualizado))

message("\nModelo 3 com erros-padrão robustos (HC3):")
modelo_3_robusto <- coeftest(modelo_3_residualizado, vcov = vcovHC(modelo_3_residualizado, type = "HC3"))
print(modelo_3_robusto)

tidy_modelo_3 <- tidy(modelo_3_residualizado, conf.int = TRUE)
write_csv(tidy_modelo_3, "outputs/tables/regressao_modelo3_residualizado.csv")

message("\nAnálise estatística concluída. Revise outputs/tables/ e outputs/figures/diagnostico_regressao.png antes de seguirmos para a Fase 7 (PCA e clusterização).")
