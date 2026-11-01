<?php
/**
 * Helpers compartidos para listados y detalle web de Vacuna al Agua.
 *
 * Incluir desde las pantallas PHP que muestran galpones o tablas paramétricas.
 *
 * Estilos: enlazar `vacunaagua_web.css` o imprimir `vacunaagua_html_estilos()`.
 */

/**
 * Bloque `<style>` con las reglas de detalle (mismo contenido que vacunaagua_web.css).
 */
function vacunaagua_html_estilos(): string
{
    $path = __DIR__ . '/vacunaagua_web.css';
    if (!is_readable($path)) {
        return '';
    }
    $css = trim((string) file_get_contents($path));
    if ($css === '') {
        return '';
    }
    return '<style>' . $css . '</style>';
}

/**
 * Fecha legible (dd/mm/yyyy) para cabeceras; acepta YYYY-MM-DD o datetime ISO.
 */
function vacunaagua_formatear_fecha(?string $raw): string
{
    $s = trim((string) $raw);
    if ($s === '') {
        return '—';
    }
    if (preg_match('/^(\d{4})-(\d{2})-(\d{2})/', $s, $m)) {
        return $m[3] . '/' . $m[2] . '/' . $m[1];
    }
    $ts = strtotime($s);
    if ($ts !== false) {
        return date('d/m/Y', $ts);
    }
    return $s;
}

/**
 * Cabecera del detalle: fecha, granja y campaña fuera de la tabla (sin recuadro oscuro).
 *
 * @param list<array<string, mixed>> $rowsFilas
 */
function vacunaagua_html_meta_cabecera(array $rowsFilas): string
{
    if ($rowsFilas === []) {
        return '';
    }
    $row = $rowsFilas[0];
    $fecha = vacunaagua_formatear_fecha(
        (string) ($row['fecha'] ?? $row['fecha_registro'] ?? '')
    );
    $granja = trim((string) ($row['granja'] ?? ''));
    $campania = trim((string) ($row['campania'] ?? ''));
    $granjaNom = trim((string) ($row['granja_nombre'] ?? $row['granjaNombre'] ?? ''));

    $html = '<div class="vacunaagua-meta">';
    $html .= '<p class="vacunaagua-meta__item"><span class="vacunaagua-meta__label">Fecha</span>'
        . '<span class="vacunaagua-meta__value">'
        . htmlspecialchars($fecha, ENT_QUOTES, 'UTF-8')
        . '</span></p>';
    if ($granja !== '' || $granjaNom !== '') {
        $gTxt = $granjaNom !== '' ? $granjaNom . ' (' . $granja . ')' : $granja;
        $html .= '<p class="vacunaagua-meta__item"><span class="vacunaagua-meta__label">Granja</span>'
            . '<span class="vacunaagua-meta__value">'
            . htmlspecialchars($gTxt, ENT_QUOTES, 'UTF-8')
            . '</span></p>';
    }
    if ($campania !== '') {
        $html .= '<p class="vacunaagua-meta__item"><span class="vacunaagua-meta__label">Campaña</span>'
            . '<span class="vacunaagua-meta__value">'
            . htmlspecialchars($campania, ENT_QUOTES, 'UTF-8')
            . '</span></p>';
    }
    $html .= '</div>';
    return $html;
}

/**
 * Título de columna de registro (no usar la fecha cruda como único texto del th).
 *
 * @param array<string, mixed> $row
 */
function vacunaagua_etiqueta_registro(array $row, int $index): string
{
    $custom = trim((string) ($row['etiqueta_registro'] ?? ''));
    if ($custom !== '' && !preg_match('/^\d{4}-\d{2}-\d{2}/', $custom)) {
        return $custom;
    }
    return 'Registro ' . ($index + 1);
}

/**
 * Subtítulo bajo «Registro N» (p. ej. hora de captura), no como celda principal.
 *
 * @param array<string, mixed> $row
 */
function vacunaagua_subtitulo_registro(array $row): string
{
    $hora = trim((string) ($row['fechaHoraRegistro'] ?? $row['created_at'] ?? ''));
    if ($hora === '') {
        return '';
    }
    if (preg_match('/(\d{2}:\d{2})/', $hora, $m)) {
        return 'Captura ' . $m[1];
    }
    return '';
}

/**
 * @param array<string, mixed> $row  fila de cabecera (puede traer `registro` JSON)
 * @return array<string, mixed>
 */
function vacunaagua_registro_de_fila(array $row): array
{
    $raw = $row['registro'] ?? [];
    if (is_string($raw) && $raw !== '') {
        $decoded = json_decode($raw, true);
        if (is_array($decoded)) {
            return $decoded;
        }
    }
    if (is_array($raw)) {
        return $raw;
    }
    return [];
}

/**
 * Lista de galpones de un registro (vacunación o decloración).
 *
 * @return list<string>
 */
function vacunaagua_lista_galpones(string $reporte, array $registro, array $row = []): array
{
    $tipo = strtolower(trim($reporte));
    if ($tipo === 'decloracion') {
        return ['TODOS'];
    }
    if (!empty($registro['galpones_todos']) || !empty($row['galpones_todos'])) {
        return ['TODOS'];
    }
    $lista = $registro['galpones'] ?? $row['galpones'] ?? [];
    if (is_string($lista)) {
        $lista = array_map('trim', explode(',', $lista));
    }
    if (!is_array($lista)) {
        $lista = [];
    }
    $partes = [];
    foreach ($lista as $g) {
        $t = trim((string) $g);
        if ($t !== '') {
            $partes[] = $t;
        }
    }
    return $partes;
}

/**
 * Texto de galpones para la columna del listado web.
 *
 * @param array<string, mixed> $registro
 */
function vacunaagua_texto_galpones(string $reporte, array $registro): string
{
    $partes = vacunaagua_lista_galpones($reporte, $registro);
    if ($partes === []) {
        return '—';
    }
    return implode(', ', $partes);
}

/**
 * @param array<string, mixed> $registro
 * @return list<array<string, mixed>>
 */
function vacunaagua_detalle_filas(array $registro): array
{
    $det = $registro['detalle'] ?? [];
    if (is_string($det) && $det !== '') {
        $decoded = json_decode($det, true);
        $det = is_array($decoded) ? $decoded : [];
    }
    if (!is_array($det)) {
        return [];
    }
    $out = [];
    foreach ($det as $f) {
        if (is_array($f)) {
            $out[] = $f;
        }
    }
    return $out;
}

/**
 * Arma HTML de una sección paramétrica con columnas por registro y galpón.
 *
 * Cada elemento de $bloques representa un registro móvil distinto (misma
 * granja/campaña/fecha). Ejemplo de encabezado:
 *
 *   |           | Registro 1      | Registro 2        |
 *   | Parámetro | Galpón 1 | G2  | Galpón 3 | Galpón 4 |
 *
 * @param list<array{
 *   etiqueta: string,
 *   reporte: string,
 *   registro: array<string, mixed>
 * }> $bloques
 */
function vacunaagua_html_tabla_seccion(
    string $tituloSeccion,
    string $seccion,
    array $bloques,
    string $parametroFijo = ''
): string {
    if ($bloques === []) {
        return '';
    }

    $cols = [];
    foreach ($bloques as $i => $bloque) {
        $reg = $bloque['registro'];
        $gps = vacunaagua_lista_galpones($bloque['reporte'], $reg);
        $filas = vacunaagua_detalle_filas($reg);
        $cols[] = [
            'etiqueta' => $bloque['etiqueta'] !== ''
                ? $bloque['etiqueta']
                : ('Registro ' . ($i + 1)),
            'subtitulo' => (string) ($bloque['subtitulo'] ?? ''),
            'galpones' => $gps,
            'filas' => $filas,
        ];
    }

    $html = '<h3 class="vacunaagua-sec-title">'
        . htmlspecialchars($tituloSeccion, ENT_QUOTES, 'UTF-8')
        . '</h3>';
    $html .= '<table class="vacunaagua-det"><thead>';

    $html .= '<tr class="vacunaagua-det__row-registro">'
        . '<th rowspan="2" class="vacunaagua-det__th-param">Parámetro</th>';
    foreach ($cols as $col) {
        $span = max(1, count($col['galpones']));
        $html .= '<th colspan="' . $span . '">'
            . htmlspecialchars($col['etiqueta'], ENT_QUOTES, 'UTF-8');
        if ($col['subtitulo'] !== '') {
            $html .= '<span class="vacunaagua-det__reg-sub">'
                . htmlspecialchars($col['subtitulo'], ENT_QUOTES, 'UTF-8')
                . '</span>';
        }
        $html .= '</th>';
    }
    $html .= '</tr><tr class="vacunaagua-det__row-galpon">';
    foreach ($cols as $col) {
        if ($col['galpones'] === []) {
            $html .= '<th>—</th>';
            continue;
        }
        foreach ($col['galpones'] as $g) {
            $html .= '<th>Galpón ' . htmlspecialchars($g, ENT_QUOTES, 'UTF-8') . '</th>';
        }
    }
    $html .= '</tr></thead><tbody>';

    $parametros = [];
    foreach ($cols as $col) {
        foreach ($col['filas'] as $f) {
            if (($f['seccion'] ?? '') !== $seccion) {
                continue;
            }
            if ($parametroFijo !== '' && ($f['parametro'] ?? '') !== $parametroFijo) {
                continue;
            }
            $p = (string) ($f['parametro'] ?? '');
            if ($p !== '') {
                $parametros[$p] = true;
            }
        }
    }
    $parametros = array_keys($parametros);
    sort($parametros, SORT_NATURAL);

    foreach ($parametros as $parametro) {
        $html .= '<tr><td class="vacunaagua-det__td-param">'
            . htmlspecialchars($parametro, ENT_QUOTES, 'UTF-8')
            . '</td>';
        foreach ($cols as $col) {
            if ($col['galpones'] === []) {
                $html .= '<td>—</td>';
                continue;
            }
            foreach ($col['galpones'] as $g) {
                $valor = '—';
                foreach ($col['filas'] as $f) {
                    if (($f['seccion'] ?? '') !== $seccion) {
                        continue;
                    }
                    if (($f['parametro'] ?? '') !== $parametro) {
                        continue;
                    }
                    if ((string) ($f['galpon'] ?? '') !== (string) $g) {
                        continue;
                    }
                    $valor = vacunaagua_valor_celda($f);
                    break;
                }
                $html .= '<td>' . htmlspecialchars($valor, ENT_QUOTES, 'UTF-8') . '</td>';
            }
        }
        $html .= '</tr>';
    }

    $html .= '</tbody></table>';
    return $html;
}

/**
 * @param array<string, mixed> $fila
 */
function vacunaagua_valor_celda(array $fila): string
{
    $t = trim((string) ($fila['valor_texto'] ?? ''));
    if ($t !== '') {
        return $t;
    }
    $h = trim((string) ($fila['hora'] ?? ''));
    if ($h !== '') {
        return $h;
    }
    if (isset($fila['flag'])) {
        $flag = $fila['flag'];
        if ($flag === true || $flag === 1 || $flag === '1') {
            return 'SI';
        }
        if ($flag === false || $flag === 0 || $flag === '0') {
            return 'NO';
        }
    }
    if (isset($fila['valor_num']) && $fila['valor_num'] !== null && $fila['valor_num'] !== '') {
        return (string) $fila['valor_num'];
    }
    return '—';
}

/**
 * Detalle web completo para varios registros del mismo día (vacunación).
 *
 * @param list<array<string, mixed>> $rowsFilas  filas BD con `reporte` + `registro`
 */
function vacunaagua_html_detalle_vacunacion(array $rowsFilas): string
{
    $bloques = [];
    $idx = 0;
    foreach ($rowsFilas as $row) {
        $reporte = (string) ($row['reporte'] ?? 'vacunacion');
        if (strtolower($reporte) !== 'vacunacion') {
            continue;
        }
        $reg = vacunaagua_registro_de_fila($row);
        $bloques[] = [
            'etiqueta' => vacunaagua_etiqueta_registro($row, $idx),
            'subtitulo' => vacunaagua_subtitulo_registro($row),
            'reporte' => $reporte,
            'registro' => $reg,
        ];
        $idx++;
    }
    if ($bloques === []) {
        return '';
    }

    $html = '<div class="vacunaagua-detalle">';
    $html .= vacunaagua_html_meta_cabecera($rowsFilas);
    $html .= vacunaagua_html_tabla_seccion(
        'Tiempo de sedeó',
        'sedeo',
        $bloques,
        'Horas'
    );
    $html .= vacunaagua_html_tabla_seccion(
        'Preparación de solución vacunal',
        'solucion',
        $bloques
    );
    $html .= '</div>';
    return $html;
}
