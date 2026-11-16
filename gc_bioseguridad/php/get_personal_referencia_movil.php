<?php
declare(strict_types=1);

/**
 * Personal que puede llegar a la granja, para la tranquera.
 * Une bio_personal (foto_ruta del alta) y san_personal_proveedor, sin duplicar DNI.
 * No filtra por el usuario logueado.
 */

ob_start();
require_once __DIR__ . '/auth_movil.php';
bio_cors_headers();
date_default_timezone_set('America/Lima');
bio_validate_bearer_token();

require_once __DIR__ . '/nomina_proveedor_movil_lib.php';

if (!function_exists('conectar_joya_mysqli')) {
    bio_send_json(200, false, 'personal', null, 'SIN_CONEXION');
}

$conn = conectar_joya_mysqli();
if (!$conn) {
    bio_send_json(200, false, 'personal', null, 'SIN_CONEXION');
}

/**
 * @return list<array{dni:string,nombre:string,tiene_foto:bool}>
 */
function bio_ref_personas(mysqli $conn): array
{
    $porDni = [];

    if (bio_nom_tabla_existe($conn, 'bio_personal')) {
        $foto = bio_ref_columna($conn, 'bio_personal', ['foto_ruta', 'foto', 'ruta_foto', 'imagen']);
        $fotoSql = $foto !== null ? ", TRIM(`{$foto}`) AS foto" : ", '' AS foto";
        $estado = bio_ref_columna($conn, 'bio_personal', ['estado']);
        $where = $estado !== null ? "WHERE UPPER(TRIM(`{$estado}`)) = 'ACTIVO'" : '';
        $filas = bio_nom_filas(
            $conn,
            "SELECT TRIM(dni) AS dni,
                    TRIM(CONCAT(TRIM(IFNULL(nombres,'')), ' ', TRIM(IFNULL(apellidos,'')))) AS nombre
                    {$fotoSql}
               FROM bio_personal {$where}"
        );
        foreach ($filas as $row) {
            $dni = bio_ref_dni((string) ($row['dni'] ?? ''));
            if ($dni === '') {
                continue;
            }
            $nombre = trim((string) ($row['nombre'] ?? ''));
            $ruta = trim((string) ($row['foto'] ?? ''));
            $porDni[$dni] = [
                'dni' => $dni,
                'nombre' => $nombre !== '' ? $nombre : $dni,
                'tiene_foto' => $ruta !== '',
            ];
        }
    }

    if (bio_nom_tabla_existe($conn, 'san_personal_proveedor')) {
        $foto = bio_ref_columna($conn, 'san_personal_proveedor', ['foto_ruta', 'foto', 'ruta_foto', 'imagen']);
        $fotoSql = $foto !== null ? ", TRIM(`{$foto}`) AS foto" : ", '' AS foto";
        $activo = bio_ref_columna($conn, 'san_personal_proveedor', ['activo']);
        $where = $activo !== null ? "WHERE `{$activo}` = 1" : '';
        $filas = bio_nom_filas(
            $conn,
            "SELECT TRIM(dni) AS dni, TRIM(nombre) AS nombre {$fotoSql}
               FROM san_personal_proveedor {$where}"
        );
        foreach ($filas as $row) {
            $dni = bio_ref_dni((string) ($row['dni'] ?? ''));
            if ($dni === '' || isset($porDni[$dni])) {
                continue;
            }
            $nombre = trim((string) ($row['nombre'] ?? ''));
            $ruta = trim((string) ($row['foto'] ?? ''));
            $porDni[$dni] = [
                'dni' => $dni,
                'nombre' => $nombre !== '' ? $nombre : $dni,
                'tiene_foto' => $ruta !== '',
            ];
        }
    }

    $out = array_values($porDni);
    usort($out, static function (array $a, array $b): int {
        return strcmp($a['nombre'], $b['nombre']);
    });

    return $out;
}

function bio_ref_dni(string $raw): string
{
    $d = preg_replace('/\D/', '', $raw) ?? '';

    return (strlen($d) >= 6 && strlen($d) <= 15) ? $d : '';
}

function bio_ref_columna(mysqli $conn, string $tabla, array $candidatas): ?string
{
    $r = @$conn->query('SHOW COLUMNS FROM `' . str_replace('`', '', $tabla) . '`');
    if (!$r) {
        return null;
    }
    $cols = [];
    while ($c = $r->fetch_assoc()) {
        $cols[strtolower((string) $c['Field'])] = (string) $c['Field'];
    }
    foreach ($candidatas as $c) {
        if (isset($cols[$c])) {
            return $cols[$c];
        }
    }

    return null;
}

try {
    $hay = bio_nom_tabla_existe($conn, 'bio_personal')
        || bio_nom_tabla_existe($conn, 'san_personal_proveedor');
    $personas = $hay ? bio_ref_personas($conn) : [];
    $conn->close();
} catch (Throwable $e) {
    error_log('[bioseguridad] get_personal_referencia: ' . $e->getMessage());
    bio_send_json(200, false, 'personal', null, 'PERSONAL');
}

if (!$hay) {
    bio_send_json(200, false, 'personal', null, 'PERSONAL');
}

bio_send_json(200, true, 'Personal', ['personas' => $personas]);
