<?php
declare(strict_types=1);

/**
 * Catálogo de avisos del control de ingreso para trabajar sin señal.
 *
 * Mismo criterio que la consulta en línea (`consultar_estatus_sanitario_*`),
 * pero sin filtrar por DNI/placa: la app lo descarga y calcula en el equipo
 *   · granja en situación especial (estatus vigentes),
 *   · persona/vehículo que ingresó a una granja en situación especial,
 *   · visita previa (hoy) a una granja de mayor edad.
 */

require_once __DIR__ . '/estatus_sanitario_movil_lib.php';
require_once __DIR__ . '/orden_edad_movil_lib.php';
require_once __DIR__ . '/planificacion_movil_lib.php';

/** Máximo de pares granja|campaña cuya edad se calcula (cada uno consulta HC). */
const BIO_AV_MAX_EDADES = 120;

/**
 * Ingresos de los últimos días a granjas con estatus vigente (todas las personas).
 *
 * @param array<string, array<string,mixed>> $vigentes granja3 => estatus
 * @return array<string, list<array<string,mixed>>> dni => orígenes
 */
function bio_av_riesgo_dnis(mysqli $conn, array $vigentes, string $fecha): array
{
    if ($vigentes === []) {
        return [];
    }
    $granjas = array_keys($vigentes);
    $desde = date('Y-m-d', strtotime($fecha . ' -' . (BIO_ES_DIAS_VENTANA - 1) . ' days'));
    $exprDni = bio_es_dni_norm_sql('d.dni');
    $marks = implode(',', array_fill(0, count($granjas), '?'));
    $sql = 'SELECT ' . $exprDni . ' AS dni, TRIM(r.granja) AS granja, TRIM(r.campania) AS campania,
                   r.fecha AS fecha, r.hora AS hora
              FROM `' . bio_tabla_ingreso_det() . '` d
              JOIN `' . bio_tabla_ingreso_cab() . '` r ON r.id = d.idCab
             WHERE LPAD(TRIM(r.granja), 3, \'0\') IN (' . $marks . ')
               AND r.fecha BETWEEN ? AND ?
             ORDER BY r.fecha DESC, r.hora DESC';
    $st = $conn->prepare($sql);
    if (!$st) {
        return [];
    }
    $types = str_repeat('s', count($granjas)) . 'ss';
    $params = array_merge($granjas, [$desde, $fecha]);
    $st->bind_param($types, ...$params);
    $st->execute();
    $res = $st->get_result();

    $nombres = bio_es_nombres_granjas($conn, $granjas);
    $out = [];
    $vistos = [];
    while ($r = $res->fetch_assoc()) {
        $g3 = bio_norm_granja((string) $r['granja']);
        $e = $vigentes[$g3] ?? null;
        if ($e === null || (string) $r['fecha'] < (string) $e['fechaInicio']) {
            continue;
        }
        $dni = bio_es_norm_dni_key((string) $r['dni']);
        if (strlen($dni) !== 8) {
            continue;
        }
        $clave = $dni . '|' . $g3;
        if (isset($vistos[$clave])) {
            continue;
        }
        $vistos[$clave] = true;
        $out[$dni][] = [
            'granja' => $g3,
            'nombreGranja' => $nombres[$g3] ?? '',
            'campania' => bio_norm_campania((string) $r['campania']),
            'estado' => $e['estado'],
            'estadoLabel' => $e['estadoLabel'],
            'fechaIngreso' => (string) $r['fecha'],
            'horaIngreso' => (string) $r['hora'],
            'fechaFin' => (string) $e['fechaFin'],
        ];
    }
    $st->close();

    return $out;
}

/**
 * Igual que [bio_av_riesgo_dnis] pero por placa (detalle multi-vehículo y cabecera).
 *
 * @param array<string, array<string,mixed>> $vigentes
 * @return array<string, list<array<string,mixed>>> placa => orígenes
 */
function bio_av_riesgo_placas(mysqli $conn, array $vigentes, string $fecha): array
{
    if ($vigentes === []) {
        return [];
    }
    $granjas = array_keys($vigentes);
    $desde = date('Y-m-d', strtotime($fecha . ' -' . (BIO_ES_DIAS_VENTANA - 1) . ' days'));
    $marks = implode(',', array_fill(0, count($granjas), '?'));
    $types = str_repeat('s', count($granjas)) . 'ss';
    $params = array_merge($granjas, [$desde, $fecha]);
    $crudas = [];

    $tablaVeh = bio_tabla_ingreso_veh();
    $chk = @$conn->query("SHOW TABLES LIKE '" . $tablaVeh . "'");
    if ($chk && $chk->num_rows > 0) {
        $chk->free();
        $expr = bio_es_placa_norm_sql('v.placa');
        $st = $conn->prepare(
            'SELECT ' . $expr . ' AS placa, v.ingresa AS ingresa,
                    TRIM(r.granja) AS granja, TRIM(r.campania) AS campania,
                    r.fecha AS fecha, r.hora AS hora
               FROM ' . $tablaVeh . ' v
               JOIN `' . bio_tabla_ingreso_cab() . '` r ON r.id = v.idCab
              WHERE LPAD(TRIM(r.granja), 3, \'0\') IN (' . $marks . ')
                AND r.fecha BETWEEN ? AND ?'
        );
        if ($st) {
            $st->bind_param($types, ...$params);
            $st->execute();
            $res = $st->get_result();
            while ($res && ($r = $res->fetch_assoc())) {
                $crudas[] = $r;
            }
            $st->close();
        }
    }

    $exprH = bio_es_placa_norm_sql('r.placa');
    $st = $conn->prepare(
        'SELECT ' . $exprH . ' AS placa, 1 AS ingresa,
                TRIM(r.granja) AS granja, TRIM(r.campania) AS campania,
                r.fecha AS fecha, r.hora AS hora
           FROM `' . bio_tabla_ingreso_cab() . '` r
          WHERE TRIM(r.placa) <> \'\'
            AND LPAD(TRIM(r.granja), 3, \'0\') IN (' . $marks . ')
            AND r.fecha BETWEEN ? AND ?'
    );
    if ($st) {
        $st->bind_param($types, ...$params);
        $st->execute();
        $res = $st->get_result();
        while ($res && ($r = $res->fetch_assoc())) {
            $crudas[] = $r;
        }
        $st->close();
    }

    usort($crudas, static function ($a, $b) {
        return strcmp((string) $b['fecha'] . (string) $b['hora'], (string) $a['fecha'] . (string) $a['hora']);
    });

    $nombres = bio_es_nombres_granjas($conn, $granjas);
    $out = [];
    $vistos = [];
    foreach ($crudas as $c) {
        $g3 = bio_norm_granja((string) $c['granja']);
        $e = $vigentes[$g3] ?? null;
        $placa = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', (string) $c['placa']));
        if ($e === null || $placa === '' || (string) $c['fecha'] < (string) $e['fechaInicio']) {
            continue;
        }
        $clave = $placa . '|' . $g3;
        if (isset($vistos[$clave])) {
            continue;
        }
        $vistos[$clave] = true;
        $out[$placa][] = [
            'granja' => $g3,
            'nombreGranja' => $nombres[$g3] ?? '',
            'campania' => bio_norm_campania((string) $c['campania']),
            'estado' => $e['estado'],
            'estadoLabel' => $e['estadoLabel'],
            'fechaIngreso' => (string) $c['fecha'],
            'horaIngreso' => (string) $c['hora'],
            'fechaFin' => (string) $e['fechaFin'],
            'ingresa' => (int) ($c['ingresa'] ?? 1) === 0 ? 0 : 1,
        ];
    }

    return $out;
}

/**
 * Ingresos de hoy (todas las granjas) por DNI y por placa, para el orden de edad.
 *
 * @return array{dnis: array<string, list<array<string,string>>>, placas: array<string, list<array<string,string>>>}
 */
function bio_av_visitas_hoy(mysqli $conn, string $fecha): array
{
    $dnis = [];
    $vistos = [];
    $st = $conn->prepare(
        'SELECT d.dni AS dni, TRIM(r.granja) AS granja, TRIM(r.campania) AS campania, r.hora AS hora
           FROM `' . bio_tabla_ingreso_det() . '` d
           JOIN `' . bio_tabla_ingreso_cab() . '` r ON r.id = d.idCab
          WHERE r.fecha = ?
          ORDER BY r.hora DESC'
    );
    if ($st) {
        $st->bind_param('s', $fecha);
        $st->execute();
        $res = $st->get_result();
        while ($r = $res->fetch_assoc()) {
            $g3 = bio_norm_granja((string) $r['granja']);
            $dni = preg_replace('/\D+/', '', (string) $r['dni']) ?? '';
            $camp = bio_norm_campania((string) $r['campania']);
            if ($g3 === '' || $dni === '') {
                continue;
            }
            $clave = $dni . '|' . $g3 . '|' . $camp;
            if (isset($vistos[$clave])) {
                continue;
            }
            $vistos[$clave] = true;
            $dnis[$dni][] = ['granja' => $g3, 'campania' => $camp, 'hora' => (string) $r['hora']];
        }
        $st->close();
    }

    $crudas = [];
    $tablaVeh = bio_tabla_ingreso_veh();
    $chk = @$conn->query("SHOW TABLES LIKE '" . $tablaVeh . "'");
    if ($chk && $chk->num_rows > 0) {
        $chk->free();
        $expr = bio_es_placa_norm_sql('v.placa');
        $st = $conn->prepare(
            'SELECT ' . $expr . ' AS placa, TRIM(r.granja) AS granja, TRIM(r.campania) AS campania, r.hora AS hora
               FROM ' . $tablaVeh . ' v
               JOIN `' . bio_tabla_ingreso_cab() . '` r ON r.id = v.idCab
              WHERE r.fecha = ?'
        );
        if ($st) {
            $st->bind_param('s', $fecha);
            $st->execute();
            $res = $st->get_result();
            while ($res && ($r = $res->fetch_assoc())) {
                $crudas[] = $r;
            }
            $st->close();
        }
    }
    $exprH = bio_es_placa_norm_sql('r.placa');
    $st = $conn->prepare(
        'SELECT ' . $exprH . ' AS placa, TRIM(r.granja) AS granja, TRIM(r.campania) AS campania, r.hora AS hora
           FROM `' . bio_tabla_ingreso_cab() . '` r
          WHERE TRIM(r.placa) <> \'\' AND r.fecha = ?'
    );
    if ($st) {
        $st->bind_param('s', $fecha);
        $st->execute();
        $res = $st->get_result();
        while ($res && ($r = $res->fetch_assoc())) {
            $crudas[] = $r;
        }
        $st->close();
    }

    $placas = [];
    $vistosP = [];
    foreach ($crudas as $c) {
        $g3 = bio_norm_granja((string) $c['granja']);
        $placa = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', (string) $c['placa']));
        $camp = bio_norm_campania((string) $c['campania']);
        if ($g3 === '' || $placa === '') {
            continue;
        }
        $clave = $placa . '|' . $g3 . '|' . $camp;
        if (isset($vistosP[$clave])) {
            continue;
        }
        $vistosP[$clave] = true;
        $placas[$placa][] = ['granja' => $g3, 'campania' => $camp, 'hora' => (string) $c['hora']];
    }

    return ['dnis' => $dnis, 'placas' => $placas];
}

/**
 * Descarga completa.
 *
 * @param string[] $destinos «granja|campania» que la app puede registrar (Mis granjas)
 * @return array<string,mixed>
 */
function bio_av_descargar(mysqli $conn, string $fecha, array $destinos): array
{
    $out = [
        'disponible' => true,
        'fecha' => $fecha,
        'generado' => date('Y-m-d H:i:s'),
        'estatusDisponible' => false,
        'granjasEstatus' => (object) [],
        'riesgoDnis' => (object) [],
        'riesgoPlacas' => (object) [],
        'edades' => (object) [],
        'nombresGranja' => (object) [],
        'visitasHoyDnis' => (object) [],
        'visitasHoyPlacas' => (object) [],
    ];

    if (bio_es_tablas_existen($conn)) {
        $out['estatusDisponible'] = true;
        $vigentes = bio_es_vigentes($conn, [], $fecha);
        if ($vigentes !== []) {
            $nombres = bio_es_nombres_granjas($conn, array_keys($vigentes));
            $pub = [];
            foreach ($vigentes as $g3 => $info) {
                unset($info['id']);
                $info['nombreGranja'] = $nombres[$g3] ?? '';
                $pub[$g3] = $info;
            }
            $out['granjasEstatus'] = $pub;
            $rd = bio_av_riesgo_dnis($conn, $vigentes, $fecha);
            $rp = bio_av_riesgo_placas($conn, $vigentes, $fecha);
            $out['riesgoDnis'] = $rd === [] ? (object) [] : $rd;
            $out['riesgoPlacas'] = $rp === [] ? (object) [] : $rp;
        }
    }

    $hoy = bio_av_visitas_hoy($conn, $fecha);
    $out['visitasHoyDnis'] = $hoy['dnis'] === [] ? (object) [] : $hoy['dnis'];
    $out['visitasHoyPlacas'] = $hoy['placas'] === [] ? (object) [] : $hoy['placas'];

    // Pares granja|campaña cuya edad hace falta: destinos de la app, visitas
    // planificadas del día y granjas ya visitadas hoy.
    $pares = [];
    foreach ($destinos as $d) {
        $partes = explode('|', (string) $d);
        $g = bio_norm_granja((string) ($partes[0] ?? ''));
        $c = bio_norm_campania((string) ($partes[1] ?? ''));
        if ($g !== '' && $c !== '') {
            $pares[$g . '|' . $c] = [$g, $c];
        }
    }
    foreach (bio_plan_visitas_rango($conn, $fecha, $fecha) as $v) {
        $g = bio_norm_granja((string) $v['granja']);
        $c = bio_norm_campania((string) $v['campania']);
        if ($g !== '' && $c !== '') {
            $pares[$g . '|' . $c] = [$g, $c];
        }
    }
    foreach ([$hoy['dnis'], $hoy['placas']] as $mapa) {
        foreach ($mapa as $lista) {
            foreach ($lista as $v) {
                if ($v['granja'] !== '' && $v['campania'] !== '') {
                    $pares[$v['granja'] . '|' . $v['campania']] = [$v['granja'], $v['campania']];
                }
            }
        }
    }

    $edades = [];
    $granjas = [];
    foreach (array_slice($pares, 0, BIO_AV_MAX_EDADES, true) as $clave => [$g, $c]) {
        $granjas[$g] = true;
        try {
            $edad = bio_oe_edad_granja($conn, $g, $c, $fecha);
        } catch (Throwable $e) {
            $edad = null;
        }
        if ($edad !== null && $edad > 0) {
            $edades[$clave] = $edad;
        }
    }
    $out['edades'] = $edades === [] ? (object) [] : $edades;
    $nombres = bio_es_nombres_granjas($conn, array_keys($granjas));
    $out['nombresGranja'] = $nombres === [] ? (object) [] : $nombres;

    return $out;
}
