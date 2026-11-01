<?php
declare(strict_types=1);

/**
 * Nómina DNI → proveedor para el control de ingreso sin planificación.
 *
 * La app la descarga y, al escanear personas que no figuran en ninguna visita,
 * propone el proveedor al que pertenecen:
 *   · `nomina`: personal activo que cada proveedor registró en el portal
 *     (`san_personal_proveedor`, «Planificación de proveedor»);
 *   · `historial`: proveedor con el que la persona figuró en planificaciones o
 *     ingresos recientes, para los DNI que aún no están en ninguna nómina.
 * Solo lectura.
 */

require_once __DIR__ . '/bio_plan_tablas_lib.php';

/** Días hacia atrás que se revisan en planificaciones e ingresos. */
const BIO_NOM_DIAS_HISTORIAL = 180;

/** Máximo de proveedores por DNI (una persona puede trabajar para varios). */
const BIO_NOM_MAX_RUC_POR_DNI = 3;

/** DNI (8 dígitos) o CEE (6–15 alfanuméricos); '' si no cumple. */
function bio_nom_doc_norm(string $raw): string
{
    $t = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', $raw));
    if (preg_match('/^\d{8}$/', $t)) {
        return $t;
    }
    if (preg_match('/^\d{10}$/', $t)) {
        $t = substr($t, 0, 9);
    }
    $len = strlen($t);

    return ($len >= 6 && $len <= 15 && !preg_match('/^\d{8}$/', $t)) ? $t : '';
}

function bio_nom_ruc_norm(string $raw): string
{
    $r = (string) preg_replace('/\D/', '', $raw);

    return strlen($r) === 11 ? $r : '';
}

function bio_nom_tabla_existe(mysqli $conn, string $tabla): bool
{
    $r = @$conn->query("SHOW TABLES LIKE '" . $conn->real_escape_string($tabla) . "'");

    return $r && $r->num_rows > 0;
}

/**
 * Filas de una consulta sin parámetros; [] si la tabla o columna no existe.
 *
 * @return list<array<string,mixed>>
 */
function bio_nom_filas(mysqli $conn, string $sql, string $types = '', array $params = []): array
{
    try {
        $st = @$conn->prepare($sql);
        if (!$st) {
            return [];
        }
        if ($params !== []) {
            $st->bind_param($types, ...$params);
        }
        if (!$st->execute()) {
            $st->close();

            return [];
        }
        $res = $st->get_result();
        $out = [];
        while ($res && ($row = $res->fetch_assoc())) {
            $out[] = $row;
        }
        $st->close();

        return $out;
    } catch (Throwable $e) {
        return [];
    }
}

/**
 * @param array<string, list<string>> $mapa
 */
function bio_nom_agregar(array &$mapa, string $dni, string $ruc): void
{
    if ($dni === '' || $ruc === '') {
        return;
    }
    $lista = $mapa[$dni] ?? [];
    if (in_array($ruc, $lista, true) || count($lista) >= BIO_NOM_MAX_RUC_POR_DNI) {
        return;
    }
    $lista[] = $ruc;
    $mapa[$dni] = $lista;
}

/**
 * Procesos guardados del proveedor (mismo separador que el portal).
 *
 * @return list<string>
 */
function bio_nom_procesos(string $raw): array
{
    $out = [];
    foreach (preg_split('/[\r\n,;|]+/', trim($raw)) ?: [] as $p) {
        $p = trim((string) $p);
        if ($p !== '' && strcasecmp($p, 'Otro') !== 0 && !in_array($p, $out, true)) {
            $out[] = $p;
        }
    }

    return $out;
}

/**
 * @return array{disponible:bool,generado:string,proveedores:array<string,string>,procesos:array<string,list<string>>,ultimoProceso:array<string,string>,nomina:array<string,list<string>>,historial:array<string,list<string>>}
 */
function bio_nom_descargar(mysqli $conn): array
{
    $proveedores = [];
    $procesos = [];
    $ultimoProceso = [];
    $nomina = [];
    $historial = [];

    // Razón social y procesos asignados a los proveedores con usuario en el portal.
    $filasUsuario = bio_nom_filas(
        $conn,
        "SELECT TRIM(ruc) AS ruc, TRIM(razonsocial) AS razon, proceso
           FROM san_usuario_proveedor
          WHERE TRIM(razonsocial) <> ''"
    );
    if ($filasUsuario === []) {
        $filasUsuario = bio_nom_filas(
            $conn,
            "SELECT TRIM(ruc) AS ruc, TRIM(razonsocial) AS razon, '' AS proceso
               FROM san_usuario_proveedor
              WHERE TRIM(razonsocial) <> ''"
        );
    }
    foreach ($filasUsuario as $r) {
        $ruc = bio_nom_ruc_norm((string) $r['ruc']);
        if ($ruc === '') {
            continue;
        }
        if (!isset($proveedores[$ruc])) {
            $proveedores[$ruc] = trim((string) $r['razon']);
        }
        foreach (bio_nom_procesos((string) ($r['proceso'] ?? '')) as $p) {
            if (!in_array($p, $procesos[$ruc] ?? [], true)) {
                $procesos[$ruc][] = $p;
            }
        }
    }

    if (bio_nom_tabla_existe($conn, 'san_personal_proveedor')) {
        foreach (bio_nom_filas(
            $conn,
            'SELECT TRIM(ruc) AS ruc, TRIM(dni) AS dni
               FROM san_personal_proveedor
              WHERE activo = 1
              ORDER BY fechaHoraModificacion DESC'
        ) as $r) {
            bio_nom_agregar(
                $nomina,
                bio_nom_doc_norm((string) $r['dni']),
                bio_nom_ruc_norm((string) $r['ruc'])
            );
        }
    }

    $desde = date('Y-m-d', strtotime('-' . BIO_NOM_DIAS_HISTORIAL . ' days'));
    $fuentes = [
        [bio_plan_tabla_cab(), bio_plan_tabla_det()],
        ['san_fact_ingresogranja_cab', 'san_fact_ingresogranja_det'],
    ];
    foreach ($fuentes as [$cab, $det]) {
        if (!bio_nom_tabla_existe($conn, $cab) || !bio_nom_tabla_existe($conn, $det)) {
            continue;
        }
        $filas = bio_nom_filas(
            $conn,
            "SELECT TRIM(d.dni) AS dni, TRIM(c.proveedorRuc) AS ruc, TRIM(c.proveedor) AS proveedor
               FROM `{$det}` d
               JOIN `{$cab}` c ON c.id = d.idCab
              WHERE c.fecha >= ? AND TRIM(c.proveedorRuc) <> ''
              ORDER BY c.fecha DESC",
            's',
            [$desde]
        );
        foreach ($filas as $r) {
            $dni = bio_nom_doc_norm((string) $r['dni']);
            $ruc = bio_nom_ruc_norm((string) $r['ruc']);
            if ($dni === '' || $ruc === '' || isset($nomina[$dni])) {
                continue;
            }
            bio_nom_agregar($historial, $dni, $ruc);
            $prov = trim((string) $r['proveedor']);
            if ($prov !== '' && !isset($proveedores[$ruc])) {
                $proveedores[$ruc] = $prov;
            }
        }

        // Último proceso (motivo) con que vino cada proveedor.
        foreach (bio_nom_filas(
            $conn,
            "SELECT TRIM(proveedorRuc) AS ruc, TRIM(motivo) AS motivo
               FROM `{$cab}`
              WHERE fecha >= ? AND TRIM(proveedorRuc) <> '' AND TRIM(motivo) <> ''
              ORDER BY fecha DESC",
            's',
            [$desde]
        ) as $r) {
            $ruc = bio_nom_ruc_norm((string) $r['ruc']);
            if ($ruc !== '' && !isset($ultimoProceso[$ruc])) {
                $ultimoProceso[$ruc] = trim((string) $r['motivo']);
            }
        }
    }

    return [
        'disponible' => true,
        'generado' => date('c'),
        'proveedores' => $proveedores,
        'procesos' => $procesos,
        'ultimoProceso' => $ultimoProceso,
        'nomina' => $nomina,
        'historial' => $historial,
    ];
}
