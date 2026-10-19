// =============================================================================
// projections.js — Health Inequality Explorer
// Comparação de técnicas de projeção (PCA, t-SNE, UMAP) com coloração por
// diferentes algoritmos de clusterização. Dados: data/projecoes.json, gerado
// por R/09_projecoes_clusterizacao.R.
//
// Cuidados de leitura embutidos na interface: eixos de t-SNE/UMAP não têm
// interpretação, só a vizinhança local vale; as métricas vêm de uma execução
// com parâmetros fixos e variam com eles (ver tabela de sensibilidade).
// =============================================================================

(function () {
  const PALETA_GRADIENTE = ['#1F6F5C', '#8A9B5C', '#C98A2B', '#B5451F']; // mesma de profiles.js
  const PALETA_HDBSCAN = ['#3E6D9C', '#8C5E8C', '#6B8E7F'];
  const COR_RUIDO = '#B9AE9A';

  const METODOS = [
    { chave: 'pca', rotulo: 'PCA', eixos: 'eixos = componentes principais' },
    { chave: 'tsne', rotulo: 't-SNE', eixos: 'eixos sem interpretação' },
    { chave: 'umap', rotulo: 'UMAP', eixos: 'eixos sem interpretação' }
  ];

  const ALGORITMOS = [
    { chave: 'cluster_kmeans_6d', rotulo: 'K-Means nas 6 variáveis' },
    { chave: 'cluster_fase7', rotulo: 'K-Means em PC1/PC2 (seções acima)' },
    { chave: 'cluster_ward', rotulo: 'Hierárquico (Ward)' },
    { chave: 'cluster_pam', rotulo: 'PAM (K-medoides)' },
    { chave: 'cluster_gmm', rotulo: 'Misturas gaussianas (GMM)' },
    { chave: 'cluster_hdbscan', rotulo: 'HDBSCAN (densidade)' }
  ];

  const estado = { dados: null, corPorCluster: {}, nomePorCluster: {}, modo: 'lado', algoritmo: 'cluster_kmeans_6d', destaque: '' };

  function escapar(texto) {
    return String(texto).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  async function carregar(caminho) {
    const resposta = await fetch(`${caminho}?v=${Date.now()}`);
    if (!resposta.ok) throw new Error(`Falha ao carregar ${caminho}`);
    return resposta.json();
  }

  function corDoPais(pais) {
    const rotulo = pais[estado.algoritmo];
    if (estado.algoritmo === 'cluster_hdbscan') {
      return rotulo === 0 ? COR_RUIDO : PALETA_HDBSCAN[(rotulo - 1) % PALETA_HDBSCAN.length];
    }
    return estado.corPorCluster[rotulo] || COR_RUIDO;
  }

  function desenharPainel(metodo, grande) {
    const largura = grande ? 900 : 420;
    const altura = grande ? 520 : 360;
    const margem = grande ? 28 : 16;
    const raio = grande ? 5.5 : 3.8;
    const paises = estado.dados.paises;

    const xs = paises.map(p => p[metodo.chave][0]);
    const ys = paises.map(p => p[metodo.chave][1]);
    const xMin = Math.min(...xs), xMax = Math.max(...xs);
    const yMin = Math.min(...ys), yMax = Math.max(...ys);
    const sx = v => margem + ((v - xMin) / (xMax - xMin)) * (largura - 2 * margem);
    const sy = v => altura - margem - ((v - yMin) / (yMax - yMin)) * (altura - 2 * margem);

    const pontos = paises.map(p => {
      const [x, y] = p[metodo.chave];
      return `<circle cx="${sx(x).toFixed(1)}" cy="${sy(y).toFixed(1)}" r="${raio}" fill="${corDoPais(p)}" fill-opacity="0.82"><title>${escapar(p.nome)}</title></circle>`;
    }).join('');

    let destaque = '';
    if (estado.destaque) {
      const alvo = paises.find(p => p.iso3 === estado.destaque);
      if (alvo) {
        const cx = sx(alvo[metodo.chave][0]);
        const cy = sy(alvo[metodo.chave][1]);
        const noLadoDireito = cx > largura * 0.7;
        destaque = `
          <circle cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="${raio + 4}" fill="none" stroke="#2A2015" stroke-width="1.6"/>
          <text x="${(cx + (noLadoDireito ? -(raio + 8) : raio + 8)).toFixed(1)}" y="${(cy - raio - 4).toFixed(1)}" text-anchor="${noLadoDireito ? 'end' : 'start'}" class="proj-destaque-label">${escapar(alvo.nome)}</text>`;
      }
    }

    return `
      <figure class="proj-painel ${grande ? 'proj-painel-grande' : ''}">
        <figcaption class="proj-painel-titulo">${metodo.rotulo} <span>${metodo.eixos}</span></figcaption>
        <svg viewBox="0 0 ${largura} ${altura}" role="img" aria-label="Projeção ${metodo.rotulo} dos países, coloridos por grupo">${pontos}${destaque}</svg>
      </figure>`;
  }

  function desenharGrade() {
    const grade = document.getElementById('proj-grid');
    if (!grade) return;
    const escolhidos = estado.modo === 'lado' ? METODOS : METODOS.filter(m => m.chave === estado.modo);
    grade.className = `proj-grid ${estado.modo === 'lado' ? 'proj-grid-lado' : 'proj-grid-unico'}`;
    grade.innerHTML = escolhidos.map(m => desenharPainel(m, estado.modo !== 'lado')).join('');
  }

  function desenharLegenda() {
    const legenda = document.getElementById('proj-legenda');
    if (!legenda) return;
    const paises = estado.dados.paises;
    const contagem = {};
    paises.forEach(p => { contagem[p[estado.algoritmo]] = (contagem[p[estado.algoritmo]] || 0) + 1; });

    const rotulos = Object.keys(contagem).map(Number).sort((a, b) => a - b);
    legenda.innerHTML = rotulos.map(r => {
      let cor, nome;
      if (estado.algoritmo === 'cluster_hdbscan') {
        cor = r === 0 ? COR_RUIDO : PALETA_HDBSCAN[(r - 1) % PALETA_HDBSCAN.length];
        nome = r === 0 ? 'Ruído (sem grupo)' : `Grupo ${r}`;
      } else {
        cor = estado.corPorCluster[r] || COR_RUIDO;
        nome = estado.nomePorCluster[r] || `Grupo ${r}`;
      }
      return `<span class="pca-legend-item"><span class="pca-legend-dot" style="background:${cor}"></span>${escapar(nome)} (${contagem[r]})</span>`;
    }).join('');
  }

  function desenharMetricas() {
    const container = document.getElementById('proj-metricas');
    if (!container) return;
    const linhas = estado.dados.metricas;
    const projecoes = linhas.filter(l => l.metodo !== 'Espaço original (6D)');
    const colunas = [
      { chave: 'trustworthiness', rotulo: 'Trustworthiness', dica: 'Quão poucos "falsos vizinhos" a projeção cria (1 = nenhum).' },
      { chave: 'continuity', rotulo: 'Continuity', dica: 'Quão poucos vizinhos reais a projeção separa (1 = nenhum).' },
      { chave: 'consistencia_vizinhos', rotulo: 'Vizinhos do mesmo grupo', dica: 'Fração dos 10 vizinhos mais próximos que pertencem ao mesmo grupo.' },
      { chave: 'silhueta_2d', rotulo: 'Silhueta 2D', dica: 'Separação dos grupos no plano (maior = mais separados).' }
    ];
    const melhor = {};
    colunas.forEach(c => { melhor[c.chave] = Math.max(...projecoes.map(l => l[c.chave])); });

    const cabecalho = colunas.map(c => `<th title="${escapar(c.dica)}">${c.rotulo}</th>`).join('');
    const corpo = linhas.map(l => {
      const referencia = l.metodo === 'Espaço original (6D)';
      const celulas = colunas.map(c => {
        const destaque = !referencia && l[c.chave] === melhor[c.chave];
        return `<td class="${destaque ? 'proj-melhor' : ''}">${l[c.chave].toFixed(3)}</td>`;
      }).join('');
      return `<tr class="${referencia ? 'proj-referencia' : ''}"><th scope="row">${escapar(l.metodo)}</th>${celulas}</tr>`;
    }).join('');

    container.innerHTML = `<table class="proj-tabela"><thead><tr><th>Técnica</th>${cabecalho}</tr></thead><tbody>${corpo}</tbody></table>`;

    const p = estado.dados.parametros;
    const nota = document.getElementById('proj-nota');
    if (nota) {
      nota.innerHTML = `Valores em negrito = melhor entre as três projeções. Parâmetros desta execução: t-SNE com perplexity ${p.perplexity}, UMAP com n_neighbors ${p.n_neighbors}, vizinhança de ${p.k_vizinhos_metricas} países. Os resultados de t-SNE e UMAP variam com esses parâmetros — a análise de sensibilidade completa está em <code>outputs/tables/projecoes_sensibilidade_parametros.csv</code>. A silhueta 2D costuma superar a do espaço original (6D): t-SNE e UMAP tendem a exagerar a separação visual entre grupos.`;
    }
  }

  function redesenhar() {
    desenharGrade();
    desenharLegenda();
  }

  function configurarControles() {
    const modo = document.getElementById('proj-modo');
    if (modo) {
      modo.querySelectorAll('.filter-chip').forEach(botao => {
        botao.addEventListener('click', () => {
          modo.querySelectorAll('.filter-chip').forEach(b => b.classList.remove('active'));
          botao.classList.add('active');
          estado.modo = botao.dataset.modo;
          redesenhar();
        });
      });
    }

    const seletorAlg = document.getElementById('proj-algoritmo');
    if (seletorAlg) {
      seletorAlg.innerHTML = ALGORITMOS.map(a => `<option value="${a.chave}">${a.rotulo}</option>`).join('');
      seletorAlg.addEventListener('change', () => { estado.algoritmo = seletorAlg.value; redesenhar(); });
    }

    const seletorPais = document.getElementById('proj-destaque');
    if (seletorPais) {
      const ordenados = [...estado.dados.paises].sort((a, b) => a.nome.localeCompare(b.nome));
      seletorPais.innerHTML = '<option value="">Nenhum</option>' +
        ordenados.map(p => `<option value="${p.iso3}">${escapar(p.nome)}</option>`).join('');
      seletorPais.addEventListener('change', () => { estado.destaque = seletorPais.value; redesenhar(); });
    }
  }

  async function iniciar() {
    const grade = document.getElementById('proj-grid');
    if (!grade) return;
    try {
      const [dados, clusters] = await Promise.all([carregar('data/projecoes.json'), carregar('data/clusters.json')]);
      estado.dados = dados;

      // Mesma lógica de cores de profiles.js: clusters ordenados por expectativa de vida
      [...clusters].sort((a, b) => b.expectativa_vida_media - a.expectativa_vida_media)
        .forEach((c, i) => {
          estado.corPorCluster[c.cluster] = PALETA_GRADIENTE[i];
          estado.nomePorCluster[c.cluster] = c.nome_cluster;
        });

      configurarControles();
      redesenhar();
      desenharMetricas();
    } catch (erro) {
      console.error('Erro ao iniciar comparação de projeções:', erro);
      grade.innerHTML = `<p class="heatmap-erro">Não foi possível carregar a comparação de projeções (${escapar(erro.message)}). Rode R/09_projecoes_clusterizacao.R para gerar data/projecoes.json.</p>`;
    }
  }

  document.addEventListener('DOMContentLoaded', iniciar);
})();
