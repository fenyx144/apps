<?php
declare(strict_types=1);

/**
 * Descarga de la nómina DNI → proveedor para proponer el proveedor en un
 * ingreso no planificado (también sin señal). Solo lectura.
 *
 * Si algo falla responde `data.disponible = false` y la app conserva lo que tenía.
 */

ob_start();
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/nomina_proveedor_movil_lib.php';

$neutro = ['disponible' => false];

try {
    if (!function_exists('conectar_joya_mysqli')) {
        bio_send_json(200, true, 'Nómina no disponible', $neutro);
    }
    $conn = conectar_joya_mysqli();
    if (!$conn) {
        bio_send_json(200, true, 'Nómina no disponible', $neutro);
    }
    $data = bio_nom_descargar($conn);
    $conn->close();
} catch (Throwable $e) {
    error_log('[bioseguridad] descargar_nomina_proveedores: ' . $e->getMessage());
    bio_send_json(200, true, 'Nómina no disponible', $neutro);
}

bio_send_json(200, true, 'Nómina descargada', $data);
