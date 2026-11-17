<?php
declare(strict_types=1);

/**
 * Guarda uno o varios movimientos de almacén. El uuid deduplica la cola offline.
 * POST { uuid, granja, fecha, operacion, insumo_id, cantidad, dni, nombre }
 * o   { ops: [ ... ] }
 */

ob_start();
require_once __DIR__ . '/php7_compat.php';
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/bioseguridad_movil_lib.php';
require_once __DIR__ . '/almacen_movil_lib.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    bio_send_json(405, false, 'Use POST');
}

if (!function_exists('conectar_joya_mysqli')) {
    bio_send_json(200, false, 'sin señal', null, 'SIN_CONEXION');
}
$conn = conectar_joya_mysqli();
if (!$conn) {
    bio_send_json(200, false, 'sin señal', null, 'SIN_CONEXION');
}

bio_alm_asegurar($conn);

$raw = file_get_contents('php://input');
$body = json_decode($raw ? $raw : '', true);
if (!is_array($body)) {
    bio_send_json(400, false, 'JSON inválido');
}

$ops = array();
if (isset($body['ops']) && is_array($body['ops'])) {
    $ops = $body['ops'];
} else {
    $ops = array($body);
}

$usuario = bio_alm_usuario();
$resultados = array();
foreach ($ops as $op) {
    if (!is_array($op)) {
        continue;
    }
    $r = bio_alm_guardar($conn, $op, $usuario);
    $uuid = '';
    if (isset($op['uuid'])) {
        $uuid = (string) $op['uuid'];
    } elseif (isset($op['id'])) {
        $uuid = (string) $op['id'];
    }
    $resultados[] = array(
        'uuid' => isset($r['uuid']) ? $r['uuid'] : $uuid,
        'ok' => !empty($r['ok']),
        'duplicado' => !empty($r['duplicado']),
        'message' => isset($r['message']) ? $r['message'] : '',
    );
}

bio_send_json(200, true, 'Almacén', array('resultados' => $resultados));
