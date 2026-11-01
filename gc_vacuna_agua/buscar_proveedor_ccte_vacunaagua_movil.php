<?php
/**
 * Búsqueda de laboratorios (RUC / razón social) en maestro ccte.
 *
 * Endpoint propio de Vacuna al Agua. Misma consulta que bioseguridad, pero
 * con la conexión que ya usan el resto de scripts de esta carpeta
 * (conexion_grs / conectar_joya_mysqli).
 *
 * Desplegar en:
 *   .../sanidad/flutter/vacunaagua/buscar_proveedor_ccte_vacunaagua_movil.php
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
    vac_send_json(500, false, 'Error de configuración: función de conexión no disponible', null, 'MISSING_CONEXION');
}

$conn = conectar_joya_mysqli();
if (!$conn) {
    vac_send_json(500, false, 'Error de conexión a la base de datos', null, 'DB_CONNECT_ERROR');
}

// ccte guarda la razón social en latin1, igual que la búsqueda de bioseguridad.
$conn->set_charset('latin1');

$raw = file_get_contents('php://input');
$body = json_decode(is_string($raw) ? $raw : '', true);
if (!is_array($body)) {
    $body = $_POST;
}

$q = trim((string) ($body['q'] ?? ''));
$limite = (int) ($body['limite'] ?? 25);
if ($limite < 5) {
    $limite = 5;
}
if ($limite > 40) {
    $limite = 40;
}

if ($q === '') {
    $conn->close();
    vac_send_json(200, false, 'Escriba RUC o razón social.');
}

$digits = preg_replace('/\D/', '', $q) ?? '';
$soloDigitos = ($digits !== '' && preg_match('/^[\d\s.\-]+$/u', $q) === 1);
$tieneLetras = preg_match('/[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]/u', $q) === 1;
$longitud = mb_strlen($q, 'UTF-8');

if ($longitud < 3 && strlen($digits) !== 11) {
    $conn->close();
    vac_send_json(200, false, 'Escriba al menos 3 caracteres para buscar.');
}

$busqueda = [];
$tipos = '';
$params = [];

if ($soloDigitos && strlen($digits) >= 3) {
    $busqueda[] = 'TRIM(codigo) LIKE ?';
    $tipos .= 's';
    $params[] = $digits . '%';
}
if ($tieneLetras) {
    $busqueda[] = 'UPPER(nombre) LIKE ?';
    $tipos .= 's';
    $params[] = '%' . mb_strtoupper($q, 'UTF-8') . '%';
}

if ($busqueda === []) {
    $conn->close();
    vac_send_json(200, false, 'Escriba al menos 3 caracteres para buscar.');
}

$fallbackCcte = !empty($body['fallback']) && ($body['fallback'] === true || $body['fallback'] === 1 || $body['fallback'] === '1');
$filtroCat = $fallbackCcte ? '' : vac_proveedor_sql_filtro_ccte($conn, 'codigo');

$sql = '
    SELECT TRIM(codigo) AS ruc, TRIM(nombre) AS razonsocial
    FROM ccte
    WHERE CHAR_LENGTH(TRIM(codigo)) = 11
      AND (' . implode(' OR ', $busqueda) . ')
      ' . $filtroCat . '
    ORDER BY razonsocial ASC
    LIMIT ?
';
$tipos .= 'i';
$params[] = $limite;

$stmt = $conn->prepare($sql);
if (!$stmt) {
    $err = $conn->error;
    $conn->close();
    vac_send_json(500, false, 'Error al preparar consulta: ' . $err, null, 'DB_PREPARE');
}

$stmt->bind_param($tipos, ...$params);
$stmt->execute();
$result = $stmt->get_result();

$items = [];
if ($result) {
    while ($row = $result->fetch_assoc()) {
        $ruc = preg_replace('/\D/', '', (string) ($row['ruc'] ?? '')) ?? '';
        if (strlen($ruc) !== 11) {
            continue;
        }
        $nombre = trim((string) ($row['razonsocial'] ?? ''));
        if ($nombre === '') {
            continue;
        }
        $items[] = [
            'ruc' => $ruc,
            'razonsocial' => $nombre,
        ];
    }
    $result->free();
}

$stmt->close();
$conn->close();

vac_send_json(200, true, 'OK', vac_utf8([
    'items' => $items,
    'total' => count($items),
]));
