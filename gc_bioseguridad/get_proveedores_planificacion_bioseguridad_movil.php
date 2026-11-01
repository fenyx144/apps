<?php
/**
 * Catálogo compacto: proveedores con usuario web que planifican visitas.
 *
 * Fuente: `san_usuario_proveedor` (codigo = usuario, columna `ruc`, `razonsocial`).
 *
 * Desplegar en:
 *   .../sanidad/flutter/bioseguridad/get_proveedores_planificacion_bioseguridad_movil.php
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

$sql = '
    SELECT DISTINCT
        TRIM(codigo) AS codigo,
        TRIM(ruc) AS ruc,
        TRIM(razonsocial) AS razonsocial
    FROM san_usuario_proveedor
    WHERE TRIM(razonsocial) <> \'\'
    ORDER BY razonsocial ASC
';

$result = mysqli_query($conexion, $sql);
if (!$result) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al consultar proveedores: ' . mysqli_error($conexion),
    ], JSON_UNESCAPED_UNICODE);
    mysqli_close($conexion);
    exit;
}

$items = [];
$vistos = [];
while ($row = mysqli_fetch_assoc($result)) {
    $nombre = trim((string) ($row['razonsocial'] ?? ''));
    if ($nombre === '') {
        continue;
    }
    $ruc = preg_replace('/\D/', '', (string) ($row['ruc'] ?? ''));
    if (strlen($ruc) !== 11) {
        continue;
    }
    $clave = 'r:' . $ruc;
    if (isset($vistos[$clave])) {
        continue;
    }
    $vistos[$clave] = true;
    $items[] = [
        'ruc' => $ruc,
        'razonsocial' => $nombre,
        'codigo' => trim((string) ($row['codigo'] ?? '')),
    ];
}

mysqli_free_result($result);
mysqli_close($conexion);

echo json_encode([
    'success' => true,
    'data' => [
        'items' => $items,
        'total' => count($items),
        'actualizadoEn' => date('c'),
    ],
], JSON_UNESCAPED_UNICODE);
