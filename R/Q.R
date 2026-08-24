setwd("C:/Users/luiz1/OneDrive/Área de Trabalho/health-inequality-explorer/health-inequality-explorer")

source("R/01_coleta_dados.R")
source("R/02_limpeza_dados.R")
source("R/03_analise_exploratoria.R")
source("R/04_analise_estatistica.R")
source("R/05_pca_clusterizacao.R")
source("R/06_modelagem.R")
source("R/07_exportacao_dashboard.R")


list.files("R")


# 1) Japão e Alemanha estão no núcleo (159 países)?
dados_nucleo <- read_csv("data/processed/dados_corte_nucleo.csv")
dados_nucleo |> filter(pais_nome %in% c("Japan", "Germany"))

Se o resultado vier vazio (0 linhas), significa que um dos 7 indicadores do núcleo está faltando pra eles em 2015 — e esse segundo comando mostra qual:
  
  r
# 2) Qual indicador especificamente está faltando?
dados_largos <- read_csv("data/processed/dados_largos.csv")
dados_largos |> 
  filter(pais_nome %in% c("Japan", "Germany"), ano == 2015) |>
  select(pais_nome, expectativa_vida, mortalidade_infantil, prevalencia_obesidade, 
         pib_per_capita_ppp, populacao, gasto_saude_pc_ppp, prevalencia_tabagismo)


library(httr2)
library(jsonlite)
library(dplyr)
library(readr)
library(purrr)
library(stringr)
library(broom)
library(performance)
library(ggrepel)
library(cluster)
library(factoextra)
library(lmtest)
library(sandwich)
library(tidyr)
library(ggplot2)
library(corrplot)
library(scales)




setwd("..")
getwd()

