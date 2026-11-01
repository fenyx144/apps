<?php
declare(strict_types=1);

/**
 * Depuración · Estatus sanitario, situación especial y orden de edad (ingreso app).
 *
 * URL (XAMPP):
 *   http://localhost/sanidad/flutter/bioseguridad/debug_estatus_sanitario_bioseguridad.php
 *
 * Mismos parámetros que consultar_estatus_sanitario_bioseguridad_movil.php:
 *   fecha, granja, campania, dnis (coma o repetido), placas
 *
 * Acceso: sesión activa del portal Sanidad, red local, o clave ?clave=bio_estatus_debug.
 */

date_default_timezone_set('America/Lima');

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

$remote = (string) (isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : '');
$localOk = in_array($remote, ['127.0.0.1', '::1'], true)
    || strpos($remote, '192.168.') === 0
    || strpos($remote, '10.') === 0;
$clave = (string) (isset($_GET['clave']) ? $_GET['clave'] : (isset($_POST['clave']) ? $_POST['clave'] : ''));
$claveOk = $clave !== '' && hash_equals('bio_estatus_debug', $clave);
$sesionPortalOk = !empty($_SESSION['active']);

if (!$localOk && !$claveOk && !$sesionPortalOk) {
    http_response_code(403);
    header('Content-Type: text/html; charset=utf-8');
    $login = '../../../login.php';
    echo '<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>Debug estatus</title></head><body>';
    echo '<p><strong>Acceso denegado.</strong> Esta herramienta no usa el token de la app móvil.</p>';
    echo '<ul>';
    echo '<li>Inicie sesión en el <a href="' . htmlspecialchars($login, ENT_QUOTES, 'UTF-8') . '">portal Sanidad</a> en este mismo navegador y vuelva a abrir esta URL.</li>';
    echo '<li>O use <code>?clave=bio_estatus_debug</code> (solo diagnóstico autorizado).</li>';
    echo '<li>En red local también entra sin sesión.</li>';
    echo '</ul></body></html>';
    exit;
}

// bio_norm_granja, bio_norm_campania, bio_norm_fecha (mismo orden que consultar_estatus_*.php).
require_once __DIR__ . '/auth_movil.php';
require_once __DIR__ . '/estatus_sanitario_movil_lib.php';
require_once __DIR__ . '/orden_edad_movil_lib.php';

$conPath = __DIR__ . '/../../../conexion_grs/conexion.php';
$conOk = is_file($conPath) && (function_exists('conectar_joya_mysqli') || defined('API_TOKEN'));

function dbg_h(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function dbg_param(string $k): string
{
    if (isset($_POST[$k])) {
        return trim((string) $_POST[$k]);
    }
    if (isset($_GET[$k])) {
        return trim((string) $_GET[$k]);
    }

    return '';
}

function dbg_lista(string $raw): array
{
    if ($raw === '') {
        return [];
    }
    $parts = preg_split('/[\s,;]+/', $raw) ?: [];

    $parts = array_map('trim', $parts);
    $out = [];
    foreach ($parts as $x) {
        if ($x !== '') {
            $out[] = $x;
        }
    }

    return $out;
}

function dbg_tabla_existe(mysqli $conn, string $tabla): bool
{
    $tabla = trim($tabla);
    if ($tabla === '') {
        return false;
    }
    $res = @$conn->query("SHOW TABLES LIKE '" . $conn->real_escape_string($tabla) . "'");
    if (!$res) {
        return false;
    }
    $ok = $res->num_rows > 0;
    $res->free();

    return $ok;
}

function dbg_endpoint_script_path(): string
{
    $dir = str_replace('\\', '/', dirname((string) ($_SERVER['SCRIPT_NAME'] ?? '')));

    return rtrim($dir, '/') . '/consultar_estatus_sanitario_bioseguridad_movil.php';
}

/** URL pública (la que usa la app móvil). */
function dbg_endpoint_url(string $override = ''): string
{
    $override = trim($override);
    if ($override !== '') {
        return $override;
    }
    $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $host = (string) ($_SERVER['HTTP_HOST'] ?? 'localhost');

    return $scheme . '://' . $host . dbg_endpoint_script_path();
}

/**
 * URL loopback para probar HTTP en el mismo servidor (evita timeout saliendo por Internet).
 *
 * @return array{url:string,hostHeader:string}
 */
function dbg_endpoint_url_local(): array
{
    $vhost = (string) ($_SERVER['HTTP_HOST'] ?? 'localhost');
    $vhost = preg_replace('/:\d+$/', '', $vhost) ?? $vhost;

    return [
        'url' => 'http://127.0.0.1' . dbg_endpoint_script_path(),
        'hostHeader' => $vhost,
    ];
}

/**
 * POST JSON al endpoint real (igual que ApiService.consultarEstatusSanitario).
 *
 * @return array<string,mixed>
 */
/**
 * @param array{hostHeader?:string,timeoutSec?:int} $opts
 * @return array<string,mixed>
 */
function dbg_probar_endpoint(string $url, string $token, array $body, array $opts = []): array
{
    $timeout = (int) ($opts['timeoutSec'] ?? 45);
    if ($timeout < 10) {
        $timeout = 10;
    }
    $hostHeader = trim((string) ($opts['hostHeader'] ?? ''));

    $out = [
        'url' => $url,
        'hostHeader' => $hostHeader !== '' ? $hostHeader : null,
        'tokenUsado' => $token !== '',
        'httpStatus' => 0,
        'curlError' => '',
        'raw' => '',
        'json' => null,
        'success' => false,
        'message' => '',
        'data' => null,
        'elapsedMs' => 0,
    ];
    if ($token === '') {
        $out['message'] = 'Sin token Bearer: indique token o marque usar API_TOKEN del servidor.';

        return $out;
    }

    $payload = json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($payload === false) {
        $out['message'] = 'No se pudo serializar el cuerpo JSON.';

        return $out;
    }

    $headers = [
        'Content-Type: application/json',
        'Accept: application/json',
        'Authorization: Bearer ' . $token,
    ];
    if ($hostHeader !== '') {
        $headers[] = 'Host: ' . $hostHeader;
    }

    if (function_exists('curl_init')) {
        $t0 = microtime(true);
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_CONNECTTIMEOUT => 12,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_SSL_VERIFYHOST => 0,
        ]);
        $raw = curl_exec($ch);
        $out['httpStatus'] = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $out['curlError'] = curl_error($ch) ?: '';
        curl_close($ch);
        $out['elapsedMs'] = (int) round((microtime(true) - $t0) * 1000);
        $out['raw'] = is_string($raw) ? $raw : '';
    } else {
        $headerStr = implode("\r\n", $headers);
        $ctx = stream_context_create([
            'http' => [
                'method' => 'POST',
                'header' => $headerStr . "\r\n",
                'content' => $payload,
                'timeout' => $timeout,
                'ignore_errors' => true,
            ],
        ]);
        $raw = @file_get_contents($url, false, $ctx);
        $out['raw'] = is_string($raw) ? $raw : '';
        if (isset($http_response_header[0]) && preg_match('/\s(\d{3})\s/', (string) $http_response_header[0], $m)) {
            $out['httpStatus'] = (int) $m[1];
        }
    }

    if ($out['raw'] === '') {
        $out['message'] = $out['curlError'] !== '' ? $out['curlError'] : 'Respuesta vacía del endpoint.';

        return $out;
    }

    $decoded = json_decode($out['raw'], true);
    if (!is_array($decoded)) {
        $out['message'] = 'El endpoint no devolvió JSON válido (¿401 HTML?).';

        return $out;
    }
    $out['json'] = $decoded;
    $out['success'] = ($decoded['success'] ?? false) === true;
    $out['message'] = (string) ($decoded['message'] ?? '');
    $out['data'] = $decoded['data'] ?? null;

    return $out;
}

/** @param mixed $x */
function dbg_json_norm($x)
{
    if ($x instanceof stdClass) {
        $x = (array) $x;
    }
    if (is_array($x)) {
        ksort($x);
        foreach ($x as $k => $v) {
            $x[$k] = dbg_json_norm($v);
        }
    }

    return $x;
}

/**
 * Trazas de por qué un DNI no tiene enRiesgo (misma lógica que bio_es_origenes_por_dni).
 *
 * @return array<string,mixed>
 */
function dbg_traza_dni(mysqli $conn, string $dni, string $fecha, string $granjaDestino): array
{
    $dniKey = bio_es_norm_dni_key($dni);
    $granjaDestino = $granjaDestino !== '' ? bio_norm_granja($granjaDestino) : '';
    $desde = date('Y-m-d', strtotime($fecha . ' -' . (BIO_ES_DIAS_VENTANA - 1) . ' days'));
    $exprDni = bio_es_dni_norm_sql('d.dni');

    $traza = [
        'dniEntrada' => $dni,
        'dniNormalizado' => $dniKey,
        'granjaDestino' => $granjaDestino,
        'ventanaDesde' => $desde,
        'ventanaHasta' => $fecha,
        'ingresosEnVentana' => 0,
        'ingresosGranjaConEstatusVigente' => 0,
        'descartadosMismaGranjaDestino' => 0,
        'origenesFinales' => [],
        'ultimosIngresos' => [],
    ];

    if (strlen($dniKey) !== 8) {
        $traza['error'] = 'DNI inválido (se esperan 8 dígitos).';

        return $traza;
    }

    $cab = bio_tabla_ingreso_cab();
    $det = bio_tabla_ingreso_det();
    if (!dbg_tabla_existe($conn, $cab) || !dbg_tabla_existe($conn, $det)) {
        $traza['error'] = 'Faltan tablas de ingreso: ' . $cab . ' / ' . $det;

        return $traza;
    }

    $sqlSimple = 'SELECT TRIM(r.granja) AS granja, r.fecha, r.hora, TRIM(r.campania) AS campania
                    FROM `' . $det . '` d
                    JOIN `' . $cab . '` r ON r.id = d.idCab
                   WHERE ' . $exprDni . ' = ?
                     AND r.fecha BETWEEN ? AND ?
                   ORDER BY r.fecha DESC, r.hora DESC
                   LIMIT 15';
    $st = $conn->prepare($sqlSimple);
    if ($st) {
        $st->bind_param('sss', $dniKey, $desde, $fecha);
        $st->execute();
        $res = $st->get_result();
        while ($res && ($r = $res->fetch_assoc())) {
            $traza['ultimosIngresos'][] = $r;
        }
        $st->close();
        $traza['ingresosEnVentana'] = count($traza['ultimosIngresos']);
    }

    $origenes = bio_es_origenes_por_dni($conn, [$dniKey], $fecha, $granjaDestino);
    $traza['origenesFinales'] = $origenes[$dniKey] ?? [];
    $traza['enRiesgoApp'] = ($traza['origenesFinales'] !== []);

    $sqlJoin = 'SELECT TRIM(r.granja) AS granja, r.fecha, UPPER(TRIM(e.estado)) AS estado,
                       e.fechaInicio, e.fechaFin
                  FROM `' . $det . '` d
                  JOIN `' . $cab . '` r ON r.id = d.idCab
                  JOIN ' . BIO_ES_TABLA . ' e ON LPAD(TRIM(e.granja), 3, \'0\') = LPAD(TRIM(r.granja), 3, \'0\')
                 WHERE ' . $exprDni . ' = ?
                   AND UPPER(TRIM(e.estado)) IN (\'SOSPECHA\',\'CONFIRMADO\')
                   AND r.fecha BETWEEN ? AND ?
                   AND r.fecha >= e.fechaInicio
                   AND e.fechaInicio <= ?
                   AND (e.fechaFin IS NULL OR e.fechaFin >= ?)
                 ORDER BY r.fecha DESC
                 LIMIT 20';
    $st2 = $conn->prepare($sqlJoin);
    if ($st2) {
        $st2->bind_param('sssss', $dniKey, $desde, $fecha, $fecha, $fecha);
        $st2->execute();
        $res2 = $st2->get_result();
        $filas = [];
        while ($res2 && ($r = $res2->fetch_assoc())) {
            $g3 = bio_norm_granja((string) $r['granja']);
            if ($granjaDestino !== '' && $g3 === $granjaDestino) {
                $traza['descartadosMismaGranjaDestino']++;
                continue;
            }
            $filas[] = $r;
        }
        $st2->close();
        $traza['ingresosGranjaConEstatusVigente'] = count($filas);
        $traza['ingresosConEstatusDetalle'] = $filas;
    }

    return $traza;
}

/**
 * Trazas del aviso «visitó una granja de mayor edad» (orden de edad, mismo día).
 *
 * @return array<string,mixed>
 */
function dbg_traza_orden_edad_dni(
    mysqli $conn,
    string $dni,
    string $fecha,
    string $granja,
    string $campania
): array {
    $dniKey = bio_es_norm_dni_key($dni);
    $granja = $granja !== '' ? bio_norm_granja($granja) : '';
    $campania = bio_norm_campania($campania);
    $traza = [
        'dni' => $dniKey,
        'granjaDestino' => $granja,
        'campaniaDestino' => $campania,
        'fecha' => $fecha,
        'edadGranjaDestino' => null,
        'ordenEdadDisponible' => false,
        'visitasHoyOtrasGranjas' => [],
        'comparacionEdades' => [],
        'origenesMayorEdad' => [],
        'enRiesgoApp' => false,
        'textoCortoApp' => '',
    ];
    if (strlen($dniKey) !== 8) {
        $traza['error'] = 'DNI inválido (8 dígitos).';

        return $traza;
    }
    if ($granja === '' || $campania === '') {
        $traza['error'] = 'Indique granja y campaña del registro: sin edad destino no hay aviso de orden de edad.';

        return $traza;
    }
    $edadDest = bio_oe_edad_granja($conn, $granja, $campania, $fecha);
    $traza['edadGranjaDestino'] = $edadDest;
    $traza['ordenEdadDisponible'] = $edadDest !== null;
    if ($edadDest === null) {
        $traza['error'] = 'No se resolvió edad de granja/campaña destino (HC o maes_zonas).';

        return $traza;
    }
    $visitas = bio_oe_visitas_hoy_por_dni($conn, [$dniKey], $fecha, $granja);
    $traza['visitasHoyOtrasGranjas'] = $visitas[$dniKey] ?? [];
    foreach ($traza['visitasHoyOtrasGranjas'] as $v) {
        $g = (string) ($v['granja'] ?? '');
        $c = (string) ($v['campania'] ?? '');
        $edad = bio_oe_edad_granja($conn, $g, $c, $fecha);
        $traza['comparacionEdades'][] = [
            'granja' => $g,
            'campania' => $c,
            'hora' => (string) ($v['hora'] ?? ''),
            'edadOrigen' => $edad,
            'edadDestino' => $edadDest,
            'cuentaComoMayorEdad' => ($edad !== null && $edad > $edadDest),
        ];
    }
    $traza['origenesMayorEdad'] = bio_oe_filtrar_mayor_edad(
        $conn,
        $traza['visitasHoyOtrasGranjas'],
        $fecha,
        $edadDest
    );
    $traza['enRiesgoApp'] = $traza['origenesMayorEdad'] !== [];
    if ($traza['enRiesgoApp']) {
        $traza['textoCortoApp'] = 'DNI ' . $dniKey . ' visitó una granja de mayor edad';
    }

    return $traza;
}

/**
 * @return array<string,mixed>
 */
function dbg_traza_orden_edad_placa(
    mysqli $conn,
    string $placa,
    string $fecha,
    string $granja,
    string $campania
): array {
    $placaNorm = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', $placa));
    $granja = $granja !== '' ? bio_norm_granja($granja) : '';
    $campania = bio_norm_campania($campania);
    $traza = [
        'placa' => $placaNorm,
        'granjaDestino' => $granja,
        'campaniaDestino' => $campania,
        'fecha' => $fecha,
        'edadGranjaDestino' => null,
        'ordenEdadDisponible' => false,
        'visitasHoyOtrasGranjas' => [],
        'comparacionEdades' => [],
        'origenesMayorEdad' => [],
        'enRiesgoApp' => false,
        'textoCortoApp' => '',
    ];
    if ($placaNorm === '') {
        $traza['error'] = 'Placa vacía.';

        return $traza;
    }
    if ($granja === '' || $campania === '') {
        $traza['error'] = 'Indique granja y campaña del registro.';

        return $traza;
    }
    $edadDest = bio_oe_edad_granja($conn, $granja, $campania, $fecha);
    $traza['edadGranjaDestino'] = $edadDest;
    $traza['ordenEdadDisponible'] = $edadDest !== null;
    if ($edadDest === null) {
        $traza['error'] = 'No se resolvió edad destino.';

        return $traza;
    }
    $visitas = bio_oe_visitas_hoy_por_placa($conn, [$placaNorm], $fecha, $granja);
    $traza['visitasHoyOtrasGranjas'] = $visitas[$placaNorm] ?? [];
    foreach ($traza['visitasHoyOtrasGranjas'] as $v) {
        $g = (string) ($v['granja'] ?? '');
        $c = (string) ($v['campania'] ?? '');
        $edad = bio_oe_edad_granja($conn, $g, $c, $fecha);
        $traza['comparacionEdades'][] = [
            'granja' => $g,
            'campania' => $c,
            'hora' => (string) ($v['hora'] ?? ''),
            'edadOrigen' => $edad,
            'edadDestino' => $edadDest,
            'cuentaComoMayorEdad' => ($edad !== null && $edad > $edadDest),
        ];
    }
    $traza['origenesMayorEdad'] = bio_oe_filtrar_mayor_edad(
        $conn,
        $traza['visitasHoyOtrasGranjas'],
        $fecha,
        $edadDest
    );
    $traza['enRiesgoApp'] = $traza['origenesMayorEdad'] !== [];
    if ($traza['enRiesgoApp']) {
        $traza['textoCortoApp'] = 'Placa ' . $placaNorm . ' visitó una granja de mayor edad';
    }

    return $traza;
}

/** @param mixed $map */
function dbg_map_from_json($map): array
{
    if ($map instanceof stdClass) {
        $map = (array) $map;
    }

    return is_array($map) ? $map : [];
}

$fecha = dbg_param('fecha');
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $fecha)) {
    $fecha = date('Y-m-d');
}
$granjaRaw = preg_replace('/\D+/', '', dbg_param('granja'));
$granja = bio_norm_granja($granjaRaw !== null ? $granjaRaw : '');
$campania = bio_norm_campania(dbg_param('campania'));
$dnisIn = dbg_lista(dbg_param('dnis'));
$dnis = [];
foreach ($dnisIn as $d) {
    $dnis[] = bio_es_norm_dni_key($d);
}
$dnis = array_slice($dnis, 0, 60);
$dnisOk = [];
foreach ($dnis as $d) {
    if (strlen($d) === 8) {
        $dnisOk[] = $d;
    }
}
$dnis = $dnisOk;
$placas = array_slice(dbg_lista(dbg_param('placas')), 0, 20);

$formatJson = (dbg_param('format') === 'json');
$endpointOverride = dbg_param('endpoint_url');
$tokenInput = dbg_param('token');
$formEnviado = isset($_GET['fecha']) || isset($_POST['fecha']);
$usarTokenServidor = $formEnviado ? (dbg_param('usar_token') === '1') : true;
$tokenBearer = $tokenInput;
if ($tokenBearer === '' && $usarTokenServidor && defined('API_TOKEN')) {
    $tokenBearer = (string) API_TOKEN;
}

$postBody = [
    'fecha' => $fecha,
    'granja' => $granja,
    'campania' => $campania,
    'dnis' => $dnis,
    'placas' => $placas,
];

$diag = [
    'servidor' => [
        'hora' => date('Y-m-d H:i:s'),
        'remoteAddr' => $remote,
        'conexionPhp' => $conOk,
        'conectar_joya_mysqli' => function_exists('conectar_joya_mysqli'),
    ],
    'entrada' => [
        'fecha' => $fecha,
        'granja' => $granja,
        'campania' => $campania,
        'dnis' => $dnis,
        'placas' => $placas,
    ],
    'app' => [
        'consultaSeDispara' => ($granja !== '' || $dnis !== [] || $placas !== []),
        'notaGranjaVacia' => 'Con varias granjas en Mis granjas, la app puede mandar granja vacía; igual debe avisar si hay DNIs y el API responde disponible=true.',
    ],
];

$respuestaDirecta = null;
$endpointReal = null;
$trazasDni = [];
$trazasOrdenEdadDni = [];
$trazasOrdenEdadPlaca = [];
$conn = null;

if (function_exists('conectar_joya_mysqli')) {
    $conn = conectar_joya_mysqli();
}
$diag['servidor']['mysqli'] = ($conn instanceof mysqli);

if ($conn) {
    $diag['tablas'] = [
        'estatus' => bio_es_tablas_existen($conn),
        'ingresoCab' => dbg_tabla_existe($conn, bio_tabla_ingreso_cab()),
        'ingresoDet' => dbg_tabla_existe($conn, bio_tabla_ingreso_det()),
        'ingresoVeh' => dbg_tabla_existe($conn, bio_tabla_ingreso_veh()),
    ];
    try {
        $vigentesTodas = bio_es_vigentes($conn, [], $fecha);
        $diag['estatusVigentesHoy'] = array_values($vigentesTodas);
    } catch (Throwable $e) {
        $diag['estatusVigentesHoyError'] = $e->getMessage();
    }

    try {
        $respuestaDirecta = bio_es_consultar($conn, $fecha, $granja, $dnis, $placas);
        try {
            $respuestaDirecta['ordenEdad'] = bio_oe_consultar($conn, $fecha, $granja, $campania, $dnis, $placas);
        } catch (Throwable $eOe) {
            $respuestaDirecta['ordenEdad'] = ['error' => $eOe->getMessage()];
        }
    } catch (Throwable $e) {
        $diag['errorConsultaDirecta'] = $e->getMessage();
    }

    foreach ($dnis as $dni) {
        $trazasDni[$dni] = dbg_traza_dni($conn, $dni, $fecha, $granja);
        $trazasOrdenEdadDni[$dni] = dbg_traza_orden_edad_dni($conn, $dni, $fecha, $granja, $campania);
    }
    foreach ($placas as $placa) {
        $trazasOrdenEdadPlaca[$placa] = dbg_traza_orden_edad_placa($conn, $placa, $fecha, $granja, $campania);
    }

    $conn->close();
} else {
    $diag['error'] = 'No hay conexión MySQL (conectar_joya_mysqli).';
}

$endpointPublicUrl = dbg_endpoint_url($endpointOverride);
$endpointLocal = dbg_endpoint_url_local();
$forzarPublico = dbg_param('endpoint_publico') === '1';

// En el mismo servidor, llamar al dominio público suele salir a Internet y hacer timeout.
// Por defecto probamos loopback (127.0.0.1 + Host) y opcionalmente la URL pública.
$endpointReal = null;
if (!$forzarPublico && $endpointOverride === '') {
    $endpointReal = dbg_probar_endpoint(
        $endpointLocal['url'],
        $tokenBearer,
        $postBody,
        ['hostHeader' => $endpointLocal['hostHeader'], 'timeoutSec' => 45]
    );
    $diag['endpoint'] = [
        'modo' => 'local_loopback',
        'url' => $endpointLocal['url'],
        'hostHeader' => $endpointLocal['hostHeader'],
        'urlPublicaApp' => $endpointPublicUrl,
        'httpStatus' => $endpointReal['httpStatus'] ?? 0,
        'elapsedMs' => $endpointReal['elapsedMs'] ?? 0,
        'success' => $endpointReal['success'] ?? false,
        'message' => $endpointReal['message'] ?? '',
        'tokenConfigurado' => $tokenBearer !== '',
        'apiTokenEnServidor' => defined('API_TOKEN'),
        'nota' => 'La app móvil usa la URL pública. Si solo falla endpoint_publico, el móvil puede estar bien; compare consulta directa vs loopback.',
    ];
} else {
    $endpointReal = dbg_probar_endpoint($endpointPublicUrl, $tokenBearer, $postBody, ['timeoutSec' => 45]);
    $diag['endpoint'] = [
        'modo' => $forzarPublico ? 'publico_forzado' : 'url_manual',
        'url' => $endpointPublicUrl,
        'httpStatus' => $endpointReal['httpStatus'] ?? 0,
        'elapsedMs' => $endpointReal['elapsedMs'] ?? 0,
        'success' => $endpointReal['success'] ?? false,
        'message' => $endpointReal['message'] ?? '',
        'tokenConfigurado' => $tokenBearer !== '',
        'apiTokenEnServidor' => defined('API_TOKEN'),
    ];
}

if (!$forzarPublico && $endpointOverride === '' && !($endpointReal['success'] ?? false)) {
    $endpointPublicTry = dbg_probar_endpoint($endpointPublicUrl, $tokenBearer, $postBody, ['timeoutSec' => 25]);
    $diag['endpointPublicoOpcional'] = [
        'url' => $endpointPublicUrl,
        'httpStatus' => $endpointPublicTry['httpStatus'] ?? 0,
        'success' => $endpointPublicTry['success'] ?? false,
        'message' => $endpointPublicTry['message'] ?? ($endpointPublicTry['curlError'] ?? ''),
        'elapsedMs' => $endpointPublicTry['elapsedMs'] ?? 0,
    ];
    if (($endpointPublicTry['success'] ?? false) && is_array($endpointPublicTry['data'] ?? null)) {
        $endpointReal = $endpointPublicTry;
    }
}

$dataParaApp = null;
$fuenteApp = 'ninguna';
if (($endpointReal['success'] ?? false) && is_array($endpointReal['data'] ?? null)) {
    $dataParaApp = $endpointReal['data'];
    $fuenteApp = 'endpoint_http';
} elseif (is_array($respuestaDirecta)) {
    $dataParaApp = $respuestaDirecta;
    $fuenteApp = 'consulta_directa_php';
}

$diag['simulacionApp'] = ['fuente' => $fuenteApp];
if (is_array($dataParaApp)) {
    $mapDnis = dbg_map_from_json($dataParaApp['dnis'] ?? []);
    $ordenEdad = is_array($dataParaApp['ordenEdad'] ?? null) ? $dataParaApp['ordenEdad'] : [];
    $mapOeDnis = dbg_map_from_json($ordenEdad['dnis'] ?? []);
    $mapOePlacas = dbg_map_from_json($ordenEdad['placas'] ?? []);
    $oeDisponible = ($ordenEdad['disponible'] ?? false) === true;
    $diag['simulacionApp']['ordenEdad'] = [
        'disponible' => $oeDisponible,
        'edadGranja' => $ordenEdad['edadGranja'] ?? null,
        'nota' => 'Requiere granja + campaña del registro. Compara ingresos de HOY en otras granjas con edad > edadGranja.',
    ];
    foreach ($dnis as $dni) {
        $item = is_array($mapDnis) ? ($mapDnis[$dni] ?? null) : null;
        $enRiesgo = is_array($item) && !empty($item['enRiesgo']);
        $oeItem = is_array($mapOeDnis) ? ($mapOeDnis[$dni] ?? null) : null;
        $oeRiesgo = is_array($oeItem) && !empty($oeItem['enRiesgo']);
        $diag['simulacionApp'][$dni] = [
            'mostrariaEtiquetaSituacionEspecial' => $enRiesgo,
            'motivoSituacionEspecial' => $enRiesgo
                ? 'enRiesgo=true (' . $fuenteApp . ')'
                : (($dataParaApp['disponible'] ?? false)
                    ? 'enRiesgo=false (sin orígenes en granja con estatus)'
                    : 'disponible=false (app no muestra avisos)'),
            'mostrariaEtiquetaOrdenEdad' => $oeRiesgo,
            'textoCortoOrdenEdadApp' => $oeRiesgo
                ? ('DNI ' . $dni . ' visitó una granja de mayor edad')
                : ($oeDisponible
                    ? 'Sin aviso orden de edad (enRiesgo=false)'
                    : 'ordenEdad.disponible=false (falta edad destino o campaña)'),
            'origenesOrdenEdad' => is_array($oeItem) ? ($oeItem['origenes'] ?? []) : [],
        ];
    }
    foreach ($placas as $placaRaw) {
        $placaNorm = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', $placaRaw));
        if ($placaNorm === '') {
            continue;
        }
        $oeItem = is_array($mapOePlacas) ? ($mapOePlacas[$placaNorm] ?? null) : null;
        $oeRiesgo = is_array($oeItem) && !empty($oeItem['enRiesgo']);
        $diag['simulacionApp']['placa:' . $placaNorm] = [
            'mostrariaEtiquetaOrdenEdad' => $oeRiesgo,
            'textoCortoOrdenEdadApp' => $oeRiesgo
                ? ('Placa ' . $placaNorm . ' visitó una granja de mayor edad')
                : ($oeDisponible ? 'Sin aviso orden de edad' : 'ordenEdad no disponible'),
            'origenesOrdenEdad' => is_array($oeItem) ? ($oeItem['origenes'] ?? []) : [],
        ];
    }
    $diag['simulacionApp']['granjaEnEstatusCard'] = ($dataParaApp['granjaEnEstatus'] ?? null) !== null;
}

if (is_array($respuestaDirecta) && ($endpointReal['success'] ?? false) && is_array($endpointReal['data'] ?? null)) {
    $normDirecta = dbg_json_norm($respuestaDirecta);
    $normHttp = dbg_json_norm($endpointReal['data']);
    $diag['comparacionDirectaVsEndpoint'] = [
        'coinciden' => $normDirecta === $normHttp,
        'nota' => 'Si difieren, el endpoint HTTP puede estar en otro servidor/BD o fallar auth parcialmente.',
    ];
}

if ($formatJson) {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'diagnostico' => $diag,
        'respuestaDirecta' => $respuestaDirecta,
        'endpointReal' => [
            'httpStatus' => $endpointReal['httpStatus'] ?? 0,
            'success' => $endpointReal['success'] ?? false,
            'message' => $endpointReal['message'] ?? '',
            'data' => $endpointReal['data'] ?? null,
            'raw' => $endpointReal['raw'] ?? '',
        ],
        'trazasDni' => $trazasDni,
        'trazasOrdenEdadDni' => $trazasOrdenEdadDni,
        'trazasOrdenEdadPlaca' => $trazasOrdenEdadPlaca,
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}

$dnisDefault = $dnis !== [] ? implode(', ', $dnis) : dbg_param('dnis');
$placasDefault = $placas !== [] ? implode(', ', $placas) : dbg_param('placas');
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Debug · Estatus y orden de edad (Bioseguridad móvil)</title>
    <style>
        body { font-family: system-ui, sans-serif; margin: 1rem 1.25rem 2rem; background: #f8fafc; color: #0f172a; }
        h1 { font-size: 1.25rem; margin: 0 0 0.5rem; }
        .muted { color: #64748b; font-size: 0.88rem; }
        form { display: grid; grid-template-columns: repeat(auto-fill, minmax(11rem, 1fr)); gap: 0.65rem 1rem; background: #fff; border: 1px solid #e2e8f0; border-radius: 0.5rem; padding: 1rem; margin: 1rem 0; }
        label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.78rem; font-weight: 600; }
        input, textarea { font: inherit; padding: 0.35rem 0.5rem; border: 1px solid #cbd5e1; border-radius: 0.35rem; }
        textarea { grid-column: 1 / -1; min-height: 2.5rem; }
        button { grid-column: 1 / -1; justify-self: start; padding: 0.45rem 0.9rem; background: #2563eb; color: #fff; border: 0; border-radius: 0.4rem; cursor: pointer; font-weight: 600; }
        pre { background: #0f172a; color: #e2e8f0; padding: 0.75rem; border-radius: 0.45rem; overflow: auto; font-size: 0.78rem; }
        .ok { color: #16a34a; font-weight: 700; }
        .bad { color: #dc2626; font-weight: 700; }
        table { border-collapse: collapse; width: 100%; font-size: 0.82rem; background: #fff; }
        th, td { border: 1px solid #e2e8f0; padding: 0.35rem 0.5rem; text-align: left; vertical-align: top; }
        th { background: #f1f5f9; }
        section { margin-top: 1.25rem; }
    </style>
</head>
<body>
    <h1>Debug · Situación especial y orden de edad</h1>
    <p class="muted">Consulta <strong>directa en PHP</strong> y el <strong>endpoint HTTP real</strong> (<code>consultar_estatus_sanitario_bioseguridad_movil.php</code>) con Bearer, igual que la app. Incluye bloque <code>ordenEdad</code> (aviso «visitó una granja de mayor edad»).</p>
    <p class="muted">Orden de edad: use la <strong>fecha de hoy</strong>, la <strong>granja y campaña</strong> que está registrando, y DNIs/placas que ya tengan otro ingreso hoy en otra granja con edad promedio mayor.</p>
    <p class="muted">JSON: <code>&amp;format=json</code>. Token: vacío + «usar API_TOKEN del servidor» (desde <code>conexion.php</code>) o pegue el token de la app.</p>

    <form method="get" action="">
        <label>Fecha (AAAA-MM-DD)
            <input name="fecha" value="<?= dbg_h($fecha) ?>">
        </label>
        <label>Granja destino (3 díg.)
            <input name="granja" value="<?= dbg_h($granja !== '' ? $granja : dbg_param('granja')) ?>" placeholder="621">
        </label>
        <label>Campaña (requerida p. orden de edad)
            <input name="campania" value="<?= dbg_h($campania !== '' ? $campania : dbg_param('campania')) ?>" placeholder="2025-01">
        </label>
        <label>DNIs (coma o espacio)
            <textarea name="dnis" placeholder="12345678, 87654321"><?= dbg_h($dnisDefault) ?></textarea>
        </label>
        <label>Placas
            <textarea name="placas" placeholder="AHX742"><?= dbg_h($placasDefault) ?></textarea>
        </label>
        <label>URL endpoint (opcional)
            <input name="endpoint_url" value="<?= dbg_h($endpointOverride) ?>" placeholder="<?= dbg_h(dbg_endpoint_url()) ?>">
        </label>
        <label>Bearer token (opcional)
            <input name="token" type="password" value="<?= dbg_h($tokenInput) ?>" autocomplete="off" placeholder="Si vacío, usa API_TOKEN del servidor">
        </label>
        <label style="flex-direction:row;align-items:center;gap:0.4rem;font-weight:500;grid-column:1/-1;">
            <input type="hidden" name="usar_token" value="0">
            <input type="checkbox" name="usar_token" value="1" <?= $usarTokenServidor ? 'checked' : '' ?>>
            Usar API_TOKEN de conexion.php si no escribo token
        </label>
        <button type="submit">Consultar (directo + endpoint real)</button>
    </form>

    <section>
        <h2>Servidor y tablas</h2>
        <pre><?= dbg_h(json_encode($diag, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)) ?></pre>
    </section>

    <?php if ($dnis !== [] || $placas !== []): ?>
    <section>
        <h2>Simulación app (etiquetas en ingreso)</h2>
        <?php
        $oeMeta = is_array($diag['simulacionApp']['ordenEdad'] ?? null) ? $diag['simulacionApp']['ordenEdad'] : [];
        ?>
        <p class="muted">
            Orden de edad:
            <?= !empty($oeMeta['disponible']) ? '<span class="ok">disponible</span>' : '<span class="bad">no disponible</span>' ?>
            · edad granja destino: <?= dbg_h((string) ($oeMeta['edadGranja'] ?? '—')) ?>
        </p>
        <?php if ($dnis !== []): ?>
        <table>
            <thead><tr>
                <th>DNI</th>
                <th>Situación especial</th>
                <th>Orden de edad</th>
                <th>Texto corto app (orden edad)</th>
            </tr></thead>
            <tbody>
            <?php foreach ($dnis as $dni):
                $sim = $diag['simulacionApp'][$dni] ?? null;
                $okEs = is_array($sim) && !empty($sim['mostrariaEtiquetaSituacionEspecial']);
                $okOe = is_array($sim) && !empty($sim['mostrariaEtiquetaOrdenEdad']);
                ?>
                <tr>
                    <td><?= dbg_h($dni) ?></td>
                    <td class="<?= $okEs ? 'ok' : 'bad' ?>"><?= $okEs ? 'SÍ' : 'NO' ?></td>
                    <td class="<?= $okOe ? 'ok' : 'bad' ?>"><?= $okOe ? 'SÍ' : 'NO' ?></td>
                    <td><?= dbg_h(is_array($sim) ? (string) ($sim['textoCortoOrdenEdadApp'] ?? '') : '') ?></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>
        <?php if ($placas !== []): ?>
        <table style="margin-top:0.75rem;">
            <thead><tr><th>Placa</th><th>Orden de edad</th><th>Texto corto app</th></tr></thead>
            <tbody>
            <?php foreach ($placas as $placaRaw):
                $pn = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', $placaRaw));
                if ($pn === '') {
                    continue;
                }
                $sim = $diag['simulacionApp']['placa:' . $pn] ?? null;
                $okOe = is_array($sim) && !empty($sim['mostrariaEtiquetaOrdenEdad']);
                ?>
                <tr>
                    <td><?= dbg_h($pn) ?></td>
                    <td class="<?= $okOe ? 'ok' : 'bad' ?>"><?= $okOe ? 'SÍ' : 'NO' ?></td>
                    <td><?= dbg_h(is_array($sim) ? (string) ($sim['textoCortoOrdenEdadApp'] ?? '') : '') ?></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
        <?php endif; ?>
    </section>

    <?php if ($dnis !== []): ?>
    <section>
        <h2>Trazas situación especial (por DNI)</h2>
        <pre><?= dbg_h(json_encode($trazasDni, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)) ?></pre>
    </section>
    <section>
        <h2>Trazas orden de edad (por DNI)</h2>
        <p class="muted">Ingresos de hoy en otras granjas y comparación edad origen &gt; edad destino.</p>
        <pre><?= dbg_h(json_encode($trazasOrdenEdadDni, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)) ?></pre>
    </section>
    <?php endif; ?>
    <?php if ($placas !== []): ?>
    <section>
        <h2>Trazas orden de edad (por placa)</h2>
        <pre><?= dbg_h(json_encode($trazasOrdenEdadPlaca, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)) ?></pre>
    </section>
    <?php endif; ?>
    <?php endif; ?>

    <section>
        <h2>Endpoint HTTP real (como la app)</h2>
        <p class="muted">
            HTTP <?= (int) ($endpointReal['httpStatus'] ?? 0) ?> ·
            <?= ($endpointReal['success'] ?? false) ? '<span class="ok">success</span>' : '<span class="bad">falló</span>' ?> ·
            <?= dbg_h((string) ($endpointReal['message'] ?? '')) ?>
        </p>
        <p class="muted"><code><?= dbg_h((string) ($endpointReal['url'] ?? '')) ?></code></p>
        <?php if (!($endpointReal['tokenUsado'] ?? false)): ?>
        <p class="bad">No se llamó al endpoint: falta token Bearer.</p>
        <?php endif; ?>
        <pre><?= dbg_h(json_encode($endpointReal['json'] ?? $endpointReal['raw'] ?? '', JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)) ?></pre>
    </section>

    <section>
        <h2>Consulta directa PHP (lib, sin HTTP)</h2>
        <pre><?= dbg_h(json_encode($respuestaDirecta, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)) ?></pre>
    </section>
</body>
</html>
