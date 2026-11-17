<?php
declare(strict_types=1);

/**
 * Doble escritura de la anomalía de un artículo: rgarita y san_agentes_causales.
 * anomalia y agenteCausal (o agente_causal) son opcionales.
 */

ob_start();
require_once __DIR__ . '/php7_compat.php';
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/bioseguridad_movil_lib.php';
require_once __DIR__ . '/bio_articulos_agc_lib.php';

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

$raw = file_get_contents('php://input');
$body = json_decode($raw ? $raw : '', true);
if (!is_array($body)) {
    $body = $_POST;
}
if (!is_array($body)) {
    bio_send_json(400, false, 'JSON inválido');
}

$res = bio_art_agc_guardar($conn, $body);
$conn->close();
if (empty($res['ok'])) {
    bio_send_json(500, false, (string) (isset($res['message']) ? $res['message'] : 'No se pudo guardar'));
}

bio_send_json(200, true, 'Anomalía registrada', array(
    'id' => (string) (isset($res['id']) ? $res['id'] : ''),
));
