# =============================================================================
# 06_modelagem.R
# Health Inequality Explorer — Esperado vs. Observado
#
# Pergunta central (Seção 9 do escopo original): dado o perfil
# socioeconômico de um país, qual expectativa de vida seria "esperada"
# — e quais países estão sistematicamente acima ou abaixo disso?
#
# Reaproveitamos a especificação estatística validada na Fase 6
# (Modelo 2/3: PIB, obesidade, tabagismo, população, gasto em saúde)
# em vez de criar um modelo novo — o "esperado" precisa vir do mesmo
# modelo que já diagnosticamos e defendemos, não de uma escolha
# diferente feita só para esta análise.
# =============================================================================

source("R/funcoes.R")
library(broom)
library(ggplot2)
library(ggrepel)

dados_com_cluster <- read_csv("data/processed/dados_com_cluster.csv", show_col_types = FALSE)

# -----------------------------------------------------------------------
# A. Reajustar o modelo final da Fase 6
# -----------------------------------------------------------------------
# Mesma especificação do Modelo 2 (Fase 6) — reajustamos aqui em vez de
# carregar um objeto salvo, para manter o script autocontido e a
# especificação sempre visível/auditável junto com o resultado.

modelo_esperado <- lm(
  expectativa_vida ~ log(pib_per_capita_ppp) + prevalencia_obesidade +
    prevalencia_tabagismo + log(populacao) + log(gasto_saude_pc_ppp),
  data = dados_com_cluster
)

message(sprintf("R² do modelo (mesmo da Fase 6): %.3f", summary(modelo_esperado)$r.squared))

# -----------------------------------------------------------------------
# B. Calcular esperado, resíduo e classificação estatística
# -----------------------------------------------------------------------
# PERGUNTA: quais países têm expectativa de vida observada muito acima
# ou abaixo do que o modelo prevê para o perfil socioeconômico deles?
# POR QUE RESÍDUOS STUDENTIZADOS (não o resíduo bruto): a Fase 6
# detectou heterocedasticidade nesse mesmo modelo — a variância dos
# erros não é constante ao longo dos valores ajustados. Resíduos
# studentizados (rstudent()) ajustam para isso e para a alavancagem de
# cada observação, tornando a comparação entre países mais justa do
# que usar o resíduo bruto (observado - esperado) diretamente.
# CRITÉRIO DE CLASSIFICAÇÃO: ±1 desvio-padrão do resíduo studentizado
# como limite entre "dentro do esperado" e "acima/abaixo do esperado".
# Sob distribuição aproximadamente normal, isso classifica ~68% dos
# países como "dentro do esperado" e ~16% em cada extremo — um
# critério estatístico padrão, não um corte arbitrário escolhido a
# dedo.
# LIMITAÇÃO: o modelo explica ~74% da variância (R² da Fase 6) — os
# ~26% restantes incluem fatores não medidos (qualidade institucional,
# conflitos, epidemias, erros de medição dos próprios indicadores).
# "Abaixo do esperado" não significa "sistema de saúde ruim" — significa
# apenas que a expectativa de vida observada é menor do que as 5
# variáveis do modelo, sozinhas, preveriam.

dados_esperado <- dados_com_cluster |>
  mutate(
    expectativa_esperada = fitted(modelo_esperado),
    residuo_bruto = expectativa_vida - expectativa_esperada,
    residuo_studentizado = rstudent(modelo_esperado)
  )

desvio_padrao_residuo <- sd(dados_esperado$residuo_studentizado)

dados_esperado <- dados_esperado |>
  mutate(
    classificacao = case_when(
      residuo_studentizado > 1  ~ "Acima do esperado",
      residuo_studentizado < -1 ~ "Abaixo do esperado",
      TRUE                      ~ "Dentro do esperado"
    ),
    classificacao = factor(classificacao,
                            levels = c("Abaixo do esperado", "Dentro do esperado", "Acima do esperado"))
  )

message("\nDistribuição da classificação:")
print(table(dados_esperado$classificacao))

# -----------------------------------------------------------------------
# C. Países nos extremos
# -----------------------------------------------------------------------

top_acima <- dados_esperado |>
  filter(classificacao == "Acima do esperado") |>
  arrange(desc(residuo_studentizado)) |>
  select(pais_nome, regiao, nome_cluster, expectativa_vida, expectativa_esperada, residuo_studentizado)

top_abaixo <- dados_esperado |>
  filter(classificacao == "Abaixo do esperado") |>
  arrange(residuo_studentizado) |>
  select(pais_nome, regiao, nome_cluster, expectativa_vida, expectativa_esperada, residuo_studentizado)

message(sprintf("\n%d países acima do esperado. Os 10 mais extremos:", nrow(top_acima)))
print(head(top_acima, 10))

message(sprintf("\n%d países abaixo do esperado. Os 10 mais extremos:", nrow(top_abaixo)))
print(head(top_abaixo, 10))

write_csv(dados_esperado |>
            select(pais_iso3, pais_nome, regiao, nome_cluster, expectativa_vida,
                   expectativa_esperada, residuo_bruto, residuo_studentizado, classificacao),
          "outputs/tables/esperado_vs_observado.csv")

# -----------------------------------------------------------------------
# D. Gráfico: observado vs. esperado
# -----------------------------------------------------------------------
# PERGUNTA: dá para ver visualmente quais países se destacam, e a
# classificação faz sentido perto da linha de 45°?
# POR QUE ESSE GRÁFICO: o eixo x é o que o modelo prevê, o eixo y é o
# que foi observado de verdade — países exatamente sobre a linha
# diagonal (esperado = observado) tiveram resultado igual ao previsto;
# distância vertical da linha é o resíduo.
# COMO INTERPRETAR: pontos bem acima da linha = melhor que o esperado;
# bem abaixo = pior que o esperado. Rotulamos só os 8 mais extremos de
# cada lado para não poluir o gráfico.
# LIMITAÇÃO: como o próprio prompt do projeto pede, isso não é um
# veredito sobre qualidade do sistema de saúde — é só distância em
# relação a um modelo com R²~0.74, sujeito às limitações já
# documentadas na Fase 6 (heterocedasticidade, colinearidade PIB×gasto
# em saúde, N limitado a 159 países).

paises_para_rotular <- bind_rows(head(top_acima, 8), head(top_abaixo, 8))

grafico_esperado_observado <- ggplot(dados_esperado,
                                      aes(x = expectativa_esperada, y = expectativa_vida, color = classificacao)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
  geom_point(alpha = 0.7, size = 2) +
  geom_text_repel(
    data = dados_esperado |> filter(pais_nome %in% paises_para_rotular$pais_nome),
    aes(label = pais_nome), size = 3, max.overlaps = 20, show.legend = FALSE
  ) +
  scale_color_manual(values = c("Abaixo do esperado" = "#E41A1C",
                                 "Dentro do esperado" = "#999999",
                                 "Acima do esperado" = "#377EB8")) +
  labs(
    title = "Expectativa de vida: observada vs. esperada pelo modelo",
    x = "Expectativa de vida esperada (anos)", y = "Expectativa de vida observada (anos)",
    color = "Classificação"
  ) +
  theme_minimal()

ggsave("outputs/figures/esperado_vs_observado.png", grafico_esperado_observado, width = 11, height = 8)
message("\nGráfico salvo em outputs/figures/esperado_vs_observado.png")

# -----------------------------------------------------------------------
# E. Classificação vs. cluster (Fase 7) — cruzamento
# -----------------------------------------------------------------------
# PERGUNTA: "acima/abaixo do esperado" está distribuído igualmente
# entre os 4 clusters de desenvolvimento, ou se concentra em algum
# grupo específico?
# POR QUE ISSO IMPORTA: se "acima do esperado" se concentrasse todo num
# único cluster, isso sugeriria que o modelo está sistematicamente mal
# ajustado para aquele grupo de países (um problema de especificação),
# não uma variação real de desempenho dentro do grupo.
# COMO INTERPRETAR: distribuição parecida entre clusters é o cenário
# mais saudável — significa que o modelo funciona igualmente bem (ou
# mal) para os 4 perfis de desenvolvimento, e que a classificação
# captura variação real dentro de cada grupo, não um viés do modelo.

message("\nCruzamento classificação x cluster:")
print(table(Cluster = dados_esperado$nome_cluster, Classificacao = dados_esperado$classificacao))

message("\nModelagem (esperado vs. observado) concluída. Revise outputs/figures/esperado_vs_observado.png e outputs/tables/esperado_vs_observado.csv antes de seguirmos para a Fase 9 (exportação para o dashboard).")
