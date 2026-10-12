# =============================================================================
# 09_projecoes_clusterizacao.R
# Health Inequality Explorer — Comparação de projeções (PCA, t-SNE, UMAP) e
# de algoritmos de clusterização
#
# PERGUNTA CENTRAL: ao reduzir os 6 indicadores de perfil de cada país para 2
# dimensões, qual técnica de projeção preserva melhor a estrutura de grupos
# dos dados — e essa estrutura de grupos depende do algoritmo de clusterização
# escolhido?
#
# DESENHO (decisões que evitam conclusões enganosas):
#   1. Os grupos são definidos no ESPAÇO ORIGINAL padronizado (6 dimensões),
#      NÃO nas coordenadas de uma projeção. Na Fase 7 o K-Means rodou sobre
#      PC1/PC2; usar esses rótulos para "avaliar" o PCA seria circular (o PCA
#      sairia favorecido por construção). Aqui, os rótulos vêm de fora de
#      qualquer projeção, e cada projeção é colorida pelos MESMOS rótulos.
#      Os clusters da Fase 7 são mantidos como referência de comparação (ARI).
#   2. Qualidade da projeção é medida por métricas de preservação de
#      vizinhança (trustworthiness e continuity) e de separação dos grupos
#      (silhueta em 2D, consistência dos k vizinhos), não pela "beleza" visual.
#   3. t-SNE e UMAP têm hiperparâmetros (perplexity, n_neighbors) e
#      componente aleatório: rodamos uma grade de parâmetros e várias
#      sementes e reportamos a variação, em vez de mostrar uma única figura
#      favorável.
#
# LIMITAÇÕES QUE DEVEM IR PARA O ARTIGO:
#   - Eixos de t-SNE/UMAP não têm interpretação (diferente de PC1/PC2), e
#     distâncias entre clusters distantes na projeção não são confiáveis.
#     Só vizinhança local é interpretável.
#   - Com N = 159 países, t-SNE/UMAP trabalham com poucos pontos; resultados
#     são mais sensíveis a parâmetros do que em bases grandes.
#   - Não há "verdade" de grupos: ARI compara algoritmos entre si, não contra
#     um gabarito.
#
# SAÍDAS:
#   outputs/tables/projecoes_metricas.csv
#   outputs/tables/projecoes_sensibilidade_parametros.csv
#   outputs/tables/projecoes_estabilidade_sementes.csv
#   outputs/tables/clusterizacao_algoritmos_resumo.csv
#   outputs/tables/clusterizacao_algoritmos_ari.csv
#   outputs/tables/clusterizacao_remocao_variaveis.csv
#   outputs/tables/clusterizacao_ampliacao_variaveis.csv
#   outputs/figures/projecoes_comparacao.png
#   outputs/figures/projecoes_sensibilidade.png
#   data/processed/projecoes.csv
#   dashboard/data/projecoes.json
#
# Pacotes novos: install.packages(c("Rtsne", "uwot", "mclust", "dbscan"))
# =============================================================================

source("R/funcoes.R")
library(ggplot2)
library(ggrepel)
library(Rtsne)
library(uwot)
library(mclust)
library(dbscan)
library(cluster)
library(jsonlite)

SEED <- 42
K <- 4          # mesmo K da Fase 7 (decisão de julgamento já documentada)
K_VIZINHOS <- 10

VARS_PERFIL <- c("expectativa_vida", "mortalidade_infantil", "prevalencia_obesidade",
                  "pib_per_capita_ppp", "gasto_saude_pc_ppp", "prevalencia_tabagismo")
VARS_LOG <- c("mortalidade_infantil", "pib_per_capita_ppp", "gasto_saude_pc_ppp")

dir.create("outputs/tables", showWarnings = FALSE, recursive = TRUE)
dir.create("outputs/figures", showWarnings = FALSE, recursive = TRUE)
dir.create("dashboard/data", showWarnings = FALSE, recursive = TRUE)

dados <- read_csv("data/processed/dados_com_cluster.csv", show_col_types = FALSE)
message(sprintf("Países: %d", nrow(dados)))

# -----------------------------------------------------------------------
# Funções auxiliares
# -----------------------------------------------------------------------

# Mesmas transformações da Fase 7 (log nas variáveis assimétricas) + z-score.
preparar_matriz <- function(df, vars) {
  m <- df |>
    mutate(across(any_of(VARS_LOG), log),
           across(any_of("medicos_per_10k"), log1p)) |>
    select(all_of(vars)) |>
    scale() |>
    as.data.frame() |>
    as.matrix()
  m
}

# Ranks de vizinhança por linha (0 = o próprio ponto, 1 = vizinho mais próximo...)
matriz_ranks <- function(D) {
  t(apply(D, 1, function(d) rank(d, ties.method = "first") - 1))
}

# Trustworthiness: vizinhos "intrusos" na projeção (não eram vizinhos no
# espaço original). Continuity: vizinhos originais "expulsos" da projeção.
# Ambas em [0, 1]; 1 = vizinhança local perfeitamente preservada.
trust_cont <- function(X_orig, X_emb, k = K_VIZINHOS) {
  n <- nrow(X_orig)
  Ro <- matriz_ranks(as.matrix(dist(X_orig)))
  Re <- matriz_ranks(as.matrix(dist(X_emb)))
  norma <- 2 / (n * k * (2 * n - 3 * k - 1))
  soma_t <- 0
  soma_c <- 0
  for (i in seq_len(n)) {
    viz_o <- which(Ro[i, ] >= 1 & Ro[i, ] <= k)
    viz_e <- which(Re[i, ] >= 1 & Re[i, ] <= k)
    intrusos <- setdiff(viz_e, viz_o)
    expulsos <- setdiff(viz_o, viz_e)
    soma_t <- soma_t + sum(Ro[i, intrusos] - k)
    soma_c <- soma_c + sum(Re[i, expulsos] - k)
  }
  c(trust = 1 - norma * soma_t, cont = 1 - norma * soma_c)
}

# Métricas de uma projeção, dado um vetor de rótulos de grupo.
avaliar_projecao <- function(X, emb, rotulos, k = K_VIZINHOS) {
  tc <- trust_cont(X, emb, k)
  Re <- matriz_ranks(as.matrix(dist(emb)))
  consistencia <- mean(vapply(seq_len(nrow(emb)), function(i) {
    viz <- which(Re[i, ] >= 1 & Re[i, ] <= k)
    mean(rotulos[viz] == rotulos[i])
  }, numeric(1)))
  silhueta <- mean(silhouette(as.integer(factor(rotulos)), dist(emb))[, 3])
  set.seed(SEED)
  km_2d <- kmeans(emb, centers = K, nstart = 25)$cluster
  tibble(
    trustworthiness = tc[["trust"]],
    continuity = tc[["cont"]],
    consistencia_vizinhos = consistencia,
    silhueta_2d = silhueta,
    ari_cluster_2d_vs_6d = adjustedRandIndex(km_2d, rotulos)
  )
}

proj_pca <- function(X) prcomp(X, center = FALSE, scale. = FALSE)$x[, 1:2]

proj_tsne <- function(X, perplexity = 15, seed = SEED) {
  set.seed(seed)
  Rtsne(X, dims = 2, perplexity = perplexity, theta = 0, pca = FALSE,
        check_duplicates = FALSE, max_iter = 1000)$Y
}

proj_umap <- function(X, n_neighbors = 15, min_dist = 0.1, seed = SEED) {
  set.seed(seed)
  umap(X, n_neighbors = n_neighbors, min_dist = min_dist, n_components = 2,
       metric = "euclidean")
}

# Alinha os números dos clusters de um agrupamento com os da referência
# (força bruta sobre as K! permutações — K=4 são só 24). Serve apenas para
# as cores coincidirem entre figuras; não altera nenhuma métrica.
alinhar_rotulos <- function(novo, ref) {
  tab <- table(factor(novo), factor(ref))
  k <- nrow(tab)
  if (ncol(tab) != k) return(novo)
  perms <- as.matrix(expand.grid(rep(list(seq_len(k)), k)))
  perms <- perms[apply(perms, 1, function(p) length(unique(p)) == k), , drop = FALSE]
  scores <- apply(perms, 1, function(p) sum(tab[cbind(seq_len(k), p)]))
  p <- perms[which.max(scores), ]
  as.integer(colnames(tab))[p][as.integer(factor(novo))]
}

# -----------------------------------------------------------------------
# 1. Clusterização no espaço original (6D) com 5 algoritmos
# -----------------------------------------------------------------------
# POR QUE VÁRIOS ALGORITMOS: cada um assume uma "forma" de grupo diferente —
# K-Means e Ward: grupos compactos/esféricos; PAM (K-medoids): como K-Means,
# porém mais robusto a outliers; GMM (misturas gaussianas): grupos elípticos
# com pertencimento probabilístico; HDBSCAN: baseado em densidade, não exige
# K e pode marcar pontos como ruído. Se todos concordam, a estrutura é
# robusta; se divergem, o "número de grupos" depende do método — resultado
# em si relevante.

X <- preparar_matriz(dados, VARS_PERFIL)
rownames(X) <- dados$pais_iso3
ref <- dados$cluster   # clusters da Fase 7 (K-Means sobre PC1/PC2)

set.seed(SEED)
lab_km <- kmeans(X, centers = K, nstart = 50)$cluster
lab_km <- alinhar_rotulos(lab_km, ref)

lab_ward <- alinhar_rotulos(cutree(hclust(dist(X), method = "ward.D2"), K), ref)

set.seed(SEED)
lab_pam <- alinhar_rotulos(pam(X, K)$clustering, ref)

gmm <- Mclust(X, G = K, verbose = FALSE)
lab_gmm <- alinhar_rotulos(gmm$classification, ref)

gmm_bic <- Mclust(X, G = 1:8, verbose = FALSE)
message(sprintf("GMM: G escolhido por BIC (1 a 8) = %d (modelo %s)",
                 gmm_bic$G, gmm_bic$modelName))

hdb <- hdbscan(X, minPts = 5)
lab_hdb <- hdb$cluster   # 0 = ruído
message(sprintf("HDBSCAN: %d clusters, %d países marcados como ruído",
                 max(lab_hdb), sum(lab_hdb == 0)))

algoritmos <- list(
  "K-Means (6D)" = lab_km,
  "Ward (6D)" = lab_ward,
  "PAM (6D)" = lab_pam,
  "GMM (6D)" = lab_gmm,
  "HDBSCAN (6D)" = lab_hdb,
  "K-Means em PC1/PC2 (Fase 7)" = ref
)

resumo_algoritmos <- purrr::imap_dfr(algoritmos, function(lab, nome) {
  valido <- lab != 0
  sil <- if (length(unique(lab[valido])) > 1)
    mean(silhouette(as.integer(factor(lab[valido])), dist(X[valido, ]))[, 3]) else NA_real_
  tibble(algoritmo = nome,
         n_clusters = length(unique(lab[valido])),
         n_ruido = sum(!valido),
         silhueta_6d = sil)
})
write_csv(resumo_algoritmos, "outputs/tables/clusterizacao_algoritmos_resumo.csv")
message("\nResumo dos algoritmos:")
print(resumo_algoritmos)

nomes <- names(algoritmos)
ari_mat <- outer(nomes, nomes, Vectorize(function(a, b)
  adjustedRandIndex(algoritmos[[a]], algoritmos[[b]])))
dimnames(ari_mat) <- list(nomes, nomes)
write_csv(as_tibble(round(ari_mat, 3), rownames = "algoritmo"),
          "outputs/tables/clusterizacao_algoritmos_ari.csv")
message("\nConcordância entre algoritmos (ARI; 1 = idênticos, ~0 = acaso):")
print(round(ari_mat, 2))

# Rótulos principais usados para colorir todas as projeções
rotulos <- lab_km

# -----------------------------------------------------------------------
# 2. Projeções e métricas de qualidade (parâmetros padrão)
# -----------------------------------------------------------------------

PERPLEXITY_PADRAO <- 15
NEIGHBORS_PADRAO <- 15

proj <- list(
  "PCA" = proj_pca(X),
  "t-SNE" = proj_tsne(X, PERPLEXITY_PADRAO),
  "UMAP" = proj_umap(X, NEIGHBORS_PADRAO)
)

metricas <- bind_rows(
  tibble(metodo = "Espaço original (6D)") |> bind_cols(avaliar_projecao(X, X, rotulos)),
  purrr::imap_dfr(proj, function(emb, nome) {
    tibble(metodo = nome) |> bind_cols(avaliar_projecao(X, emb, rotulos))
  })
)
write_csv(metricas, "outputs/tables/projecoes_metricas.csv")
message("\nMétricas de qualidade das projeções (rótulos: K-Means 6D):")
print(metricas, width = Inf)

# -----------------------------------------------------------------------
# 3. Sensibilidade a hiperparâmetros e estabilidade entre sementes
# -----------------------------------------------------------------------

grade_perplexity <- c(5, 15, 30, 45)   # precisa ser < (N-1)/3 ≈ 52
grade_neighbors <- c(5, 15, 30, 45)

emb_grade <- list()
sens <- list()
for (p in grade_perplexity) {
  e <- proj_tsne(X, p)
  emb_grade[[sprintf("t-SNE perplexity=%d", p)]] <- e
  sens[[length(sens) + 1]] <- tibble(metodo = "t-SNE", parametro = sprintf("perplexity=%d", p)) |>
    bind_cols(avaliar_projecao(X, e, rotulos))
}
for (nn in grade_neighbors) {
  e <- proj_umap(X, nn)
  emb_grade[[sprintf("UMAP n_neighbors=%d", nn)]] <- e
  sens[[length(sens) + 1]] <- tibble(metodo = "UMAP", parametro = sprintf("n_neighbors=%d", nn)) |>
    bind_cols(avaliar_projecao(X, e, rotulos))
}
sens <- bind_rows(sens)
write_csv(sens, "outputs/tables/projecoes_sensibilidade_parametros.csv")
message("\nSensibilidade a hiperparâmetros:")
print(sens, width = Inf)

SEMENTES <- 1:10
estab <- bind_rows(
  purrr::map_dfr(SEMENTES, function(s)
    tibble(metodo = "t-SNE", semente = s) |>
      bind_cols(avaliar_projecao(X, proj_tsne(X, PERPLEXITY_PADRAO, seed = s), rotulos))),
  purrr::map_dfr(SEMENTES, function(s)
    tibble(metodo = "UMAP", semente = s) |>
      bind_cols(avaliar_projecao(X, proj_umap(X, NEIGHBORS_PADRAO, seed = s), rotulos)))
)
estab_resumo <- estab |>
  group_by(metodo) |>
  summarise(across(c(trustworthiness, continuity, consistencia_vizinhos, silhueta_2d),
                   list(media = mean, dp = sd), .names = "{.col}_{.fn}"),
            .groups = "drop")
write_csv(estab_resumo, "outputs/tables/projecoes_estabilidade_sementes.csv")
message("\nEstabilidade entre 10 sementes (PCA é determinístico):")
print(estab_resumo, width = Inf)

# -----------------------------------------------------------------------
# 4. Ampliar / remover características
# -----------------------------------------------------------------------
# (a) Remoção, uma variável por vez: se o agrupamento quase não muda ao
#     retirar uma variável (ARI alto contra o agrupamento base), ela é
#     redundante para a estrutura de grupos; se muda muito, é informativa.
#     Não removemos nada automaticamente — é um diagnóstico.
# (b) Ampliação: incluir os indicadores secundários (escolaridade e médicos),
#     o que reduz a amostra (só países com ambos). A comparação é feita no
#     MESMO subconjunto de países, com e sem as variáveis novas, para não
#     confundir efeito de variável com efeito de amostra.

sil_media <- function(lab, M) mean(silhouette(lab, dist(M))[, 3])

remocao <- bind_rows(
  tibble(variavel_removida = "(nenhuma — base)", ari_vs_base = 1, silhueta_6d = sil_media(lab_km, X)),
  purrr::map_dfr(VARS_PERFIL, function(v) {
    Xv <- preparar_matriz(dados, setdiff(VARS_PERFIL, v))
    set.seed(SEED)
    lab <- kmeans(Xv, centers = K, nstart = 50)$cluster
    tibble(variavel_removida = v,
           ari_vs_base = adjustedRandIndex(lab, lab_km),
           silhueta_6d = sil_media(lab, Xv))
  })
)
write_csv(remocao, "outputs/tables/clusterizacao_remocao_variaveis.csv")
message("\nRemoção de uma variável por vez (K-Means, K=4):")
print(remocao)

VARS_EXTRA <- c("escolaridade_esperada", "medicos_per_10k")
if (all(VARS_EXTRA %in% names(dados))) {
  sub <- dados |> filter(if_all(all_of(VARS_EXTRA), ~ !is.na(.x)))
  X6 <- preparar_matriz(sub, VARS_PERFIL)
  X8 <- preparar_matriz(sub, c(VARS_PERFIL, VARS_EXTRA))
  set.seed(SEED); l6 <- kmeans(X6, centers = K, nstart = 50)$cluster
  set.seed(SEED); l8 <- kmeans(X8, centers = K, nstart = 50)$cluster
  ampliacao <- tibble(
    n_paises = nrow(sub),
    ari_6_vs_8_variaveis = adjustedRandIndex(l6, l8),
    silhueta_6_variaveis = sil_media(l6, X6),
    silhueta_8_variaveis = sil_media(l8, X8)
  )
  write_csv(ampliacao, "outputs/tables/clusterizacao_ampliacao_variaveis.csv")
  message("\nAmpliação com indicadores secundários (mesmo subconjunto de países):")
  print(ampliacao, width = Inf)
} else {
  message("\n[AVISO] Indicadores secundários não encontrados em dados_com_cluster.csv — ampliação pulada.")
}

# -----------------------------------------------------------------------
# 5. Figuras
# -----------------------------------------------------------------------
# Cores ordenadas pela expectativa de vida média de cada cluster (do melhor
# ao pior), independente da numeração arbitrária do K-Means.

ordem <- dados |>
  mutate(cl = rotulos) |>
  group_by(cl) |>
  summarise(m = mean(expectativa_vida), .groups = "drop") |>
  arrange(desc(m)) |>
  pull(cl)
cores <- setNames(c("#1F6F5C", "#8A9B5C", "#C98A2B", "#B5451F")[seq_along(ordem)],
                  as.character(ordem))

emb_df <- purrr::imap_dfr(proj, function(emb, nome) {
  tibble(metodo = nome, pais_iso3 = dados$pais_iso3, pais_nome = dados$pais_nome,
         dim1 = emb[, 1], dim2 = emb[, 2], cluster = factor(rotulos))
})
emb_df$metodo <- factor(emb_df$metodo, levels = names(proj))

destaque <- c("Brazil", "Japan", "Germany", "India", "Nigeria", "United States", "China")

fig_comparacao <- ggplot(emb_df, aes(dim1, dim2, color = cluster)) +
  geom_point(size = 2, alpha = 0.85) +
  geom_text_repel(data = emb_df |> filter(pais_nome %in% destaque),
                  aes(label = pais_nome), size = 3, color = "grey20",
                  max.overlaps = 30, show.legend = FALSE) +
  facet_wrap(~ metodo, scales = "free") +
  scale_color_manual(values = cores, name = "Cluster\n(K-Means 6D)") +
  labs(title = "Mesmos países, mesmos grupos, três projeções",
       subtitle = "Cor = K-Means (K=4) no espaço original de 6 indicadores. Eixos de t-SNE/UMAP não têm interpretação.",
       x = NULL, y = NULL) +
  theme_minimal() +
  theme(axis.text = element_blank(), panel.grid = element_blank(),
        strip.text = element_text(face = "bold"))

ggsave("outputs/figures/projecoes_comparacao.png", fig_comparacao, width = 13, height = 4.8, dpi = 150)

grade_df <- purrr::imap_dfr(emb_grade, function(emb, nome) {
  tibble(config = nome, dim1 = emb[, 1], dim2 = emb[, 2], cluster = factor(rotulos))
})
grade_df$config <- factor(grade_df$config, levels = names(emb_grade))

fig_sens <- ggplot(grade_df, aes(dim1, dim2, color = cluster)) +
  geom_point(size = 1.3, alpha = 0.85) +
  facet_wrap(~ config, scales = "free", ncol = 4) +
  scale_color_manual(values = cores, guide = "none") +
  labs(title = "Sensibilidade de t-SNE e UMAP aos hiperparâmetros", x = NULL, y = NULL) +
  theme_minimal() +
  theme(axis.text = element_blank(), panel.grid = element_blank(),
        strip.text = element_text(size = 8))

ggsave("outputs/figures/projecoes_sensibilidade.png", fig_sens, width = 13, height = 6.5, dpi = 150)

# -----------------------------------------------------------------------
# 6. Exportação (CSV + JSON para o dashboard)
# -----------------------------------------------------------------------

saida <- dados |>
  transmute(pais_iso3, pais_nome, regiao,
            cluster_fase7 = ref,
            cluster_kmeans_6d = lab_km, cluster_ward = lab_ward,
            cluster_pam = lab_pam, cluster_gmm = lab_gmm, cluster_hdbscan = lab_hdb,
            pca_x = proj[["PCA"]][, 1], pca_y = proj[["PCA"]][, 2],
            tsne_x = proj[["t-SNE"]][, 1], tsne_y = proj[["t-SNE"]][, 2],
            umap_x = proj[["UMAP"]][, 1], umap_y = proj[["UMAP"]][, 2])
write_csv(saida, "data/processed/projecoes.csv")

projecoes_json <- list(
  parametros = list(k = K, perplexity = PERPLEXITY_PADRAO, n_neighbors = NEIGHBORS_PADRAO,
                    k_vizinhos_metricas = K_VIZINHOS),
  metricas = lapply(seq_len(nrow(metricas)), function(i) {
    r <- metricas[i, ]
    r[-1] <- round(r[-1], 3)
    as.list(r)
  }),
  paises = lapply(seq_len(nrow(saida)), function(i) {
    r <- saida[i, ]
    list(iso3 = r$pais_iso3, nome = r$pais_nome, regiao = r$regiao,
         cluster_kmeans_6d = r$cluster_kmeans_6d, cluster_fase7 = r$cluster_fase7,
         cluster_ward = r$cluster_ward, cluster_pam = r$cluster_pam,
         cluster_gmm = r$cluster_gmm, cluster_hdbscan = r$cluster_hdbscan,
         pca = round(c(r$pca_x, r$pca_y), 3),
         tsne = round(c(r$tsne_x, r$tsne_y), 3),
         umap = round(c(r$umap_x, r$umap_y), 3))
  })
)
write_json(projecoes_json, "dashboard/data/projecoes.json", pretty = FALSE,
           auto_unbox = TRUE, na = "null")

message("\nConcluído. Figuras em outputs/figures/, tabelas em outputs/tables/, JSON em dashboard/data/projecoes.json")
message("COMO LER: compare trustworthiness/continuity (vizinhança local preservada) e")
message("consistência de vizinhos/silhueta 2D (grupos separados) entre PCA, t-SNE e UMAP;")
message("confira se a conclusão se mantém ao variar parâmetros e sementes antes de citá-la no artigo.")
