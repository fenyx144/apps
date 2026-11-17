<?php
declare(strict_types=1);

/**
 * Registra en san_agentes_causales la anomalía de alcoholemia.
 * anomalia y agenteCausal (o agente_causal) son opcionales.
 */

ob_start();
require_once __DIR__ . '/php7_compat.php';
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/bioseguridad_movil_lib.php';
require_once __DIR__ . '/bio_alcoholemia_agc_lib.php';

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

$res = bio_alc_guardar($conn, $body);
$conn->close();
if (empty($res['ok'])) {
    bio_send_json(500, false, (string) ($res['message'] ?? 'No se pudo guardar'));
}

bio_send_json(200, true, !empty($res['omitido']) ? 'Sin anomalía' : 'Anomalía registrada', array(
    'id' => (string) ($res['id'] ?? ''),
    'omitido' => !empty($res['omitido']),
));
