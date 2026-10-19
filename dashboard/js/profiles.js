// =============================================================================
// profiles.js — Health Profiles (PCA scatter + cards de cluster)
// =============================================================================

const GRADIENTE_CLUSTER = ['#1F6F5C', '#8A9B5C', '#C98A2B', '#B5451F']; // teal -> sage -> gold -> rust

async function carregarJSONProfiles(caminho) {
  const resposta = await fetch(`${caminho}?v=${Date.now()}`);
  if (!resposta.ok) throw new Error(`Falha ao carregar ${caminho}`);
  return resposta.json();
}

function formatarPib(valor) {
  return '$' + Math.round(valor).toLocaleString('en-US');
}

function desenharScatterPCA(paises, corPorCluster) {
  const svg = document.getElementById('pca-scatter');
  const largura = 900;
  const altura = 480;
  const margem = 30;

  const pc1s = paises.map(p => p.pc1);
  const pc2s = paises.map(p => p.pc2);
  const pc1Min = Math.min(...pc1s), pc1Max = Math.max(...pc1s);
  const pc2Min = Math.min(...pc2s), pc2Max = Math.max(...pc2s);

  const escalaX = v => margem + ((v - pc1Min) / (pc1Max - pc1Min)) * (largura - 2 * margem);
  const escalaY = v => altura - margem - ((v - pc2Min) / (pc2Max - pc2Min)) * (altura - 2 * margem);

  const eixos = `
    <line x1="${margem}" y1="${altura / 2}" x2="${largura - margem}" y2="${altura / 2}" stroke="#E4D9C5" stroke-width="1" />
    <line x1="${largura / 2}" y1="${margem}" x2="${largura / 2}" y2="${altura - margem}" stroke="#E4D9C5" stroke-width="1" />
  `;

  const pontos = paises.map(p => {
    const cor = corPorCluster[p.cluster] || '#9C8C77';
    return `<circle cx="${escalaX(p.pc1).toFixed(1)}" cy="${escalaY(p.pc2).toFixed(1)}" r="5" fill="${cor}" fill-opacity="0.8" />
      <title>${p.nome}</title>`;
  }).join('');

  svg.innerHTML = eixos + pontos;
}

function renderizarLegenda(clustersOrdenados, corPorCluster) {
  const container = document.getElementById('pca-legend');
  container.innerHTML = clustersOrdenados.map(c => `
    <span class="pca-legend-item">
      <span class="pca-legend-dot" style="background:${corPorCluster[c.cluster]}"></span>
      ${c.nome_cluster}
    </span>
  `).join('');
}

function renderizarCardsCluster(clustersOrdenados, corPorCluster, paisesPorCluster) {
  const container = document.getElementById('cluster-grid');

  container.innerHTML = clustersOrdenados.map(c => {
    const paisesDoCluster = paisesPorCluster[c.cluster] || [];
    const tagsPaises = paisesDoCluster.map(nome => `<span class="country-tag">${nome}</span>`).join('');

    return `
      <div class="cluster-card" style="border-top-color:${corPorCluster[c.cluster]}">
        <p class="cluster-card-eyebrow">${c.n_paises} países</p>
        <p class="cluster-card-name">${c.nome_cluster}</p>
        <div class="cluster-stats">
          <div><p class="cluster-stat-label">Expectativa de vida</p><p class="cluster-stat-value">${c.expectativa_vida_media.toFixed(1)} anos</p></div>
          <div><p class="cluster-stat-label">Mortalidade infantil</p><p class="cluster-stat-value">${c.mortalidade_infantil_media.toFixed(1)}</p></div>
          <div><p class="cluster-stat-label">PIB per capita</p><p class="cluster-stat-value">${formatarPib(c.pib_per_capita_medio)}</p></div>
          <div><p class="cluster-stat-label">Gasto em saúde</p><p class="cluster-stat-value">${formatarPib(c.gasto_saude_medio)}</p></div>
          <div><p class="cluster-stat-label">Obesidade</p><p class="cluster-stat-value">${c.obesidade_media.toFixed(1)}%</p></div>
          <div><p class="cluster-stat-label">Tabagismo</p><p class="cluster-stat-value">${c.tabagismo_medio.toFixed(1)}%</p></div>
        </div>
        <button type="button" class="cluster-toggle" data-cluster="${c.cluster}">Ver os ${paisesDoCluster.length} países &darr;</button>
        <div class="cluster-country-list" id="lista-cluster-${c.cluster}">${tagsPaises}</div>
      </div>
    `;
  }).join('');

  container.querySelectorAll('.cluster-toggle').forEach(botao => {
    botao.addEventListener('click', () => {
      const lista = document.getElementById(`lista-cluster-${botao.dataset.cluster}`);
      const aberto = lista.classList.toggle('open');
      const nPaises = lista.children.length;
      botao.textContent = aberto ? `Ocultar países ${String.fromCharCode(8593)}` : `Ver os ${nPaises} países ${String.fromCharCode(8595)}`;
    });
  });
}

async function iniciarPerfis() {
  try {
    const [clusters, paises] = await Promise.all([
      carregarJSONProfiles('data/clusters.json'),
      carregarJSONProfiles('data/countries.json')
    ]);

    const clustersOrdenados = [...clusters].sort((a, b) => b.expectativa_vida_media - a.expectativa_vida_media);

    const corPorCluster = {};
    clustersOrdenados.forEach((c, i) => { corPorCluster[c.cluster] = GRADIENTE_CLUSTER[i]; });

    const paisesPorCluster = {};
    paises.forEach(p => {
      if (!paisesPorCluster[p.cluster]) paisesPorCluster[p.cluster] = [];
      paisesPorCluster[p.cluster].push(p.nome);
    });
    Object.values(paisesPorCluster).forEach(lista => lista.sort());

    desenharScatterPCA(paises, corPorCluster);
    renderizarLegenda(clustersOrdenados, corPorCluster);
    renderizarCardsCluster(clustersOrdenados, corPorCluster, paisesPorCluster);
  } catch (erro) {
    console.error('Erro ao iniciar Health Profiles:', erro);
  }
}

document.addEventListener('DOMContentLoaded', iniciarPerfis);
