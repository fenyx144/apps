<?php
declare(strict_types=1);

/**
 * Consulta informativa del «Estatus Sanitario Granja» (portal web, Bioseguridad
 * física) para el control de ingreso de la app.
 *
 * Responde dos cosas, siempre sin bloquear nada:
 *   · si la granja que se está registrando tiene un estatus vigente
 *     (`sospecha` o `confirmado`), y
 *   · si alguno de los DNIs que ingresan viene de OTRA granja que hoy está en
 *     situación especial: es la etiqueta que ve el vigilante en la garita.
 *
 * El origen se deduce de los ingresos ya registrados (`san_fact_ingresogranja_*`)
 * en granjas con estatus vigente, no de una marca que
 * haya que mantener: cuando el estatus termina (los 7 días de la sospecha o el
 * fin de la campaña del confirmado), la etiqueta desaparece sola.
 *
 * Solo lectura. Si las tablas aún no existen (migración pendiente) o la consulta
 * falla, se responde `disponible = false` y la app se queda en estado neutro.
 */

const BIO_ES_TABLA = 'restatussanitario';
const BIO_ES_TABLA_DET = 'restatussanitariodet';

require_once __DIR__ . '/bioseguridad_movil_lib.php';

/** Días hacia atrás en los que se busca el ingreso previo. */
const BIO_ES_DIAS_VENTANA = 30;

/** Etiquetas de los estados, iguales que en el portal web. */
function bio_es_estado_label(string $estado): string
{
    $e = strtoupper(trim($estado));
    if ($e === 'SOSPECHA') {
        return 'Sospecha';
    }
    if ($e === 'CONFIRMADO') {
        return 'Confirmado';
    }

    return $e;
}

function bio_es_estado_norm(string $estado): string
{
    $e = strtoupper(trim($estado));

    return in_array($e, ['SOSPECHA', 'CONFIRMADO'], true) ? $e : '';
}

/** DNI de 8 dígitos (LPAD) para claves JSON y comparación con la app. */
function bio_es_norm_dni_key(string $raw): string
{
    $d = preg_replace('/\D+/', '', $raw) ?? '';
    if ($d === '') {
        return '';
    }
    if (strlen($d) > 8) {
        $d = substr($d, -8);
    }

    return str_pad($d, 8, '0', STR_PAD_LEFT);
}

function bio_es_dni_norm_sql(string $col): string
{
    return "LPAD(TRIM(REPLACE(REPLACE(REPLACE({$col}, '-', ''), ' ', ''), '.', '')), 8, '0')";
}

function bio_es_tabla_existe_simple(mysqli $conn, string $tabla): bool
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

function bio_es_tablas_existen(mysqli $conn): bool
{
    if (bio_es_tabla_existe_simple($conn, BIO_ES_TABLA)
        && bio_es_tabla_existe_simple($conn, BIO_ES_TABLA_DET)) {
        return true;
    }
    $st = $conn->prepare(
        'SELECT COUNT(*) AS n FROM information_schema.tables
          WHERE table_schema = DATABASE() AND table_name IN (?, ?)'
    );
    if (!$st) {
        return false;
    }
    $t1 = BIO_ES_TABLA;
    $t2 = BIO_ES_TABLA_DET;
    $st->bind_param('ss', $t1, $t2);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();

    return (int) ($row['n'] ?? 0) === 2;
}

/**
 * Nombres de granja desde ccos (vacío si algo falla).
 *
 * @param string[] $granjas3
 * @return array<string,string> granja3 => nombre
 */
function bio_es_nombres_granjas(mysqli $conn, array $granjas3): array
{
    $granjas = array_values(array_unique(array_filter($granjas3, 'strlen')));
    if ($granjas === []) {
        return [];
    }
    try {
        // `ccos.codigo` es el cenco de 6 dígitos (granja + campaña): el nombre
        // de la granja es el de cualquiera de sus campañas.
        $ph = implode(',', array_fill(0, count($granjas), '?'));
        $st = $conn->prepare('SELECT LEFT(TRIM(codigo), 3) AS codigo, TRIM(nombre) AS nombre FROM ccos WHERE LEFT(TRIM(codigo), 3) IN (' . $ph . ')');
        if (!$st) {
            return [];
        }
        $st->bind_param(str_repeat('s', count($granjas)), ...$granjas);
        $st->execute();
        $out = [];
        $res = $st->get_result();
        while ($r = $res->fetch_assoc()) {
            $cod = (string) $r['codigo'];
            $nom = (string) bio_utf8((string) $r['nombre']);
            // El nombre bueno es el de la campaña en curso; si otra campaña
            // trae uno vacío, no se pisa el que ya había.
            if ($nom !== '' || !isset($out[$cod])) {
                $out[$cod] = $nom;
            }
        }
        $st->close();

        return $out;
    } catch (Throwable $e) {
        return [];
    }
}

/**
 * Estatus vigente en `$fecha` para las granjas indicadas (vacío = todas).
 *
 * @param string[] $granjas3
 * @return array<string, array<string,mixed>> granja3 => estatus
 */
function bio_es_vigentes(mysqli $conn, array $granjas3, string $fecha): array
{
    $parts = [
        'e.fechaInicio <= ?',
        '(e.fechaFin IS NULL OR e.fechaFin >= ?)',
        "UPPER(TRIM(e.estado)) IN ('SOSPECHA','CONFIRMADO')",
    ];
    $types = ['ss'];
    $params = [$fecha, $fecha];

    $granjas = array_values(array_unique(array_filter($granjas3, 'strlen')));
    if ($granjas !== []) {
        $parts[] = "LPAD(TRIM(e.granja), 3, '0') IN (" . implode(',', array_fill(0, count($granjas), '?')) . ')';
        foreach ($granjas as $g) {
            $types[] = 's';
            $params[] = $g;
        }
    }

    $st = $conn->prepare(
        'SELECT e.id, TRIM(e.granja) AS granja, TRIM(e.campania) AS campania, e.estado,
                e.fechaInicio, e.fechaFin
           FROM ' . BIO_ES_TABLA . ' e
          WHERE ' . implode(' AND ', $parts) . '
          ORDER BY e.fechaInicio DESC, e.fechaHoraRegistro DESC'
    );
    if (!$st) {
        return [];
    }
    $st->bind_param(implode('', $types), ...$params);
    $st->execute();
    $res = $st->get_result();

    $porGranja = [];
    $ids = [];
    while ($r = $res->fetch_assoc()) {
        $g3 = bio_norm_granja((string) $r['granja']);
        $estado = bio_es_estado_norm((string) $r['estado']);
        if ($g3 === '' || $estado === '' || isset($porGranja[$g3])) {
            // Un estatus por granja: el más reciente manda para la etiqueta.
            continue;
        }
        $id = (string) $r['id'];
        $ids[] = $id;
        $porGranja[$g3] = [
            'id' => $id,
            'granja' => $g3,
            'campania' => bio_norm_campania((string) $r['campania']),
            'estado' => $estado,
            'estadoLabel' => bio_es_estado_label($estado),
            'fechaInicio' => (string) $r['fechaInicio'],
            'fechaFin' => $r['fechaFin'] === null ? '' : (string) $r['fechaFin'],
            'galpones' => [],
        ];
    }
    $st->close();

    if ($ids !== []) {
        $galpones = bio_es_galpones($conn, $ids);
        foreach ($porGranja as $g3 => $info) {
            $porGranja[$g3]['galpones'] = $galpones[$info['id']] ?? [];
        }
    }

    return $porGranja;
}

/**
 * Galpones por id de estatus.
 *
 * @param string[] $ids
 * @return array<string, list<string>>
 */
function bio_es_galpones(mysqli $conn, array $ids): array
{
    $ids = array_values(array_unique(array_filter($ids, 'strlen')));
    if ($ids === []) {
        return [];
    }
    $st = $conn->prepare(
        'SELECT idestatus, TRIM(galpon) AS galpon FROM ' . BIO_ES_TABLA_DET . '
          WHERE idestatus IN (' . implode(',', array_fill(0, count($ids), '?')) . ')
          ORDER BY idestatus, posicion'
    );
    if (!$st) {
        return [];
    }
    $st->bind_param(str_repeat('s', count($ids)), ...$ids);
    $st->execute();
    $res = $st->get_result();
    $out = [];
    while ($r = $res->fetch_assoc()) {
        $out[(string) $r['idestatus']][] = (string) $r['galpon'];
    }
    $st->close();

    return $out;
}

/**
 * Ingresos previos de los DNIs dados en granjas con estatus vigente.
 *
 * `r.fecha >= e.fechaInicio` deja fuera los ingresos anteriores al estatus: la
 * etiqueta avisa de quien entró a una granja mientras estaba en situación
 * especial, no de quien pasó por ahí antes de que se declarara.
 *
 * @param string[] $dnis
 * @return array<string, list<array<string,mixed>>> dni => orígenes
 */
function bio_es_origenes_por_dni(mysqli $conn, array $dnis, string $fecha, string $granjaExcluir): array
{
    $dnis = array_values(array_unique(array_filter($dnis, 'strlen')));
    if ($dnis === []) {
        return [];
    }
    $desde = date('Y-m-d', strtotime($fecha . ' -' . (BIO_ES_DIAS_VENTANA - 1) . ' days'));

    $granjaExcluir = $granjaExcluir !== '' ? bio_norm_granja($granjaExcluir) : '';
    $exprDni = bio_es_dni_norm_sql('d.dni');
    $marks = implode(',', array_fill(0, count($dnis), '?'));
    $sql = 'SELECT ' . $exprDni . ' AS dni, TRIM(r.granja) AS granja, TRIM(r.campania) AS campania,
                   r.fecha AS fecha, r.hora AS hora,
                   e.estado AS estado, e.fechaInicio AS fechaInicio, e.fechaFin AS fechaFin
              FROM `' . bio_tabla_ingreso_det() . '` d
              JOIN `' . bio_tabla_ingreso_cab() . '` r ON r.id = d.idCab
              JOIN ' . BIO_ES_TABLA . ' e ON LPAD(TRIM(e.granja), 3, \'0\') = LPAD(TRIM(r.granja), 3, \'0\')
             WHERE ' . $exprDni . ' IN (' . $marks . ')
               AND UPPER(TRIM(e.estado)) IN (\'SOSPECHA\',\'CONFIRMADO\')
               AND r.fecha BETWEEN ? AND ?
               AND r.fecha >= e.fechaInicio
               AND e.fechaInicio <= ?
               AND (e.fechaFin IS NULL OR e.fechaFin >= ?)
             ORDER BY r.fecha DESC, r.hora DESC';
    $st = $conn->prepare($sql);
    if (!$st) {
        return [];
    }
    $types = str_repeat('s', count($dnis)) . 'ssss';
    $params = array_merge($dnis, [$desde, $fecha, $fecha, $fecha]);
    $st->bind_param($types, ...$params);
    $st->execute();
    $res = $st->get_result();

    $granjas = [];
    $crudas = [];
    while ($r = $res->fetch_assoc()) {
        $estado = bio_es_estado_norm((string) $r['estado']);
        $g3 = bio_norm_granja((string) $r['granja']);
        if ($estado === '' || $g3 === '') {
            continue;
        }
        $dni = bio_es_norm_dni_key((string) $r['dni']);
        if (strlen($dni) !== 8) {
            continue;
        }
        if ($granjaExcluir !== '' && $g3 === $granjaExcluir) {
            continue;
        }
        $granjas[$g3] = true;
        $crudas[] = [
            'dni' => $dni,
            'granja' => $g3,
            'campania' => bio_norm_campania((string) $r['campania']),
            'fecha' => (string) $r['fecha'],
            'hora' => (string) $r['hora'],
            'estado' => $estado,
            'fechaFin' => $r['fechaFin'] === null ? '' : (string) $r['fechaFin'],
        ];
    }
    $st->close();

    if ($crudas === []) {
        return [];
    }
    $nombres = bio_es_nombres_granjas($conn, array_keys($granjas));

    $out = [];
    $vistos = [];
    foreach ($crudas as $c) {
        $clave = $c['dni'] . '|' . $c['granja'];
        if (isset($vistos[$clave])) {
            continue;
        }
        $vistos[$clave] = true;
        $out[$c['dni']][] = [
            'granja' => $c['granja'],
            'nombreGranja' => $nombres[$c['granja']] ?? '',
            'campania' => $c['campania'],
            'estado' => $c['estado'],
            'estadoLabel' => bio_es_estado_label($c['estado']),
            'fechaIngreso' => $c['fecha'],
            'horaIngreso' => $c['hora'],
            'fechaFin' => $c['fechaFin'],
        ];
    }

    return $out;
}

/**
 * Respuesta completa de la consulta.
 *
 * @param string[] $dnis
 * @param string[] $placas
 * @return array<string,mixed>
 */
function bio_es_consultar(mysqli $conn, string $fecha, string $granja, array $dnis, array $placas = []): array
{
    $granja = $granja !== '' ? bio_norm_granja($granja) : '';
    $dnis = array_values(array_unique(array_filter(
        array_map(static function ($d) {
            return bio_es_norm_dni_key((string) $d);
        }, $dnis),
        static function ($d) {
            return strlen($d) === 8;
        }
    )));
    $placas = array_values(array_unique(array_filter(
        array_map(static function ($p) {
            return strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', (string) $p));
        }, $placas),
        static function ($p) {
            return $p !== '';
        }
    )));

    $out = [
        'disponible' => false,
        'fecha' => $fecha,
        'granja' => $granja,
        'granjaEnEstatus' => null,
        'dnis' => (object) [],
        'placas' => (object) [],
    ];
    if (!bio_es_tablas_existen($conn)) {
        return $out;
    }
    $out['disponible'] = true;

    $vigentes = bio_es_vigentes($conn, $granja !== '' ? [$granja] : [], $fecha);
    if ($granja !== '' && isset($vigentes[$granja])) {
        $info = $vigentes[$granja];
        unset($info['id']);
        $out['granjaEnEstatus'] = $info;
    }

    $origenes = bio_es_origenes_por_dni($conn, $dnis, $fecha, $granja);
    $porDni = [];
    foreach ($dnis as $dni) {
        $lista = $origenes[$dni] ?? [];
        $porDni[$dni] = [
            'enRiesgo' => $lista !== [],
            'origenes' => $lista,
        ];
    }
    $out['dnis'] = $porDni === [] ? (object) [] : $porDni;

    $origenesVeh = bio_es_origenes_por_placa($conn, $placas, $fecha, $granja);
    $porPlaca = [];
    foreach ($placas as $placa) {
        $lista = $origenesVeh[$placa] ?? [];
        $porPlaca[$placa] = [
            'enRiesgo' => $lista !== [],
            'origenes' => $lista,
        ];
    }
    $out['placas'] = $porPlaca === [] ? (object) [] : $porPlaca;

    return $out;
}

/** Expresión SQL de una placa sin guiones, espacios ni puntos, en mayúsculas. */
function bio_es_placa_norm_sql(string $col): string
{
    return "REPLACE(REPLACE(REPLACE(UPPER(TRIM({$col})), '-', ''), ' ', ''), '.', '')";
}

/**
 * Ingresos previos de los vehículos dados en granjas con estatus vigente.
 *
 * Mismo criterio que los DNIs ([bio_es_origenes_por_dni]), pero por placa. Mira
 * el detalle multi-vehículo (`san_fact_ingresogranja_veh`) y la
 * cabecera (`san_fact_ingresogranja_cab.placa`), que cubre ingresos con una sola placa
 * tabla.
 *
 * @param string[] $placas
 * @return array<string, list<array<string,mixed>>> placa normalizada => orígenes
 */
function bio_es_origenes_por_placa(mysqli $conn, array $placas, string $fecha, string $granjaExcluir): array
{
    $norm = [];
    foreach ($placas as $p) {
        $p = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', (string) $p));
        if ($p !== '') {
            $norm[$p] = true;
        }
    }
    $placas = array_keys($norm);
    if ($placas === []) {
        return [];
    }
    $granjaExcluir = $granjaExcluir !== '' ? bio_norm_granja($granjaExcluir) : '';
    $desde = date('Y-m-d', strtotime($fecha . ' -' . (BIO_ES_DIAS_VENTANA - 1) . ' days'));
    $marks = implode(',', array_fill(0, count($placas), '?'));
    $filtroFecha = ' AND UPPER(TRIM(e.estado)) IN (\'SOSPECHA\',\'CONFIRMADO\')
               AND r.fecha BETWEEN ? AND ?
               AND r.fecha >= e.fechaInicio
               AND e.fechaInicio <= ?
               AND (e.fechaFin IS NULL OR e.fechaFin >= ?)';

    $crudas = [];

    // 1) Detalle multi-vehículo (una fila por placa), si la tabla ya existe.
    $tablaVeh = bio_tabla_ingreso_veh();
    $chk = @$conn->query("SHOW TABLES LIKE '" . $tablaVeh . "'");
    if ($chk && $chk->num_rows > 0) {
        $chk->free();
        $expr = bio_es_placa_norm_sql('v.placa');
        $sql = 'SELECT ' . $expr . ' AS placa, v.ingresa AS ingresa,
                       TRIM(r.granja) AS granja, TRIM(r.campania) AS campania,
                       r.fecha AS fecha, r.hora AS hora,
                       e.estado AS estado, e.fechaFin AS fechaFin
                  FROM ' . $tablaVeh . ' v
                  JOIN `' . bio_tabla_ingreso_cab() . '` r ON r.id = v.idCab
                  JOIN ' . BIO_ES_TABLA . ' e ON LPAD(TRIM(e.granja), 3, \'0\') = LPAD(TRIM(r.granja), 3, \'0\')
                 WHERE ' . $expr . ' IN (' . $marks . ')' . $filtroFecha . '
                 ORDER BY r.fecha DESC, r.hora DESC';
        $st = $conn->prepare($sql);
        if ($st) {
            $types = str_repeat('s', count($placas)) . 'ssss';
            $params = array_merge($placas, [$desde, $fecha, $fecha, $fecha]);
            $st->bind_param($types, ...$params);
            $st->execute();
            $res = $st->get_result();
            while ($res && ($r = $res->fetch_assoc())) {
                $crudas[] = $r;
            }
            $st->close();
        }
    }

    // 2) Cabecera del ingreso (una sola placa por registro, apps anteriores).
    $exprH = bio_es_placa_norm_sql('r.placa');
    $sqlH = 'SELECT ' . $exprH . ' AS placa, 1 AS ingresa,
                    TRIM(r.granja) AS granja, TRIM(r.campania) AS campania,
                    r.fecha AS fecha, r.hora AS hora,
                    e.estado AS estado, e.fechaFin AS fechaFin
               FROM `' . bio_tabla_ingreso_cab() . '` r
               JOIN ' . BIO_ES_TABLA . ' e ON LPAD(TRIM(e.granja), 3, \'0\') = LPAD(TRIM(r.granja), 3, \'0\')
              WHERE TRIM(r.placa) <> \'\' AND ' . $exprH . ' IN (' . $marks . ')' . $filtroFecha . '
              ORDER BY r.fecha DESC, r.hora DESC';
    $st = $conn->prepare($sqlH);
    if ($st) {
        $types = str_repeat('s', count($placas)) . 'ssss';
        $params = array_merge($placas, [$desde, $fecha, $fecha, $fecha]);
        $st->bind_param($types, ...$params);
        $st->execute();
        $res = $st->get_result();
        while ($res && ($r = $res->fetch_assoc())) {
            $crudas[] = $r;
        }
        $st->close();
    }

    if ($crudas === []) {
        return [];
    }

    $granjas = [];
    $validas = [];
    foreach ($crudas as $c) {
        $estado = bio_es_estado_norm((string) $c['estado']);
        $g3 = bio_norm_granja((string) $c['granja']);
        $placa = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', (string) $c['placa']));
        if ($estado === '' || $g3 === '' || $placa === '') {
            continue;
        }
        if ($granjaExcluir !== '' && $g3 === $granjaExcluir) {
            continue;
        }
        $granjas[$g3] = true;
        $validas[] = [
            'placa' => $placa,
            'granja' => $g3,
            'campania' => bio_norm_campania((string) $c['campania']),
            'fecha' => (string) $c['fecha'],
            'hora' => (string) $c['hora'],
            'estado' => $estado,
            'fechaFin' => $c['fechaFin'] === null ? '' : (string) $c['fechaFin'],
            'ingresa' => (int) ($c['ingresa'] ?? 1) === 0 ? 0 : 1,
        ];
    }
    if ($validas === []) {
        return [];
    }
    $nombres = bio_es_nombres_granjas($conn, array_keys($granjas));

    $out = [];
    $vistos = [];
    foreach ($validas as $c) {
        $clave = $c['placa'] . '|' . $c['granja'];
        if (isset($vistos[$clave])) {
            continue;
        }
        $vistos[$clave] = true;
        $out[$c['placa']][] = [
            'granja' => $c['granja'],
            'nombreGranja' => $nombres[$c['granja']] ?? '',
            'campania' => $c['campania'],
            'estado' => $c['estado'],
            'estadoLabel' => bio_es_estado_label($c['estado']),
            'fechaIngreso' => $c['fecha'],
            'horaIngreso' => $c['hora'],
            'fechaFin' => $c['fechaFin'],
            'ingresa' => $c['ingresa'],
        ];
    }

    return $out;
}
