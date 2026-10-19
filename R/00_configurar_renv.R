# =============================================================================
# 00_configurar_renv.R
# Health Inequality Explorer — Trava de versões de pacotes (reprodutibilidade)
#
# PERGUNTA: se alguém (incluindo você, daqui a 1 ano) rodar este projeto de
# novo, vai obter os MESMOS resultados? Sem travar as versões dos pacotes R,
# a resposta não é garantida — uma atualização do dplyr, do broom ou do
# performance pode mudar um default e alterar um coeficiente ou um p-valor
# silenciosamente.
#
# O QUE renv FAZ: cria um "retrato" (data/lockfile) das versões exatas de
# cada pacote usado no projeto, isolado do resto do seu computador. Quem
# clonar o repositório e rodar renv::restore() reinstala exatamente essas
# versões, não as mais recentes disponíveis no CRAN.
#
# COMO RODAR (uma única vez, na raiz do projeto):
#   1. install.packages("renv")            # se ainda não tiver
#   2. source("R/00_configurar_renv.R")    # este script
#
# O que este script faz, na ordem:
#   1. Inicializa o renv neste projeto (cria renv/ e .Rprofile).
#   2. Roda os scripts 01 a 07 (para garantir que TODOS os pacotes
#      realmente usados no projeto fiquem registrados — renv::snapshot()
#      só grava pacotes que ele detecta sendo carregados/usados).
#   3. Tira o "retrato" (snapshot) em renv.lock.
#
# IMPORTANTE: depois de rodar isso uma vez, renv/ e renv.lock devem ser
# COMMITADOS no Git (não são dados brutos, são metadados de reprodutibilidade
# — diferente de data/raw/, que o .gitignore exclui de propósito).
# =============================================================================

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv")
}

# -----------------------------------------------------------------------
# 1. Inicializar o renv neste projeto
# -----------------------------------------------------------------------
# bare = TRUE: não tenta adivinhar dependências a partir de arquivos
# existentes antes de rodarmos o pipeline — vamos deixar o snapshot()
# do passo 3 detectar tudo de forma precisa, depois de rodar o código de
# verdade.

renv::init(bare = TRUE)

message("\n[renv] Projeto inicializado. Agora rodando o pipeline completo para o renv detectar todas as dependências reais...\n")

# -----------------------------------------------------------------------
# 2. Rodar o pipeline inteiro (necessário para o renv "ver" cada pacote
#    sendo de fato usado — um library() em um script que nunca roda não
#    é detectado)
# -----------------------------------------------------------------------
# Se algum desses passos falhar por falta de pacote, instale o pacote
# indicado no erro e rode a linha novamente antes de continuar.

source("R/01_coleta_dados.R")
source("R/02_limpeza_dados.R")
source("R/03_analise_exploratoria.R")
source("R/04_analise_estatistica.R")
source("R/05_pca_clusterizacao.R")
source("R/06_modelagem.R")
source("R/07_exportacao_dashboard.R")

# -----------------------------------------------------------------------
# 3. Tirar o retrato das versões (renv.lock)
# -----------------------------------------------------------------------

renv::snapshot()

message("\n[renv] Concluído. Um arquivo renv.lock foi criado na raiz do projeto.")
message("[renv] Commite renv/ e renv.lock no Git — eles são o que garante reprodutibilidade.")
message("[renv] A partir de agora, qualquer pessoa que clonar o repositório roda apenas:")
message("       install.packages(\"renv\"); renv::restore()")
message("       para reobter exatamente as mesmas versões de pacote que você usou.")
