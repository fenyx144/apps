/**
 * Listado de planificaciones (pestaña Planificación).
 * Estilos: reutilizar clases .bio-filtros-row / .bio-tabla del módulo bioseguridad.
 */
(function () {
  const urlBase = window.BIO_PLAN_LISTADO_URL || '';
  const $desde = document.getElementById('bio-plan-desde');
  const $hasta = document.getElementById('bio-plan-hasta');
  const $granja = document.getElementById('bio-plan-granja');
  const $q = document.getElementById('bio-plan-q');
  const $btn = document.getElementById('bio-plan-buscar');
  const $tbody = document.getElementById('bio-plan-tbody');
  const $vacio = document.getElementById('bio-plan-vacio');

  function hoyLocal() {
    const d = new Date();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  function esc(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/"/g, '&quot;');
  }

  function render(filas) {
    if (!$tbody) return;
    $tbody.innerHTML = '';
    if (!filas.length) {
      if ($vacio) $vacio.hidden = false;
      return;
    }
    if ($vacio) $vacio.hidden = true;
    for (const v of filas) {
      const tr = document.createElement('tr');
      const prov =
        (v.razonsocial || v.proveedor || '').trim() ||
        (v.motivo || '').trim();
      const gal =
        (v.galpones && v.galpones.length
          ? v.galpones.join(', ')
          : v.galpon || '') || '—';
      const placas =
        (v.placas && v.placas.length ? v.placas.join(', ') : v.placa) || '—';
      const np =
        (v.personas && v.personas.length) ||
        (v.numpersonas ? Number(v.numpersonas) : 0);
      tr.innerHTML =
        `<td>${esc(v.fecha)}</td>` +
        `<td>${esc(v.granja)} ${esc(v.nombreGranja)}</td>` +
        `<td>${esc(v.campania)}</td>` +
        `<td>${esc(prov)}</td>` +
        `<td>${esc(gal)}</td>` +
        `<td>${esc(placas)}</td>` +
        `<td>${esc(np)}</td>` +
        `<td>${esc(v.registradoPor)}</td>`;
      $tbody.appendChild(tr);
    }
  }

  async function cargar() {
    if (!urlBase) return;
    const params = new URLSearchParams({
      desde: $desde?.value || hoyLocal(),
      hasta: $hasta?.value || hoyLocal(),
      granja: ($granja?.value || '').trim(),
      q: ($q?.value || '').trim(),
    });
    const res = await fetch(`${urlBase}?${params.toString()}`, {
      credentials: 'same-origin',
    });
    const data = await res.json();
    if (!data.success) {
      render([]);
      return;
    }
    render(data.visitas || []);
  }

  const hoy = hoyLocal();
  if ($desde && !$desde.value) $desde.value = hoy;
  if ($hasta && !$hasta.value) $hasta.value = hoy;
  $btn?.addEventListener('click', () => cargar());
  $q?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') cargar();
  });
  cargar();
})();
