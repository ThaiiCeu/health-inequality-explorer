// =============================================================================
// expected.js — Esperado vs. Observado
// =============================================================================

const CORES_CLASSIFICACAO = {
  'Acima do esperado': '#1F6F5C',
  'Dentro do esperado': '#C9BBA3',
  'Abaixo do esperado': '#B5451F'
};

let TODOS_PAISES_EXP = [];
let graficoEsperado = null;
let filtroAtivo = 'todos';

async function carregarJSONExpected(caminho) {
  const resposta = await fetch(`${caminho}?v=${Date.now()}`);
  if (!resposta.ok) throw new Error(`Falha ao carregar ${caminho}`);
  return resposta.json();
}

function renderizarGraficoEsperado() {
  if (typeof Chart === 'undefined') {
    console.error('Chart.js não carregado.');
    return;
  }

  const ctx = document.getElementById('expected-chart');
  const paisesFiltrados = filtroAtivo === 'todos'
    ? TODOS_PAISES_EXP
    : TODOS_PAISES_EXP.filter(p => p.classificacao === filtroAtivo);

  const minEixo = Math.min(...TODOS_PAISES_EXP.map(p => Math.min(p.expectativa_esperada, p.expectativa_vida))) - 2;
  const maxEixo = Math.max(...TODOS_PAISES_EXP.map(p => Math.max(p.expectativa_esperada, p.expectativa_vida))) + 2;

  const dataset = {
    label: 'Países',
    data: paisesFiltrados.map(p => ({ x: p.expectativa_esperada, y: p.expectativa_vida, nome: p.nome, classificacao: p.classificacao })),
    backgroundColor: paisesFiltrados.map(p => CORES_CLASSIFICACAO[p.classificacao] + 'CC'),
    pointRadius: 5,
    pointHoverRadius: 7
  };

  const linhaDiagonal = {
    label: 'Esperado = observado',
    data: [{ x: minEixo, y: minEixo }, { x: maxEixo, y: maxEixo }],
    type: 'line',
    borderColor: '#9C8C77',
    borderDash: [4, 4],
    borderWidth: 1.5,
    pointRadius: 0,
    fill: false
  };

  if (graficoEsperado) graficoEsperado.destroy();

  graficoEsperado = new Chart(ctx, {
    type: 'scatter',
    data: { datasets: [linhaDiagonal, dataset] },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: (item) => {
              if (item.dataset.label !== 'Países') return null;
              const p = item.raw;
              return `${p.nome} — esperado ${p.x.toFixed(1)}, observado ${p.y.toFixed(1)} (${p.classificacao})`;
            }
          }
        }
      },
      scales: {
        x: { min: minEixo, max: maxEixo, title: { display: true, text: 'Expectativa de vida esperada (anos)', color: '#6B5B47' }, ticks: { color: '#6B5B47' }, grid: { color: '#E4D9C5' } },
        y: { min: minEixo, max: maxEixo, title: { display: true, text: 'Expectativa de vida observada (anos)', color: '#6B5B47' }, ticks: { color: '#6B5B47' }, grid: { color: '#E4D9C5' } }
      }
    }
  });
}

function renderizarExtremos() {
  const acima = [...TODOS_PAISES_EXP]
    .filter(p => p.classificacao === 'Acima do esperado')
    .sort((a, b) => b.residuo_studentizado - a.residuo_studentizado)
    .slice(0, 8);

  const abaixo = [...TODOS_PAISES_EXP]
    .filter(p => p.classificacao === 'Abaixo do esperado')
    .sort((a, b) => a.residuo_studentizado - b.residuo_studentizado)
    .slice(0, 8);

  document.getElementById('extremes-acima').innerHTML = acima.map(p => `
    <div class="extreme-row">
      <span class="extreme-name">${p.nome}</span>
      <span class="extreme-value" style="color:#1F6F5C">+${p.residuo_studentizado.toFixed(2)}</span>
    </div>
  `).join('');

  document.getElementById('extremes-abaixo').innerHTML = abaixo.map(p => `
    <div class="extreme-row">
      <span class="extreme-name">${p.nome}</span>
      <span class="extreme-value" style="color:#B5451F">${p.residuo_studentizado.toFixed(2)}</span>
    </div>
  `).join('');
}

function configurarFiltros() {
  const botoes = document.querySelectorAll('#classification-filters .filter-chip');
  botoes.forEach(botao => {
    botao.addEventListener('click', () => {
      botoes.forEach(b => b.classList.remove('active'));
      botao.classList.add('active');
      filtroAtivo = botao.dataset.filtro;
      renderizarGraficoEsperado();
    });
  });
}

async function iniciarEsperado() {
  try {
    TODOS_PAISES_EXP = await carregarJSONExpected('data/countries.json');
    configurarFiltros();
    renderizarGraficoEsperado();
    renderizarExtremos();
  } catch (erro) {
    console.error('Erro ao iniciar Esperado vs. Observado:', erro);
  }
}

document.addEventListener('DOMContentLoaded', iniciarEsperado);
