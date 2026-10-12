# 🌎 Health Inequality Explorer

Análise de dados em Estatística, R, Machine Learning e visualização interativa sobre desigualdades de saúde entre países.

**[→ Repositório no GitHub](https://github.com/ThaiiCeu/health-inequality-explorer)**

**[→ Dashboard interativo](https://thaiiceu.github.io/health-inequality-explorer/)** (publicado via GitHub Pages)

*(Também dá para rodar localmente — ver "Como reproduzir a análise" abaixo.)*

---

## Pergunta principal

Em que medida indicadores socioeconômicos e de acesso ao sistema de saúde explicam as diferenças nos resultados de saúde entre países, e quais países apresentam desempenho em saúde acima ou abaixo do esperado dado seu nível de desenvolvimento?

### Perguntas secundárias

1. Quais indicadores estão mais fortemente associados à expectativa de vida?
2. Existem agrupamentos naturais de países com perfis semelhantes de desenvolvimento e saúde?
3. Quais países superam ou ficam abaixo do resultado de saúde esperado, controlando pelo nível socioeconômico?
4. A relação entre desenvolvimento e mortalidade infantil segue o mesmo padrão da expectativa de vida?
5. Quanto da variação em saúde entre países pode ser resumida em poucas dimensões latentes (PCA)?

---

## Fontes de dados

Nove indicadores coletados via API, de duas fontes oficiais:

| Indicador | Fonte | Código |
|---|---|---|
| Expectativa de vida ao nascer | WHO GHO | `WHOSIS_000001` |
| Mortalidade infantil (<5 anos) | WHO GHO | `MDG_0000000007` |
| Médicos por 10.000 habitantes | WHO GHO | `HWF_0001` |
| Prevalência de obesidade (adultos) | WHO GHO | `NCD_BMI_30A` |
| PIB per capita (PPP) | World Bank | `NY.GDP.PCAP.PP.KD` |
| Escolaridade esperada | World Bank | `SE.SCH.LIFE` |
| População total | World Bank | `SP.POP.TOTL` |
| Gasto em saúde per capita (PPP) | World Bank | `SH.XPD.CHEX.PP.CD` |
| Prevalência de tabagismo (adultos) | World Bank | `SH.PRV.SMOK` |

Coleta reproduzível via API (janela 2000–2022), com busca de indicadores por nome em vez de códigos fixos, para resistir a mudanças na API da WHO (já anunciadas pela própria organização). Detalhes completos em [`docs/METODOLOGIA.md`](docs/METODOLOGIA.md).

---

## Metodologia (resumo)

- **Amostra**: corte transversal de **2015**, 159 países (núcleo de 7 indicadores com melhor cobertura simultânea).
- **Regressão múltipla**: expectativa de vida em função de PIB per capita, obesidade, tabagismo, população e gasto em saúde (todos com transformação log onde havia assimetria). R² ajustado = 0,728. Diagnóstico completo (VIF, normalidade, heterocedasticidade) com correção via erros-padrão robustos (HC3).
- **PCA e clusterização**: 2 componentes principais retidos (81,4% da variância); 4 clusters via K-Means, validados contra clusterização hierárquica.
- **Projeções e algoritmos de clusterização**: PCA, t-SNE e UMAP comparados quanto à preservação de vizinhança (trustworthiness, continuity), consistência de vizinhos do mesmo grupo e silhueta 2D, com análise de sensibilidade a hiperparâmetros e a 10 sementes. Os grupos são definidos no espaço original padronizado (6D) por cinco algoritmos (K-Means, Ward, PAM, GMM, HDBSCAN), para não favorecer o PCA por circularidade. Inclui análise de remoção de variáveis e de ampliação com as variáveis secundárias.
- **Esperado vs. observado**: resíduos studentizados do modelo de regressão, classificados por desvio-padrão (critério estatístico, não corte arbitrário).

Documentação metodológica completa — com todas as decisões, números e limitações — em [`docs/METODOLOGIA.md`](docs/METODOLOGIA.md).

---

## Tecnologias

**Análise de dados**: R (tidyverse, httr2, jsonlite, broom, performance, sandwich, lmtest, factoextra, cluster, corrplot, Rtsne, uwot, mclust, dbscan)
**Dashboard**: HTML, CSS, JavaScript, [D3.js](https://d3js.org/) (mapa), [Chart.js](https://www.chartjs.org/) (gráficos)
**Arquitetura**: R processa e exporta dados em JSON estático → front-end HTML/CSS/JS consome via `fetch()` → hospedável gratuitamente no GitHub Pages (sem servidor rodando)

---

## Estrutura do repositório

```
health-inequality-explorer/
│
├── README.md
├── .gitignore
├── renv.lock           # versões travadas dos pacotes R (reprodutibilidade)
├── renv/               # infraestrutura do renv (commitado, exceto renv/library/)
│
├── data/
│   ├── raw/            # dados brutos da API (não versionado — ver .gitignore)
│   ├── processed/      # dados limpos e prontos para análise
│   └── external/       # referência de países (World Bank)
│
├── R/
│   ├── funcoes.R                  # funções reutilizáveis (coleta, limpeza)
│   ├── 00_configurar_renv.R       # roda uma vez para travar versões de pacote
│   ├── 01_coleta_dados.R
│   ├── 02_limpeza_dados.R
│   ├── 03_analise_exploratoria.R
│   ├── 04_analise_estatistica.R
│   ├── 05_pca_clusterizacao.R
│   ├── 06_modelagem.R             # esperado vs. observado
│   ├── 07_exportacao_dashboard.R
│   ├── 08_sensibilidade_ano.R     # checagem de robustez: 2010 vs. 2015
│   └── 09_projecoes_clusterizacao.R  # PCA vs. t-SNE vs. UMAP + 5 algoritmos de clusterização
│
├── dashboard/
│   ├── index.html
│   ├── css/style.css
│   ├── js/                        # main, explorer, profiles, heatmap, projections, regression, expected, map, methodology
│   └── data/                      # JSONs exportados pelo R (gerados por 07 e 09)
│
├── outputs/
│   ├── figures/        # gráficos gerados nas Fases 5-8
│   └── tables/          # tabelas de resultados (regressão, clusters, etc.)
│
└── docs/
    ├── METODOLOGIA.md   # documentação metodológica completa
    └── ARTIGO.md        # rascunho do artigo (comparação de projeções)
```

---

## Principais resultados

- **PIB per capita** explica fortemente a expectativa de vida, com retornos decrescentes — sustentado mesmo após correção para heterocedasticidade.
- **Gasto em saúde** tem associação apenas marginal além do PIB (colinearidade forte entre as duas variáveis, VIF ≈ 10) — um achado honesto sobre os limites dos dados, não um resultado forçado.
- **4 perfis de país** emergem da clusterização, com o achado de que obesidade não acompanha desenvolvimento de forma linear (transição epidemiológica).
- **Países "abaixo do esperado"** se concentram no Sul da África — consistente com o impacto histórico da epidemia de HIV/AIDS, um fator não capturado pelas variáveis do modelo.

---

## Como reproduzir a análise

**Opção A — com renv (recomendado, garante as mesmas versões de pacote que foram usadas na análise original):**

```r
install.packages("renv")
renv::restore()   # reinstala exatamente as versões travadas em renv.lock

source("R/01_coleta_dados.R")        # coleta via API (precisa de internet)
source("R/02_limpeza_dados.R")
source("R/03_analise_exploratoria.R")
source("R/04_analise_estatistica.R")
source("R/05_pca_clusterizacao.R")
source("R/06_modelagem.R")
source("R/07_exportacao_dashboard.R") # gera os JSONs do dashboard
source("R/08_sensibilidade_ano.R")
source("R/09_projecoes_clusterizacao.R") # projeções + clusterização (~20 s)
```

**Opção B — sem renv (mais simples, mas sem garantia de versão):**

```r
# 1. Instale os pacotes necessários
install.packages(c("httr2", "jsonlite", "dplyr", "readr", "purrr", "stringr",
                    "tidyr", "ggplot2", "corrplot", "scales", "broom",
                    "performance", "sandwich", "lmtest", "factoextra",
                    "cluster", "ggrepel", "Rtsne", "uwot", "mclust", "dbscan"))

# 2. Rode os scripts em ordem, a partir da raiz do repositório
source("R/01_coleta_dados.R")        # coleta via API (precisa de internet)
source("R/02_limpeza_dados.R")
source("R/03_analise_exploratoria.R")
source("R/04_analise_estatistica.R")
source("R/05_pca_clusterizacao.R")
source("R/06_modelagem.R")
source("R/07_exportacao_dashboard.R") # gera os JSONs do dashboard
source("R/08_sensibilidade_ano.R")
source("R/09_projecoes_clusterizacao.R") # projeções + clusterização (~20 s)
```

Para ver o dashboard localmente:

```bash
cd dashboard
python3 -m http.server 8000
# abra http://localhost:8000 no navegador
```

(`fetch()` não funciona abrindo o `index.html` direto como arquivo — precisa de um servidor local ou do GitHub Pages.)

**Sem R e sem análise nenhuma:** os JSONs do dashboard já estão versionados em `dashboard/data/`. Basta clonar o repositório (ou baixar o ZIP em *Code → Download ZIP*), ter Python instalado e rodar os três comandos acima. No Windows, se `python3` não funcionar, use `python -m http.server 8000`. Alternativa: abrir a pasta `dashboard/` no VS Code e usar a extensão *Live Server*.

---

## Limitações

- Corte transversal de um único ano — não captura tendências individuais por país.
- Amostra de 159 de ~217 países reconhecidos, por exigência de cobertura simultânea dos indicadores.
- Desenho observacional — correlação não implica causalidade em nenhuma das análises.
- Ausência de variáveis de carga de doença específica (HIV/AIDS, conflitos, desastres).
- Fontes secundárias (escolaridade, tabagismo) têm lacunas de cobertura conhecidas.

Lista completa de limitações e decisões metodológicas de julgamento em [`docs/METODOLOGIA.md`](docs/METODOLOGIA.md).

---

## Próximos passos

- Adicionar mais anos de referência para permitir análise de painel (atualmente restrito a corte transversal).
- Incorporar indicadores de carga de doença específica quando disponíveis com boa cobertura.
- Testar especificações não-lineares adicionais para a relação PIB–saúde.

---

## Autoria

Projeto desenvolvido como peça de portfólio em Estatística e Data Analytics/Data Science.
