<?php
declare(strict_types=1);

/**
 * Foto ya registrada del personal (bio_personal.foto_ruta o la del proveedor).
 * GET ?dni=
 */

ob_start();
require_once __DIR__ . '/php7_compat.php';
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/nomina_proveedor_movil_lib.php';

$dni = preg_replace('/\D/', '', (string) ($_GET['dni'] ?? '')) ?? '';
if ($dni === '' || !function_exists('conectar_joya_mysqli')) {
    bio_send_json(404, false, 'Sin foto', null, 'SIN_FOTO');
}

$conn = conectar_joya_mysqli();
if (!$conn) {
    bio_send_json(404, false, 'Sin foto', null, 'SIN_FOTO');
}

$ruta = bio_foto_ruta($conn, $dni);
$conn->close();
$abs = $ruta !== '' ? bio_foto_archivo($ruta) : null;
if ($abs === null) {
    bio_send_json(404, false, 'Sin foto', null, 'SIN_FOTO');
}

if (ob_get_length()) {
    ob_end_clean();
}
$mime = function_exists('mime_content_type') ? (mime_content_type($abs) ?: 'image/jpeg') : 'image/jpeg';
header('Content-Type: ' . $mime);
header('Content-Length: ' . (string) filesize($abs));
header('Cache-Control: private, max-age=300');
readfile($abs);
exit;

function bio_foto_ruta(mysqli $conn, string $dni): string
{
    if (bio_nom_tabla_existe($conn, 'bio_personal')) {
        $col = bio_foto_col($conn, 'bio_personal');
        if ($col !== null) {
            $st = $conn->prepare(
                "SELECT TRIM(`{$col}`) AS foto FROM bio_personal WHERE TRIM(dni) = ? AND TRIM(`{$col}`) <> '' LIMIT 1"
            );
            if ($st) {
                $st->bind_param('s', $dni);
                $st->execute();
                $row = $st->get_result()->fetch_assoc();
                $st->close();
                $foto = trim((string) ($row['foto'] ?? ''));
                if ($foto !== '') {
                    return $foto;
                }
            }
        }
    }
    if (bio_nom_tabla_existe($conn, 'san_personal_proveedor')) {
        $col = bio_foto_col($conn, 'san_personal_proveedor');
        if ($col !== null) {
            $st = $conn->prepare(
                "SELECT TRIM(`{$col}`) AS foto FROM san_personal_proveedor WHERE TRIM(dni) = ? AND TRIM(`{$col}`) <> '' LIMIT 1"
            );
            if ($st) {
                $st->bind_param('s', $dni);
                $st->execute();
                $row = $st->get_result()->fetch_assoc();
                $st->close();
                return trim((string) ($row['foto'] ?? ''));
            }
        }
    }

    return '';
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
    $rel = str_replace('\\', '/', $ruta);
    $marca = 'storage/personal/';
    $pos = stripos($rel, $marca);
    if ($pos !== false) {
        $rel = substr($rel, $pos);
    }
    $rel = ltrim($rel, '/');
    $candidatos = [
        'C:/xampp/htdocs/bioseguridad/api/public/' . $rel,
        'C:/xampp/htdocs/sanidad/bioseguridad/api/public/' . $rel,
    ];
    if (!empty($_SERVER['DOCUMENT_ROOT'])) {
        $doc = rtrim(str_replace('\\', '/', (string) $_SERVER['DOCUMENT_ROOT']), '/');
        $candidatos[] = $doc . '/bioseguridad/api/public/' . $rel;
        $candidatos[] = dirname($doc) . '/bioseguridad/api/public/' . $rel;
    }
    $candidatos[] = __DIR__ . '/api/public/' . $rel;
    $candidatos[] = dirname(__DIR__) . '/bioseguridad/api/public/' . $rel;
    foreach ($candidatos as $c) {
        if (is_file($c)) {
            return $c;
        }
    }

    return null;
}
