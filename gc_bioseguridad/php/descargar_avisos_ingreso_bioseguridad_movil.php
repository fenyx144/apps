<?php
declare(strict_types=1);

/**
 * Descarga de los avisos del control de ingreso para trabajar sin señal:
 * granjas en situación especial, quién ingresó a ellas (últimos 30 días),
 * ingresos de hoy y edades de granja para el aviso de orden de edad.
 * Solo lectura.
 *
 * Parámetros (GET, POST de formulario o JSON):
 *   fecha     AAAA-MM-DD (por defecto hoy)
 *   destinos  lista «granja|campania» que el equipo puede registrar (Mis granjas)
 *
 * Si algo falla responde `data.disponible = false` y la app conserva lo que tenía.
 */

ob_start();
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

include_once __DIR__ . '/../../../conexion_grs/conexion.php';
require_once __DIR__ . '/avisos_ingreso_offline_lib.php';

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
$destRaw = $param('destinos') ?? [];
$destinos = is_array($destRaw) ? $destRaw : explode(',', (string) $destRaw);
$destinos = array_slice(array_map('strval', $destinos), 0, 60);

$neutro = ['disponible' => false, 'fecha' => $fecha];

try {
    if (!function_exists('conectar_joya_mysqli')) {
        bio_send_json(200, true, 'Avisos no disponibles', $neutro);
    }
    $conn = conectar_joya_mysqli();
    if (!$conn) {
        bio_send_json(200, true, 'Avisos no disponibles', $neutro);
    }
    $data = bio_av_descargar($conn, $fecha, $destinos);
    $conn->close();
} catch (Throwable $e) {
    error_log('[bioseguridad] descargar_avisos_ingreso: ' . $e->getMessage());
    bio_send_json(200, true, 'Avisos no disponibles', $neutro);
}

bio_send_json(200, true, 'Avisos descargados', $data);
