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

veri_exigir_token();

$conn = veri_conectar();
if (!$conn) {
    veri_json(500, false, 'Error de conexión a la base de datos');
}
if (!veri_tablas_ok($conn)) {
    mysqli_close($conn);
    veri_json(500, false, 'Faltan las tablas veri_* en la base de datos');
}

$roster = veri_roster($conn);
$plantillas = veri_plantillas($conn, array_keys($roster));
$version = veri_diff_and_log($conn, $roster);
$total = count($roster);
$usuario = trim((string) ($_GET['usuario'] ?? ''));
$puede = veri_puede_enrolar($conn, $usuario);

$desdeRaw = trim((string) ($_GET['desde'] ?? ''));
if ($desdeRaw === '') {
    $altas = [];
    foreach ($roster as $dni => $persona) {
        $altas[] = veri_alta_row($persona, $plantillas);
    }
    mysqli_close($conn);
    veri_json(200, true, 'Nómina completa', [
        'version' => (string) $version,
        'sin_cambios' => false,
        'full' => true,
        'altas' => $altas,
        'bajas' => [],
        'total' => $total,
        'puede_enrolar' => $puede,
    ]);
}

$desde = (int) $desdeRaw;
if ($desde >= $version) {
    mysqli_close($conn);
    veri_json(200, true, 'Sin cambios', [
        'version' => (string) $version,
        'sin_cambios' => true,
        'full' => false,
        'altas' => [],
        'bajas' => [],
        'total' => $total,
        'puede_enrolar' => $puede,
    ]);
}

$min = veri_min_seq($conn);
if ($desde < $min) {
    $altas = [];
    foreach ($roster as $dni => $persona) {
        $altas[] = veri_alta_row($persona, $plantillas);
    }
    mysqli_close($conn);
    veri_json(200, true, 'Nómina completa', [
        'version' => (string) $version,
        'sin_cambios' => false,
        'full' => true,
        'altas' => $altas,
        'bajas' => [],
        'total' => $total,
        'puede_enrolar' => $puede,
    ]);
}

$st = $conn->prepare('SELECT dni, accion FROM veri_nomina_cambio WHERE seq > ? ORDER BY seq ASC');
$acc = [];
if ($st) {
    $st->bind_param('i', $desde);
    $st->execute();
    $rs = $st->get_result();
    if ($rs) {
        while ($row = $rs->fetch_assoc()) {
            $acc[(string) $row['dni']] = (string) $row['accion'];
        }
    }
    $st->close();
}

$altas = [];
$bajas = [];
foreach ($acc as $dni => $a) {
    $dni = (string) $dni;
    if ($a === 'A' && isset($roster[$dni])) {
        $altas[] = veri_alta_row($roster[$dni], $plantillas);
    } else {
        $bajas[] = $dni;
    }
}
mysqli_close($conn);
veri_json(200, true, 'Cambios de nómina', [
    'version' => (string) $version,
    'sin_cambios' => false,
    'full' => false,
    'altas' => $altas,
    'bajas' => $bajas,
    'total' => $total,
    'puede_enrolar' => $puede,
]);
