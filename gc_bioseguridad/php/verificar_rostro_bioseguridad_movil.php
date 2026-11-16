<?php
declare(strict_types=1);

/**
 * Identificación 1:N. Recibe la foto capturada y busca entre el personal
 * con foto registrada (bio_personal.foto_ruta y san_personal_proveedor).
 *
 * Motor: el mismo ArcFace w600k_mbf de gc_verificacion (512 floats, coseno,
 * umbral 0.45, margen 0.10). Las plantillas se cachean en bio_rostro_plantilla.
 *
 * POST JSON: { "foto": "<jpeg base64>" }
 * data: { verificado, dni, nombre, empresa, similitud, motivo }
 */

ob_start();
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/nomina_proveedor_movil_lib.php';

const BIO_VER_UMBRAL = 0.45;
const BIO_VER_MARGEN = 0.10;
const BIO_VER_MODELO = 'arcface-w600k_mbf';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    bio_send_json(405, false, 'Use POST');
}

@set_time_limit(180);

$raw = file_get_contents('php://input') ?: '';
$body = json_decode($raw, true);
if (!is_array($body)) {
    bio_send_json(400, false, 'JSON inválido');
}

$foto = trim((string) ($body['foto'] ?? ''));
if (strncmp($foto, 'data:', 5) === 0) {
    $pos = strpos($foto, ',');
    $foto = $pos === false ? '' : substr($foto, $pos + 1);
}
$bin = base64_decode($foto, true);
if ($bin === false || strlen($bin) < 32 || strlen($foto) > 1500000) {
    bio_send_json(400, false, 'Foto no válida');
}

if (!function_exists('conectar_joya_mysqli')) {
    bio_send_json(200, false, 'sin señal', ['verificado' => false, 'motivo' => 'sin_senal']);
}
$conn = conectar_joya_mysqli();
if (!$conn) {
    bio_send_json(200, false, 'sin señal', ['verificado' => false, 'motivo' => 'sin_senal']);
}

bio_ver_asegurar_tabla($conn);

$tmp = sys_get_temp_dir() . '/rostro_' . bin2hex(random_bytes(8));
@mkdir($tmp, 0700, true);
$probe = $tmp . '/probe.jpg';
file_put_contents($probe, $bin);

$galeria = bio_ver_galeria($conn);
$cache = bio_ver_cache($conn);
$pendientes = [['id' => 'probe', 'path' => $probe]];
$meta = [];
foreach ($galeria as $p) {
    $hash = sha1_file($p['path']) ?: '';
    $p['hash'] = $hash;
    $meta[$p['dni']] = $p;
    $guardada = $cache[$p['dni']] ?? null;
    if ($guardada === null || ($guardada['foto_hash'] ?? '') !== $hash || count($guardada['vector']) !== 512) {
        $pendientes[] = ['id' => $p['dni'], 'path' => $p['path']];
    }
}

$emb = bio_ver_embed($pendientes);
if ($emb === null) {
    bio_ver_limpiar($tmp);
    $conn->close();
    bio_send_json(200, false, 'sin motor', ['verificado' => false, 'motivo' => 'sin_motor']);
}

$probeVec = $emb['probe'] ?? null;
if (!is_array($probeVec) || count($probeVec) !== 512) {
    bio_ver_limpiar($tmp);
    $conn->close();
    bio_send_json(200, true, 'Sin rostro', [
        'verificado' => false,
        'motivo' => 'sin_rostro',
        'dni' => '',
        'nombre' => '',
        'empresa' => '',
        'similitud' => 0,
    ]);
}

$plantillas = [];
foreach ($meta as $dni => $p) {
    $vec = $emb[$dni] ?? ($cache[$dni]['vector'] ?? null);
    if (!is_array($vec) || count($vec) !== 512) {
        continue;
    }
    if (isset($emb[$dni])) {
        bio_ver_guardar($conn, $p, $vec);
    }
    $plantillas[] = ['dni' => $dni, 'nombre' => $p['nombre'], 'empresa' => $p['empresa'], 'vector' => $vec];
}
$conn->close();
bio_ver_limpiar($tmp);

if ($plantillas === []) {
    bio_send_json(200, true, 'Sin foto', [
        'verificado' => false,
        'motivo' => 'sin_foto',
        'dni' => '',
        'nombre' => '',
        'empresa' => '',
        'similitud' => 0,
    ]);
}

$best = null;
$bs = -2.0;
$second = 0.0;
foreach ($plantillas as $p) {
    $s = bio_ver_coseno($probeVec, $p['vector']);
    if ($s > $bs) {
        if ($best !== null && $bs > $second) {
            $second = $bs;
        }
        $bs = $s;
        $best = $p;
    } elseif ($s > $second) {
        $second = $s;
    }
}
$ok = $best !== null && $bs >= BIO_VER_UMBRAL && ($bs - $second) >= BIO_VER_MARGEN;

bio_send_json(200, true, $ok ? 'Coincide' : 'No coincide', [
    'verificado' => $ok,
    'motivo' => $ok ? 'ok' : 'no_coincide',
    'dni' => $ok ? $best['dni'] : '',
    'nombre' => $ok ? $best['nombre'] : '',
    'empresa' => $ok ? $best['empresa'] : '',
    'similitud' => round($bs, 3),
]);

function bio_ver_asegurar_tabla(mysqli $conn): void
{
    $conn->query(
        'CREATE TABLE IF NOT EXISTS `bio_rostro_plantilla` (
          `dni` varchar(15) NOT NULL,
          `nombre` varchar(120) NOT NULL DEFAULT \'\',
          `empresa` varchar(120) NOT NULL DEFAULT \'\',
          `foto_hash` char(40) NOT NULL DEFAULT \'\',
          `vector` mediumtext NOT NULL,
          `modelo` varchar(40) NOT NULL DEFAULT \'arcface-w600k_mbf\',
          `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`dni`)
        ) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4'
    );
}

/** @return list<array{dni:string,nombre:string,empresa:string,path:string}> */
function bio_ver_galeria(mysqli $conn): array
{
    $out = [];
    $vistos = [];
    if (bio_nom_tabla_existe($conn, 'bio_personal')) {
        $col = bio_ver_col($conn, 'bio_personal');
        if ($col !== null) {
            $sql = "SELECT TRIM(p.dni) AS dni,
                           TRIM(CONCAT(TRIM(IFNULL(p.nombres,'')), ' ', TRIM(IFNULL(p.apellidos,'')))) AS nombre,
                           TRIM(`{$col}`) AS foto,
                           TRIM(IFNULL(e.razon_social, IFNULL(p.empresa,''))) AS empresa
                      FROM bio_personal p
                      LEFT JOIN bio_empresa e ON e.id = p.empresa_id
                     WHERE TRIM(`{$col}`) <> ''";
            $rs = @$conn->query($sql);
            if (!$rs) {
                $sql = "SELECT TRIM(dni) AS dni,
                               TRIM(CONCAT(TRIM(IFNULL(nombres,'')), ' ', TRIM(IFNULL(apellidos,'')))) AS nombre,
                               TRIM(`{$col}`) AS foto, '' AS empresa
                          FROM bio_personal WHERE TRIM(`{$col}`) <> ''";
                $rs = @$conn->query($sql);
            }
            while ($rs && ($row = $rs->fetch_assoc())) {
                $item = bio_ver_item($row);
                if ($item === null || isset($vistos[$item['dni']])) {
                    continue;
                }
                $vistos[$item['dni']] = true;
                $out[] = $item;
            }
        }
    }
    if (bio_nom_tabla_existe($conn, 'san_personal_proveedor')) {
        $col = bio_ver_col($conn, 'san_personal_proveedor');
        if ($col !== null) {
            $rs = @$conn->query(
                "SELECT TRIM(dni) AS dni, TRIM(nombre) AS nombre, TRIM(`{$col}`) AS foto, '' AS empresa
                   FROM san_personal_proveedor WHERE TRIM(`{$col}`) <> ''"
            );
            while ($rs && ($row = $rs->fetch_assoc())) {
                $item = bio_ver_item($row);
                if ($item === null || isset($vistos[$item['dni']])) {
                    continue;
                }
                $vistos[$item['dni']] = true;
                $out[] = $item;
            }
        }
    }

    return $out;
}

function bio_ver_col(mysqli $conn, string $tabla): ?string
{
    $r = @$conn->query('SHOW COLUMNS FROM `' . str_replace('`', '', $tabla) . '`');
    if (!$r) {
        return null;
    }
    $cols = [];
    while ($c = $r->fetch_assoc()) {
        $cols[strtolower((string) $c['Field'])] = (string) $c['Field'];
    }
    foreach (['foto_ruta', 'foto', 'ruta_foto', 'imagen'] as $c) {
        if (isset($cols[$c])) {
            return $cols[$c];
        }
    }

    return null;
}

/** @param array<string,mixed> $row */
function bio_ver_item(array $row): ?array
{
    $dni = preg_replace('/\D/', '', (string) ($row['dni'] ?? '')) ?? '';
    if (strlen($dni) < 6 || strlen($dni) > 15) {
        return null;
    }
    $path = bio_ver_archivo((string) ($row['foto'] ?? ''));
    if ($path === null) {
        return null;
    }
    $nombre = trim((string) ($row['nombre'] ?? ''));

    return [
        'dni' => $dni,
        'nombre' => $nombre !== '' ? $nombre : $dni,
        'empresa' => trim((string) ($row['empresa'] ?? '')),
        'path' => $path,
    ];
}

function bio_ver_archivo(string $ruta): ?string
{
    $ruta = trim($ruta);
    if ($ruta === '') {
        return null;
    }
    if (is_file($ruta)) {
        return $ruta;
    }
    $rel = ltrim($ruta, '/');
    foreach ([
        __DIR__ . '/api/public/' . $rel,
        __DIR__ . '/../api/public/' . $rel,
        dirname(__DIR__, 2) . '/portalbioseguridad/api/public/' . $rel,
        dirname(__DIR__, 3) . '/portalbioseguridad/api/public/' . $rel,
    ] as $c) {
        if (is_file($c)) {
            return $c;
        }
    }

    return null;
}

/** @return array<string,array{foto_hash:string,vector:list<float>}> */
function bio_ver_cache(mysqli $conn): array
{
    $out = [];
    $rs = @$conn->query('SELECT dni, foto_hash, vector FROM bio_rostro_plantilla');
    while ($rs && ($row = $rs->fetch_assoc())) {
        $vec = json_decode((string) ($row['vector'] ?? ''), true);
        if (!is_array($vec)) {
            continue;
        }
        $floats = [];
        foreach ($vec as $n) {
            $floats[] = (float) $n;
        }
        $out[(string) $row['dni']] = [
            'foto_hash' => (string) ($row['foto_hash'] ?? ''),
            'vector' => $floats,
        ];
    }

    return $out;
}

/**
 * @param list<array{id:string,path:string}> $imagenes
 * @return array<string,list<float>>|null
 */
function bio_ver_embed(array $imagenes): ?array
{
    $arc = bio_ver_modelo('w600k_mbf.onnx');
    $yunet = bio_ver_modelo('face_detection_yunet_2023mar.onnx');
    $py = bio_ver_python();
    if ($arc === null || $yunet === null || $py === null) {
        return null;
    }
    $cmd = bio_ver_cmd($py, __DIR__ . '/rostro_embed.py', $arc, $yunet);
    $spec = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    // bypass_shell en Windows: CreateProcess recibe el comando ya entre comillas
    // y el pipe 0 es el stdin de python. Con cmd.exe /c ese JSON no llega.
    $opts = ['bypass_shell' => PHP_OS_FAMILY === 'Windows'];
    $proc = proc_open($cmd, $spec, $pipes, null, null, $opts);
    if (!is_resource($proc)) {
        return null;
    }
    $payload = json_encode(['imagenes' => $imagenes], JSON_UNESCAPED_UNICODE);
    if (!is_string($payload)) {
        fclose($pipes[0]);
        fclose($pipes[1]);
        fclose($pipes[2]);
        proc_close($proc);
        return null;
    }
    stream_set_blocking($pipes[0], true);
    fwrite($pipes[0], $payload);
    fclose($pipes[0]);
    $stdout = bio_ver_leer_pipe($pipes[1], $pipes[2], $proc);
    fclose($pipes[1]);
    fclose($pipes[2]);
    proc_close($proc);
    $json = json_decode($stdout ?: '', true);
    if (!is_array($json) || empty($json['ok']) || !is_array($json['vectores'] ?? null)) {
        return null;
    }
    $out = [];
    foreach ($json['vectores'] as $id => $vec) {
        if (!is_array($vec) || count($vec) !== 512) {
            continue;
        }
        $floats = [];
        foreach ($vec as $n) {
            $floats[] = (float) $n;
        }
        $out[(string) $id] = $floats;
    }

    return $out;
}

function bio_ver_modelo(string $nombre): ?string
{
    foreach ([__DIR__ . '/models/' . $nombre, __DIR__ . '/../assets/models/' . $nombre] as $p) {
        if (is_file($p)) {
            return $p;
        }
    }

    return null;
}

function bio_ver_python(): ?string
{
    $fijo = bio_ver_python_fijo();
    if ($fijo !== null) {
        return $fijo;
    }
    if (PHP_OS_FAMILY === 'Windows') {
        foreach (['python', 'py'] as $bin) {
            $path = bio_ver_where($bin);
            if ($path !== null) {
                return $path;
            }
        }

        return null;
    }
    foreach (['python3', 'python'] as $bin) {
        $out = [];
        $code = 1;
        @exec('command -v ' . escapeshellarg($bin) . ' 2>/dev/null', $out, $code);
        $path = ($code === 0 && !empty($out[0])) ? trim((string) $out[0]) : '';
        if ($path !== '' && is_file($path)) {
            return $path;
        }
    }

    return null;
}

/** Ruta absoluta en la constante BIO_PYTHON o en la variable de entorno homónima. */
function bio_ver_python_fijo(): ?string
{
    $raw = '';
    if (defined('BIO_PYTHON')) {
        $raw = trim((string) BIO_PYTHON);
    }
    if ($raw === '') {
        $env = getenv('BIO_PYTHON');
        if (is_string($env)) {
            $raw = trim($env);
        }
    }
    if ($raw === '' || !bio_ver_ruta_absoluta($raw) || !is_file($raw)) {
        return null;
    }
    if (PHP_OS_FAMILY === 'Windows' && stripos($raw, '\\WindowsApps\\') !== false) {
        return null;
    }

    return $raw;
}

function bio_ver_ruta_absoluta(string $path): bool
{
    if (PHP_OS_FAMILY === 'Windows') {
        return (bool) preg_match('/^[A-Za-z]:[\\\\\\/]/', $path) || str_starts_with($path, '\\\\');
    }

    return str_starts_with($path, '/');
}

/** Primera ruta de `where` que no sea el alias de la Microsoft Store. */
function bio_ver_where(string $bin): ?string
{
    $out = [];
    $code = 1;
    @exec('where ' . $bin . ' 2>NUL', $out, $code);
    if ($code !== 0) {
        return null;
    }
    foreach ($out as $line) {
        $path = trim((string) $line);
        if ($path === '' || stripos($path, '\\WindowsApps\\') !== false) {
            continue;
        }
        if (is_file($path)) {
            return $path;
        }
    }

    return null;
}

function bio_ver_quote(string $arg): string
{
    if (PHP_OS_FAMILY === 'Windows') {
        return '"' . str_replace('"', '', $arg) . '"';
    }

    return escapeshellarg($arg);
}

function bio_ver_cmd(string $py, string $script, string $arc, string $yunet): string
{
    // Cada ruta entre comillas dobles, que es lo que cmd y CreateProcess aceptan.
    return bio_ver_quote($py) . ' ' . bio_ver_quote($script)
        . ' --arcface ' . bio_ver_quote($arc)
        . ' --yunet ' . bio_ver_quote($yunet);
}

/** Lee stdout sin dejar el buffer de stderr lleno (eso cuelga el pipe en Windows). */
function bio_ver_leer_pipe($stdoutPipe, $stderrPipe, $proc): string
{
    stream_set_blocking($stdoutPipe, false);
    stream_set_blocking($stderrPipe, false);
    $stdout = '';
    while (true) {
        $stdout .= (string) stream_get_contents($stdoutPipe);
        stream_get_contents($stderrPipe);
        $status = proc_get_status($proc);
        if (empty($status['running'])) {
            $stdout .= (string) stream_get_contents($stdoutPipe);
            stream_get_contents($stderrPipe);
            break;
        }
        usleep(20000);
    }

    return $stdout;
}

/** @param array{dni:string,nombre:string,empresa:string,hash?:string} $p */
function bio_ver_guardar(mysqli $conn, array $p, array $vec): void
{
    $json = json_encode(array_values($vec));
    if (!is_string($json)) {
        return;
    }
    $st = $conn->prepare(
        'INSERT INTO bio_rostro_plantilla (dni, nombre, empresa, foto_hash, vector, modelo, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, NOW())
         ON DUPLICATE KEY UPDATE nombre = VALUES(nombre), empresa = VALUES(empresa),
           foto_hash = VALUES(foto_hash), vector = VALUES(vector), modelo = VALUES(modelo), updated_at = NOW()'
    );
    if (!$st) {
        return;
    }
    $dni = $p['dni'];
    $nombre = substr($p['nombre'], 0, 120);
    $empresa = substr($p['empresa'], 0, 120);
    $hash = (string) ($p['hash'] ?? '');
    $modelo = BIO_VER_MODELO;
    $st->bind_param('ssssss', $dni, $nombre, $empresa, $hash, $json, $modelo);
    $st->execute();
    $st->close();
}

function bio_ver_coseno(array $a, array $b): float
{
    $s = 0.0;
    $n = min(count($a), count($b));
    for ($i = 0; $i < $n; $i++) {
        $s += $a[$i] * $b[$i];
    }

    return $s;
}

function bio_ver_limpiar(string $dir): void
{
    foreach (glob($dir . '/*') ?: [] as $f) {
        @unlink($f);
    }
    @rmdir($dir);
}
