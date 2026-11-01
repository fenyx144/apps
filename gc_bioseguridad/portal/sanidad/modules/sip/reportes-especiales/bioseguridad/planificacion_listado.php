<?php
/**
 * Pestaña «Planificación» (listado con filtros).
 *
 * Copiar este archivo y `planificacion_listado.js` al servidor en:
 *   sanidad/modules/sip/reportes-especiales/bioseguridad/
 *
 * En el índice de bioseguridad física, registrar la pestaña ANTES de Ingreso /
 * Salida, apuntando el iframe o panel a este PHP (mismo patrón que Garita, Cerco, etc.).
 *
 * Requiere columna `galpon` en san_fact_planvisita_cab (sql/alter_planvisita_galpon.sql).
 */
declare(strict_types=1);

$baseUrl = '../../../flutter/bioseguridad/listar_planificaciones_bioseguridad_movil.php';
?>
<div id="bio-plan-listado" class="bio-reporte-panel">
  <div class="bio-filtros-row">
    <label>Desde <input type="date" id="bio-plan-desde" /></label>
    <label>Hasta <input type="date" id="bio-plan-hasta" /></label>
    <label>Granja
      <input type="text" id="bio-plan-granja" maxlength="10" placeholder="621" />
    </label>
    <label>Buscar
      <input type="search" id="bio-plan-q" placeholder="Proveedor, placa, galpón…" />
    </label>
    <button type="button" id="bio-plan-buscar" class="btn btn-primary btn-sm">Buscar</button>
  </div>
  <div class="table-responsive bio-tabla-wrap">
    <table class="table table-striped table-sm bio-tabla" id="bio-plan-tabla">
      <thead>
        <tr>
          <th>Fecha</th>
          <th>Granja</th>
          <th>Campaña</th>
          <th>Proveedor / motivo</th>
          <th>Galpones</th>
          <th>Placas</th>
          <th>Personas</th>
          <th>Registró</th>
        </tr>
      </thead>
      <tbody id="bio-plan-tbody"></tbody>
    </table>
  </div>
  <p id="bio-plan-vacio" class="text-muted small" hidden>Sin planificaciones para los filtros.</p>
</div>
<script>
  window.BIO_PLAN_LISTADO_URL = <?= json_encode($baseUrl, JSON_UNESCAPED_UNICODE) ?>;
</script>
<script src="planificacion_listado.js"></script>
