<?php
/**
 * Listado JSON de planificaciones (portal + consultas internas).
 *
 * Desplegar en:
 *   .../sanidad/flutter/bioseguridad/listar_planificaciones_bioseguridad_movil.php
 *
 * Parámetros GET: desde, hasta (YYYY-MM-DD), granja (opc.), q (buscar texto).
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
require_once __DIR__ . '/php/planificacion_movil_lib.php';

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

$desde = trim((string) ($_GET['desde'] ?? date('Y-m-d')));
$hasta = trim((string) ($_GET['hasta'] ?? $desde));
$granja = trim((string) ($_GET['granja'] ?? ''));
$q = trim((string) ($_GET['q'] ?? ''));

if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $desde)) {
    $desde = date('Y-m-d');
}
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $hasta)) {
    $hasta = $desde;
}
if ($hasta < $desde) {
    [$desde, $hasta] = [$hasta, $desde];
}

try {
    $filas = bio_plan_listado_portal($conexion, $desde, $hasta, $granja, $q);
    echo json_encode([
        'success' => true,
        'desde' => $desde,
        'hasta' => $hasta,
        'total' => count($filas),
        'visitas' => $filas,
    ], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'No se pudo listar la planificación',
    ], JSON_UNESCAPED_UNICODE);
}
