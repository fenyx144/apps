<?php
declare(strict_types=1);

/**
 * Nombres de tablas de planificación (`san_fact_planvisita_*`).
 * El esquema se define solo en migracion_bioseguridad_app.php / sql/.
 */

function bio_plan_tabla_cab(): string
{
    return 'san_fact_planvisita_cab';
}

function bio_plan_tabla_det(): string
{
    return 'san_fact_planvisita_det';
}

function bio_plan_tabla_veh(): string
{
    return 'san_fact_planvisita_veh';
}

/** @deprecated alias; esquema ya migrado en prod */
function bio_plan_ensure_tablas(mysqli $conn): bool
{
    unset($conn);

    return true;
}

function bio_plan_tablas_existen(mysqli $conn): bool
{
    return bio_plan_ensure_tablas($conn);
}

function bio_plan_tiene_cols_areaproveedor(mysqli $conn): bool
{
    unset($conn);

    return true;
}

/** Carga bio_fetch_rows (lib móvil o portal) sin depender de un solo directorio. */
function bio_plan_require_fetch_rows(): void
{
    if (function_exists('bio_fetch_rows')) {
        return;
    }
    foreach ([
        __DIR__ . '/bioseguridad_movil_lib.php',
        __DIR__ . '/bioseguridad_lib.php',
        __DIR__ . '/../../modules/sip/reportes-especiales/bioseguridad/bioseguridad_lib.php',
    ] as $path) {
        if (!is_file($path)) {
            continue;
        }
        require_once $path;
        if (function_exists('bio_fetch_rows')) {
            return;
        }
    }
}

function bio_plan_asegurar_cols_areaproveedor(mysqli $conn): bool
{
    return bio_plan_tablas_existen($conn);
}

function bio_plan_tiene_col_galpon(mysqli $conn): bool
{
    if (!function_exists('bio_col_exists')) {
        require_once __DIR__ . '/bioseguridad_movil_lib.php';
    }

    return bio_col_exists($conn, bio_plan_tabla_cab(), 'galpon');
}

function bio_plan_asegurar_col_galpon(mysqli $conn): bool
{
    if (bio_plan_tiene_col_galpon($conn)) {
        return true;
    }
    $cab = bio_plan_tabla_cab();
    @$conn->query(
        'ALTER TABLE `' . $cab . '` ADD COLUMN `galpon` varchar(120) NOT NULL DEFAULT \'\' AFTER `observacion`'
    );

    return bio_plan_tiene_col_galpon($conn);
}

/** Fragmento SELECT para `galpon` si la columna ya existe en cab. */
function bio_plan_sql_col_galpon(mysqli $conn): string
{
    if (!bio_plan_tiene_col_galpon($conn)) {
        return '';
    }

    return ', TRIM(p.galpon) AS galpon';
}

/**
 * @return string[] códigos de galpón (varios en un varchar separados por coma).
 */
function bio_plan_galpones_desde_texto(string $raw): array
{
    $out = [];
    foreach (preg_split('/\s*,\s*/', trim($raw)) ?: [] as $g) {
        $g = trim((string) $g);
        if ($g !== '' && !in_array($g, $out, true)) {
            $out[] = $g;
        }
    }

    return $out;
}

function bio_plan_serializar_galpones(array $codigosGalpon): string
{
    $txt = implode(', ', bio_plan_galpones_desde_texto(implode(',', $codigosGalpon)));
    if ($txt === '') {
        return '';
    }

    return mb_strlen($txt, 'UTF-8') <= 120 ? $txt : mb_substr($txt, 0, 120, 'UTF-8');
}

/** Día de pollo: días(fecha − fec_ing) + 1 (igual seguimiento de crianza). */
function bio_plan_edad_dias_fec_ing(string $fechaYmd, string $fecIngYmd): ?int
{
    $fechaYmd = trim($fechaYmd);
    $fecIngYmd = trim($fecIngYmd);
    if ($fechaYmd === '' || $fecIngYmd === '' || strpos($fecIngYmd, '0000') === 0) {
        return null;
    }
    try {
        $d1 = new DateTimeImmutable($fechaYmd);
        $d0 = new DateTimeImmutable($fecIngYmd);
    } catch (Throwable $e) {
        return null;
    }
    $edad = (int) $d0->diff($d1)->days + 1;
    if ($edad <= 0 || $edad > 2000) {
        return null;
    }

    return $edad;
}

/** Código CENCO de 6 caracteres (granja + campaña), igual ccos / control plagas. */
function bio_plan_codigo_cenco6(string $granja3, string $campania): string
{
    if (function_exists('ccos_norm_granja')) {
        $granja3 = ccos_norm_granja($granja3);
    } elseif (function_exists('bio_norm_granja')) {
        $granja3 = bio_norm_granja($granja3);
    } else {
        $granja3 = trim($granja3);
    }
    if (function_exists('ccos_norm_campania')) {
        $campania = ccos_norm_campania($campania);
    } else {
        $d = preg_replace('/\D/', '', trim($campania)) ?? '';
        $campania = $d !== '' ? substr(str_pad($d, 3, '0', STR_PAD_LEFT), -3) : '';
    }
    if ($granja3 === '' || $campania === '') {
        return '';
    }
    $raw = $granja3 . $campania;
    if (function_exists('cp_cenco_canon')) {
        return cp_cenco_canon($raw);
    }

    return strlen($raw) === 6 ? $raw : '';
}

function bio_plan_galpon_codigo_coincide(string $a, string $b): bool
{
    $a = trim($a);
    $b = trim($b);
    if ($a === '' || $b === '') {
        return false;
    }
    if ($a === $b) {
        return true;
    }
    if (ctype_digit($a) && ctype_digit($b)) {
        return (int) $a === (int) $b;
    }

    return false;
}

/**
 * Códigos de galpón de un CENCO (misma unión que get_cencos_galpones.php seguimiento).
 *
 * @return list<string>
 */
function bio_plan_lista_galpones_cenco(mysqli $conn, string $cenco6): array
{
    $cenco6 = trim($cenco6);
    if (strlen($cenco6) !== 6) {
        return [];
    }
    bio_plan_require_fetch_rows();
    $rows = bio_fetch_rows(
        $conn,
        'SELECT DISTINCT TRIM(g.tcodint) AS codigo
           FROM ccos AS c
           INNER JOIN regcencosgalpones AS g ON LEFT(c.codigo, 3) = TRIM(g.tcencos)
          WHERE c.codigo = ?
            AND c.swac = \'A\'
            AND CHAR_LENGTH(c.codigo) = 6
            AND LEFT(c.codigo, 1) IN (\'6\', \'5\')
            AND RIGHT(c.codigo, 3) <> \'000\'
            AND LEFT(c.codigo, 3) NOT IN (\'619\', \'624\', \'650\', \'668\', \'669\', \'680\')
            AND g.tcodint IS NOT NULL
          ORDER BY g.tcodint ASC',
        's',
        [$cenco6]
    );
    $out = [];
    foreach ($rows as $r) {
        $c = trim((string) ($r['codigo'] ?? ''));
        if ($c !== '' && !in_array($c, $out, true)) {
            $out[] = $c;
        }
    }

    return $out;
}

/**
 * Galpones por granja (regcencosgalpones.tcodint; tcencos = granja 3 dígitos).
 *
 * @return list<string>
 */
function bio_plan_lista_galpones_granja(mysqli $conn, string $granja3): array
{
    if (function_exists('ccos_norm_granja')) {
        $granja3 = ccos_norm_granja($granja3);
    } else {
        $granja3 = trim($granja3);
    }
    if ($granja3 === '') {
        return [];
    }
    bio_plan_require_fetch_rows();
    $rows = bio_fetch_rows(
        $conn,
        'SELECT DISTINCT TRIM(g.tcodint) AS codigo
           FROM regcencosgalpones AS g
          WHERE TRIM(g.tcencos) = ?
          ORDER BY g.tcodint ASC',
        's',
        [$granja3]
    );
    $out = [];
    foreach ($rows as $r) {
        $c = trim((string) ($r['codigo'] ?? ''));
        if ($c !== '' && !in_array($c, $out, true)) {
            $out[] = $c;
        }
    }

    return $out;
}

/**
 * Galpones del CENCO con fec_ing_min (maes_zonas; igual get_cencos_galpones seguimiento).
 *
 * @return list<array{tcodint:string,fec_ing_min:string}>
 */
function bio_plan_galpones_meta_cenco(mysqli $conn, string $cenco6, string $fechaYmd = ''): array
{
    $cenco6 = trim($cenco6);
    if (strlen($cenco6) !== 6) {
        return [];
    }
    bio_plan_require_fetch_rows();
    $fechaYmd = trim($fechaYmd);
    $filtroFecha = '';
    if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $fechaYmd)) {
        $filtroFecha = " AND DATE(fec_ing) <= '" . $fechaYmd . "'";
    }
    $rows = bio_fetch_rows(
        $conn,
        'SELECT TRIM(g.tcodint) AS tcodint, m.fecha AS fec_ing_min
           FROM ccos AS c
           INNER JOIN regcencosgalpones AS g ON LEFT(c.codigo, 3) = TRIM(g.tcencos)
           LEFT JOIN (
                SELECT tcencos, tcodint, DATE_FORMAT(MIN(fec_ing), \'%Y-%m-%d\') AS fecha
                  FROM maes_zonas
                 WHERE tcodigo IN (\'P0001001\',\'P0001002\')
                   AND fec_ing IS NOT NULL
                   AND fec_ing > \'1900-01-01\'
                   ' . $filtroFecha . '
                 GROUP BY tcencos, tcodint
           ) AS m ON c.codigo = m.tcencos AND TRIM(g.tcodint) = TRIM(m.tcodint)
          WHERE c.codigo = ?
            AND c.swac = \'A\'
            AND g.tcodint IS NOT NULL
          ORDER BY g.tcodint ASC',
        's',
        [$cenco6]
    );
    $out = [];
    foreach ($rows as $r) {
        $cod = trim((string) ($r['tcodint'] ?? ''));
        if ($cod === '') {
            continue;
        }
        $out[] = [
            'tcodint' => $cod,
            'fec_ing_min' => trim((string) ($r['fec_ing_min'] ?? '')),
        ];
    }

    return $out;
}

/**
 * Edad promedio en [fechaYmd]. Si no hay galpones seleccionados, promedia todos los del CENCO.
 *
 * @param list<array{tcodint:string,fec_ing_min:string}> $galponesMeta
 * @param string[] $galponesSel
 */
function bio_plan_edad_promedio_galpones_en_fecha(
    array $galponesMeta,
    array $galponesSel,
    string $fechaYmd
): ?int {
    if ($galponesMeta === []) {
        return null;
    }
    $edades = [];
    if ($galponesSel !== []) {
        foreach ($galponesSel as $cod) {
            $gal = trim((string) $cod);
            if ($gal === '') {
                continue;
            }
            foreach ($galponesMeta as $g) {
                if (!bio_plan_galpon_codigo_coincide((string) ($g['tcodint'] ?? ''), $gal)) {
                    continue;
                }
                $e = bio_plan_edad_dias_fec_ing($fechaYmd, (string) ($g['fec_ing_min'] ?? ''));
                if ($e !== null) {
                    $edades[] = $e;
                }
                break;
            }
        }
    } else {
        foreach ($galponesMeta as $g) {
            $e = bio_plan_edad_dias_fec_ing($fechaYmd, (string) ($g['fec_ing_min'] ?? ''));
            if ($e !== null) {
                $edades[] = $e;
            }
        }
    }
    if ($edades === []) {
        return null;
    }

    return (int) round(array_sum($edades) / count($edades));
}

/** Edad promedio granja/campaña desde maes_zonas (fallback cuando HC/cargaproduccion00 no responde). */
function bio_plan_edad_granja_maes_zonas(
    mysqli $conn,
    string $granja3,
    string $campania,
    string $fechaYmd,
    string $galponCsv = ''
): ?int {
    $cenco = bio_plan_codigo_cenco6($granja3, $campania);
    if ($cenco === '') {
        return null;
    }
    $fechaYmd = trim($fechaYmd);
    $meta = bio_plan_galpones_meta_cenco($conn, $cenco, $fechaYmd);
    if ($meta === [] && function_exists('cp_cenco_canon')) {
        $alt = cp_cenco_canon(trim($granja3) . trim($campania));
        if ($alt !== '' && $alt !== $cenco) {
            $meta = bio_plan_galpones_meta_cenco($conn, $alt, $fechaYmd);
        }
    }
    $sel = bio_plan_galpones_desde_texto($galponCsv);

    return bio_plan_edad_promedio_galpones_en_fecha($meta, $sel, trim($fechaYmd));
}
