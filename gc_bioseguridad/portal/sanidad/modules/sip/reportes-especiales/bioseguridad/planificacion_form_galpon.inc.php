<?php
/**
 * Fragmento para el formulario de «Planificar llegada» en el portal.
 *
 * 1) Ejecutar sql/alter_planvisita_galpon.sql en la BD.
 * 2) Incluir este fragmento en la pantalla donde se guarda san_fact_planvisita_cab.
 * 3) Al guardar, persistir $_POST['galpones_plan'] (array) o galpon_plan (texto)
 *    en cab.galpon como lista separada por comas (máx. 120 caracteres).
 */
declare(strict_types=1);

/**
 * @param string[] $codigosGalpon
 */
function bio_plan_serializar_galpones(array $codigosGalpon): string
{
    // En servidor: sanidad/modules/sip/reportes-especiales/bioseguridad → flutter/bioseguridad/php
    require_once __DIR__ . '/../../../../flutter/bioseguridad/php/bio_plan_tablas_lib.php';
    $parts = [];
    foreach ($codigosGalpon as $g) {
        $g = trim((string) $g);
        if ($g !== '' && !in_array($g, $parts, true)) {
            $parts[] = $g;
        }
    }
    $txt = implode(', ', $parts);

    return mb_strlen($txt, 'UTF-8') > 120 ? mb_substr($txt, 0, 120, 'UTF-8') : $txt;
}

// Ejemplo de campo multi (adaptar IDs/clases al formulario existente):
// <select name="galpones_plan[]" multiple class="form-control" size="6">…</select>
// O picker de galpones por granja/campaña (mismo catálogo CENCOS que ingreso web).
