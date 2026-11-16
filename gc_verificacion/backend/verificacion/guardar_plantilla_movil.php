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

$dni = preg_replace('/\D/', '', (string) ($body['dni'] ?? '')) ?? '';
if (strlen($dni) !== 8) {
    veri_json(400, false, 'DNI no válido');
}

$nombre = veri_corte(trim((string) ($body['nombre'] ?? '')), 120);
if (mb_strlen($nombre) < 2) {
    veri_json(400, false, 'Nombre no válido');
}

$vector = $body['vector'] ?? null;
if (!is_array($vector) || count($vector) !== 512) {
    veri_json(400, false, 'Vector no válido: se esperan 512 valores');
}
$floats = [];
foreach (array_values($vector) as $v) {
    if (!is_numeric($v) || !is_finite((float) $v)) {
        veri_json(400, false, 'Vector no válido: valor no numérico');
    }
    $floats[] = (float) $v;
}
$vectorJson = json_encode($floats, JSON_UNESCAPED_UNICODE);
if (!is_string($vectorJson)) {
    veri_json(400, false, 'Vector no válido');
}

$miniatura = trim((string) ($body['miniatura'] ?? ''));
if ($miniatura !== '') {
    if (strlen($miniatura) > 150000) {
        veri_json(400, false, 'Miniatura muy pesada');
    }
    $bin = base64_decode($miniatura, true);
    if ($bin === false || strlen($bin) < 3 || substr($bin, 0, 3) !== "\xFF\xD8\xFF") {
        veri_json(400, false, 'Miniatura no válida: se espera JPEG en base64');
    }
}

$modelo = veri_corte(trim((string) ($body['modelo'] ?? '')), 40);
if ($modelo === '') {
    $modelo = 'arcface-w600k_mbf';
}
$usuario = veri_corte(trim((string) ($body['usuario'] ?? '')), 30);
$tidandroid = veri_corte(trim((string) ($body['tidandroid'] ?? '')), 80);

$conn = veri_conectar();
if (!$conn) {
    veri_json(500, false, 'Error de conexión a la base de datos');
}
if (!veri_tabla_existe($conn, 'veri_plantilla')) {
    mysqli_close($conn);
    veri_json(500, false, 'Falta la tabla veri_plantilla');
}
if (!veri_puede_enrolar($conn, $usuario)) {
    mysqli_close($conn);
    veri_json(403, false, 'No autorizado para enrolar');
}

$st = $conn->prepare(
    'INSERT INTO veri_plantilla (dni, nombre, vector, miniatura, modelo, estado, usuario, tidandroid) VALUES (?, ?, ?, ?, ?, \'A\', ?, ?) ' .
    'ON DUPLICATE KEY UPDATE nombre = VALUES(nombre), vector = VALUES(vector), miniatura = VALUES(miniatura), modelo = VALUES(modelo), estado = \'A\', usuario = VALUES(usuario), tidandroid = VALUES(tidandroid)'
);
if (!$st) {
    mysqli_close($conn);
    veri_json(500, false, 'Error al preparar: ' . $conn->error);
}
$st->bind_param('sssssss', $dni, $nombre, $vectorJson, $miniatura, $modelo, $usuario, $tidandroid);
$hecho = $st->execute();
$err = $st->error;
$st->close();
mysqli_close($conn);

if (!$hecho) {
    veri_json(500, false, 'No se guardó: ' . $err);
}
veri_json(200, true, 'Plantilla guardada', [
    'dni' => $dni,
    'updated_at' => date('Y-m-d H:i:s'),
]);
