// =============================================================================
// methodology.js — accordion da seção Metodologia
// =============================================================================

function iniciarAccordion() {
  const gatilhos = document.querySelectorAll('.accordion-trigger');

  gatilhos.forEach(gatilho => {
    gatilho.addEventListener('click', () => {
      const painel = gatilho.nextElementSibling;
      const aberto = painel.classList.toggle('open');
      gatilho.setAttribute('aria-expanded', aberto ? 'true' : 'false');
    });
  });

  // Abre o primeiro item por padrão, para não ficar tudo colapsado
  if (gatilhos.length > 0) {
    gatilhos[0].click();
  }
}

document.addEventListener('DOMContentLoaded', iniciarAccordion);
