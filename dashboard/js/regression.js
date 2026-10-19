// =============================================================================
// regression.js — What Drives Health
// =============================================================================

const INFO_VARIAVEIS = {
  'log(pib_per_capita_ppp)': {
    nome: 'PIB per capita',
    nota: 'Associação positiva e significativa mesmo controlando pelas outras variáveis — um aumento percentual no PIB está associado a maior expectativa de vida, com retornos decrescentes (por isso o modelo usa a variável em escala log).'
  },
  'prevalencia_obesidade': {
    nome: 'Prevalência de obesidade',
    nota: 'Sem associação estatisticamente significativa neste modelo, uma vez controlado pelas demais variáveis.'
  },
  'prevalencia_tabagismo': {
    nome: 'Prevalência de tabagismo',
    nota: 'Coeficiente positivo — resultado contraintuitivo, interpretado como confundimento histórico (países hoje desenvolvidos tiveram picos de tabagismo décadas atrás), não como efeito protetor real do tabagismo.'
  },
  'log(populacao)': {
    nome: 'População (tamanho do país)',
    nota: 'Variável de controle de escala — sem associação significativa com expectativa de vida.'
  },
  'log(gasto_saude_pc_ppp)': {
    nome: 'Gasto em saúde per capita',
    nota: 'Associação apenas marginal (não significativa a 5% após corrigir para heterocedasticidade) — a alta colinearidade com PIB per capita (ver nota abaixo) limita a capacidade de isolar esse efeito.'
  }
};

async function carregarJSONRegressao(caminho) {
  const resposta = await fetch(`${caminho}?v=${Date.now()}`);
  if (!resposta.ok) throw new Error(`Falha ao carregar ${caminho}`);
  return resposta.json();
}

function renderizarStatsModelo(dados) {
  const container = document.getElementById('model-stats');
  container.innerHTML = `
    <div class="model-stat">
      <p class="model-stat-label">R² ajustado</p>
      <p class="model-stat-value">${dados.r_quadrado_ajustado.toFixed(3)}</p>
    </div>
    <div class="model-stat">
      <p class="model-stat-label">Países na amostra</p>
      <p class="model-stat-value">${dados.n_paises}</p>
    </div>
  `;
}

function renderizarCoeficientes(coeficientes) {
  const container = document.getElementById('coef-list');

  const linhas = coeficientes
    .filter(c => c.variavel !== '(Intercept)')
    .map(c => {
      const info = INFO_VARIAVEIS[c.variavel] || { nome: c.variavel, nota: '' };
      const positivo = c.estimativa >= 0;

      let classeIndicador = 'not-sig';
      let tagTexto = 'Não significativo';
      let tagClasse = 'not-sig';
      if (c.significativo_5pct) {
        classeIndicador = positivo ? 'sig-pos' : 'sig-neg';
        tagTexto = positivo ? 'Associação positiva' : 'Associação negativa';
        tagClasse = 'sig';
      }

      return `
        <div class="coef-row">
          <span class="coef-indicator ${classeIndicador}"></span>
          <div class="coef-body">
            <div class="coef-name-row">
              <span class="coef-name">${info.nome}</span>
              <span class="coef-sig-tag ${tagClasse}">${tagTexto}</span>
              <span class="coef-p">p = ${c.p_valor.toFixed(3)}</span>
            </div>
            <p class="coef-note">${info.nota}</p>
          </div>
        </div>
      `;
    }).join('');

  container.innerHTML = linhas;
}

function renderizarCallout(dados) {
  document.getElementById('vif-callout').innerHTML = `
    <strong>Sobre multicolinearidade:</strong> PIB per capita e gasto em saúde são fortemente correlacionados entre si (r = 0,86), o que infla a incerteza de seus coeficientes individuais (VIF ≈ 10). ${dados.nota_metodologica}
  `;
}

async function iniciarRegressao() {
  try {
    const dados = await carregarJSONRegressao('data/regressao.json');
    renderizarStatsModelo(dados);
    renderizarCoeficientes(dados.coeficientes);
    renderizarCallout(dados);
  } catch (erro) {
    console.error('Erro ao iniciar What Drives Health:', erro);
  }
}

document.addEventListener('DOMContentLoaded', iniciarRegressao);
