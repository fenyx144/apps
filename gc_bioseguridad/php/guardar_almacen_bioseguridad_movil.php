<?php
declare(strict_types=1);

/**
 * Registra movimientos de almacén. El rol se valida en el servidor (403).
 * POST { operacion, granja_cod, categoria, item, cantidad, fecha, ... }
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

if (!bio_alm_tabla($conn, 'bio_almacen_mov')) {
    bio_send_json(200, false, 'Migración 015 no aplicada', null, 'SIN_TABLA');
}

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
$actor = bio_alm_actor($conn, $usuario);
if ($actor['rol'] !== 'grs' && $actor['rol'] !== 'empresa') {
    bio_send_json(403, false, 'No autorizado', null, 'forbidden');
}

$resultados = array();
foreach ($ops as $op) {
    if (!is_array($op)) {
        continue;
    }
    $r = bio_alm_guardar($conn, $op, $usuario);
    if (!empty($r['http']) && (int) $r['http'] === 403) {
        bio_send_json(403, false, (string) $r['message'], null, 'forbidden');
    }
    $uuid = '';
    if (isset($op['uuid'])) {
        $uuid = (string) $op['uuid'];
    } elseif (isset($op['id'])) {
        $uuid = (string) $op['id'];
    }
    $resultados[] = array(
        'uuid' => isset($r['uuid']) ? $r['uuid'] : $uuid,
        'ok' => !empty($r['ok']),
        'message' => isset($r['message']) ? $r['message'] : '',
        'par_id' => isset($r['par_id']) ? $r['par_id'] : 0,
    );
}

bio_send_json(200, true, 'Almacén', array('resultados' => $resultados));
