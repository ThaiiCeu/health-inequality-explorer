// =============================================================================
// map.js — Mapa Interativo
// =============================================================================

const URL_GEOJSON = 'https://raw.githubusercontent.com/johan/world.geo.json/master/countries.geo.json';

const NOMES_INDICADORES_MAPA = {
  expectativa_vida: 'Expectativa de vida (anos)',
  mortalidade_infantil: 'Mortalidade infantil (por 1.000)',
  prevalencia_obesidade: 'Prevalência de obesidade (%)',
  pib_per_capita_ppp: 'PIB per capita (US$ PPP)',
  gasto_saude_pc_ppp: 'Gasto em saúde per capita (US$ PPP)',
  prevalencia_tabagismo: 'Prevalência de tabagismo (%)'
};

let PAISES_MAPA = [];
let SERIE_MAPA = {};
let geojsonMundo = null;
let pathGenerator = null;

async function carregarJSONMapa(caminho) {
  const resposta = await fetch(`${caminho}?v=${Date.now()}`);
  if (!resposta.ok) throw new Error(`Falha ao carregar ${caminho}`);
  return resposta.json();
}

async function carregarGeoJSON() {
  const resposta = await fetch(URL_GEOJSON);
  if (!resposta.ok) throw new Error(`Falha ao carregar fronteiras mundiais: ${resposta.status}`);
  return resposta.json();
}

function popularSelectsFiltro() {
  const regioes = [...new Set(PAISES_MAPA.map(p => p.regiao))].sort();
  const selectRegiao = document.getElementById('map-region');
  regioes.forEach(r => {
    const opt = document.createElement('option');
    opt.value = r;
    opt.textContent = r;
    selectRegiao.appendChild(opt);
  });

  const clusters = [...new Set(PAISES_MAPA.map(p => p.nome_cluster))];
  const selectCluster = document.getElementById('map-cluster');
  clusters.forEach(c => {
    const opt = document.createElement('option');
    opt.value = c;
    opt.textContent = c;
    selectCluster.appendChild(opt);
  });
}

function valorParaPais(iso3, indicador, ano) {
  const serie = SERIE_MAPA[iso3]?.[indicador];
  if (!serie) return null;
  const idx = serie.anos.indexOf(ano);
  return idx === -1 ? null : serie.valores[idx];
}

function desenharMapaBase() {
  const svg = d3.select('#world-map');
  const largura = 960, altura = 500;

  const projecao = d3.geoNaturalEarth1().fitSize([largura, altura - 20], geojsonMundo);
  pathGenerator = d3.geoPath().projection(projecao);

  svg.selectAll('path')
    .data(geojsonMundo.features)
    .join('path')
    .attr('d', pathGenerator)
    .attr('data-iso3', d => d.id)
    .on('mousemove', mostrarTooltip)
    .on('mouseleave', ocultarTooltip)
    .on('click', (evento, d) => mostrarDetalhePais(d.id));

  atualizarCoresMapa();
}

function escalaCor(valor, min, max) {
  if (valor === null || min === max) return '#E4D9C5';
  const t = (valor - min) / (max - min);
  if (t < 0.5) {
    return d3.interpolateRgb('#FBF6EE', '#C98A2B')(t * 2);
  }
  return d3.interpolateRgb('#C98A2B', '#2A2015')((t - 0.5) * 2);
}

function atualizarCoresMapa() {
  const indicador = document.getElementById('map-indicator').value;
  const ano = parseInt(document.getElementById('map-year').value, 10);
  const regiaoFiltro = document.getElementById('map-region').value;
  const clusterFiltro = document.getElementById('map-cluster').value;

  const paisesPorIso3 = {};
  PAISES_MAPA.forEach(p => { paisesPorIso3[p.iso3] = p; });

  const valores = PAISES_MAPA
    .map(p => valorParaPais(p.iso3, indicador, ano))
    .filter(v => v !== null && v !== undefined);
  const min = Math.min(...valores);
  const max = Math.max(...valores);

  d3.select('#world-map').selectAll('path')
    .attr('fill', d => {
      const valor = valorParaPais(d.id, indicador, ano);
      return valor === null ? '#F1EDE3' : escalaCor(valor, min, max);
    })
    .classed('no-data', d => valorParaPais(d.id, indicador, ano) === null)
    .classed('dimmed', d => {
      const pais = paisesPorIso3[d.id];
      if (!pais) return false;
      const foraRegiao = regiaoFiltro !== 'todas' && pais.regiao !== regiaoFiltro;
      const foraCluster = clusterFiltro !== 'todos' && pais.nome_cluster !== clusterFiltro;
      return foraRegiao || foraCluster;
    });

  document.getElementById('map-legend').innerHTML = `
    <span>${min.toFixed(1)}</span>
    <span class="map-legend-gradient"></span>
    <span>${max.toFixed(1)}</span>
    <span style="margin-left:8px;">${NOMES_INDICADORES_MAPA[indicador]}</span>
  `;
}

function mostrarTooltip(evento, d) {
  const pais = PAISES_MAPA.find(p => p.iso3 === d.id);
  const tooltip = document.getElementById('map-tooltip');

  if (!pais) {
    tooltip.style.display = 'none';
    return;
  }

  const indicador = document.getElementById('map-indicator').value;
  const ano = parseInt(document.getElementById('map-year').value, 10);
  const valor = valorParaPais(pais.iso3, indicador, ano);

  tooltip.textContent = valor === null
    ? `${pais.nome} — sem dado em ${ano}`
    : `${pais.nome}: ${valor.toFixed(1)}`;
  tooltip.style.display = 'block';

  const containerRect = document.querySelector('.map-panel').getBoundingClientRect();
  tooltip.style.left = (evento.clientX - containerRect.left + 14) + 'px';
  tooltip.style.top = (evento.clientY - containerRect.top + 10) + 'px';
}

function ocultarTooltip() {
  document.getElementById('map-tooltip').style.display = 'none';
}

function mostrarDetalhePais(iso3) {
  const pais = PAISES_MAPA.find(p => p.iso3 === iso3);
  const container = document.getElementById('map-detail');

  if (!pais) {
    container.innerHTML = '<p class="map-detail-empty">Sem dados detalhados para este país no núcleo de análise.</p>';
    return;
  }

  container.innerHTML = `
    <p class="map-detail-name">${pais.nome}</p>
    <p class="map-detail-meta">${pais.regiao} · ${pais.nome_cluster} · ${pais.classificacao}</p>
    <div class="map-detail-stats">
      <div><p class="compare-stat-label">Expectativa de vida</p><p class="compare-stat-value">${pais.expectativa_vida.toFixed(1)} anos</p></div>
      <div><p class="compare-stat-label">Mortalidade infantil</p><p class="compare-stat-value">${pais.mortalidade_infantil.toFixed(1)}</p></div>
      <div><p class="compare-stat-label">PIB per capita</p><p class="compare-stat-value">$${Math.round(pais.pib_per_capita_ppp).toLocaleString('en-US')}</p></div>
      <div><p class="compare-stat-label">Gasto em saúde</p><p class="compare-stat-value">$${Math.round(pais.gasto_saude_pc_ppp).toLocaleString('en-US')}</p></div>
    </div>
  `;
}

function configurarControlesMapa() {
  document.getElementById('map-indicator').addEventListener('change', atualizarCoresMapa);
  document.getElementById('map-region').addEventListener('change', atualizarCoresMapa);
  document.getElementById('map-cluster').addEventListener('change', atualizarCoresMapa);

  const inputAno = document.getElementById('map-year');
  inputAno.addEventListener('input', () => {
    document.getElementById('map-year-label').textContent = inputAno.value;
    atualizarCoresMapa();
  });
}

async function iniciarMapa() {
  try {
    const [paises, serie, geojson] = await Promise.all([
      carregarJSONMapa('data/countries.json'),
      carregarJSONMapa('data/serie_temporal.json'),
      carregarGeoJSON()
    ]);

    PAISES_MAPA = paises;
    SERIE_MAPA = serie;
    geojsonMundo = geojson;

    popularSelectsFiltro();
    configurarControlesMapa();
    desenharMapaBase();
  } catch (erro) {
    console.error('Erro ao iniciar o mapa:', erro);
    document.getElementById('map-panel')?.insertAdjacentHTML(
      'afterend',
      '<p style="color:var(--rust-dark); font-size:13px;">Não foi possível carregar o mapa. Veja o console (F12) para detalhes — provavelmente uma falha ao buscar o arquivo de fronteiras mundiais (precisa de internet).</p>'
    );
  }
}

document.addEventListener('DOMContentLoaded', iniciarMapa);
