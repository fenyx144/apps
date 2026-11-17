<?php
declare(strict_types=1);

/**
 * Kardex y catálogo de almacén de una granja.
 * GET ?granja=001
 */

ob_start();
require_once __DIR__ . '/php7_compat.php';
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/bioseguridad_movil_lib.php';
require_once __DIR__ . '/almacen_movil_lib.php';

if (!function_exists('conectar_joya_mysqli')) {
    bio_send_json(200, false, 'sin señal', null, 'SIN_CONEXION');
}
$conn = conectar_joya_mysqli();
if (!$conn) {
    bio_send_json(200, false, 'sin señal', null, 'SIN_CONEXION');
}

bio_alm_asegurar($conn);
$granja = substr(trim((string) (isset($_GET['granja']) ? $_GET['granja'] : '')), 0, 20);

bio_send_json(200, true, 'Almacén', array(
    'granja' => $granja,
    'insumos' => bio_alm_insumos($conn),
    'kardex' => bio_alm_kardex($conn, $granja),
    'prestamos' => bio_alm_prestamos($conn, $granja),
));
