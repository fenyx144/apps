<?php
declare(strict_types=1);

ob_start();
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Authorization, Content-Type, X-Requested-With');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(200);
    exit;
}
header('Content-Type: application/json; charset=utf-8');
error_reporting(E_ALL);
ini_set('display_errors', '0');
date_default_timezone_set('America/Lima');

include_once __DIR__ . '/../../../conexion_grs/conexion.php';
require_once __DIR__ . '/verificacion_movil_lib.php';
require_once __DIR__ . '/../g_app_version_lib.php';

veri_exigir_token();

$tcod = trim((string) ($_GET['tcod'] ?? $_GET['app'] ?? ''));
$version = trim((string) ($_GET['version'] ?? ''));
$avisoDesde = trim((string) ($_GET['version_warning_desde'] ?? ''));
$avisoParam = $avisoDesde !== '' ? $avisoDesde : null;

if ($tcod === '') {
    veri_json(400, false, 'Indique tcod (código de app).');
}

$conn = conectar_joya_mysqli();
if (!$conn) {
    veri_json(500, false, 'Error de conexión');
}

$clientVersion = $version !== '' ? $version : '0.0.0';
$eval = g_app_evaluar_version($conn, $tcod, $clientVersion, $avisoParam);
$row = g_app_fetch_activa($conn, $tcod);
$conn->close();

$payload = g_app_payload_movil($eval, $tcod);
if (is_array($row)) {
    $payload['tmejoradev'] = trim((string) ($row['tmejoradev'] ?? '')) ?: null;
    $payload['tmejorauser'] = trim((string) ($row['tmejorauser'] ?? '')) ?: null;
}

veri_json(200, true, 'OK', $payload);
