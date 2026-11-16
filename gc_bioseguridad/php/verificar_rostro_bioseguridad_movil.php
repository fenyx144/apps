<?php
declare(strict_types=1);

/**
 * Valida en el servidor la foto capturada contra la foto ya registrada
 * de ese DNI (bio_personal.foto_ruta o san_personal_proveedor).
 *
 * POST JSON: { "dni": "12345678", "foto": "<jpeg base64>" }
 * Mismo sobre que guardar_plantilla_movil.php de gc_verificacion
 * (success, message, data). La decisión no se toma en el teléfono.
 *
 * data.verificado  true|false
 * data.motivo      ok | sin_foto | no_coincide | sin_rostro
 */

ob_start();
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/nomina_proveedor_movil_lib.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    bio_send_json(405, false, 'Use POST');
}

$raw = file_get_contents('php://input') ?: '';
$body = json_decode($raw, true);
if (!is_array($body)) {
    bio_send_json(400, false, 'JSON inválido');
}

$dni = preg_replace('/\D/', '', (string) ($body['dni'] ?? '')) ?? '';
if (strlen($dni) < 6 || strlen($dni) > 15) {
    bio_send_json(400, false, 'DNI no válido');
}

$foto = trim((string) ($body['foto'] ?? ''));
if (strncmp($foto, 'data:', 5) === 0) {
    $pos = strpos($foto, ',');
    $foto = $pos === false ? '' : substr($foto, $pos + 1);
}
if ($foto === '' || strlen($foto) > 800000) {
    bio_send_json(400, false, 'Foto no válida');
}
$bin = base64_decode($foto, true);
if ($bin === false || strlen($bin) < 32) {
    bio_send_json(400, false, 'Foto no válida');
}

if (!function_exists('conectar_joya_mysqli')) {
    bio_send_json(200, false, 'sin señal', ['verificado' => false, 'motivo' => 'sin_senal', 'dni' => $dni]);
}
$conn = conectar_joya_mysqli();
if (!$conn) {
    bio_send_json(200, false, 'sin señal', ['verificado' => false, 'motivo' => 'sin_senal', 'dni' => $dni]);
}

$ficha = bio_ver_ficha($conn, $dni);
$conn->close();

$nombre = $ficha['nombre'] ?? '';
$ruta = $ficha['foto'] ?? '';
$abs = $ruta !== '' ? bio_foto_archivo($ruta) : null;
if ($abs === null) {
    bio_send_json(200, true, 'Sin foto', [
        'verificado' => false,
        'motivo' => 'sin_foto',
        'dni' => $dni,
        'nombre' => $nombre,
    ]);
}

$ref = @file_get_contents($abs);
if ($ref === false || $ref === '') {
    bio_send_json(200, true, 'Sin foto', [
        'verificado' => false,
        'motivo' => 'sin_foto',
        'dni' => $dni,
        'nombre' => $nombre,
    ]);
}

$ha = bio_ver_dhash($bin);
$hb = bio_ver_dhash($ref);
if ($ha === null || $hb === null) {
    bio_send_json(200, true, 'Sin rostro', [
        'verificado' => false,
        'motivo' => 'sin_rostro',
        'dni' => $dni,
        'nombre' => $nombre,
    ]);
}

$dist = 0;
for ($i = 0; $i < 64; $i++) {
    if ($ha[$i] !== $hb[$i]) {
        $dist++;
    }
}
$sim = round(1 - ($dist / 64), 3);
$ok = $dist <= 18;

bio_send_json(200, true, $ok ? 'Coincide' : 'No coincide', [
    'verificado' => $ok,
    'motivo' => $ok ? 'ok' : 'no_coincide',
    'dni' => $dni,
    'nombre' => $nombre,
    'similitud' => $sim,
]);

/** @return array{nombre:string,foto:string} */
function bio_ver_ficha(mysqli $conn, string $dni): array
{
    $nombre = '';
    $foto = '';
    if (bio_nom_tabla_existe($conn, 'bio_personal')) {
        $col = bio_foto_col($conn, 'bio_personal');
        $fotoSql = $col !== null ? ", TRIM(`{$col}`) AS foto" : ", '' AS foto";
        $st = $conn->prepare(
            "SELECT TRIM(CONCAT(TRIM(IFNULL(nombres,'')), ' ', TRIM(IFNULL(apellidos,'')))) AS nombre
                    {$fotoSql}
               FROM bio_personal WHERE TRIM(dni) = ? LIMIT 1"
        );
        if ($st) {
            $st->bind_param('s', $dni);
            $st->execute();
            $row = $st->get_result()->fetch_assoc();
            $st->close();
            if ($row) {
                $nombre = trim((string) ($row['nombre'] ?? ''));
                $foto = trim((string) ($row['foto'] ?? ''));
            }
        }
    }
    if ($foto === '' && bio_nom_tabla_existe($conn, 'san_personal_proveedor')) {
        $col = bio_foto_col($conn, 'san_personal_proveedor');
        $fotoSql = $col !== null ? ", TRIM(`{$col}`) AS foto" : ", '' AS foto";
        $st = $conn->prepare(
            "SELECT TRIM(nombre) AS nombre {$fotoSql}
               FROM san_personal_proveedor WHERE TRIM(dni) = ? LIMIT 1"
        );
        if ($st) {
            $st->bind_param('s', $dni);
            $st->execute();
            $row = $st->get_result()->fetch_assoc();
            $st->close();
            if ($row) {
                if ($nombre === '') {
                    $nombre = trim((string) ($row['nombre'] ?? ''));
                }
                $foto = trim((string) ($row['foto'] ?? ''));
            }
        }
    }

    return ['nombre' => $nombre, 'foto' => $foto];
}

/** @return list<int>|null */
function bio_ver_dhash(string $bin): ?array
{
    if (!function_exists('imagecreatefromstring')) {
        return null;
    }
    $im = @imagecreatefromstring($bin);
    if (!$im) {
        return null;
    }
    $small = imagecreatetruecolor(9, 8);
    imagecopyresampled($small, $im, 0, 0, 0, 0, 9, 8, imagesx($im), imagesy($im));
    $bits = [];
    for ($y = 0; $y < 8; $y++) {
        for ($x = 0; $x < 8; $x++) {
            $izq = bio_ver_lum(imagecolorat($small, $x, $y));
            $der = bio_ver_lum(imagecolorat($small, $x + 1, $y));
            $bits[] = $izq > $der ? 1 : 0;
        }
    }
    imagedestroy($im);
    imagedestroy($small);

    return $bits;
}

function bio_ver_lum(int $rgb): int
{
    $r = ($rgb >> 16) & 255;
    $g = ($rgb >> 8) & 255;
    $b = $rgb & 255;

    return (int) round(0.299 * $r + 0.587 * $g + 0.114 * $b);
}

function bio_foto_col(mysqli $conn, string $tabla): ?string
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

function bio_foto_archivo(string $ruta): ?string
{
    $ruta = trim($ruta);
    if ($ruta === '') {
        return null;
    }
    if (is_file($ruta)) {
        return $ruta;
    }
    $rel = ltrim($ruta, '/');
    $candidatos = [
        __DIR__ . '/api/public/' . $rel,
        __DIR__ . '/../api/public/' . $rel,
        dirname(__DIR__, 2) . '/portalbioseguridad/api/public/' . $rel,
        dirname(__DIR__, 3) . '/portalbioseguridad/api/public/' . $rel,
    ];
    foreach ($candidatos as $c) {
        if (is_file($c)) {
            return $c;
        }
    }

    return null;
}
