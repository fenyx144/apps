<?php
/**
 * Catálogo de laboratorios habilitados para Vacuna al Agua (configuración web).
 *
 * Desplegar en:
 *   .../sanidad/flutter/vacunaagua/get_proveedores_vacunaagua_movil.php
 */
declare(strict_types=1);

ob_start();
require_once __DIR__ . '/auth_movil.php';
require_once __DIR__ . '/vac_proveedor_lib.php';
vac_cors_headers();
date_default_timezone_set('America/Lima');
vac_validate_bearer_token();

include_once __DIR__ . '/../../../conexion_grs/conexion.php';

if (!function_exists('conectar_joya_mysqli')) {
    vac_send_json(500, false, 'Error de configuración del servidor', null, 'MISSING_CONEXION');
}

$conn = conectar_joya_mysqli();
if (!$conn) {
    vac_send_json(500, false, 'Error de conexión a la base de datos', null, 'DB_CONNECT_ERROR');
}

$conn->set_charset('latin1');
$items = vac_proveedor_lista_movil($conn);
$conn->close();

vac_send_json(200, true, 'OK', vac_utf8([
    'items' => $items,
    'total' => count($items),
    'actualizadoEn' => date('c'),
]));
