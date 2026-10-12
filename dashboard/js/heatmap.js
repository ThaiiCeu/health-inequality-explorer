// =============================================================================
// heatmap.js — Health Inequality Explorer
// Matriz país × indicador (técnica pixel-oriented de visualização
// multivariada — ver docs/METODOLOGIA.md e a seção "Técnica ou Sistema"
// do artigo para a justificativa de design).
//
// Cada linha é um país, cada coluna um dos 6 indicadores usados no PCA/
// clusterização, cada célula colorida pelo valor padronizado (z-score).
// Complementa o scatter de PCA acima: o scatter mostra a posição
// resumida em 2 dimensões, esta matriz mostra as 6 variáveis originais
// lado a lado, sem perda de informação por redução de dimensionalidade.
// =============================================================================

(function () {
  const CORES_CLUSTER_HEATMAP = ['#1F6F5C', '#8A9B5C', '#C98A2B', '#B5451F'];

  async function carregarDadosHeatmap() {
    const resposta = await fetch(`data/heatmap.json?v=${Date.now()}`);
    if (!resposta.ok) throw new Error('Falha ao carregar heatmap.json');
    return resposta.json();
  }

  // Escala de cor divergente: rust (z muito negativo) -> creme (z perto
  // de 0) -> teal (z muito positivo). Mesma lógica de "abaixo da média /
  // dentro da média / acima da média" usada no resto do dashboard, só
  // que contínua em vez de 3 categorias.
  function corParaZ(z) {
    const zClamp = Math.max(-2.5, Math.min(2.5, z));
    if (zClamp < 0) {
      const t = (zClamp + 2.5) / 2.5; // 0 (z=-2.5) -> 1 (z=0)
      return d3.interpolateRgb('#B5451F', '#F5EEE0')(t);
    } else {
      const t = zClamp / 2.5; // 0 (z=0) -> 1 (z=2.5)
      return d3.interpolateRgb('#F5EEE0', '#1F6F5C')(t);
    }
  }

  // Indicadores em que valor ALTO é desfavorável à saúde da população: a cor é
  // invertida para que verde signifique sempre "situação mais favorável".
  // O z-score mostrado no tooltip continua sendo o valor real (não invertido).
  const CHAVES_INVERTIDAS = ['mortalidade_infantil', 'prevalencia_obesidade', 'prevalencia_tabagismo'];

  // Países de referência rotulados à esquerda da matriz.
  const PAISES_REFERENCIA = ['JPN', 'DEU', 'USA', 'CHN', 'BRA', 'IND', 'ZAF', 'NGA', 'TCD'];

  function desenharHeatmap(dados) {
    const container = document.getElementById('heatmap-panel');
    if (!container) return;

    const indicadores = dados.indicadores;
    const paises = dados.paises;

    const larguraCol = 110;
    const alturaLabelTopo = 140;
    const larguraFaixaCluster = 8;
    const larguraGutter = 96;          // espaço para nomes de países de referência
    const xMatriz = larguraFaixaCluster + larguraGutter;
    const larguraTotal = xMatriz + indicadores.length * larguraCol + 24;
    const alturaLinha = 4;
    const alturaCabecalhoCluster = 22; // faixa com o nome de cada grupo, acima do bloco
    const margemInferior = 8;

    // Posição vertical de cada país, com um cabeçalho antes de cada cluster
    let y = 0;
    let clusterAnterior = null;
    const posicoes = paises.map(pais => {
      if (pais.cluster !== clusterAnterior) {
        y += alturaCabecalhoCluster;
        clusterAnterior = pais.cluster;
      }
      const topo = y;
      y += alturaLinha;
      return topo;
    });
    const alturaTotal = alturaLabelTopo + y + margemInferior;

    container.innerHTML = '';

    const svg = d3.select(container)
      .append('svg')
      .attr('viewBox', `0 0 ${larguraTotal} ${alturaTotal}`)
      .attr('width', '100%')
      .attr('role', 'img')
      .attr('aria-label', 'Matriz de países por indicador, colorida por valor padronizado');

    const tooltip = d3.select(container)
      .append('div')
      .attr('class', 'heatmap-tooltip')
      .style('opacity', 0);

    // Cabeçalho das colunas
    const cabecalho = svg.append('g').attr('transform', `translate(${xMatriz}, ${alturaLabelTopo - 8})`);
    indicadores.forEach((ind, i) => {
      const cx = i * larguraCol + 6;
      const invertido = CHAVES_INVERTIDAS.includes(ind.chave);
      cabecalho.append('text')
        .attr('x', cx)
        .attr('y', 0)
        .attr('text-anchor', 'start')
        .attr('transform', `rotate(-35, ${cx}, 0)`)
        .attr('class', 'heatmap-col-label')
        .text(invertido ? `${ind.rotulo} *` : ind.rotulo);
    });

    const corpo = svg.append('g').attr('transform', `translate(0, ${alturaLabelTopo})`);

    const contagem = {};
    paises.forEach(p => { contagem[p.cluster] = (contagem[p.cluster] || 0) + 1; });

    clusterAnterior = null;
    paises.forEach((pais, linha) => {
      const yLinha = posicoes[linha];
      const corCluster = CORES_CLUSTER_HEATMAP[(pais.cluster - 1) % CORES_CLUSTER_HEATMAP.length];

      // Cabeçalho do bloco: nome do grupo e número de países
      if (pais.cluster !== clusterAnterior) {
        corpo.append('text')
          .attr('x', larguraFaixaCluster + 6)
          .attr('y', yLinha - 7)
          .attr('class', 'heatmap-cluster-label')
          .attr('fill', corCluster)
          .text(`${pais.nome_cluster} (${contagem[pais.cluster]} países)`);
        clusterAnterior = pais.cluster;
      }

      // Faixa lateral de cor do cluster
      corpo.append('rect')
        .attr('x', 0).attr('y', yLinha)
        .attr('width', larguraFaixaCluster).attr('height', alturaLinha)
        .attr('fill', corCluster);

      // Nome dos países de referência
      if (PAISES_REFERENCIA.includes(pais.iso3)) {
        corpo.append('text')
          .attr('x', xMatriz - 4)
          .attr('y', yLinha + alturaLinha / 2 + 3)
          .attr('text-anchor', 'end')
          .attr('class', 'heatmap-pais-label')
          .text(pais.nome);
        corpo.append('line')
          .attr('x1', xMatriz - 2).attr('x2', xMatriz)
          .attr('y1', yLinha + alturaLinha / 2).attr('y2', yLinha + alturaLinha / 2)
          .attr('stroke', '#2A2015').attr('stroke-width', 0.8);
      }

      const linhaGrupo = corpo.append('g')
        .attr('class', 'heatmap-row')
        .on('mouseenter', function () {
          tooltip.style('opacity', 1).html(
            `<strong>${pais.nome}</strong><br>${pais.nome_cluster}<br>` +
            indicadores.map((ind, i) => `${ind.rotulo}: z = ${pais.valores[i].toFixed(2)}`).join('<br>')
          );
        })
        .on('mousemove', function (event) {
          const [mx, my] = d3.pointer(event, container);
          tooltip.style('left', `${mx + 16}px`).style('top', `${my + 8}px`);
        })
        .on('mouseleave', function () {
          tooltip.style('opacity', 0);
        });

      indicadores.forEach((ind, i) => {
        const z = CHAVES_INVERTIDAS.includes(ind.chave) ? -pais.valores[i] : pais.valores[i];
        linhaGrupo.append('rect')
          .attr('x', xMatriz + i * larguraCol)
          .attr('y', yLinha)
          .attr('width', larguraCol - 1)
          .attr('height', alturaLinha)
          .attr('fill', corParaZ(z));
      });
    });
  }

  function desenharLegendaHeatmap() {
    const legenda = document.getElementById('heatmap-legend');
    if (!legenda) return;
    legenda.innerHTML = `
      <span class="heatmap-legend-label">Menos favorável</span>
      <span class="heatmap-legend-swatch" style="background: linear-gradient(90deg, #B5451F, #F5EEE0, #1F6F5C);"></span>
      <span class="heatmap-legend-label">Mais favorável</span>
      <span class="heatmap-legend-note">Cor = valor padronizado (z-score) do país no indicador. * Em mortalidade infantil, obesidade e tabagismo, valor alto é desfavorável à saúde, então a escala é invertida (verde = menor valor). O tooltip mostra o z-score real. Linhas ordenadas por grupo e, dentro dele, por expectativa de vida.</span>
    `;
  }

  async function iniciarHeatmap() {
    const container = document.getElementById('heatmap-panel');
    if (!container) return;
    try {
      const dados = await carregarDadosHeatmap();
      desenharHeatmap(dados);
      desenharLegendaHeatmap();
    } catch (erro) {
      container.innerHTML = `<p class="heatmap-erro">Não foi possível carregar a matriz de indicadores (${erro.message}).</p>`;
    }
  }

  if (typeof d3 === 'undefined') {
    const painel = document.getElementById('heatmap-panel');
    if (painel) painel.innerHTML = '<p class="heatmap-erro">D3.js não carregou — a matriz não pode ser desenhada.</p>';
  } else {
    document.addEventListener('DOMContentLoaded', iniciarHeatmap);
  }
})();
