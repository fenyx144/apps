<?php
declare(strict_types=1);

/**
 * Aviso informativo de orden de visitas por edad de granja (menor → mayor).
 *
 * Si en el mismo día la persona o el vehículo ya ingresó a otra granja con edad
 * promedio mayor que la granja que se está registrando, la app muestra una
 * etiqueta (no bloquea el registro).
 */

require_once __DIR__ . '/estatus_sanitario_movil_lib.php';
require_once __DIR__ . '/bio_plan_tablas_lib.php';

/**
 * Edad promedio de la campaña en [fecha] (cargaproduccion00 vía HC).
 */
function bio_oe_edad_granja(mysqli $conn, string $granja3, string $campania, string $fecha): ?int
{
    $granja3 = bio_norm_granja($granja3);
    $campania = bio_norm_campania($campania);
    if ($granja3 === '' || $campania === '') {
        return null;
    }
    static $hcLoaded = false;
    if (!$hcLoaded) {
        $hcPath = __DIR__ . '/../../modules/sip/historia-clinica/hc_observaciones_lib.php';
        if (is_file($hcPath)) {
            require_once $hcPath;
        }
        $hcLoaded = true;
    }
    if (function_exists('hc_obs_edad_resuelta')) {
        try {
            $info = hc_obs_edad_resuelta($conn, $granja3, $campania, '', $fecha);
            $edad = $info['edad'] ?? null;
            if ($edad !== null) {
                $n = (int) $edad;
                if ($n > 0) {
                    return $n;
                }
            }
        } catch (Throwable $e) {
            // fallback maes_zonas
        }
    }

    return bio_plan_edad_granja_maes_zonas($conn, $granja3, $campania, $fecha, '');
}

/**
 * Ingresos del mismo día por DNI (otras granjas).
 *
 * @param string[] $dnis
 * @return array<string, list<array<string,mixed>>>
 */
function bio_oe_visitas_hoy_por_dni(mysqli $conn, array $dnis, string $fecha, string $granjaExcluir): array
{
    $dnis = array_values(array_unique(array_filter($dnis, 'strlen')));
    if ($dnis === []) {
        return [];
    }
    $marks = implode(',', array_fill(0, count($dnis), '?'));
    $sql = 'SELECT d.dni AS dni, TRIM(r.granja) AS granja, TRIM(r.campania) AS campania,
                   r.hora AS hora
              FROM `' . bio_tabla_ingreso_det() . '` d
              JOIN `' . bio_tabla_ingreso_cab() . '` r ON r.id = d.idCab
             WHERE d.dni IN (' . $marks . ')
               AND r.fecha = ?
             ORDER BY r.hora DESC, r.granja ASC';
    $st = $conn->prepare($sql);
    if (!$st) {
        return [];
    }
    $types = str_repeat('s', count($dnis)) . 's';
    $params = array_merge($dnis, [$fecha]);
    $st->bind_param($types, ...$params);
    $st->execute();
    $res = $st->get_result();

    $out = [];
    $vistos = [];
    while ($r = $res->fetch_assoc()) {
        $g3 = bio_norm_granja((string) $r['granja']);
        if ($g3 === '' || $g3 === $granjaExcluir) {
            continue;
        }
        $dni = preg_replace('/\D+/', '', (string) $r['dni']) ?? '';
        if ($dni === '') {
            continue;
        }
        $clave = $dni . '|' . $g3 . '|' . bio_norm_campania((string) $r['campania']);
        if (isset($vistos[$clave])) {
            continue;
        }
        $vistos[$clave] = true;
        $out[$dni][] = [
            'granja' => $g3,
            'campania' => bio_norm_campania((string) $r['campania']),
            'hora' => (string) $r['hora'],
        ];
    }
    $st->close();

    return $out;
}

/**
 * Ingresos del mismo día por placa (otras granjas).
 *
 * @param string[] $placas
 * @return array<string, list<array<string,mixed>>>
 */
function bio_oe_visitas_hoy_por_placa(mysqli $conn, array $placas, string $fecha, string $granjaExcluir): array
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
    $marks = implode(',', array_fill(0, count($placas), '?'));
    $crudas = [];

    $tablaVeh = bio_tabla_ingreso_veh();
    $chk = @$conn->query("SHOW TABLES LIKE '" . $tablaVeh . "'");
    if ($chk && $chk->num_rows > 0) {
        $chk->free();
        $expr = bio_es_placa_norm_sql('v.placa');
        $sql = 'SELECT ' . $expr . ' AS placa,
                       TRIM(r.granja) AS granja, TRIM(r.campania) AS campania,
                       r.hora AS hora
                  FROM ' . $tablaVeh . ' v
                  JOIN `' . bio_tabla_ingreso_cab() . '` r ON r.id = v.idCab
                 WHERE ' . $expr . ' IN (' . $marks . ')
                   AND r.fecha = ?
                 ORDER BY r.hora DESC';
        $st = $conn->prepare($sql);
        if ($st) {
            $types = str_repeat('s', count($placas)) . 's';
            $params = array_merge($placas, [$fecha]);
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
    $sqlH = 'SELECT ' . $exprH . ' AS placa,
                    TRIM(r.granja) AS granja, TRIM(r.campania) AS campania,
                    r.hora AS hora
               FROM `' . bio_tabla_ingreso_cab() . '` r
              WHERE TRIM(r.placa) <> \'\' AND ' . $exprH . ' IN (' . $marks . ')
                AND r.fecha = ?
              ORDER BY r.hora DESC';
    $st = $conn->prepare($sqlH);
    if ($st) {
        $types = str_repeat('s', count($placas)) . 's';
        $params = array_merge($placas, [$fecha]);
        $st->bind_param($types, ...$params);
        $st->execute();
        $res = $st->get_result();
        while ($res && ($r = $res->fetch_assoc())) {
            $crudas[] = $r;
        }
        $st->close();
    }

    $out = [];
    $vistos = [];
    foreach ($crudas as $c) {
        $g3 = bio_norm_granja((string) $c['granja']);
        $placa = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', (string) $c['placa']));
        if ($g3 === '' || $placa === '' || $g3 === $granjaExcluir) {
            continue;
        }
        $clave = $placa . '|' . $g3 . '|' . bio_norm_campania((string) $c['campania']);
        if (isset($vistos[$clave])) {
            continue;
        }
        $vistos[$clave] = true;
        $out[$placa][] = [
            'granja' => $g3,
            'campania' => bio_norm_campania((string) $c['campania']),
            'hora' => (string) $c['hora'],
        ];
    }

    return $out;
}

/**
 * @param list<array<string,mixed>> $visitas
 * @return list<array<string,mixed>>
 */
function bio_oe_filtrar_mayor_edad(mysqli $conn, array $visitas, string $fecha, ?int $edadDestino): array
{
    if ($edadDestino === null || $visitas === []) {
        return [];
    }
    $granjas = [];
    foreach ($visitas as $v) {
        $granjas[$v['granja']] = true;
    }
    $nombres = bio_es_nombres_granjas($conn, array_keys($granjas));
    $out = [];
    foreach ($visitas as $v) {
        $edad = bio_oe_edad_granja($conn, (string) $v['granja'], (string) $v['campania'], $fecha);
        if ($edad === null || $edad <= $edadDestino) {
            continue;
        }
        $g3 = (string) $v['granja'];
        $out[] = [
            'granja' => $g3,
            'nombreGranja' => $nombres[$g3] ?? '',
            'campania' => (string) $v['campania'],
            'edad' => $edad,
            'horaIngreso' => bio_norm_hora((string) ($v['hora'] ?? '')),
        ];
    }

    return $out;
}

/**
 * @param string[] $dnis
 * @param string[] $placas
 * @return array<string,mixed>
 */
function bio_oe_consultar(
    mysqli $conn,
    string $fecha,
    string $granja,
    string $campania,
    array $dnis,
    array $placas
): array {
    $granja = $granja !== '' ? bio_norm_granja($granja) : '';
    $campania = bio_norm_campania($campania);
    $edadDest = ($granja !== '' && $campania !== '')
        ? bio_oe_edad_granja($conn, $granja, $campania, $fecha)
        : null;

    $out = [
        'disponible' => $edadDest !== null,
        'fecha' => $fecha,
        'granja' => $granja,
        'campania' => $campania,
        'edadGranja' => $edadDest,
        'dnis' => (object) [],
        'placas' => (object) [],
    ];
    if ($edadDest === null) {
        return $out;
    }

    $visitasDni = bio_oe_visitas_hoy_por_dni($conn, $dnis, $fecha, $granja);
    $porDni = [];
    foreach ($dnis as $dni) {
        $lista = bio_oe_filtrar_mayor_edad($conn, $visitasDni[$dni] ?? [], $fecha, $edadDest);
        $porDni[$dni] = [
            'enRiesgo' => $lista !== [],
            'origenes' => $lista,
        ];
    }
    $out['dnis'] = $porDni === [] ? (object) [] : $porDni;

    $visitasPlaca = bio_oe_visitas_hoy_por_placa($conn, $placas, $fecha, $granja);
    $porPlaca = [];
    foreach ($placas as $placa) {
        $p = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', (string) $placa));
        if ($p === '') {
            continue;
        }
        $lista = bio_oe_filtrar_mayor_edad($conn, $visitasPlaca[$p] ?? [], $fecha, $edadDest);
        $porPlaca[$p] = [
            'enRiesgo' => $lista !== [],
            'origenes' => $lista,
        ];
    }
    $out['placas'] = $porPlaca === [] ? (object) [] : $porPlaca;

    return $out;
}
