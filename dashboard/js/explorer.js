// =============================================================================
// explorer.js — Country Explorer
// =============================================================================

const PAISES_PADRAO = ['Brazil', 'Japan', 'Germany'];
const CORES_LINHAS = ['#B5451F', '#1F6F5C', '#6B5B47', '#8B6F47'];

const NOMES_INDICADORES = {
  expectativa_vida: 'Expectativa de vida (anos)',
  mortalidade_infantil: 'Mortalidade infantil (por 1.000)',
  prevalencia_obesidade: 'Prevalência de obesidade (%)',
  pib_per_capita_ppp: 'PIB per capita (US$ PPP)',
  gasto_saude_pc_ppp: 'Gasto em saúde per capita (US$ PPP)',
  prevalencia_tabagismo: 'Prevalência de tabagismo (%)'
};

const CLASSIFICACAO_BADGE = {
  'Acima do esperado': 'badge-acima',
  'Abaixo do esperado': 'badge-abaixo',
  'Dentro do esperado': 'badge-dentro'
};

let TODOS_PAISES = [];
let SERIE_TEMPORAL = {};
let KPIS_GLOBAIS = {};
let paisesSelecionados = [];
let graficoEvolucao = null;

async function carregarJSONExplorer(caminho) {
  const resposta = await fetch(`${caminho}?v=${Date.now()}`);
  if (!resposta.ok) throw new Error(`Falha ao carregar ${caminho}`);
  return resposta.json();
}

function formatarValorIndicador(indicador, valor) {
  if (valor === null || valor === undefined) return '—';
  if (indicador === 'pib_per_capita_ppp' || indicador === 'gasto_saude_pc_ppp') {
    return '$' + Math.round(valor).toLocaleString('en-US');
  }
  return valor.toLocaleString('pt-BR', { maximumFractionDigits: 1 });
}

function popularDatalist() {
  const datalist = document.getElementById('country-list');
  datalist.innerHTML = TODOS_PAISES
    .map(p => `<option value="${p.nome}"></option>`)
    .join('');
}

function renderizarChips() {
  const container = document.getElementById('country-chips');
  container.innerHTML = paisesSelecionados.map(nome => `
    <span class="chip">
      ${nome}
      <button type="button" data-remover="${nome}" aria-label="Remover ${nome}">×</button>
    </span>
  `).join('');

  container.querySelectorAll('button[data-remover]').forEach(botao => {
    botao.addEventListener('click', () => {
      paisesSelecionados = paisesSelecionados.filter(n => n !== botao.dataset.remover);
      atualizarTudo();
    });
  });
}

function renderizarCardsComparacao() {
  const container = document.getElementById('compare-grid');

  container.innerHTML = paisesSelecionados.map(nome => {
    const pais = TODOS_PAISES.find(p => p.nome === nome);
    if (!pais) return '';

    const classeBadge = CLASSIFICACAO_BADGE[pais.classificacao] || 'badge-dentro';

    const linhasIndicadores = [
      { chave: 'expectativa_vida', valor: pais.expectativa_vida, mediaGlobal: KPIS_GLOBAIS.expectativa_vida_media },
      { chave: 'mortalidade_infantil', valor: pais.mortalidade_infantil, mediaGlobal: KPIS_GLOBAIS.mortalidade_infantil_media },
      { chave: 'pib_per_capita_ppp', valor: pais.pib_per_capita_ppp, mediaGlobal: null },
      { chave: 'gasto_saude_pc_ppp', valor: pais.gasto_saude_pc_ppp, mediaGlobal: KPIS_GLOBAIS.gasto_saude_medio }
    ];

    const linhasHTML = linhasIndicadores.map(item => {
      let deltaHTML = '';
      if (item.mediaGlobal) {
        const diferenca = item.valor - item.mediaGlobal;
        const percentual = (diferenca / item.mediaGlobal) * 100;
        const classeDelta = diferenca >= 0 ? 'delta-pos' : 'delta-neg';
        const sinal = diferenca >= 0 ? '+' : '';
        deltaHTML = `<span class="compare-stat-delta ${classeDelta}">${sinal}${percentual.toFixed(0)}% vs. média</span>`;
      }
      return `
        <div class="compare-stat-row">
          <span class="compare-stat-label">${NOMES_INDICADORES[item.chave].split(' (')[0]}</span>
          <span>
            <span class="compare-stat-value">${formatarValorIndicador(item.chave, item.valor)}</span>
            ${deltaHTML}
          </span>
        </div>
      `;
    }).join('');

    return `
      <div class="compare-card">
        <p class="compare-card-name">${pais.nome}</p>
        <p class="compare-card-region">${pais.regiao}</p>
        <span class="badge badge-cluster">${pais.nome_cluster}</span>
        <span class="badge ${classeBadge}">${pais.classificacao}</span>
        <div class="compare-stats">${linhasHTML}</div>
      </div>
    `;
  }).join('');
}

function renderizarGraficoEvolucao() {
  const painel = document.querySelector('.chart-panel');

  if (typeof Chart === 'undefined') {
    console.error('Chart.js não carregou — verifique a tag <script> do CDN em index.html.');
    document.getElementById('evolution-chart').insertAdjacentHTML(
      'afterend',
      '<p style="font-size:13px; color:var(--rust-dark);">Não foi possível carregar a biblioteca do gráfico (Chart.js). Veja o console do navegador (F12) para detalhes.</p>'
    );
    return;
  }

  try {
    const indicador = document.getElementById('indicator-select').value;
    const ctx = document.getElementById('evolution-chart');

    const datasets = paisesSelecionados.map((nome, i) => {
      const pais = TODOS_PAISES.find(p => p.nome === nome);
      const serie = pais ? SERIE_TEMPORAL[pais.iso3]?.[indicador] : null;
      if (!serie) return null;

      return {
        label: nome,
        data: serie.anos.map((ano, idx) => ({ x: ano, y: serie.valores[idx] })),
        borderColor: CORES_LINHAS[i % CORES_LINHAS.length],
        backgroundColor: CORES_LINHAS[i % CORES_LINHAS.length],
        borderWidth: 2,
        pointRadius: 0,
        tension: 0.15
      };
    }).filter(Boolean);

    if (graficoEvolucao) graficoEvolucao.destroy();

    graficoEvolucao = new Chart(ctx, {
      type: 'line',
      data: { datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: 'nearest', intersect: false },
        plugins: {
          legend: { position: 'top', labels: { font: { family: 'Inter', size: 12.5 }, color: '#2A2015', usePointStyle: true } },
          tooltip: { titleFont: { family: 'Inter' }, bodyFont: { family: 'Inter' } }
        },
        scales: {
          x: { type: 'linear', ticks: { stepSize: 5, font: { family: 'IBM Plex Mono', size: 11 }, color: '#6B5B47' }, grid: { color: '#E4D9C5' } },
          y: { title: { display: true, text: NOMES_INDICADORES[indicador], font: { family: 'Inter', size: 12 }, color: '#6B5B47' }, ticks: { font: { family: 'IBM Plex Mono', size: 11 }, color: '#6B5B47' }, grid: { color: '#E4D9C5' } }
        }
      }
    });
  } catch (erro) {
    console.error('Erro ao renderizar o gráfico de evolução:', erro);
  }
}

function atualizarTudo() {
  renderizarChips();
  renderizarCardsComparacao();
  renderizarGraficoEvolucao();
}

function configurarBuscaPais() {
  const input = document.getElementById('country-search');
  input.addEventListener('change', () => {
    const nome = input.value.trim();
    const existe = TODOS_PAISES.some(p => p.nome === nome);
    const jaSelecionado = paisesSelecionados.includes(nome);

    if (existe && !jaSelecionado && paisesSelecionados.length < 4) {
      paisesSelecionados.push(nome);
      atualizarTudo();
    }
    input.value = '';
  });
}

async function iniciarExplorer() {
  try {
    [TODOS_PAISES, SERIE_TEMPORAL, KPIS_GLOBAIS] = await Promise.all([
      carregarJSONExplorer('data/countries.json'),
      carregarJSONExplorer('data/serie_temporal.json'),
      carregarJSONExplorer('data/kpis_globais.json')
    ]);

    popularDatalist();
    configurarBuscaPais();

    document.getElementById('indicator-select').addEventListener('change', renderizarGraficoEvolucao);

    const nomesDisponiveis = TODOS_PAISES.map(p => p.nome);
    paisesSelecionados = PAISES_PADRAO.filter(n => nomesDisponiveis.includes(n));
    if (paisesSelecionados.length === 0) {
      paisesSelecionados = nomesDisponiveis.slice(0, 3);
    }

    atualizarTudo();
  } catch (erro) {
    console.error('Erro ao iniciar o Country Explorer:', erro);
  }
}

document.addEventListener('DOMContentLoaded', iniciarExplorer);
