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

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    veri_json(405, false, 'Use POST');
}

veri_exigir_token();

$raw = file_get_contents('php://input') ?: '';
$body = json_decode($raw, true);
if (!is_array($body)) {
    veri_json(400, false, 'JSON inválido');
}

$registros = $body['registros'] ?? null;
if (!is_array($registros)) {
    $registros = isset($body['uuid']) ? [$body] : [];
}
if ($registros === []) {
    veri_json(400, false, 'No hay registros');
}
if (count($registros) > 200) {
    veri_json(400, false, 'Lote muy grande: máximo 200');
}

$conn = veri_conectar();
if (!$conn) {
    veri_json(500, false, 'Error de conexión a la base de datos');
}
if (!veri_tabla_existe($conn, 'veri_evento')) {
    mysqli_close($conn);
    veri_json(500, false, 'Falta la tabla veri_evento');
}

$resultados = [];
$ok = 0;
foreach ($registros as $item) {
    if (!is_array($item)) {
        $resultados[] = ['id' => '', 'ok' => false, 'message' => 'Registro inválido'];
        continue;
    }
    $res = veri_insertar_evento($conn, $item);
    $resultados[] = $res;
    if (!empty($res['ok'])) {
        $ok++;
    }
}
mysqli_close($conn);

veri_json($ok > 0 ? 200 : 400, $ok > 0, $ok > 0 ? 'Guardado' : 'No se guardó', [
    'resultados' => $resultados,
    'ok' => $ok,
    'total' => count($resultados),
]);
