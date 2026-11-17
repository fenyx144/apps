<?php
declare(strict_types=1);

/**
 * Contexto de almacén: rol, acciones, granjas, resumen, implementos, insumos y kardex.
 * GET ?granja_cod=&categoria=&desde=&hasta=
 */

ob_start();
require_once __DIR__ . '/php7_compat.php';
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/bioseguridad_movil_lib.php';
require_once __DIR__ . '/almacen_movil_lib.php';

if (!function_exists('conectar_joya_mysqli')) {
    bio_send_json(200, false, 'sin señal', null, 'SIN_CONEXION');
}
$conn = conectar_joya_mysqli();
if (!$conn) {
    bio_send_json(200, false, 'sin señal', null, 'SIN_CONEXION');
}

if (!bio_alm_tabla($conn, 'bio_almacen_mov')) {
    bio_send_json(200, false, 'Migración 015 no aplicada', null, 'SIN_TABLA');
}

$usuario = bio_alm_usuario();
$actor = bio_alm_actor($conn, $usuario);
if ($actor['rol'] !== 'grs' && $actor['rol'] !== 'empresa') {
    bio_send_json(403, false, 'No autorizado', null, 'forbidden');
}

$granja = substr(trim((string) (isset($_GET['granja_cod']) ? $_GET['granja_cod'] : (isset($_GET['granja']) ? $_GET['granja'] : ''))), 0, 20);
$categoria = isset($_GET['categoria']) ? (string) $_GET['categoria'] : '';
$desde = isset($_GET['desde']) ? (string) $_GET['desde'] : '';
$hasta = isset($_GET['hasta']) ? (string) $_GET['hasta'] : '';

$stock = bio_alm_stock($conn, $actor, $granja);
if (empty($stock['ok'])) {
    $http = isset($stock['http']) ? (int) $stock['http'] : 200;
    bio_send_json($http, false, (string) $stock['message'], null, $http === 403 ? 'forbidden' : null);
}
$kardex = bio_alm_kardex($conn, $actor, $granja, $categoria, $desde, $hasta);
if (empty($kardex['ok'])) {
    $http = isset($kardex['http']) ? (int) $kardex['http'] : 200;
    bio_send_json($http, false, (string) $kardex['message'], null, $http === 403 ? 'forbidden' : null);
}

$eid = $actor['rol'] === 'empresa' ? (int) $actor['empresa_id'] : 0;
bio_send_json(200, true, 'Almacén', array(
    'rol' => $stock['rol'],
    'acciones' => $stock['acciones'],
    'granja_cod' => $granja,
    'granjas' => $stock['granjas'],
    'resumen' => $stock['resumen'],
    'uniformes' => $stock['uniformes'],
    'implementos' => $stock['implementos'],
    'insumos' => $stock['insumos'],
    'ropa_tipos' => $stock['ropa_tipos'],
    'personal' => bio_alm_personal_granja($conn, $granja, $eid),
    'kardex' => $kardex['items'],
));
