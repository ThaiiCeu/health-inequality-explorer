# Health Inequality Explorer — Metodologia e Documentação Consolidada

> Este documento consolida as decisões metodológicas, achados e limitações de todas as fases de análise (coleta → limpeza → exploratória → estatística → PCA/cluster → esperado vs. observado). Serve como base para a seção de Metodologia do dashboard e para o README do repositório.

---

## 1. Pergunta de pesquisa

**Pergunta principal:** Em que medida indicadores socioeconômicos e de acesso ao sistema de saúde explicam as diferenças nos resultados de saúde entre países, e quais países apresentam desempenho em saúde acima ou abaixo do esperado dado seu nível de desenvolvimento?

**Perguntas secundárias:**
1. Quais indicadores socioeconômicos e de acesso à saúde estão mais fortemente associados à expectativa de vida?
2. Existem agrupamentos naturais de países com perfis semelhantes de desenvolvimento e saúde?
3. Controlando pelo nível socioeconômico esperado, quais países superam ou ficam abaixo do resultado de saúde esperado?
4. A relação entre desenvolvimento socioeconômico e mortalidade infantil segue o mesmo padrão da expectativa de vida, ou os fatores associados são distintos?
5. Quanto da variação em saúde entre países pode ser resumida em poucas dimensões latentes (PCA)?

---

## 2. Fontes de dados

| Indicador | Fonte | Código | Observações |
|---|---|---|---|
| Expectativa de vida ao nascer | WHO GHO | `WHOSIS_000001` | — |
| Mortalidade infantil (<5 anos) | WHO GHO | `MDG_0000000007` | Código oficial ODS/MDG, preferido sobre alias `u5mr` por estabilidade |
| Médicos por 10.000 hab. | WHO GHO | `HWF_0001` | Unidade é por 10.000, não por 1.000 |
| Prevalência de obesidade (adultos) | WHO GHO | `NCD_BMI_30A` | Age-standardized — escolhida sobre a versão *crude* para comparabilidade entre países |
| PIB per capita (PPP) | World Bank | `NY.GDP.PCAP.PP.KD` | — |
| Escolaridade esperada (anos) | World Bank | `SE.SCH.LIFE` | Cobertura despenca após ~2018 (ver Seção 3) |
| População total | World Bank | `SP.POP.TOTL` | Usada como controle de escala, não como preditor de desenvolvimento |
| Gasto em saúde per capita (PPP) | World Bank | `SH.XPD.CHEX.PP.CD` | Migrado da WHO para o World Bank (ver nota abaixo) |
| Prevalência de tabagismo (adultos) | World Bank | `SH.PRV.SMOK` | Total, age-standardized |

**Nota sobre gasto em saúde e tabagismo:** as tentativas iniciais de usar códigos nativos da WHO GHO (`GHED_CHE_pc_PPP_SHA2011`, `SDGTOBACCO`) retornaram 0 registros — a base GHED (gasto em saúde) vive em portais regionais da WHO, não no endpoint global `ghoapi.azureedge.net`. Resolvido migrando os dois indicadores para o World Bank, que expõe os mesmos dados (originados da própria WHO) de forma mais estável. Os códigos finais foram confirmados via busca programática na API do World Bank (`wb_buscar_indicador()`), não copiados de documentação externa.

**Nota sobre a API da WHO:** a WHO já anunciou depreciação da API OData atual (`ghoapi.azureedge.net`). O pipeline de coleta busca indicadores por nome em vez de fixar códigos "às cegas", tornando-o mais resiliente a essa migração futura.

---

## 3. Coleta e período

- Janela de coleta: **2000–2022** (todos os anos, para permitir análise de cobertura e evolução temporal antes de fixar um ano de referência).
- Manifesto de coleta salvo em `data/raw/manifesto_coleta.csv` (fonte, código, timestamp de cada indicador).

---

## 4. Limpeza e preparação

- **Chave de junção entre fontes:** código ISO3, não nome do país em texto livre — WHO e World Bank grafam nomes de forma diferente (ex.: "Russian Federation" vs. "Russia"). A lista oficial de países do World Bank (`wb_obter_paises()`, filtrando `region != "Aggregates"`) serve como árbitro de quais entidades são países de fato e como fonte única do nome canônico.
- **Duplicidade por desagregação de sexo (WHO):** vários indicadores vêm desagregados por sexo (masculino/feminino/ambos). Resolvido priorizando a categoria "ambos os sexos" quando existe.
- **Duplicidade por revisão de estimativa (mortalidade infantil):** a WHO mantém múltiplas revisões da mesma estimativa ao longo do tempo. Resolvido mantendo sempre a publicação mais recente (campo `Date`), não a primeira linha encontrada.
- **Valores ausentes:** linhas sem valor numérico são descartadas na extração (não há imputação).

### Núcleo vs. indicadores secundários

Dois indicadores (`medicos_per_10k` e `escolaridade_esperada`) têm cobertura de país-ano muito mais fraca que os outros sete — exigir os 9 simultaneamente reduzia a amostra utilizável para ~74 países mesmo no melhor ano. Decisão: tratá-los como **secundários**, usados apenas em análises específicas (checagem de robustez), enquanto o **núcleo de 7 indicadores** (expectativa de vida, mortalidade infantil, obesidade, PIB per capita, população, gasto em saúde, tabagismo) define a amostra principal.

---

## 5. Ano de referência e amostra final

- **Ano de referência: 2015** — ano com maior cobertura simultânea do núcleo (159 países, empatado com 2020).
- **2020 foi descartado apesar do empate em cobertura** porque a pandemia distorceu anormalmente expectativa de vida e mortalidade em muitos países naquele ano — confirmado visualmente na Fase 5 (queda abrupta em todas as regiões no gráfico de evolução temporal).
- **Amostras finais:**
  - Núcleo (N=159): `data/processed/dados_corte_nucleo.csv` — usada em regressão, PCA e clusterização.
  - Completa (N=74): `data/processed/dados_corte_completo.csv` — usada apenas em checagens de robustez.

---

## 6. Principais achados da análise exploratória (Fase 5)

- **PIB × expectativa de vida:** relação de retornos decrescentes clara em escala log — sustenta a hipótese de que ganhos de renda importam mais nos níveis mais baixos de desenvolvimento.
- **Distribuições assimétricas:** PIB per capita, gasto em saúde e mortalidade infantil são fortemente enviesados à direita — todos entram em log nas análises multivariadas subsequentes.
- **Correlações de atenção:**
  - PIB × gasto em saúde: **0.86** (risco de multicolinearidade, tratado na Fase 6).
  - Mortalidade infantil × expectativa de vida: **-0.80** (quase-tautológico; mortalidade infantil não é usada como preditora de expectativa de vida por esse motivo).
  - Obesidade × mortalidade infantil: **-0.42**, refletindo transição epidemiológica (obesidade mais prevalente em países desenvolvidos, que têm menor mortalidade infantil) — não uma relação protetora direta.
- **Mortalidade infantil × PIB (log-log):** relação mais íngreme/direta que a de expectativa de vida — sustenta a hipótese de que mortalidade infantil é mais sensível a acesso básico à saúde do que a riqueza em si.
- **Dado ausente identificado:** `prevalencia_tabagismo` (World Bank) não tem nenhum registro para 2019 especificamente — gap real da fonte, não erro de pipeline (confirmado checando o CSV bruto diretamente).

---

## 7. Análise estatística — regressão (Fase 6)

**Especificação final (Modelo 2 / Modelo 3):**
```
expectativa_vida ~ log(pib_per_capita_ppp) + prevalencia_obesidade +
                    prevalencia_tabagismo + log(populacao) + log(gasto_saude_pc_ppp)
```
N=159, R²=0.737, R² ajustado=0.728.

### Resultados por hipótese

- **H1 (PIB → expectativa de vida): sustentada com confiança.** `log(PIB)` significativo em todas as especificações, inclusive com erros-padrão robustos a heterocedasticidade (HC3, p=0.0053).
- **H2 (gasto em saúde além do PIB): suporte apenas marginal.** O teste F clássico (comparação Modelo 1 vs. Modelo 2) deu p=0.0197, mas o teste robusto a heterocedasticidade (Wald com HC3) deu **p=0.069** — não significativo a 5%. Boa parte da significância original era artefato da heterocedasticidade detectada nos resíduos.
- **Tabagismo com sinal contraintuitivo:** coeficiente positivo e significativo (mais tabagismo associado a mais expectativa de vida) em todas as especificações — interpretado como confundimento histórico (países desenvolvidos tiveram tabagismo alto décadas atrás e hoje têm boa expectativa de vida por outros motivos), **não como efeito causal real**.

### Diagnósticos e correções aplicadas

- **VIF:** `log(PIB)` e `log(gasto_saude)` com VIF ≈ 10.3–10.5 (limiar de atenção). Resolvido com uma especificação alternativa (gasto em saúde "residualizado" — resíduo da regressão de `log(gasto_saude)` sobre `log(PIB)`), que elimina a colinearidade (VIF cai para ~1.03) sem descartar informação. Resultado idêntico ao Modelo 2 (mesmos valores ajustados), apenas mais limpo para interpretação individual dos coeficientes.
- **Não-normalidade dos resíduos** (Shapiro-Wilk, p<0.001) e **heterocedasticidade** (Breusch-Pagan, p<0.001) detectadas — corrigidas com erros-padrão robustos (HC3) em todos os testes de significância reportados a partir da Fase 6.
- **Sem observações influentes** (distância de Cook, threshold 0.9).
- **Seleção stepwise testada e descartada:** demonstração mostrou que o algoritmo (AIC, both directions) descarta `log(populacao)` e `prevalencia_obesidade` e mantém uma das duas variáveis colineares de forma arbitrária — não resolve a pergunta de pesquisa sobre gasto em saúde, e os p-valores resultantes não são válidos para inferência (problema de inferência seletiva). Não usado na especificação final.
- **Checagem de robustez (N=74, com secundários):** ao incluir escolaridade e médicos per capita, o efeito do PIB praticamente desaparece (coef. ≈ 0, p=0.83) — escolaridade parece capturar boa parte do que o PIB representava. Achado interessante, mas com ressalva: a amostra de 74 países não é aleatória (são os países com melhor infraestrutura estatística).

---

## 8. PCA e clusterização (Fase 7)

**Variáveis usadas:** os 6 indicadores de perfil de desenvolvimento/saúde do núcleo (expectativa de vida, mortalidade infantil [log], obesidade, PIB per capita [log], gasto em saúde [log], tabagismo). `população` foi excluída por ser indicador de escala, não de desenvolvimento.

### PCA

- **PC1 (65.9% da variância):** eixo geral de desenvolvimento — expectativa de vida, PIB e gasto em saúde de um lado, mortalidade infantil do outro.
- **PC2 (15.5% da variância):** quase exclusivamente tabagismo (loading 0.959) — eixo praticamente independente do desenvolvimento geral, confirmando visualmente o achado da regressão (Seção 7).
- Critério de Kaiser sugere reter só 1 componente (autovalor do PC2 = 0.93, ligeiramente abaixo de 1); optou-se por reter 2 componentes pela interpretabilidade clara do PC2 e pela queda visível no scree plot — decisão de julgamento, documentada como tal.

### Clusterização (K-Means, K=4)

Escolhido sobre o k=2 "estatisticamente ótimo" (maior silhouette) por oferecer perfis mais ricos e diferenciados substantivamente. Comparação com clusterização hierárquica (Ward.D2) mostra forte concordância nos extremos (grupos de maior e menor desenvolvimento) e concordância mais fraca no grupo de renda média — sinal de que a fronteira entre desenvolvimento baixo e médio é mais um gradiente contínuo do que uma quebra categórica nítida.

| Cluster | N países | Nome descritivo | Expect. vida | Mort. infantil | Países representativos |
|---|---|---|---|---|---|
| 1 | 56 | Alta longevidade e baixa mortalidade infantil | 79.2 | 5.4 | Portugal, Coreia do Sul, Israel |
| 2 | 52 | Transição intermediária de desenvolvimento | 73.3 | 18.7 | Egito, Argélia, Azerbaijão |
| 3 | 17 | Mortalidade infantil elevada, baixa prevalência de obesidade | 67.7 | 39.4 | Laos, Índia, Nepal |
| 4 | 34 | Mortalidade infantil muito elevada, indicadores de renda mais baixos | 61.7 | 75.1 | Uganda, Tanzânia, Costa do Marfim |

Os números dos clusters são atribuídos por posição na expectativa de vida média (1 = maior), e não pela numeração arbitrária do K-Means, que muda a cada execução; o script `05_pca_clusterizacao.R` faz essa ordenação antes de nomear os grupos.

Nomes deliberadamente descritivos (não valorativos) — evitam termos como "rico/pobre" ou "desenvolvido/atrasado".

**Achado adicional:** obesidade não acompanha desenvolvimento de forma linear — clusters 3 e 4 (Sul da Ásia / África Subsaariana) têm obesidade baixíssima (9–11%) apesar de perfis de saúde muito diferentes entre si; clusters 1 e 2 (renda média/alta) têm obesidade bem mais alta (22–25%) — consistente com a transição epidemiológica descrita na literatura de saúde global.

---

## 9. Esperado vs. observado (Fase 8)

Usa os valores ajustados e resíduos **studentizados** (não brutos — corrige para a heterocedasticidade já documentada) do modelo de regressão da Seção 7. Classificação: ±1 desvio-padrão do resíduo studentizado (~68%/16%/16%, critério estatístico padrão, não corte arbitrário).

**Distribuição observada:** 20 abaixo do esperado, 120 dentro do esperado, 19 acima — muito próxima do esperado teórico (~16%/68%/16%).

### Achados nos extremos

- **Abaixo do esperado, concentrado no Sul da África** (Eswatini, Lesoto, Botsuana, África do Sul, Zimbábue — os 5 mais extremos): coincide com a região historicamente mais atingida pela epidemia de HIV/AIDS, um fator de carga de doença não capturado por nenhuma das 5 variáveis do modelo. Interpretado como boa validação do modelo (o "erro" tem explicação real e conhecida), não como falha.
- **Acima do esperado:** Peru, Cabo Verde, Etiópia, Costa Rica, Jordânia, Bangladesh — Costa Rica em particular é um caso conhecido na literatura de saúde global como exemplo de bom desempenho em saúde relativo à renda.
- **Cruzamento com clusters:** o cluster 4, "Mortalidade infantil muito elevada, indicadores de renda mais baixos", concentra 35% dos países "abaixo do esperado" (vs. ~12.6% geral) — consistente com a explicação do HIV/AIDS acima (mesma região geográfica), não um sinal de mau ajuste do modelo para aquele grupo.

**Ressalva central (repetir no dashboard):** esta classificação reflete distância em relação a um modelo com R²≈0.74 e limitações conhecidas (heterocedasticidade, colinearidade PIB×gasto em saúde, N=159, ausência de variáveis de carga de doença/qualidade institucional). **Não é um veredito sobre a qualidade do sistema de saúde de nenhum país.**

---

## 10. Limitações gerais do projeto

1. **Corte transversal, não painel:** um único ano (2015) foi escolhido para evitar a complexidade de dados em painel (dependência temporal), o que significa que a análise não captura tendências individuais por país, só o retrato de um ano.
2. **Amostra reduzida em relação ao universo de países** (159 de ~217 reconhecidos) devido a exigências de cobertura simultânea.
3. **Correlação não implica causalidade** em nenhuma das análises — o desenho é observacional.
4. **Ausência de variáveis de carga de doença específica** (HIV/AIDS, conflitos, desastres) — o modelo de regressão não as inclui, o que explica boa parte dos casos "abaixo do esperado" nos resultados da Fase 8.
5. **Fontes de dados secundárias têm lacunas conhecidas:** escolaridade esperada (World Bank) tem cobertura em colapso após 2018; tabagismo (World Bank) tem ao menos um ano (2019) sem nenhum dado.
6. **Decisões de julgamento documentadas, não regras automáticas:** retenção de 2 componentes no PCA (contra o critério de Kaiser estrito) e escolha de K=4 na clusterização (contra o k=2 "ótimo" por silhouette) são decisões metodológicas informadas, não resultados puramente algorítmicos — declaradas como tal.

---

---

## 11. Projeções e comparação de algoritmos de agrupamento (script 09)

Esta etapa responde à pergunta de visualização do projeto: PCA, t-SNE e UMAP mostram a mesma estrutura de grupos?

**Desenho.**
- Variáveis: as mesmas 6 da Seção 8, padronizadas (log em mortalidade, PIB e gasto).
- Grupos de referência: K-Means (K = 4) no **espaço original de 6 dimensões**, nunca nas coordenadas de uma projeção, para não favorecer o PCA por circularidade. (Os cartões de perfil e o gráfico de PCA do painel usam o K-Means em PC1/PC2; os dois concordam com ARI = 0,956.)
- Projeções: PCA (`prcomp`), t-SNE (`Rtsne`, perplexity 15) e UMAP (`uwot`, `n_neighbors` 15, `min_dist` 0,1), com semente 42.
- Métricas (k = 10 vizinhos): trustworthiness, continuity, fração de vizinhos do mesmo grupo e silhueta 2D.
- Variabilidade: 10 sementes e varredura de perplexity e `n_neighbors` em {5, 15, 30, 45}.
- Algoritmos: K-Means, Ward.D2, PAM, GMM (`mclust`) e HDBSCAN (`dbscan`, minPts = 5), comparados por ARI e silhueta.
- Variáveis: remoção de uma por vez e inclusão de escolaridade e médicos (74 países).

**Resultados principais** (tabelas em `outputs/tables/projecoes_*.csv` e `clusterizacao_*.csv`):

| Técnica | Trustworthiness | Continuity | Vizinhos do mesmo grupo | Silhueta 2D |
|---|---|---|---|---|
| Espaço original | 1,000 | 1,000 | 0,903 | 0,332 |
| PCA | 0,942 | 0,977 | 0,927 | 0,444 |
| t-SNE | 0,982 | 0,963 | 0,934 | 0,499 |
| UMAP | 0,957 | 0,973 | 0,940 | 0,487 |

- Nenhuma técnica vence em todas as métricas. Na média de 10 sementes, o t-SNE tem trustworthiness 0,977 (dp 0,002) contra 0,965 (0,003) do UMAP; o UMAP tem consistência de vizinhos 0,942 contra 0,934 e silhueta 0,504 contra 0,481, diferenças de 1 a 2 desvios-padrão.
- O ARI entre os grupos refeitos em 2D e os de 6D varia de 0,52 a 0,90 (t-SNE) e de 0,56 a 0,88 (UMAP), contra 0,96 do PCA.
- ARI contra o K-Means: Ward 0,72, PAM 0,53, GMM 0,33, HDBSCAN 0,33 (2 grupos e 38 países de ruído).
- Remoção de variáveis (ARI): tabagismo 0,60, gasto em saúde 0,71, PIB 0,79, obesidade 0,90, expectativa de vida 0,93, mortalidade infantil 0,96.
- Inclusão das variáveis secundárias (74 países): ARI 0,70; silhueta de 0,376 para 0,324.

**Ressalva de reprodutibilidade.** t-SNE, UMAP e HDBSCAN dependem de sementes e de versões de pacote: em outro ambiente o HDBSCAN deu 3 grupos e 46 países de ruído, e a trustworthiness do t-SNE com a mesma semente foi 0,966. Os valores acima são os da execução registrada em `outputs/tables/`.

## 12. Robustez ao ano (script 08)

Repetição da regressão, do PCA e do K-Means para 2010 (N = 158): R² ajustado 0,683 (0,728 em 2015); PC1 e PC2 com 66,0% e 16,0%; PIB significativo nos dois anos (p = 0,019 e p = 0,005); gasto em saúde significativo em 2010 (p = 0,042) e marginal em 2015 (p = 0,069). Resultados em `outputs/tables/sensibilidade_ano.csv`.

---

## 13. Próximos passos

- Fase 9 (concluída): exportação dos dados finais (indicadores, clusters, classificação esperado/observado) para os formatos que o dashboard vai consumir.
- Dashboard (`dashboard/`, concluído), com esta documentação alimentando a seção de Metodologia.
- README e artigo (`docs/ARTIGO.md`), que reaproveitam as tabelas e achados deste documento; falta o resumo e a conversão para o template IEEE.
