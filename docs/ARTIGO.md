# Comparação de técnicas de projeção e de algoritmos de agrupamento na exploração visual de desigualdades de saúde entre países

> **Rascunho** nas 5 seções exigidas pela disciplina, pronto para colar no template IEEE (https://www.ieee.org/conferences_events/conferences/publishing/templates.html). Todos os números abaixo vêm de execuções reais dos scripts `R/05`, `R/08` e `R/09` sobre os dados do projeto (N = 159 países, ano de referência 2015). Faltam: nome(s) do(s) autor(es) e afiliação, resumo/abstract, figuras no formato do template e conferência final das referências.

---

## Resumo (Abstract)

*(escrever por último, 150–250 palavras: pergunta, método, achado principal — nenhuma projeção domina as demais e o número de grupos depende do algoritmo —, e limitação principal.)*

**Palavras-chave:** visualização de dados multivariados; redução de dimensionalidade; PCA; t-SNE; UMAP; agrupamento; desigualdade em saúde.

---

## I. Introdução

Projeções bidimensionais de dados multivariados são uma das ferramentas mais usadas em exploração visual: reduzem muitos atributos a um plano onde o olhar humano identifica agrupamentos e exceções. Mas a impressão visual de "grupos" depende da técnica de projeção, de seus hiperparâmetros e do algoritmo que define os grupos, e raramente essa dependência é medida. Este trabalho compara três técnicas de projeção — PCA, t-SNE e UMAP — e cinco algoritmos de agrupamento sobre um conjunto de dados real: seis indicadores de saúde e desenvolvimento de 159 países, obtidos da WHO e do World Bank.

O trabalho se enquadra no **Segundo Caso** da disciplina (exploração de um conjunto de dados de um domínio por meio de um sistema de visualização construído com bibliotecas existentes — D3.js e Chart.js). Além de comparar as técnicas, o sistema resultante, o **Health Inequality Explorer**, permite ao usuário alternar projeção e algoritmo e destacar um país nas três projeções simultaneamente.

As perguntas orientadoras são:

1. Qual técnica (PCA, t-SNE ou UMAP) preserva melhor a vizinhança local dos países e separa melhor os grupos?
2. Os grupos encontrados dependem do algoritmo de agrupamento escolhido?
3. Quais indicadores mais influenciam a formação dos grupos, e o que acontece ao removê-los ou ampliá-los?
4. Como o domínio de aplicação responde: quais fatores se associam à expectativa de vida e quais países ficam acima ou abaixo do esperado?

A Seção II apresenta a fundamentação teórica; a Seção III descreve o sistema; a Seção IV traz os resultados; a Seção V conclui.

---

## II. Fundamentação Teórica

### A. Visualização de informação e o pipeline de visualização

O propósito da visualização é o *insight* — descobertas, verificação de hipóteses, tomada de decisão — e não as imagens em si [1]. Adotamos o modelo de pipeline de Card, Mackinlay e Shneiderman [2]: dados brutos → tabelas de dados → estruturas visuais → vistas, com interação do usuário podendo atuar em cada etapa. Na interação, seguimos o princípio *overview first, zoom and filter, details on demand* [3].

### B. Técnicas de projeção para dados multivariados

Dentro da taxonomia de técnicas para dados multivariados [4], as projeções geométricas mapeiam um espaço de muitas dimensões em um espaço de poucas dimensões:

- **PCA** [5]: projeção linear que maximiza a variância retida. Determinística; os eixos (componentes) são combinações lineares interpretáveis das variáveis originais.
- **t-SNE** [6]: projeção não linear que preserva vizinhanças locais, minimizando a divergência entre distribuições de similaridade no espaço original e no plano. Depende da perplexity e de inicialização aleatória; os eixos não têm interpretação, e distâncias entre grupos distantes não são confiáveis [7].
- **UMAP** [8]: projeção não linear baseada em grafo de vizinhos e topologia fuzzy; depende de `n_neighbors` e `min_dist` e de inicialização aleatória; os mesmos cuidados de leitura do t-SNE se aplicam.

### C. Avaliação de projeções

Como "parecer bom" é subjetivo, medimos a qualidade da projeção. **Trustworthiness** e **continuity** [9] quantificam a preservação da vizinhança local: a primeira penaliza "falsos vizinhos" (pontos próximos no plano mas distantes no espaço original); a segunda penaliza vizinhos reais separados pela projeção; ambas valem de 0 a 1. Também medimos a **silhueta** [10] dos grupos no plano e a **fração dos 10 vizinhos mais próximos que pertencem ao mesmo grupo**. Usamos k = 10 vizinhos.

### D. Algoritmos de agrupamento e concordância

Cada algoritmo assume uma forma de grupo: K-Means e Ward (hierárquico), grupos compactos; PAM [11] (K-medoides), como o K-Means porém mais robusto a valores extremos; misturas gaussianas (GMM) [12], grupos elípticos com pertencimento probabilístico; HDBSCAN [13], grupos por densidade, sem fixar K e com pontos classificados como ruído. A concordância entre dois agrupamentos é medida pelo **Índice de Rand Ajustado (ARI)** [14] (1 = idênticos; ~0 = acaso). Importante: não existe "gabarito" de grupos nestes dados; o ARI compara métodos entre si, não contra a verdade.

---

## III. Técnica ou Sistema

### A. Dados e pipeline

Os seis indicadores — expectativa de vida, mortalidade infantil, prevalência de obesidade, PIB per capita (PPP), gasto em saúde per capita (PPP) e prevalência de tabagismo — foram coletados por API (WHO GHO e World Bank), padronizados por código ISO3 e reduzidos a um corte transversal de 2015 com 159 países com todos os indicadores disponíveis. Mortalidade infantil, PIB e gasto em saúde entram em log (distribuições assimétricas), e todas as variáveis são padronizadas (z-score). O pipeline em R (scripts `01` a `09`) é reprodutível e termina em arquivos JSON estáticos consumidos pelo painel.

### B. Desenho da comparação

1. Os grupos de referência são definidos **no espaço original de 6 dimensões** (K-Means, K = 4), nunca nas coordenadas de uma projeção — caso contrário o PCA seria favorecido por construção. A mesma coloração é aplicada às três projeções.
2. t-SNE (perplexity 15) e UMAP (`n_neighbors` 15, `min_dist` 0,1) foram executados com semente fixa e, para estimar variabilidade, repetidos com 10 sementes; também varremos perplexity e `n_neighbors` em {5, 15, 30, 45}.
3. Cinco algoritmos de agrupamento (K-Means, Ward, PAM, GMM, HDBSCAN) foram comparados por ARI e silhueta no espaço original.
4. A influência das variáveis foi avaliada removendo uma por vez e, separadamente, adicionando dois indicadores secundários (escolaridade esperada e médicos por 10 mil habitantes) na subamostra de 74 países que os possuem.

### C. Sistema interativo

O painel (HTML/CSS/JavaScript) tem uma seção "Perfis de saúde" com: (i) projeção PCA e cartões de perfil de cada grupo; (ii) uma **matriz país × indicador** (técnica orientada a pixel [4]) com valores padronizados, ordenada por grupo; (iii) o **comparador de projeções**, com visualização lado a lado ou individual de PCA, t-SNE e UMAP, seletor do algoritmo de agrupamento que colore os pontos, destaque de um país nas três projeções, e a tabela de métricas de qualidade. A tabela de métricas e a nota abaixo dela lembram o leitor de que os valores dependem dos hiperparâmetros. Outras seções (mapa coroplético, comparador de países, regressão e esperado vs. observado) servem ao estudo de caso do domínio (Seção IV-E).

---

## IV. Resultados

### A. Qualidade das projeções

Com os parâmetros-padrão (semente 42) e rótulos do K-Means nas 6 variáveis:

| Técnica | Trustworthiness | Continuity | Vizinhos do mesmo grupo | Silhueta 2D |
|---|---|---|---|---|
| Espaço original (6D) | 1,000 | 1,000 | 0,903 | 0,332 |
| PCA | 0,942 | 0,977 | 0,927 | 0,444 |
| t-SNE | 0,966 | 0,962 | 0,936 | 0,485 |
| UMAP | 0,961 | 0,971 | 0,952 | 0,495 |

Repetindo t-SNE e UMAP com 10 sementes, as médias (desvio-padrão) foram: trustworthiness 0,977 (0,002) e 0,964 (0,005); continuity 0,966 (0,003) e 0,970 (0,002); vizinhos do mesmo grupo 0,936 (0,006) e 0,938 (0,005); silhueta 2D 0,487 (0,017) e 0,495 (0,015). Portanto:

- **Nenhuma técnica domina.** O PCA tem a maior continuity (0,977) e a menor trustworthiness (0,942); o t-SNE tem a maior trustworthiness média; UMAP e t-SNE têm continuity semelhante.
- **A vantagem do UMAP em "vizinhos do mesmo grupo" vista com uma semente (0,952) não se sustenta entre sementes** (0,938 contra 0,936): é variação de inicialização, não diferença entre técnicas. Isso ilustra por que não se deve concluir a partir de uma única execução.
- **A silhueta 2D (0,44 a 0,50) supera a do espaço original (0,33)**: as projeções, sobretudo não lineares, exageram a separação visual entre grupos que no espaço original se tocam. A fração de vizinhos do mesmo grupo no espaço original é de apenas 0,903.

**Sensibilidade a hiperparâmetros.** Reagrupar o plano (K-Means, K = 4) e comparar com os grupos de 6D mostra concordância (ARI) muito variável: t-SNE de 0,52 (perplexity 5) a 0,91 (perplexity 30); UMAP de 0,55 (`n_neighbors` 15) a 0,91 (`n_neighbors` 30). Ou seja, a "estrutura de grupos" visível num único gráfico t-SNE/UMAP pode mudar bastante com a escolha do parâmetro, enquanto o PCA, sem parâmetros, concorda 0,96 com os grupos originais.

### B. Dependência do algoritmo de agrupamento

| Algoritmo | Nº de grupos | Ruído | Silhueta 6D | ARI vs. K-Means |
|---|---|---|---|---|
| K-Means | 4 | 0 | 0,332 | 1,00 |
| Ward | 4 | 0 | 0,318 | 0,72 |
| PAM | 4 | 0 | 0,294 | 0,53 |
| GMM | 4 | 0 | 0,220 | 0,33 |
| HDBSCAN | 3 | 46 países | 0,373* | 0,37 |

\* sem os pontos de ruído. O critério BIC escolheria 5 grupos para o GMM, e o HDBSCAN deixa 29% dos países sem grupo. A concordância entre algoritmos é moderada a baixa: **o "número de grupos" não é uma propriedade robusta dos dados, mas do método**. Isso é coerente com um contínuo de desenvolvimento, em que as fronteiras entre grupos vizinhos são arbitrárias. O K-Means calculado em PC1/PC2 (usado em versão anterior do trabalho) concorda 0,96 com o K-Means nas 6 variáveis, o que indica que a redução a dois componentes preserva essa partição específica.

### C. Influência das variáveis

Removendo uma variável por vez (K-Means, K = 4; ARI contra o agrupamento completo): tabagismo 0,60; gasto em saúde 0,71; PIB 0,79; obesidade 0,90; expectativa de vida 0,93; mortalidade infantil 0,96. O **tabagismo** é a variável que mais altera os grupos, e mortalidade infantil é praticamente redundante com expectativa de vida. Tirar obesidade ou tabagismo *aumenta* a silhueta (de 0,33 para 0,38): essas duas variáveis reduzem a coesão dos grupos. **Ampliando** com escolaridade e médicos na subamostra de 74 países, o agrupamento muda (ARI 0,70) e a silhueta cai (0,376 para 0,324): os indicadores adicionais não melhoram a separação, além de reduzir a amostra pela metade.

### D. Robustez a outro ano

Repetindo a análise para 2010 (158 países): a PCA retém variância semelhante (PC1 66,0% e PC2 16,0%, contra 65,9% e 15,5% em 2015) e a silhueta do K-Means em PC1/PC2 é parecida (0,443 contra 0,453), de modo que a estrutura geral se mantém entre os dois anos.

### E. Estudo de caso do domínio: o que se associa à saúde

Um modelo de regressão múltipla da expectativa de vida (log PIB, obesidade, tabagismo, log população, log gasto em saúde; erros-padrão robustos HC3) explica R² ajustado = 0,728 em 2015 (0,683 em 2010). O log do PIB é significativo nos dois anos (p = 0,005 em 2015; p = 0,019 em 2010). O gasto em saúde é apenas marginal em 2015 (p = 0,069; em 2010, p = 0,042), com forte colinearidade com o PIB (VIF ≈ 10). O tabagismo tem associação *positiva* e significativa nos dois anos, interpretada como confundimento histórico (países desenvolvidos tiveram tabagismo alto no passado), não como efeito causal. Os resíduos studentizados do modelo classificam 20 países como abaixo, 120 dentro e 19 acima do esperado; os cinco mais abaixo (Eswatini, Lesoto, Botsuana, África do Sul e Zimbábue) coincidem com a região mais atingida pela epidemia de HIV/AIDS, fator ausente do modelo. Todas essas associações são observacionais.

---

## V. Conclusões

Comparamos PCA, t-SNE e UMAP sobre seis indicadores de saúde de 159 países, com grupos definidos no espaço original, e obtivemos quatro conclusões. (1) Nenhuma projeção é superior em todas as métricas: PCA preserva melhor os vizinhos reais, t-SNE evita falsos vizinhos, e as diferenças entre t-SNE e UMAP em separação de grupos se confundem com a variação entre sementes. (2) Projeções não lineares exageram a separação entre grupos (silhueta 2D maior que a do espaço original) e são sensíveis a hiperparâmetros, o que recomenda reportar uma varredura em vez de um único gráfico. (3) O número de grupos depende do algoritmo (3 a 5 grupos conforme o método, com concordância moderada a baixa), sugerindo que os países formam um contínuo, com fronteiras entre perfis convencionais. (4) O tabagismo é a variável que mais molda os grupos; adicionar indicadores com menor cobertura não melhora a separação.

**Limitações.** Há um único conjunto de dados, de 159 países e 6 variáveis, em corte transversal; o ARI e a silhueta comparam métodos entre si sem gabarito de grupos; as métricas de t-SNE e UMAP dependem de hiperparâmetros e sementes (por isso reportamos médias e varredura); a regressão é observacional e não permite inferência causal; o K = 4 foi herdado de uma análise anterior por interpretabilidade, não por ser ótimo.

**Trabalhos futuros.** Repetir a comparação em conjuntos com agrupamento conhecido (para ter um gabarito), incluir outras técnicas (por exemplo, coordenadas paralelas e PaCMAP), avaliar estabilidade dos grupos por reamostragem (*bootstrap*) e estudar com usuários se as diferenças de métricas afetam a interpretação visual.

---

## Referências

[1] B. Shneiderman, "The eyes have it: a task by data type taxonomy for information visualizations," *Proc. IEEE Symp. Visual Languages*, 1996, pp. 336–343.

[2] S. K. Card, J. D. Mackinlay, B. Shneiderman, *Readings in Information Visualization: Using Vision to Think*. Morgan Kaufmann, 1999.

[3] B. Shneiderman, "Dynamic queries for visual information seeking," *IEEE Software*, vol. 11, no. 6, pp. 70–77, 1994.

[4] M. Ward, G. Grinstein, D. Keim, *Interactive Data Visualization: Foundations, Techniques, and Applications*, 2nd ed. CRC Press, 2015.

[5] I. T. Jolliffe, *Principal Component Analysis*, 2nd ed. Springer, 2002.

[6] L. van der Maaten, G. Hinton, "Visualizing data using t-SNE," *J. Machine Learning Research*, vol. 9, pp. 2579–2605, 2008.

[7] M. Wattenberg, F. Viégas, I. Johnson, "How to use t-SNE effectively," *Distill*, 2016.

[8] L. McInnes, J. Healy, J. Melville, "UMAP: Uniform Manifold Approximation and Projection for dimension reduction," arXiv:1802.03426, 2018.

[9] J. Venna, S. Kaski, "Neighborhood preservation in nonlinear projection methods: an experimental study," *Proc. ICANN*, 2001, pp. 485–491.

[10] P. J. Rousseeuw, "Silhouettes: a graphical aid to the interpretation and validation of cluster analysis," *J. Computational and Applied Mathematics*, vol. 20, pp. 53–65, 1987.

[11] L. Kaufman, P. J. Rousseeuw, *Finding Groups in Data: An Introduction to Cluster Analysis*. Wiley, 1990.

[12] L. Scrucca et al., "mclust 5: clustering, classification and density estimation using Gaussian finite mixture models," *The R Journal*, vol. 8, no. 1, pp. 289–317, 2016.

[13] R. J. G. B. Campello, D. Moulavi, J. Sander, "Density-based clustering based on hierarchical density estimates," *Proc. PAKDD*, 2013, pp. 160–172.

[14] L. Hubert, P. Arabie, "Comparing partitions," *J. Classification*, vol. 2, pp. 193–218, 1985.

[15] World Health Organization, *Global Health Observatory data repository*. https://www.who.int/data/gho

[16] World Bank, *World Development Indicators*. https://data.worldbank.org/

*(Checklist: confirmar cada referência no formato exigido pelo template; inserir figuras `outputs/figures/projecoes_comparacao.png` e `projecoes_sensibilidade.png` e uma captura do comparador do painel; preencher Resumo/Abstract e autoria.)*
