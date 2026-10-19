// =============================================================================
// main.js — Health Inequality Explorer
// Carrega os JSONs exportados pela Fase 9 (R) e popula a página.
// Precisa ser servido por um servidor local (fetch não funciona em file://).
// =============================================================================

async function carregarJSON(caminho) {
  const resposta = await fetch(`${caminho}?v=${Date.now()}`);
  if (!resposta.ok) throw new Error(`Falha ao carregar ${caminho}: ${resposta.status}`);
  return resposta.json();
}

function formatarNumero(valor, casasDecimais = 1) {
  return valor.toLocaleString('pt-BR', {
    minimumFractionDigits: casasDecimais,
    maximumFractionDigits: casasDecimais
  });
}

function formatarMoeda(valor) {
  return '$' + Math.round(valor).toLocaleString('en-US');
}

// -----------------------------------------------------------------------
// KPIs (seção Visão Geral)
// -----------------------------------------------------------------------
async function popularKPIs() {
  try {
    const kpis = await carregarJSON('data/kpis_globais.json');
    document.getElementById('kpi-expectativa').textContent = formatarNumero(kpis.expectativa_vida_media, 1);
    document.getElementById('kpi-mortalidade').textContent = formatarNumero(kpis.mortalidade_infantil_media, 1);
    document.getElementById('kpi-gasto').textContent = formatarMoeda(kpis.gasto_saude_medio);
    document.getElementById('kpi-paises').textContent = kpis.n_paises;
  } catch (erro) {
    console.error('Erro ao carregar KPIs:', erro);
  }
}

// -----------------------------------------------------------------------
// Scatter do hero — PIB x expectativa de vida, o achado central do
// projeto, usado como elemento visual de fundo em vez de decoração
// genérica. Cor por classificação esperado/observado (Fase 8).
// -----------------------------------------------------------------------
async function desenharHeroScatter() {
  try {
    const paises = await carregarJSON('data/countries.json');
    const svg = document.getElementById('hero-scatter');

    const largura = 1200;
    const altura = 700;
    const margem = { topo: 40, direita: 40, baixo: 40, esquerda: 40 };

    const pibs = paises.map(p => Math.log10(p.pib_per_capita_ppp));
    const expectativas = paises.map(p => p.expectativa_vida);

    const pibMin = Math.min(...pibs);
    const pibMax = Math.max(...pibs);
    const expMin = Math.min(...expectativas);
    const expMax = Math.max(...expectativas);

    const escalaX = (v) => margem.esquerda + ((v - pibMin) / (pibMax - pibMin)) * (largura - margem.esquerda - margem.direita);
    const escalaY = (v) => altura - margem.baixo - ((v - expMin) / (expMax - expMin)) * (altura - margem.topo - margem.baixo);

    const corPorClassificacao = {
      'Acima do esperado': '#1F6F5C',
      'Dentro do esperado': '#C9BBA3',
      'Abaixo do esperado': '#B5451F'
    };

    const circulos = paises.map(p => {
      const cx = escalaX(Math.log10(p.pib_per_capita_ppp));
      const cy = escalaY(p.expectativa_vida);
      const cor = corPorClassificacao[p.classificacao] || '#C9BBA3';
      return `<circle cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="5" fill="${cor}" fill-opacity="0.75" />`;
    }).join('');

    svg.innerHTML = circulos;
  } catch (erro) {
    console.error('Erro ao desenhar scatter do hero:', erro);
  }
}

// -----------------------------------------------------------------------
// Navegação — marca o link ativo conforme a seção visível
// -----------------------------------------------------------------------
function configurarNavegacaoAtiva() {
  const secoes = document.querySelectorAll('main > section[id]');
  const links = document.querySelectorAll('.nav-link');

  const observador = new IntersectionObserver((entradas) => {
    entradas.forEach(entrada => {
      if (entrada.isIntersecting) {
        links.forEach(link => {
          link.classList.toggle('active', link.getAttribute('href') === `#${entrada.target.id}`);
        });
      }
    });
  }, { rootMargin: '-40% 0px -55% 0px' });

  secoes.forEach(secao => observador.observe(secao));
}

// -----------------------------------------------------------------------
// Inicialização
// -----------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', () => {
  popularKPIs();
  desenharHeroScatter();
  configurarNavegacaoAtiva();
});
