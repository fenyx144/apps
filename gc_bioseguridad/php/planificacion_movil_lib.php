<?php
declare(strict_types=1);

require_once __DIR__ . '/php7_compat.php';

/**
 * Consulta informativa de la «Planificación de visitas» (portal web,
 * Bioseguridad física) para el control de ingreso de la app.
 *
 * Solo lectura sobre san_fact_planvisita_* . Nunca decide nada: la app
 * muestra «Planificado» / «No planificado» y guarda igual. Si las tablas aún
 * no existen (migración pendiente) o la consulta falla, se responde
 * `disponible = false` y la app se queda en estado neutro.
 *
 * Criterio de coincidencia:
 *   - Visitas cuya fecha programada es la fecha del registro de ingreso (la
 *     que envía la app; por defecto, hoy).
 *   - De la misma granja. La campaña no se exige: la granja + la fecha ya
 *     identifican la visita.
 *   - Placa: se compara sin guiones ni espacios y en mayúsculas.
 *   - DNI: 8 dígitos exactos.
 *   - Si el DNI o la placa están planificados ese día pero en OTRA granja, se
 *     informa como «no planificado» con la granja donde sí figura.
 */

require_once __DIR__ . '/bio_plan_tablas_lib.php';

function bio_plan_norm_placa(string $placa): string
{
    return strtoupper(preg_replace('/[^A-Za-z0-9]+/', '', $placa) ?? '');
}

/**
 * ¿El DNI ya tiene un ingreso guardado hoy vinculado a esa planificación?
 * (ingresos sincronizados en san_fact_ingresogranja_*).
 */
function bio_plan_dni_ya_ingreso(
    mysqli $conn,
    string $fecha,
    string $dni,
    int $planVisitaId
): bool {
    if ($planVisitaId <= 0 || strlen($dni) !== 8) {
        return false;
    }
    $fecha = trim($fecha);
    if ($fecha === '') {
        return false;
    }
    static $tablasOk = null;
    if ($tablasOk === null) {
        $tablasOk = bio_plan_ensure_tablas($conn);
    }
    if (!$tablasOk) {
        return false;
    }
    $cab = 'san_fact_ingresogranja_cab';
    $det = 'san_fact_ingresogranja_det';
    if (!function_exists('bio_col_exists')) {
        require_once __DIR__ . '/bioseguridad_movil_lib.php';
    }
    if (!bio_col_exists($conn, $cab, 'planVisitaId')) {
        return false;
    }
    try {
        $st = $conn->prepare(
            'SELECT 1 FROM `' . $cab . '` c
              INNER JOIN `' . $det . '` d ON d.idCab = c.id
             WHERE c.fecha = ? AND c.planVisitaId = ? AND d.dni = ?
             LIMIT 1'
        );
        if (!$st) {
            return false;
        }
        $st->bind_param('sis', $fecha, $planVisitaId, $dni);
        $st->execute();
        $res = $st->get_result();
        $hay = $res && $res->fetch_assoc();
        $st->close();

        return (bool) $hay;
    } catch (Throwable $e) {
        return false;
    }
}

/** ¿La visita incluye esa placa (cab o san_fact_planvisita_veh)? */
function bio_plan_visita_tiene_placa(array $visita, string $placaNorm): bool
{
    if ($placaNorm === '') {
        return false;
    }
    foreach ((array) ($visita['vehiculos'] ?? []) as $veh) {
        if (!is_array($veh)) {
            continue;
        }
        if (bio_plan_norm_placa((string) ($veh['placa'] ?? '')) === $placaNorm) {
            return true;
        }
    }

    return bio_plan_norm_placa((string) ($visita['placa'] ?? '')) === $placaNorm;
}

function bio_plan_cols_areaproveedor(mysqli $conn): bool
{
    unset($conn);

    return true;
}

/**
 * Visitas entre dos fechas (inclusive), con sus DNIs y nombres.
 * Es la consulta común de la verificación puntual y de la descarga offline.
 *
 * Tablas `san_fact_planvisita_cab` / `_det`: granja y campaña en campos
 * separados; detalle enlazado por `idCab` y `posicion`.
 *
 * @return array<string,array<string,mixed>> id (entero portal) => visita
 */
function bio_plan_visitas_rango(mysqli $conn, string $desde, string $hasta): array
{
    $cab = bio_plan_tabla_cab();
    $det = bio_plan_tabla_det();
    $galponSql = bio_plan_sql_col_galpon($conn);
    $st = $conn->prepare(
        'SELECT p.id, p.fecha, TRIM(p.granja) AS granja, TRIM(p.campania) AS campania,
                p.numPersonas AS numpersonas, p.usuarioRegistrador,
                p.proveedorRuc, p.proveedor,
                p.areaProveedor AS areaproveedor, p.motivo, p.observacion' . $galponSql . ',
                d.dni, d.nombre
           FROM `' . $cab . '` p
      LEFT JOIN `' . $det . '` d ON d.idCab = p.id
          WHERE p.fecha BETWEEN ? AND ?
       ORDER BY p.fecha, p.id, d.posicion'
    );
    if (!$st) {
        return [];
    }
    $st->bind_param('ss', $desde, $hasta);
    $st->execute();
    $res = $st->get_result();

    $visitas = [];
    while ($r = $res->fetch_assoc()) {
        $id = (string) $r['id'];
        if (!isset($visitas[$id])) {
            $granja = (string) $r['granja'];
            $campania = (string) $r['campania'];
            $visitas[$id] = [
                'id' => $id,
                'fecha' => (string) $r['fecha'],
                'cencos' => $granja . $campania,
                'granja' => $granja,
                'campania' => $campania,
                'placa' => '',
                'placas' => [],
                'vehiculos' => [],
                'proveedorRuc' => (string) bio_utf8((string) ($r['proveedorRuc'] ?? '')),
                'proveedor' => (string) bio_utf8((string) ($r['proveedor'] ?? '')),
                'numpersonas' => (int) $r['numpersonas'],
                // «AREA» o «PROVEEDOR» y el valor elegido, igual que en el
                // control de ingreso: la app los muestra al elegir la visita.
                'areaproveedor' => (string) bio_utf8((string) ($r['areaproveedor'] ?? '')),
                'motivo' => (string) bio_utf8((string) ($r['motivo'] ?? '')),
                'observacion' => (string) bio_utf8((string) ($r['observacion'] ?? '')),
                'galpon' => (string) bio_utf8((string) ($r['galpon'] ?? '')),
                'galpones' => bio_plan_galpones_desde_texto(
                    (string) bio_utf8((string) ($r['galpon'] ?? ''))
                ),
                // Código del usuario que planificó (`usuarioRegistrador`), sin
                // sustituir por el RUC: son datos distintos.
                'registradoPor' => (string) bio_utf8((string) $r['usuarioRegistrador']),
                'ruc' => '',
                // Razón social y proceso del proveedor que planificó: se
                // completan abajo desde `san_usuario_proveedor`.
                'razonsocial' => '',
                'proceso' => '',
                'dnis' => [],
            ];
        }
        $dni = preg_replace('/\D+/', '', (string) ($r['dni'] ?? '')) ?? '';
        if ($dni !== '' && !isset($visitas[$id]['dnis'][$dni])) {
            $visitas[$id]['dnis'][$dni] = trim((string) bio_utf8((string) ($r['nombre'] ?? '')));
        }
    }
    $st->close();

    // RUC, razón social y proceso del proveedor vinculado al código que
    // planificó (`san_usuario_proveedor`). `registradoPor` sigue siendo el
    // código de usuario; el RUC va en el campo `ruc`.
    $codigosRegistrador = array_column($visitas, 'registradoPor');
    $rucs = bio_plan_ruc_por_usuario($conn, $codigosRegistrador);
    $provs = bio_plan_proveedor_por_usuario($conn, $codigosRegistrador);
    foreach ($visitas as $id => $v) {
        $cod = strtoupper(trim((string) $v['registradoPor']));
        if (($rucs[$cod] ?? '') !== '') {
            $visitas[$id]['ruc'] = $rucs[$cod];
        }
        if (isset($provs[$cod])) {
            $visitas[$id]['razonsocial'] = $provs[$cod]['razonsocial'];
            $visitas[$id]['proceso'] = $provs[$cod]['proceso'];
        }
    }

    // Vehículos de cada visita (multi-vehículo) con su flag «ingresa a la
    // granja». Si la tabla todavía no existe, la app se queda con la única
    // placa de la cabecera.
    $vehiculos = bio_plan_placas_por_plan($conn, array_map('strval', array_keys($visitas)));
    foreach ($vehiculos as $id => $lista) {
        if ($lista === []) {
            continue;
        }
        $visitas[$id]['vehiculos'] = $lista;
        $visitas[$id]['placas'] = array_column($lista, 'placa');
        $visitas[$id]['placa'] = $lista[0]['placa'];
    }

    return $visitas;
}

/**
 * Vehículos de cada planificación desde `san_fact_planvisita_veh`, con
 * el flag «ingresa a la granja». Devuelve [] si la tabla todavía no existe.
 *
 * @param list<string> $ids
 * @return array<string, list<array{placa:string,ingresa:int}>>
 */
function bio_plan_placas_por_plan(mysqli $conn, array $ids): array
{
    if ($ids === []) {
        return [];
    }
    $veh = bio_plan_tabla_veh();
    if (!bio_plan_ensure_tablas($conn)) {
        return [];
    }

    $marks = implode(',', array_fill(0, count($ids), '?'));
    $st = $conn->prepare(
        "SELECT idCab AS idplan, TRIM(placa) AS placa, ingresa FROM `{$veh}`
          WHERE idCab IN ({$marks}) ORDER BY idCab, posicion, id"
    );
    if (!$st) {
        return [];
    }
    $st->bind_param(str_repeat('s', count($ids)), ...$ids);
    $st->execute();
    $res = $st->get_result();

    $out = [];
    while ($res && ($r = $res->fetch_assoc())) {
        $placa = trim((string) bio_utf8((string) $r['placa']));
        if ($placa !== '') {
            $out[(string) $r['idplan']][] = [
                'placa' => $placa,
                'ingresa' => (int) ($r['ingresa'] ?? 1) === 0 ? 0 : 1,
            ];
        }
    }
    $st->close();

    return $out;
}

/**
 * Razón social y procesos del proveedor asignado a cada código de usuario.
 *
 * Sale de `san_usuario_proveedor` (la tabla del portal web). Sirve para que la
 * app muestre, junto al RUC que planificó, su razón social y su proceso.
 *
 * @param list<string> $codigos
 * @return array<string, array{razonsocial:string,proceso:string}>
 */
function bio_plan_proveedor_por_usuario(mysqli $conn, array $codigos): array
{
    $norm = [];
    foreach ($codigos as $c) {
        $c = strtoupper(trim((string) $c));
        if ($c !== '') {
            $norm[$c] = true;
        }
    }
    $codigos = array_keys($norm);
    if ($codigos === []) {
        return [];
    }
    $chk = @$conn->query("SHOW TABLES LIKE 'san_usuario_proveedor'");
    if (!$chk || $chk->num_rows === 0) {
        return [];
    }
    $chk->free();

    $marks = implode(',', array_fill(0, count($codigos), '?'));
    $st = $conn->prepare(
        "SELECT UPPER(TRIM(codigo)) AS codigo, TRIM(razonsocial) AS razonsocial, TRIM(proceso) AS proceso
           FROM san_usuario_proveedor WHERE UPPER(TRIM(codigo)) IN ({$marks})"
    );
    if (!$st) {
        return [];
    }
    $st->bind_param(str_repeat('s', count($codigos)), ...$codigos);
    $st->execute();
    $res = $st->get_result();

    $out = [];
    while ($res && ($r = $res->fetch_assoc())) {
        $out[(string) $r['codigo']] = [
            'razonsocial' => trim((string) bio_utf8((string) $r['razonsocial'])),
            'proceso' => trim((string) bio_utf8((string) $r['proceso'])),
        ];
    }
    $st->close();

    return $out;
}

/**
 * RUC del proveedor por código de usuario (clave en mayúsculas).
 *
 * El RUC sale de `san_usuario_proveedor`, la misma tabla que usa la web en
 * «Planificación de proveedor» (código de usuario  RUC asignado). No se usa
 * `usuario.ruc` como fuente principal: en este servidor esa columna guarda la
 * planta o zona del usuario (p. ej. «LA JOYA»), no un RUC, y hacía que la app
 * mostrara el código del usuario en vez del RUC.
 *
 * Devuelve [] si la tabla no existe, si no hay códigos o si la consulta falla:
 * el llamador conserva entonces el código como respaldo.
 *
 * @param list<string> $codigos
 * @return array<string,string>
 */
function bio_plan_ruc_por_usuario(mysqli $conn, array $codigos): array
{
    $norm = [];
    foreach ($codigos as $c) {
        $c = strtoupper(trim((string) $c));
        if ($c !== '') {
            $norm[$c] = true;
        }
    }
    $codigos = array_keys($norm);
    if ($codigos === []) {
        return [];
    }

    $marks = implode(',', array_fill(0, count($codigos), '?'));
    $bind = str_repeat('s', count($codigos));

    // 1) Proveedor asignado (fuente real del RUC en la web).
    $chk = @$conn->query("SHOW TABLES LIKE 'san_usuario_proveedor'");
    if ($chk && $chk->num_rows > 0) {
        $chk->free();
        $st = $conn->prepare(
            "SELECT UPPER(TRIM(codigo)) AS codigo, TRIM(ruc) AS ruc
               FROM san_usuario_proveedor WHERE UPPER(TRIM(codigo)) IN ({$marks})"
        );
        if ($st) {
            $st->bind_param($bind, ...$codigos);
            $st->execute();
            $res = $st->get_result();
            $out = [];
            while ($res && ($r = $res->fetch_assoc())) {
                $ruc = preg_replace('/\D/', '', (string) bio_utf8((string) $r['ruc'])) ?? '';
                if (preg_match('/^\d{11}$/', $ruc)) {
                    $out[(string) $r['codigo']] = $ruc;
                }
            }
            $st->close();
            if ($out !== []) {
                return $out;
            }
        }
    }

    // 2) Respaldo heredado: `usuario.ruc` solo si de verdad es un RUC de 11
    // dígitos (así «LA JOYA» o «LIMA» no se cuelan como RUC).
    $col = @$conn->query("SHOW COLUMNS FROM `usuario` LIKE 'ruc'");
    if (!$col || $col->num_rows === 0) {
        return [];
    }
    $col->free();

    $st = $conn->prepare(
        "SELECT UPPER(TRIM(codigo)) AS codigo, TRIM(ruc) AS ruc
           FROM usuario WHERE UPPER(TRIM(codigo)) IN ({$marks})"
    );
    if (!$st) {
        return [];
    }
    $st->bind_param($bind, ...$codigos);
    $st->execute();
    $res = $st->get_result();

    $out = [];
    while ($res && ($r = $res->fetch_assoc())) {
        $ruc = preg_replace('/\D/', '', (string) bio_utf8((string) $r['ruc'])) ?? '';
        if (preg_match('/^\d{11}$/', $ruc)) {
            $out[(string) $r['codigo']] = $ruc;
        }
    }
    $st->close();

    return $out;
}

/**
 * Formato público de una visita (el que recibe la app).
 *
 * @param array<string,string> $nombres cencos => nombre de granja
 * @return array<string,mixed>
 */
function bio_plan_visita_publica(array $v, array $nombres): array
{
    $personas = [];
    foreach ($v['dnis'] as $dni => $nombre) {
        $personas[] = ['dni' => (string) $dni, 'nombre' => (string) $nombre];
    }

    return [
        'id' => $v['id'],
        'fecha' => $v['fecha'],
        'granja' => $v['granja'],
        'campania' => $v['campania'],
        'nombreGranja' => $nombres[$v['cencos']] ?? '',
        'placa' => $v['placa'],
        'placas' => (array) ($v['placas'] ?? []),
        'vehiculos' => (array) ($v['vehiculos'] ?? []),
        'areaproveedor' => $v['areaproveedor'],
        'motivo' => $v['motivo'],
        'observacion' => $v['observacion'],
        'numpersonas' => $v['numpersonas'],
        'registradoPor' => $v['registradoPor'],
        'ruc' => (string) ($v['ruc'] ?? ''),
        'razonsocial' => (string) ($v['razonsocial'] ?? ''),
        'proceso' => (string) ($v['proceso'] ?? ''),
        'personas' => $personas,
        'galpon' => (string) ($v['galpon'] ?? ''),
        'galpones' => array_values((array) ($v['galpones'] ?? [])),
    ];
}

/**
 * Listado para el portal (pestaña Planificación): filtros por fecha, granja y texto.
 *
 * @return array<int,array<string,mixed>>
 */
function bio_plan_listado_portal(
    mysqli $conn,
    string $desde,
    string $hasta,
    string $granjaFiltro = '',
    string $buscar = ''
): array {
    $visitas = bio_plan_visitas_rango($conn, $desde, $hasta);
    $nombres = bio_plan_nombres_cencos($conn, array_column($visitas, 'cencos'));
    $granjaF = trim($granjaFiltro);
    $q = mb_strtoupper(trim($buscar), 'UTF-8');
    $out = [];
    foreach ($visitas as $v) {
        if ($granjaF !== '' && (string) $v['granja'] !== $granjaF) {
            continue;
        }
        $pub = bio_plan_visita_publica($v, $nombres);
        if ($q !== '') {
            $blob = mb_strtoupper(
                implode(
                    ' ',
                    [
                        (string) $pub['granja'],
                        (string) $pub['nombreGranja'],
                        (string) $pub['proveedor'],
                        (string) $pub['razonsocial'],
                        (string) $pub['motivo'],
                        (string) $pub['observacion'],
                        (string) $pub['galpon'],
                        implode(' ', (array) $pub['galpones']),
                        implode(' ', (array) $pub['placas']),
                    ]
                ),
                'UTF-8'
            );
            if (strpos($blob, $q) === false) {
                continue;
            }
        }
        $out[] = $pub;
    }

    return $out;
}

/**
 * Descarga para trabajar sin señal: visitas activas desde $desde durante $dias días.
 *
 * @return array<string,mixed>
 */
function bio_plan_descargar(mysqli $conn, string $desde, int $dias): array
{
    $dias = max(1, min(31, $dias));
    $hasta = date('Y-m-d', strtotime($desde . ' +' . ($dias - 1) . ' days'));
    $out = [
        'disponible' => false,
        'desde' => $desde,
        'hasta' => $hasta,
        'generado' => date('Y-m-d H:i:s'),
        'conAreaproveedor' => true,
        'visitas' => [],
    ];
    $visitas = bio_plan_visitas_rango($conn, $desde, $hasta);
    $nombres = bio_plan_nombres_cencos($conn, array_column($visitas, 'cencos'));
    $out['disponible'] = true;
    foreach ($visitas as $v) {
        $out['visitas'][] = bio_plan_visita_publica($v, $nombres);
    }

    return $out;
}

/**
 * Nombres de granja desde ccos para los cencos dados (vacío si algo falla).
 *
 * @param string[] $cencos
 * @return array<string,string> cencos => nombre
 */
function bio_plan_nombres_cencos(mysqli $conn, array $cencos): array
{
    $cencos = array_values(array_unique(array_filter($cencos, 'strlen')));
    if ($cencos === []) {
        return [];
    }
    try {
        $ph = implode(',', array_fill(0, count($cencos), '?'));
        $st = $conn->prepare('SELECT TRIM(codigo) AS codigo, TRIM(nombre) AS nombre FROM ccos WHERE TRIM(codigo) IN (' . $ph . ')');
        if (!$st) {
            return [];
        }
        $st->bind_param(str_repeat('s', count($cencos)), ...$cencos);
        $st->execute();
        $out = [];
        $res = $st->get_result();
        while ($r = $res->fetch_assoc()) {
            $out[(string) $r['codigo']] = (string) bio_utf8((string) $r['nombre']);
        }
        $st->close();

        return $out;
    } catch (Throwable $e) {
        return [];
    }
}

/**
 * @param string[] $dnis
 * @return array<string,mixed>
 */
function bio_plan_consultar(mysqli $conn, string $fecha, string $granja, string $placa, array $dnis): array
{
    $granja = $granja !== '' ? bio_norm_granja($granja) : '';
    $placaN = bio_plan_norm_placa($placa);
    $dnis = array_values(array_unique(array_filter(
        array_map(static function ($d) {
            return preg_replace('/\D+/', '', (string) $d) ?? '';
        }, $dnis),
        static function ($d) {
            return strlen($d) === 8;
        }
    )));

    $vacio = [
        'disponible' => false,
        'fecha' => $fecha,
        'granja' => $granja,
        'placa' => null,
        'conAreaproveedor' => true,
        'dnis' => (object) [],
    ];

    // Todas las visitas activas del día (pocas filas): se filtran en PHP para
    // comparar placas normalizadas y distinguir «otra granja».
    $visitas = bio_plan_visitas_rango($conn, $fecha, $fecha);

    $nombres = bio_plan_nombres_cencos($conn, array_column($visitas, 'cencos'));
    $resumen = static function (array $v) use ($nombres): array {
        return bio_plan_visita_publica($v, $nombres);
    };
    $evaluar = static function (callable $coincide) use ($visitas, $granja, $resumen): array {
        $aqui = null;
        $otra = null;
        $todas = [];
        foreach ($visitas as $v) {
            if (!$coincide($v)) {
                continue;
            }
            $pub = $resumen($v);
            $todas[] = $pub;
            if ($granja === '' || $v['granja'] === $granja) {
                $aqui = $aqui ?? $pub;
            } else {
                $otra = $otra ?? $pub;
            }
        }

        return [
            'planificado' => $aqui !== null,
            'visita' => $aqui,
            'otraGranja' => $aqui === null ? $otra : null,
            // Todas las visitas del día que coinciden (varias granjas): la app
            // deja elegir a cuáles ingresa.
            'visitas' => $todas,
        ];
    };

    $out = $vacio;
    $out['disponible'] = true;
    $out['conAreaproveedor'] = true;
    if ($placaN !== '') {
        $out['placa'] = ['valor' => $placaN] + $evaluar(static function (array $v) use ($placaN): bool {
            return bio_plan_visita_tiene_placa($v, $placaN);
        });
    }
    $porDni = [];
    foreach ($dnis as $dni) {
        $porDni[$dni] = $evaluar(static function (array $v) use ($dni, $conn, $fecha): bool {
            if (!isset($v['dnis'][$dni])) {
                return false;
            }
            $planId = (int) ($v['id'] ?? 0);

            return !bio_plan_dni_ya_ingreso($conn, $fecha, $dni, $planId);
        });
    }
    $out['dnis'] = $porDni === [] ? (object) [] : $porDni;

    return $out;
}
