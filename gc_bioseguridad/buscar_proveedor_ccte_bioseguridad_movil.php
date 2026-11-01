<?php
/**
 * Búsqueda de proveedores (RUC / razón social) en maestro ccte.
 *
 * Solo filas con codigo de 11 dígitos (RUC). No descarga el catálogo completo:
 * la app envía un texto corto y el servidor devuelve hasta [limite] coincidencias.
 *
 * Desplegar en:
 *   .../sanidad/flutter/bioseguridad/buscar_proveedor_ccte_bioseguridad_movil.php
 *
 * Recomendado en BD: índice en TRIM(codigo) y/o nombre si la búsqueda es lenta.
 */
ob_start();

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Authorization, Content-Type, X-Requested-With');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

header('Content-Type: application/json; charset=utf-8');
error_reporting(E_ALL);
ini_set('display_errors', 0);

include_once '../../../conexion_grs_joya/conexion.php';
date_default_timezone_set('America/Lima');

$conexion = conectar_joya();

if (ob_get_level()) {
    ob_clean();
}

if (!$conexion) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error de conexión a la base de datos',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

mysqli_set_charset($conexion, 'latin1');

$raw = file_get_contents('php://input');
$body = json_decode($raw, true);
if (!is_array($body)) {
    $body = [];
}

$q = trim((string) ($body['q'] ?? ''));
$limite = (int) ($body['limite'] ?? 25);
if ($limite < 5) {
    $limite = 5;
}
if ($limite > 40) {
    $limite = 40;
}

if ($q === '') {
    echo json_encode([
        'success' => false,
        'message' => 'Escriba RUC o razón social.',
    ], JSON_UNESCAPED_UNICODE);
    mysqli_close($conexion);
    exit;
}

$digits = preg_replace('/\D/', '', $q);
$soloDigitos = ($digits !== '' && preg_match('/^[\d\s\.\-]+$/u', $q));
$tieneLetras = (bool) preg_match('/[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]/u', $q);
$longitud = mb_strlen($q, 'UTF-8');

if ($longitud < 3 && strlen($digits) !== 11) {
    echo json_encode([
        'success' => false,
        'message' => 'Escriba al menos 3 caracteres para buscar.',
    ], JSON_UNESCAPED_UNICODE);
    mysqli_close($conexion);
    exit;
}

$busqueda = [];
$tipos = '';
$params = [];

if ($soloDigitos && strlen($digits) >= 3) {
    $busqueda[] = 'TRIM(codigo) LIKE ?';
    $tipos .= 's';
    $params[] = $digits . '%';
}
if ($tieneLetras) {
    $busqueda[] = 'UPPER(nombre) LIKE ?';
    $tipos .= 's';
    $params[] = '%' . mb_strtoupper($q, 'UTF-8') . '%';
}

if ($busqueda === []) {
    echo json_encode([
        'success' => false,
        'message' => 'Escriba al menos 3 caracteres para buscar.',
    ], JSON_UNESCAPED_UNICODE);
    mysqli_close($conexion);
    exit;
}

$sql = '
    SELECT TRIM(codigo) AS ruc, TRIM(nombre) AS razonsocial
    FROM ccte
    WHERE CHAR_LENGTH(TRIM(codigo)) = 11
      AND (' . implode(' OR ', $busqueda) . ')
    ORDER BY razonsocial ASC
    LIMIT ?
';

$tipos .= 'i';
$params[] = $limite;

$stmt = mysqli_prepare($conexion, $sql);
if (!$stmt) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al preparar consulta: ' . mysqli_error($conexion),
    ], JSON_UNESCAPED_UNICODE);
    mysqli_close($conexion);
    exit;
}

mysqli_stmt_bind_param($stmt, $tipos, ...$params);
mysqli_stmt_execute($stmt);
$result = mysqli_stmt_get_result($stmt);

$items = [];
while ($row = mysqli_fetch_assoc($result)) {
    $ruc = preg_replace('/\D/', '', (string) ($row['ruc'] ?? ''));
    if (strlen($ruc) !== 11) {
        continue;
    }
    $nombre = trim((string) ($row['razonsocial'] ?? ''));
    if ($nombre === '') {
        continue;
    }
    $items[] = [
        'ruc' => $ruc,
        'razonsocial' => $nombre,
    ];
}

mysqli_stmt_close($stmt);
mysqli_close($conexion);

echo json_encode([
    'success' => true,
    'data' => [
        'items' => $items,
        'total' => count($items),
    ],
], JSON_UNESCAPED_UNICODE);
