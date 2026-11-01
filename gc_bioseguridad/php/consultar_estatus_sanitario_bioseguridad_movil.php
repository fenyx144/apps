<?php
declare(strict_types=1);

/**
 * «Estatus Sanitario Granja» para el control de ingreso de la app.
 *
 * Consulta informativa (solo lectura): ¿la granja del registro tiene un estatus
 * vigente y alguno de los DNIs viene de otra granja en situación especial?
 * La app muestra la etiqueta y guarda el ingreso igual: nunca bloquea.
 *
 * Parámetros (GET, POST de formulario o JSON):
 *   fecha   AAAA-MM-DD del registro de ingreso (por defecto hoy)
 *   granja  código de 3 dígitos de la granja que se está registrando
 *   dnis    lista de DNIs (arreglo JSON o separados por coma)
 *   placas  lista de placas de los vehículos del ingreso (arreglo JSON o
 *           separadas por coma), para el aviso de situación especial del vehículo
 *   campania campaña de la granja que se registra (para aviso de orden de edad)
 *
 * Siempre que la app esté autorizada responde 200: si las tablas del estatus no
 * existen o la consulta falla, `data.disponible = false` y la app no avisa nada.
 */

ob_start();
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

include_once __DIR__ . '/../../../conexion_grs/conexion.php';
require_once __DIR__ . '/estatus_sanitario_movil_lib.php';
require_once __DIR__ . '/orden_edad_movil_lib.php';

$raw = file_get_contents('php://input');
$input = bio_json_decode($raw);
if ($input === null) {
    $input = $_POST;
}
$param = static function (string $k) use ($input) {
    return $input[$k] ?? $_GET[$k] ?? null;
};

$fecha = bio_norm_fecha((string) ($param('fecha') ?? ''));
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $fecha)) {
    $fecha = date('Y-m-d');
}
$granja = preg_replace('/\D+/', '', (string) ($param('granja') ?? '')) ?? '';
$granja = $granja !== '' ? bio_norm_granja($granja) : '';
$dnisRaw = $param('dnis') ?? [];
$dnis = is_array($dnisRaw) ? $dnisRaw : explode(',', (string) $dnisRaw);
$dnis = array_slice($dnis, 0, 60);
$placasRaw = $param('placas') ?? [];
$placas = is_array($placasRaw) ? $placasRaw : explode(',', (string) $placasRaw);
$placas = array_slice($placas, 0, 20);
$campania = bio_norm_campania((string) ($param('campania') ?? ''));

$neutro = [
    'disponible' => false,
    'fecha' => $fecha,
    'granja' => $granja,
    'granjaEnEstatus' => null,
    'dnis' => (object) [],
    'placas' => (object) [],
    'ordenEdad' => [
        'disponible' => false,
        'fecha' => $fecha,
        'granja' => $granja,
        'campania' => $campania,
        'edadGranja' => null,
        'dnis' => (object) [],
        'placas' => (object) [],
    ],
];

try {
    if (!function_exists('conectar_joya_mysqli')) {
        bio_send_json(200, true, 'Estatus sanitario no disponible', $neutro);
    }
    $conn = conectar_joya_mysqli();
    if (!$conn) {
        bio_send_json(200, true, 'Estatus sanitario no disponible', $neutro);
    }
    $data = bio_es_consultar($conn, $fecha, $granja, $dnis, $placas);
    try {
        $data['ordenEdad'] = bio_oe_consultar($conn, $fecha, $granja, $campania, $dnis, $placas);
    } catch (Throwable $eOrd) {
        error_log('[bioseguridad] consultar_estatus orden_edad: ' . $eOrd->getMessage());
        $data['ordenEdad'] = $neutro['ordenEdad'];
    }
    $conn->close();
} catch (Throwable $e) {
    error_log('[bioseguridad] consultar_estatus_sanitario: ' . $e->getMessage());
    bio_send_json(200, true, 'Estatus sanitario no disponible', $neutro);
}

bio_send_json(
    200,
    true,
    $data['disponible'] ? 'Estatus sanitario consultado' : 'Estatus sanitario no disponible',
    $data
);
