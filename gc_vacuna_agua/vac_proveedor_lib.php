<?php
declare(strict_types=1);

/**
 * Laboratorios / proveedores habilitados para Vacuna al Agua (app móvil).
 * Mantener alineado con modules/configuracion/vacuna-agua/proveedores/vacunaagua_proveedor_lib.php
 */

const VAC_TABLA_PROVEEDOR = 'san_vacunaagua_proveedor';

function vac_proveedor_sql_create(): string
{
    return 'CREATE TABLE IF NOT EXISTS `' . VAC_TABLA_PROVEEDOR . '` (
        `ruc` varchar(11) NOT NULL,
        `activo` tinyint(1) NOT NULL DEFAULT 1,
        `usuarioReg` varchar(50) NOT NULL DEFAULT \'\',
        `fechaReg` datetime NULL DEFAULT NULL,
        PRIMARY KEY (`ruc`),
        KEY `idx_activo` (`activo`)
    ) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci';
}

function vac_proveedor_tabla_existe(mysqli $conn): bool
{
    $t = VAC_TABLA_PROVEEDOR;
    $rs = @$conn->query("SHOW TABLES LIKE '{$t}'");
    if (!$rs) {
        return false;
    }
    $ok = $rs->num_rows > 0;
    $rs->free();

    return $ok;
}

function vac_proveedor_ensure_tabla(mysqli $conn): bool
{
    if (vac_proveedor_tabla_existe($conn)) {
        return true;
    }
    if (@$conn->query(vac_proveedor_sql_create())) {
        return vac_proveedor_tabla_existe($conn);
    }

    return false;
}

function vac_proveedor_ensure_tabla_detalle(mysqli $conn): string
{
    if (vac_proveedor_ensure_tabla($conn)) {
        return '';
    }
    $err = trim((string) $conn->error);
    if ($err !== '') {
        return $err;
    }

    return 'No se pudo crear la tabla ' . VAC_TABLA_PROVEEDOR . '.';
}

function vac_proveedor_activos_count(mysqli $conn): int
{
    if (!vac_proveedor_tabla_existe($conn)) {
        return 0;
    }
    $rs = @$conn->query(
        'SELECT COUNT(*) AS n FROM `' . VAC_TABLA_PROVEEDOR . '` WHERE COALESCE(`activo`, 0) = 1'
    );
    if (!$rs || !($row = $rs->fetch_assoc())) {
        return 0;
    }
    $rs->free();

    return (int) ($row['n'] ?? 0);
}

/** @return list<array{ruc:string,razonsocial:string}> */
function vac_proveedor_lista_movil(mysqli $conn): array
{
    if (!vac_proveedor_tabla_existe($conn)) {
        return [];
    }
    $sql = '
        SELECT TRIM(p.ruc) AS ruc, TRIM(COALESCE(c.nombre, \'\')) AS razonsocial
        FROM `' . VAC_TABLA_PROVEEDOR . '` p
        LEFT JOIN ccte c ON TRIM(c.codigo) = TRIM(p.ruc)
        WHERE COALESCE(p.activo, 0) = 1
        ORDER BY razonsocial ASC
    ';
    $rs = @$conn->query($sql);
    if (!$rs) {
        return [];
    }
    $out = [];
    while ($row = $rs->fetch_assoc()) {
        $ruc = preg_replace('/\D/', '', (string) ($row['ruc'] ?? '')) ?? '';
        if (strlen($ruc) !== 11) {
            continue;
        }
        $nombre = trim((string) ($row['razonsocial'] ?? ''));
        if ($nombre === '') {
            continue;
        }
        $out[] = ['ruc' => $ruc, 'razonsocial' => $nombre];
    }
    $rs->free();

    return $out;
}

function vac_proveedor_sql_filtro_ccte(mysqli $conn, string $aliasCodigo = 'codigo'): string
{
    if (vac_proveedor_activos_count($conn) <= 0) {
        return '';
    }
    $col = $aliasCodigo;
    if (!preg_match('/^[a-zA-Z0-9_.]+$/', $col)) {
        $col = 'codigo';
    }

    return ' AND TRIM(' . $col . ') IN ('
        . 'SELECT TRIM(ruc) FROM `' . VAC_TABLA_PROVEEDOR . '` WHERE COALESCE(activo, 0) = 1'
        . ')';
}

/** @return array{ok:bool,message:string} */
function vac_proveedor_set_activo(mysqli $conn, string $ruc, bool $activo, string $usuario = ''): array
{
    $ruc = preg_replace('/\D/', '', $ruc) ?? '';
    if (strlen($ruc) !== 11) {
        return ['ok' => false, 'message' => 'RUC inválido (11 dígitos).'];
    }
    if (!vac_proveedor_ensure_tabla($conn)) {
        $det = vac_proveedor_ensure_tabla_detalle($conn);
        return [
            'ok' => false,
            'message' => 'No se pudo preparar la tabla de proveedores.'
                . ($det !== '' ? ' ' . $det : ''),
        ];
    }

    $st = $conn->prepare('SELECT TRIM(nombre) AS nombre FROM ccte WHERE TRIM(codigo) = ? LIMIT 1');
    if (!$st) {
        return ['ok' => false, 'message' => 'Error al validar el proveedor.'];
    }
    $st->bind_param('s', $ruc);
    $st->execute();
    $rs = $st->get_result();
    $nombre = '';
    if ($rs && ($row = $rs->fetch_assoc())) {
        $nombre = trim((string) ($row['nombre'] ?? ''));
    }
    $st->close();
    if ($nombre === '') {
        return ['ok' => false, 'message' => 'No se encontró ese proveedor en el sistema.'];
    }

    if (!$activo) {
        $del = $conn->prepare('DELETE FROM `' . VAC_TABLA_PROVEEDOR . '` WHERE TRIM(ruc) = ?');
        if (!$del) {
            return ['ok' => false, 'message' => 'Error al quitar proveedor.'];
        }
        $del->bind_param('s', $ruc);
        $del->execute();
        $del->close();

        return ['ok' => true, 'message' => 'Proveedor quitado del catálogo de Vacuna al Agua.'];
    }

    $usuario = substr(trim($usuario), 0, 50);
    $sql = 'INSERT INTO `' . VAC_TABLA_PROVEEDOR . '` (`ruc`, `activo`, `usuarioReg`, `fechaReg`)
            VALUES (?, 1, ?, NOW())
            ON DUPLICATE KEY UPDATE `activo` = 1, `usuarioReg` = VALUES(`usuarioReg`), `fechaReg` = NOW()';
    $ins = $conn->prepare($sql);
    if (!$ins) {
        return ['ok' => false, 'message' => 'Error al guardar proveedor.'];
    }
    $ins->bind_param('ss', $ruc, $usuario);
    $ok = $ins->execute();
    $err = $conn->error;
    $ins->close();
    if (!$ok) {
        return ['ok' => false, 'message' => 'Error al guardar: ' . $err];
    }

    return ['ok' => true, 'message' => 'Proveedor habilitado para Vacuna al Agua.'];
}
