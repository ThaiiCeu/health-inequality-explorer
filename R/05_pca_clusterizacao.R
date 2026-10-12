# =============================================================================
# 05_pca_clusterizacao.R
# Health Inequality Explorer — PCA e Clusterização
#
# Pergunta central (Fase 1, pergunta secundária 2): existem grupos de
# países com perfis semelhantes de saúde e desenvolvimento
# socioeconômico? Quais indicadores resumem a maior parte da variação
# entre países?
#
# Variáveis usadas: expectativa_vida, mortalidade_infantil,
# prevalencia_obesidade, pib_per_capita_ppp, gasto_saude_pc_ppp,
# prevalencia_tabagismo — os 6 indicadores de "perfil de
# desenvolvimento/saúde" do núcleo. 'populacao' fica de fora
# deliberadamente: é um indicador de ESCALA (tamanho do país), não de
# desenvolvimento — incluí-la misturaria "país grande" com "país
# desenvolvido", que são conceitos independentes.
# =============================================================================

source("R/funcoes.R")
library(factoextra)
library(cluster)
library(ggplot2)

dados_nucleo <- read_csv("data/processed/dados_corte_nucleo.csv", show_col_types = FALSE)

VARS_PERFIL <- c("expectativa_vida", "mortalidade_infantil", "prevalencia_obesidade",
                  "pib_per_capita_ppp", "gasto_saude_pc_ppp", "prevalencia_tabagismo")

# -----------------------------------------------------------------------
# A. Preparação: transformação e padronização
# -----------------------------------------------------------------------
# PERGUNTA: as variáveis precisam de transformação antes do PCA, e por
# quê padronizar (standardize) é obrigatório aqui?
# POR QUE LOG NAS VARIÁVEIS ASSIMÉTRICAS: PIB per capita, gasto em
# saúde e mortalidade infantil mostraram forte assimetria à direita na
# Fase 5 — sem log, essas variáveis dominariam a variância total do
# PCA só por causa da escala/assimetria, não porque carregam mais
# "sinal" real.
# POR QUE PADRONIZAR (center + scale): PCA é sensível à escala das
# variáveis — sem padronizar, PIB per capita (na casa de dezenas de
# milhares) dominaria completamente sobre prevalência de obesidade
# (0-100), independente do que realmente carregam de informação. Com
# padronização, cada variável entra com média 0 e desvio-padrão 1,
# competindo em pé de igualdade.
# LIMITAÇÃO: padronizar assume que "1 desvio-padrão de mudança" é
# comparável entre variáveis diferentes — uma simplificação necessária
# para tornar o PCA possível, mas que vale ter em mente ao interpretar
# os componentes.

dados_perfil <- dados_nucleo |>
  transmute(
    pais_iso3, pais_nome, regiao,
    expectativa_vida,
    log_mortalidade_infantil = log(mortalidade_infantil),
    prevalencia_obesidade,
    log_pib_per_capita_ppp = log(pib_per_capita_ppp),
    log_gasto_saude_pc_ppp = log(gasto_saude_pc_ppp),
    prevalencia_tabagismo
  )

matriz_perfil <- dados_perfil |>
  select(-pais_iso3, -pais_nome, -regiao) |>
  as.matrix()
rownames(matriz_perfil) <- dados_perfil$pais_iso3

matriz_padronizada <- scale(matriz_perfil, center = TRUE, scale = TRUE)

# -----------------------------------------------------------------------
# B. PCA — extração dos componentes
# -----------------------------------------------------------------------
# PERGUNTA: quantas dimensões latentes resumem a maior parte da
# variação entre os países nesses 6 indicadores, e o que cada
# dimensão representa substantivamente?
# POR QUE PCA: com 6 indicadores correlacionados entre si (vimos isso
# na matriz de correlação da Fase 5 — PIB, gasto em saúde e
# expectativa de vida todos andam juntos), boa parte da "informação"
# é redundante. PCA encontra combinações lineares que capturam o
# máximo de variância com o mínimo de dimensões.
# COMO INTERPRETAR: olhar a "proporção de variância explicada" por
# componente (scree plot) para decidir quantos reter, e os "loadings"
# (rotation) para entender o que cada componente representa — um
# loading alto (positivo ou negativo) numa variável significa que ela
# contribui fortemente para aquele componente.
# LIMITAÇÃO: PCA só captura relações LINEARES entre as variáveis
# originais — e os componentes são combinações matemáticas, não
# "coisas reais" com significado garantido; a interpretação de cada
# componente é sempre uma leitura humana dos loadings, não um fato
# objetivo do algoritmo.

pca_resultado <- prcomp(matriz_padronizada, center = FALSE, scale. = FALSE)

variancia_explicada <- tibble(
  componente = paste0("PC", seq_along(pca_resultado$sdev)),
  desvio_padrao = pca_resultado$sdev,
  variancia = pca_resultado$sdev^2,
  proporcao = variancia / sum(variancia),
  proporcao_acumulada = cumsum(proporcao)
)

message("Variância explicada por componente:")
print(variancia_explicada)
write_csv(variancia_explicada, "outputs/tables/pca_variancia_explicada.csv")

grafico_scree <- fviz_eig(pca_resultado, addlabels = TRUE,
                           main = "Variância explicada por componente (scree plot)")
ggsave("outputs/figures/pca_scree_plot.png", grafico_scree, width = 8, height = 5)

# Regra de retenção: critério de Kaiser (autovalor > 1) E variância
# acumulada. Reportamos os dois critérios em vez de escolher um só —
# quando eles concordam, a decisão fica mais sólida.
n_componentes_kaiser <- sum(pca_resultado$sdev^2 > 1)
message(sprintf(
  "\nCritério de Kaiser (autovalor > 1): reter %d componente(s).",
  n_componentes_kaiser
))
message(sprintf(
  "Variância acumulada com 2 componentes: %.1f%%",
  variancia_explicada$proporcao_acumulada[2] * 100
))

# -----------------------------------------------------------------------
# Loadings — interpretação dos componentes
# -----------------------------------------------------------------------
loadings <- as_tibble(pca_resultado$rotation, rownames = "variavel")
message("\nLoadings dos 2 primeiros componentes:")
print(loadings |> select(variavel, PC1, PC2))
write_csv(loadings, "outputs/tables/pca_loadings.csv")

grafico_loadings <- fviz_pca_var(pca_resultado, col.var = "contrib",
                                  gradient.cols = c("#377EB8", "#E41A1C"),
                                  repel = TRUE,
                                  title = "Contribuição das variáveis aos componentes principais")
ggsave("outputs/figures/pca_loadings_plot.png", grafico_loadings, width = 8, height = 7)

# Biplot com países coloridos por região — checagem visual de que o
# PC1 captura algo parecido com "nível de desenvolvimento" (regiões
# devem se separar de forma coerente com o que já sabemos da Fase 5).
grafico_biplot <- fviz_pca_biplot(pca_resultado,
                                   geom.ind = "point",
                                   col.ind = dados_perfil$regiao,
                                   pointshape = 19, pointsize = 2,
                                   repel = TRUE,
                                   legend.title = "Região",
                                   title = "PCA — países e variáveis (PC1 x PC2)")
ggsave("outputs/figures/pca_biplot.png", grafico_biplot, width = 11, height = 8)

message("\nGráficos de PCA salvos em outputs/figures/ (scree, loadings, biplot).")

# -----------------------------------------------------------------------
# C. Clusterização — número ideal de clusters
# -----------------------------------------------------------------------
# PERGUNTA: quantos grupos de países fazem sentido estatisticamente
# nesse espaço de desenvolvimento/saúde?
# POR QUE ELBOW + SILHOUETTE (os dois, não só um): o método do
# cotovelo (Elbow, baseado na soma de quadrados dentro dos clusters)
# tende a ser subjetivo — o "cotovelo" nem sempre é óbvio. Silhouette
# dá um número objetivo (entre -1 e 1) de quão bem cada país se encaixa
# no seu cluster vs. o cluster mais próximo. Usar os dois em conjunto é
# mais robusto do que confiar em um método só.
# COMO INTERPRETAR: no gráfico do cotovelo, procure o ponto onde
# adicionar mais um cluster para de reduzir a soma de quadrados de
# forma expressiva. No gráfico de silhouette, o k com o maior valor
# médio é o "estatisticamente melhor" — mas vale balancear com
# interpretabilidade (k=2 quase sempre "vence" estatisticamente, mas
# pode ser pouco útil substantivamente).
# LIMITAÇÃO: nenhum desses critérios sabe se os clusters resultantes
# fazem sentido teórico — a decisão final combina o número sugerido
# com a checagem de que os perfis resultantes (Seção E) são
# interpretáveis e distintos.

pca_scores_retidos <- pca_resultado$x[, 1:2]  # PC1 e PC2 (~variância acumulada calculada acima)

grafico_elbow <- fviz_nbclust(pca_scores_retidos, kmeans, method = "wss") +
  labs(title = "Método do cotovelo (Elbow) — soma de quadrados intra-cluster")
ggsave("outputs/figures/cluster_elbow.png", grafico_elbow, width = 8, height = 5)

grafico_silhouette_k <- fviz_nbclust(pca_scores_retidos, kmeans, method = "silhouette") +
  labs(title = "Silhouette médio por número de clusters (K-Means)")
ggsave("outputs/figures/cluster_silhouette_k.png", grafico_silhouette_k, width = 8, height = 5)

message("Gráficos de seleção de k salvos em outputs/figures/cluster_elbow.png e cluster_silhouette_k.png")

# -----------------------------------------------------------------------
# IMPORTANTE — decisão manual:
# Escolha K_CLUSTERS depois de olhar os dois gráficos acima. Deixamos
# 4 como ponto de partida (equilíbrio comum entre parcimônia e
# capacidade de diferenciar perfis de desenvolvimento), mas ajuste
# conforme o que os gráficos mostrarem.
# -----------------------------------------------------------------------
K_CLUSTERS <- 4

# -----------------------------------------------------------------------
# D. K-Means vs. Hierárquica — comparação
# -----------------------------------------------------------------------
# PERGUNTA: os dois métodos de clusterização concordam sobre os grupos,
# ou a escolha do método muda a resposta?
# POR QUE COMPARAR: K-Means assume clusters de formato aproximadamente
# esférico e é sensível à inicialização aleatória (mitigado aqui com
# nstart=25); a clusterização hierárquica (Ward.D2) não faz essa
# suposição e é determinística. Se os dois concordam, a estrutura de
# cluster é mais confiável; se divergem muito, a estrutura é menos
# robusta e a interpretação deve ser mais cautelosa.
# COMO INTERPRETAR: a tabela de contingência entre os dois métodos
# mostra quantos países cada par de clusters (K-Means x Hierárquico)
# tem em comum — números concentrados na diagonal indicam boa
# concordância.
# LIMITAÇÃO: com K=4 e N=159, "concordância perfeita" é improvável
# mesmo com uma estrutura real — pequenas divergências nas bordas
# entre grupos são esperadas e não invalidam a análise.

set.seed(42)  # reprodutibilidade do K-Means (inicialização aleatória)
kmeans_resultado <- kmeans(pca_scores_retidos, centers = K_CLUSTERS, nstart = 25)

distancias <- dist(pca_scores_retidos, method = "euclidean")
hier_resultado <- hclust(distancias, method = "ward.D2")
hier_grupos <- cutree(hier_resultado, k = K_CLUSTERS)

message(sprintf("\n=== Comparação K-Means vs. Hierárquica (K=%d) ===", K_CLUSTERS))
print(table(KMeans = kmeans_resultado$cluster, Hierarquica = hier_grupos))

silhouette_kmeans <- silhouette(kmeans_resultado$cluster, distancias)
silhouette_hier <- silhouette(hier_grupos, distancias)

message(sprintf(
  "\nSilhouette médio — K-Means: %.3f | Hierárquica: %.3f",
  mean(silhouette_kmeans[, 3]), mean(silhouette_hier[, 3])
))

# Dendrograma (clusterização hierárquica) para inspeção visual.
png("outputs/figures/cluster_dendrograma.png", width = 1400, height = 700, res = 130)
plot(hier_resultado, labels = dados_perfil$pais_iso3, cex = 0.5,
     main = "Dendrograma — clusterização hierárquica (Ward.D2)")
rect.hclust(hier_resultado, k = K_CLUSTERS, border = "#E41A1C")
dev.off()

# Usamos o resultado do K-Means como cluster "oficial" daqui em diante
# (nome mais simples para o dashboard), guardando a hierárquica como
# checagem de robustez já reportada acima.
dados_perfil <- dados_perfil |>
  mutate(cluster = factor(kmeans_resultado$cluster))

grafico_clusters <- fviz_cluster(kmeans_resultado, data = pca_scores_retidos,
                                  geom = "point", pointsize = 2,
                                  ellipse.type = "convex", repel = TRUE,
                                  main = "Clusters de países (K-Means, espaço PC1 x PC2)")
ggsave("outputs/figures/cluster_visualizacao.png", grafico_clusters, width = 9, height = 7)

# -----------------------------------------------------------------------
# E. Perfil de cada cluster
# -----------------------------------------------------------------------
# PERGUNTA: o que caracteriza cada grupo de países em termos das
# variáveis ORIGINAIS (não padronizadas) — quais têm melhor/pior
# expectativa de vida, maior/menor PIB, etc.?
# POR QUE VOLTAR ÀS VARIÁVEIS ORIGINAIS: os clusters foram formados no
# espaço padronizado/PCA, que não tem unidade interpretável
# diretamente (um "PC1 = 2" não diz nada por si só). Reportar a MÉDIA
# das variáveis originais por cluster traduz os grupos de volta para
# unidades que fazem sentido (anos de vida, dólares, percentual).
# NOMENCLATURA: evitamos rótulos subjetivos ou estigmatizantes (ex.:
# "países pobres", "países atrasados") — os clusters são identificados
# por número e descritos pelo perfil quantitativo, deixando a
# interpretação qualitativa para o texto, não para o nome do grupo.

perfil_clusters <- dados_nucleo |>
  inner_join(dados_perfil |> select(pais_iso3, cluster), by = "pais_iso3") |>
  group_by(cluster) |>
  summarise(
    n_paises = n(),
    expectativa_vida_media = mean(expectativa_vida),
    mortalidade_infantil_media = mean(mortalidade_infantil),
    obesidade_media = mean(prevalencia_obesidade),
    pib_per_capita_medio = mean(pib_per_capita_ppp),
    gasto_saude_medio = mean(gasto_saude_pc_ppp),
    tabagismo_medio = mean(prevalencia_tabagismo),
    .groups = "drop"
  ) |>
  arrange(desc(expectativa_vida_media))

message("\nPerfil médio de cada cluster:")
print(perfil_clusters)
write_csv(perfil_clusters, "outputs/tables/perfil_clusters.csv")

# -----------------------------------------------------------------------
# E2. Rótulos descritivos dos clusters
# -----------------------------------------------------------------------
# Os rótulos abaixo descrevem o perfil QUANTITATIVO que mais diferencia
# cada cluster dos demais (olhando a tabela acima) — não usamos termos
# de valor como "rico/pobre" ou "desenvolvido/atrasado" (ver nota na
# Seção E). A base de comparação é sempre a característica que mais se
# destaca NAQUELE cluster frente aos outros três, não um julgamento
# geral sobre o país.
#
# IMPORTANTE: os números dos clusters (1, 2, 3, 4) vêm da atribuição
# arbitrária do K-Means — não têm ordem natural, e mudam entre execuções
# mesmo com o mesmo agrupamento (já aconteceu neste projeto: um rótulo
# atribuído "pelo número" acabou no cluster errado depois de rodar o
# pipeline de novo). Por isso os rótulos NÃO são atribuídos por número:
# são atribuídos pela POSIÇÃO do cluster no ranking de expectativa de
# vida média (perfil_clusters já está ordenado do maior para o menor),
# o que independe da numeração. O ranking foi conferido contra a tabela
# acima na versão original da análise: o grupo de maior expectativa de
# vida é o de "alta longevidade", e assim por diante.

nomes_por_posicao <- c(
  "Alta longevidade e baixa mortalidade infantil",
  "Transição intermediária de desenvolvimento",
  "Mortalidade infantil elevada, baixa prevalência de obesidade",
  "Mortalidade infantil muito elevada, indicadores de renda mais baixos"
)
stopifnot(nrow(perfil_clusters) == length(nomes_por_posicao))

rotulos_cluster <- setNames(nomes_por_posicao, as.character(perfil_clusters$cluster))

# Checagem de sanidade: os dois grupos de menor expectativa de vida devem
# ter obesidade menor que a dos dois primeiros (padrão da transição
# epidemiológica documentado em METODOLOGIA.md, Seção 8). Se não, os
# rótulos descritivos precisam ser revistos manualmente.
if (max(perfil_clusters$obesidade_media[3:4]) >= min(perfil_clusters$obesidade_media[1:2])) {
  warning("Padrão de obesidade diferente do esperado — reconfira os rótulos dos clusters antes de usar.")
}

perfil_clusters <- perfil_clusters |>
  mutate(nome_cluster = rotulos_cluster[as.character(cluster)]) |>
  relocate(nome_cluster, .after = cluster)

message("\nPerfil dos clusters com rótulos descritivos:")
print(perfil_clusters |> select(cluster, nome_cluster, n_paises, expectativa_vida_media, mortalidade_infantil_media))
write_csv(perfil_clusters, "outputs/tables/perfil_clusters.csv")

# Países representativos: os mais próximos do centróide de cada
# cluster no espaço PC1/PC2 (não os "melhores" ou "piores" — os mais
# TÍPICOS daquele grupo).
dados_perfil_dist <- dados_perfil |>
  mutate(pc1 = pca_scores_retidos[, 1], pc2 = pca_scores_retidos[, 2])

paises_representativos <- dados_perfil_dist |>
  group_by(cluster) |>
  mutate(
    centro_pc1 = mean(pc1), centro_pc2 = mean(pc2),
    distancia_centro = sqrt((pc1 - centro_pc1)^2 + (pc2 - centro_pc2)^2)
  ) |>
  slice_min(distancia_centro, n = 3) |>
  select(cluster, pais_nome, regiao, distancia_centro) |>
  arrange(cluster, distancia_centro) |>
  mutate(nome_cluster = rotulos_cluster[as.character(cluster)]) |>
  relocate(nome_cluster, .after = cluster)

message("\nPaíses mais representativos de cada cluster (mais próximos do centro):")
print(paises_representativos, n = Inf)
write_csv(paises_representativos, "outputs/tables/paises_representativos_clusters.csv")

# -----------------------------------------------------------------------
# F. Salvar dados com cluster atribuído (para Fase 8 e dashboard)
# -----------------------------------------------------------------------
dados_com_cluster <- dados_nucleo |>
  inner_join(dados_perfil |> select(pais_iso3, cluster), by = "pais_iso3") |>
  mutate(
    pc1 = pca_scores_retidos[, 1],
    pc2 = pca_scores_retidos[, 2],
    nome_cluster = rotulos_cluster[as.character(cluster)]
  )

write_csv(dados_com_cluster, "data/processed/dados_com_cluster.csv")
message("\nDados com cluster atribuído (e rótulo descritivo) salvos em data/processed/dados_com_cluster.csv")

message("\nPCA e clusterização concluídos. Revise outputs/figures/ (scree, loadings, biplot, elbow, silhouette, dendrograma, clusters) e outputs/tables/perfil_clusters.csv antes de seguirmos para a Fase 8 (esperado vs. observado).")
