<?php
declare(strict_types=1);

/**
 * Proyección granjas / campañas / CENCOS por fecha (app Seguimiento de crianza).
 *
 * Desplegar junto con acl_mis_zonas.php (mz_proyeccion_movil_por_fecha).
 */
ob_start();
require_once __DIR__ . '/auth_movil.php';
sc_cors_headers();
date_default_timezone_set('America/Lima');

sc_validate_bearer_token();

include_once __DIR__ . '/../../../conexion_grs/conexion.php';
require_once __DIR__ . '/../../includes/modals/cencos_proyeccion_lib.php';

$fecha = trim((string) ($_GET['fecha'] ?? date('Y-m-d')));
$usuario = trim((string) ($_GET['usuario'] ?? ''));

$conn = conectar_joya_mysqli();
if (!$conn) {
    sc_send_json(500, false, 'Error de conexión a la base de datos');
}

mysqli_set_charset($conn, 'latin1');

$r = sip_cencos_proyeccion_fetch($conn, $fecha, [
    'usuario' => $usuario,
    'filtrar_zonas' => ($usuario !== ''),
    'fallback_catalogo' => true,
]);

require_once __DIR__ . '/../../modules/configuracion/mis_zonas/acl_mis_zonas.php';

if (function_exists('mz_proyeccion_movil_por_fecha')) {
    $r = mz_proyeccion_movil_por_fecha($conn, $usuario, $r, $fecha);
} elseif (function_exists('mz_proyeccion_merge_historico_anual')) {
    $r = mz_proyeccion_merge_historico_anual($conn, $usuario, $r, $fecha);
}

$conn->close();

if (empty($r['ok'])) {
    sc_send_json(400, false, (string) ($r['message'] ?? 'No se pudo cargar proyección'), sc_utf8([
        'cencos' => [],
        'granjas' => [],
        'campanias_por_granja' => [],
    ]));
}

sc_send_json(200, true, 'Proyección cargada', sc_utf8([
    'fecha' => $fecha,
    'cencos' => $r['cencos'] ?? [],
    'granjas' => $r['granjas'] ?? [],
    'campanias_por_granja' => $r['campanias_por_granja'] ?? [],
    'campania_sugerida_por_granja' => $r['campania_sugerida_por_granja'] ?? [],
    'message' => trim((string) ($r['message'] ?? '')),
]));
