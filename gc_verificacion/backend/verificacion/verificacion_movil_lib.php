<?php
declare(strict_types=1);

function veri_conectar(): ?mysqli
{
    if (!function_exists('conectar_joya_mysqli')) {
        return null;
    }
    $conn = conectar_joya_mysqli();
    if (!$conn instanceof mysqli) {
        return null;
    }
    mysqli_set_charset($conn, 'utf8mb4');
    return $conn;
}

function veri_json(int $status, bool $success, string $message, ?array $data = null): void
{
    if (ob_get_level()) {
        ob_clean();
    }
    http_response_code($status);
    $out = [
        'success' => $success,
        'message' => $message,
    ];
    if ($data !== null) {
        $out['data'] = $data;
    }
    echo json_encode($out, JSON_UNESCAPED_UNICODE);
    exit;
}

function veri_utf8(string $s): string
{
    if ($s === '' || mb_check_encoding($s, 'UTF-8')) {
        return $s;
    }
    $conv = @mb_convert_encoding($s, 'UTF-8', 'ISO-8859-1');
    return $conv === false ? $s : $conv;
}

function veri_corte(string $s, int $max): string
{
    if ($max > 0 && mb_strlen($s) > $max) {
        return mb_substr($s, 0, $max);
    }
    return $s;
}

function veri_tabla_existe(mysqli $conn, string $tabla): bool
{
    if (!preg_match('/^[A-Za-z0-9_]+$/', $tabla)) {
        return false;
    }
    $t = $conn->real_escape_string($tabla);
    $res = $conn->query("SHOW TABLES LIKE '$t'");
    return $res !== false && $res->num_rows > 0;
}

function veri_token_ok(): bool
{
    if (!defined('API_TOKEN')) {
        return false;
    }
    $auth = '';
    if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
        $auth = (string) $_SERVER['HTTP_AUTHORIZATION'];
    } elseif (isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
        $auth = (string) $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
    } elseif (function_exists('getallheaders')) {
        $h = getallheaders();
        if (isset($h['Authorization'])) {
            $auth = (string) $h['Authorization'];
        } elseif (isset($h['authorization'])) {
            $auth = (string) $h['authorization'];
        }
    }
    return $auth === 'Bearer ' . API_TOKEN;
}

function veri_exigir_token(): void
{
    if (!defined('API_TOKEN')) {
        veri_json(500, false, 'Configuración incompleta del servidor');
    }
    if (!veri_token_ok()) {
        veri_json(401, false, 'Acceso denegado. Token inválido');
    }
}

function veri_tablas_ok(mysqli $conn): bool
{
    $tablas = [
        'veri_plantilla',
        'veri_evento',
        'veri_nomina_snap',
        'veri_nomina_cambio',
    ];
    foreach ($tablas as $t) {
        if (!veri_tabla_existe($conn, $t)) {
            return false;
        }
    }
    return true;
}

function veri_max_seq(mysqli $conn): int
{
    $rs = $conn->query('SELECT MAX(seq) AS m FROM veri_nomina_cambio');
    if (!$rs) {
        return 0;
    }
    $row = $rs->fetch_assoc();
    return (int) ($row['m'] ?? 0);
}

function veri_min_seq(mysqli $conn): int
{
    $rs = $conn->query('SELECT MIN(seq) AS m FROM veri_nomina_cambio');
    if (!$rs) {
        return 0;
    }
    $row = $rs->fetch_assoc();
    return (int) ($row['m'] ?? 0);
}

function veri_prune_cambios(mysqli $conn): void
{
    @$conn->query('DELETE FROM veri_nomina_cambio WHERE created_at < (NOW() - INTERVAL 30 DAY)');
}

/** @return array<string, array<string,string>> */
function veri_roster(mysqli $conn): array
{
    $out = [];
    $rs = $conn->query(
        "SELECT dni, nombre, modelo, updated_at FROM veri_plantilla WHERE estado = 'A' ORDER BY dni"
    );
    if ($rs) {
        while ($row = $rs->fetch_assoc()) {
            $dni = preg_replace('/\D/', '', (string) ($row['dni'] ?? '')) ?? '';
            if ($dni === '' || isset($out[$dni])) {
                continue;
            }
            $out[$dni] = [
                'dni' => $dni,
                'nombre' => veri_utf8(trim((string) ($row['nombre'] ?? ''))),
                'modelo' => trim((string) ($row['modelo'] ?? '')),
                'updated_at' => (string) ($row['updated_at'] ?? ''),
            ];
        }
    }
    return $out;
}

/** @return array<string, array<string,mixed>> */
function veri_plantillas(mysqli $conn, array $dnis): array
{
    $out = [];
    $dnis = array_values(array_unique($dnis));
    if ($dnis === []) {
        return $out;
    }
    foreach (array_chunk($dnis, 500) as $lote) {
        $ph = implode(',', array_fill(0, count($lote), '?'));
        $st = $conn->prepare(
            "SELECT dni, vector, miniatura, modelo, updated_at FROM veri_plantilla WHERE dni IN ($ph)"
        );
        if (!$st) {
            continue;
        }
        $types = str_repeat('s', count($lote));
        $refs = [];
        foreach ($lote as $i => $v) {
            $refs[$i] = &$lote[$i];
        }
        $st->bind_param($types, ...$refs);
        $st->execute();
        $rs = $st->get_result();
        if ($rs) {
            while ($row = $rs->fetch_assoc()) {
                $out[(string) $row['dni']] = $row;
            }
        }
        $st->close();
    }
    return $out;
}

function veri_huella(array $persona): string
{
    return md5(
        ($persona['nombre'] ?? '') . '|' .
        ($persona['modelo'] ?? '') . '|' .
        ($persona['updated_at'] ?? '')
    );
}

/** @return array<string,string> */
function veri_snapshot(mysqli $conn): array
{
    $out = [];
    $rs = $conn->query('SELECT dni, huella FROM veri_nomina_snap');
    if ($rs) {
        while ($row = $rs->fetch_assoc()) {
            $out[(string) $row['dni']] = (string) $row['huella'];
        }
    }
    return $out;
}

function veri_registrar_cambio(mysqli $conn, string $dni, string $accion): void
{
    $st = $conn->prepare('INSERT INTO veri_nomina_cambio (dni, accion) VALUES (?, ?)');
    if ($st) {
        $st->bind_param('ss', $dni, $accion);
        @$st->execute();
        $st->close();
    }
}

function veri_diff_and_log(mysqli $conn, array $roster): int
{
    $snap = veri_snapshot($conn);
    $altas = [];
    foreach ($roster as $dni => $persona) {
        $dni = (string) $dni;
        $h = veri_huella($persona);
        if (!isset($snap[$dni]) || $snap[$dni] !== $h) {
            $altas[$dni] = $h;
        }
    }
    $bajas = [];
    foreach ($snap as $dni => $h) {
        $dni = (string) $dni;
        if (!isset($roster[$dni])) {
            $bajas[] = $dni;
        }
    }
    if ($altas === [] && $bajas === []) {
        return veri_max_seq($conn);
    }
    $stSnap = $conn->prepare(
        'INSERT INTO veri_nomina_snap (dni, huella) VALUES (?, ?) ON DUPLICATE KEY UPDATE huella = VALUES(huella)'
    );
    foreach ($altas as $dni => $h) {
        $dni = (string) $dni;
        if ($stSnap) {
            $stSnap->bind_param('ss', $dni, $h);
            @$stSnap->execute();
        }
        veri_registrar_cambio($conn, $dni, 'A');
    }
    if ($stSnap) {
        $stSnap->close();
    }
    $stDel = $conn->prepare('DELETE FROM veri_nomina_snap WHERE dni = ?');
    foreach ($bajas as $dni) {
        if ($stDel) {
            $stDel->bind_param('s', $dni);
            @$stDel->execute();
        }
        veri_registrar_cambio($conn, $dni, 'B');
    }
    if ($stDel) {
        $stDel->close();
    }
    veri_prune_cambios($conn);
    return veri_max_seq($conn);
}

/** @return array<string,mixed>|null */
function veri_plantilla_publica(array $row): ?array
{
    $vec = json_decode((string) ($row['vector'] ?? ''), true);
    if (!is_array($vec) || count($vec) !== 512) {
        return null;
    }
    return [
        'vector' => array_values($vec),
        'miniatura' => (string) ($row['miniatura'] ?? ''),
        'modelo' => (string) ($row['modelo'] ?? ''),
        'updated_at' => (string) ($row['updated_at'] ?? ''),
    ];
}

/** @return array<string,mixed> */
function veri_alta_row(array $persona, array $plantillas): array
{
    $dni = $persona['dni'];
    return [
        'dni' => $dni,
        'nombre' => (string) ($persona['nombre'] ?? ''),
        'plantilla' => isset($plantillas[$dni])
            ? veri_plantilla_publica($plantillas[$dni])
            : null,
    ];
}

/** @return array{id:string,ok:bool,message:string} */
function veri_insertar_evento(mysqli $conn, array $item): array
{
    $id = veri_corte(trim((string) ($item['uuid'] ?? '')), 36);
    if ($id === '') {
        return ['id' => '', 'ok' => false, 'message' => 'Sin uuid'];
    }
    $dni = preg_replace('/\D/', '', (string) ($item['dni'] ?? '')) ?? '';
    $dni = substr($dni, 0, 8);

    $fecha = trim((string) ($item['fecha'] ?? ''));
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $fecha)) {
        $fecha = date('Y-m-d');
    }
    $hora = trim((string) ($item['hora'] ?? ''));
    if (!preg_match('/^\d{2}:\d{2}(:\d{2})?$/', $hora)) {
        $hora = date('H:i:s');
    } elseif (strlen($hora) === 5) {
        $hora .= ':00';
    }

    $resultado = strtoupper(trim((string) ($item['resultado'] ?? 'A')));
    if ($resultado !== 'R') {
        $resultado = 'A';
    }
    $sim = null;
    if (isset($item['similitud']) && is_numeric($item['similitud'])) {
        $f = (float) $item['similitud'];
        if ($f >= 0 && $f <= 1) {
            $sim = $f;
        }
    }
    $modo = trim((string) ($item['modo'] ?? '1N'));
    if ($modo !== '11') {
        $modo = '1N';
    }
    $tidandroid = veri_corte(trim((string) ($item['tidandroid'] ?? '')), 80);
    $usuario = veri_corte(trim((string) ($item['usuario'] ?? '')), 30);
    $createdApp = null;
    $rawCreated = trim((string) ($item['created_at'] ?? ''));
    if (preg_match('/^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}(:\d{2})?)/', $rawCreated, $m)) {
        $createdApp = $m[1] . ' ' . $m[2] . (strlen($m[2]) === 5 ? ':00' : '');
    }

    $st = $conn->prepare('SELECT 1 FROM veri_evento WHERE uuid = ? LIMIT 1');
    if ($st) {
        $st->bind_param('s', $id);
        $st->execute();
        $st->store_result();
        $existe = $st->num_rows > 0;
        $st->close();
        if ($existe) {
            return ['id' => $id, 'ok' => true, 'message' => 'Ya estaba'];
        }
    }

    $st = $conn->prepare(
        'INSERT INTO veri_evento (uuid, dni, fecha, hora, resultado, similitud, modo, tidandroid, usuario, created_app, dia_serv, hora_serv) ' .
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURDATE(), CURTIME())'
    );
    if (!$st) {
        return ['id' => $id, 'ok' => false, 'message' => $conn->error];
    }
    $simStr = $sim === null ? null : (string) $sim;
    $st->bind_param(
        'ssssssssss',
        $id,
        $dni,
        $fecha,
        $hora,
        $resultado,
        $simStr,
        $modo,
        $tidandroid,
        $usuario,
        $createdApp
    );
    $hecho = $st->execute();
    $err = $st->error;
    $st->close();
    if (!$hecho) {
        if (stripos($err, 'duplicate') !== false) {
            return ['id' => $id, 'ok' => true, 'message' => 'Ya estaba'];
        }
        return ['id' => $id, 'ok' => false, 'message' => $err !== '' ? $err : 'No se insertó'];
    }
    return ['id' => $id, 'ok' => true, 'message' => 'Insertado'];
}

function veri_puede_enrolar(mysqli $conn, string $usuario): bool
{
    $usuario = trim($usuario);
    if ($usuario === '' || !veri_tabla_existe($conn, 'veri_enrolador')) {
        return false;
    }
    $st = $conn->prepare("SELECT 1 FROM veri_enrolador WHERE usuario = ? AND estado = 'A' LIMIT 1");
    if (!$st) {
        return false;
    }
    $st->bind_param('s', $usuario);
    $st->execute();
    $st->store_result();
    $ok = $st->num_rows > 0;
    $st->close();
    return $ok;
}
