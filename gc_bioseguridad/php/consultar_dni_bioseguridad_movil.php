<?php
declare(strict_types=1);

/**
 * Consulta el nombre de un DNI o carné de extranjería (API Factiliza) para la app.
 *
 * Acepta GET (?dni= / ?documento=) y POST (JSON o formulario).
 * Si el valor son 8 dígitos → `/dni/info/`; si no → `/cee/info/`.
 */

ob_start();
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/bioseguridad_movil_lib.php';

$raw = file_get_contents('php://input');
$input = bio_json_decode($raw);
if ($input === null) {
    $input = $_POST;
}

$doc = (string) ($input['documento'] ?? $input['dni'] ?? $_GET['documento'] ?? $_GET['dni'] ?? '');

$res = bio_consultar_documento_factiliza($doc);
if (!$res['success']) {
    $msg = (string) ($res['message'] ?? 'No se pudo consultar el documento.');
    $status = (strpos($msg, '8 dígitos') !== false || strpos($msg, 'válido') !== false) ? 400 : 404;
    bio_send_json($status, false, $msg, null, $status === 400 ? 'DOCUMENTO_INVALIDO' : 'DOCUMENTO_NO_ENCONTRADO');
}

$documento = (string) ($res['documento'] ?? '');
bio_send_json(200, true, 'Documento consultado', [
    'dni' => $documento,
    'documento' => $documento,
    'tipo' => (string) ($res['tipo'] ?? 'dni'),
    'nombre' => (string) ($res['nombre'] ?? ''),
]);
