<?php
/**
 * Almacén móvil sobre bio_almacen_mov (contrato portal 8988e28).
 * No crea tablas ni ejecuta la migración 016.
 * frente: LIMPIO, LAVADERO, IMPLEMENTOS, INSUMOS. tipo: SI, E, S.
 * GRS: ENVIO y SI, todas las granjas. Empresa: CONSUMO, ENTREGA,
 * DEVOLUCION, LAVADO y RELEVO, solo sus granjas.
 */
require_once __DIR__ . '/php7_compat.php';

function bio_alm_usuario()
{
    $h = '';
    if (isset($_SERVER['HTTP_X_USUARIO_CODIGO'])) {
        $h = (string) $_SERVER['HTTP_X_USUARIO_CODIGO'];
    }

    return strtoupper(substr(trim($h), 0, 30));
}

function bio_alm_tabla(mysqli $conn, $nombre)
{
    $nombre = $conn->real_escape_string($nombre);
    $rs = $conn->query("SHOW TABLES LIKE '" . $nombre . "'");

    return $rs && $rs->num_rows > 0;
}

function bio_alm_num($v)
{
    return round((float) $v, 2);
}

function bio_alm_cortar($s, $n)
{
    return substr(trim((string) $s), 0, $n);
}

function bio_alm_fecha($valor)
{
    $f = trim((string) $valor);
    if ($f === '') {
        return date('Y-m-d');
    }
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $f)) {
        return '';
    }
    $p = explode('-', $f);
    if (!checkdate((int) $p[1], (int) $p[2], (int) $p[0])) {
        return '';
    }

    return $f;
}

function bio_alm_actor(mysqli $conn, $codigo)
{
    $codigo = strtoupper(trim((string) $codigo));
    $vacio = array('rol' => '', 'empresa_id' => 0);
    if ($codigo === '') {
        return $vacio;
    }
    if (bio_alm_tabla($conn, 'bio_empresa')) {
        $rows = bio_fetch_rows(
            $conn,
            "SELECT id FROM bio_empresa WHERE UPPER(TRIM(usuario_cod)) = ? AND estado = 'ACTIVO' LIMIT 1",
            's',
            array($codigo)
        );
        if ($rows) {
            return array('rol' => 'empresa', 'empresa_id' => (int) $rows[0]['id']);
        }
        if (bio_alm_tabla($conn, 'bio_empresa_acceso')) {
            $rows = bio_fetch_rows(
                $conn,
                "SELECT e.id FROM bio_empresa_acceso a
                   INNER JOIN bio_empresa e ON e.id = a.empresa_id
                  WHERE UPPER(TRIM(a.usuario_cod)) = ? AND a.estado = 'ACTIVO' AND e.estado = 'ACTIVO'
                  LIMIT 1",
                's',
                array($codigo)
            );
            if ($rows) {
                return array('rol' => 'empresa', 'empresa_id' => (int) $rows[0]['id']);
            }
        }
        if (bio_alm_tabla($conn, 'bio_personal')) {
            $rows = bio_fetch_rows(
                $conn,
                "SELECT e.id FROM bio_personal p
                   INNER JOIN bio_empresa e ON e.id = p.empresa_id
                  WHERE UPPER(TRIM(p.usuario_cod)) = ? AND p.estado = 'ACTIVO' AND e.estado = 'ACTIVO'
                  LIMIT 1",
                's',
                array($codigo)
            );
            if ($rows) {
                return array('rol' => 'empresa', 'empresa_id' => (int) $rows[0]['id']);
            }
        }
        if (preg_match('/^EMPT[A-Z0-9]*$/', $codigo) && bio_alm_tabla($conn, 'usuario') && bio_alm_tabla($conn, 'bio_personal')) {
            $rows = bio_fetch_rows(
                $conn,
                "SELECT e.id
                   FROM bio_empresa e
                   INNER JOIN bio_personal p ON p.empresa_id = e.id AND p.estado = 'ACTIVO'
                   INNER JOIN usuario u ON UPPER(TRIM(u.codigo)) = ?
                     AND u.estado = 'A' AND TRIM(u.libtri) <> '' AND TRIM(u.libtri) = TRIM(p.dni)
                  WHERE e.estado = 'ACTIVO'
                  LIMIT 1",
                's',
                array($codigo)
            );
            if ($rows) {
                return array('rol' => 'empresa', 'empresa_id' => (int) $rows[0]['id']);
            }
        }
    }

    return array('rol' => 'grs', 'empresa_id' => 0);
}

function bio_alm_acciones($rol)
{
    if ($rol === 'grs') {
        return array('ENVIO', 'SI');
    }
    if ($rol === 'empresa') {
        return array('CONSUMO', 'ENTREGA', 'DEVOLUCION', 'LAVADO', 'RELEVO');
    }

    return array();
}

function bio_alm_granjas_todas(mysqli $conn)
{
    if (!bio_alm_tabla($conn, 'regcencosgalpones')) {
        return array();
    }
    $rows = bio_fetch_rows(
        $conn,
        "SELECT LEFT(TRIM(tcencos), 3) AS codigo, MAX(TRIM(tnomcen)) AS nombre
           FROM regcencosgalpones
          WHERE TRIM(tcencos) <> ''
          GROUP BY LEFT(TRIM(tcencos), 3)
          ORDER BY codigo",
        '',
        array()
    );
    $out = array();
    foreach ($rows as $r) {
        $cod = trim((string) $r['codigo']);
        if ($cod === '') {
            continue;
        }
        $nom = trim((string) $r['nombre']);
        $out[] = array('codigo' => $cod, 'nombre' => $nom !== '' ? $nom : $cod);
    }

    return $out;
}

function bio_alm_granjas_empresa(mysqli $conn, $empresaId, array $todas)
{
    if ($empresaId <= 0 || !bio_alm_tabla($conn, 'bio_personal')) {
        return array();
    }
    $sql = "SELECT DISTINCT codigo FROM (
                SELECT TRIM(granja_base_cod) AS codigo
                  FROM bio_personal
                 WHERE empresa_id = ? AND estado = 'ACTIVO' AND TRIM(granja_base_cod) <> ''";
    if (bio_alm_tabla($conn, 'bio_asignacion') && bio_alm_tabla($conn, 'bio_puntos')) {
        $sql .= " UNION
                SELECT TRIM(pt.granja_cod) AS codigo
                  FROM bio_asignacion a
                  INNER JOIN bio_personal p ON p.id = a.personal_id
                  INNER JOIN bio_puntos pt ON pt.id = a.punto_id
                 WHERE p.empresa_id = ? AND p.estado = 'ACTIVO' AND TRIM(pt.granja_cod) <> ''";
        $types = 'ii';
        $params = array($empresaId, $empresaId);
    } else {
        $types = 'i';
        $params = array($empresaId);
    }
    $sql .= ') g WHERE codigo <> \'\' ORDER BY codigo';
    $rows = bio_fetch_rows($conn, $sql, $types, $params);
    $por = array();
    foreach ($todas as $g) {
        $por[$g['codigo']] = $g;
    }
    $out = array();
    foreach ($rows as $r) {
        $c = trim((string) $r['codigo']);
        if ($c === '') {
            continue;
        }
        $out[] = isset($por[$c]) ? $por[$c] : array('codigo' => $c, 'nombre' => $c);
    }

    return $out;
}

function bio_alm_granjas_visibles(mysqli $conn, array $actor)
{
    $todas = bio_alm_granjas_todas($conn);
    if ($actor['rol'] === 'grs') {
        return $todas;
    }
    if ($actor['rol'] !== 'empresa') {
        return array();
    }

    return bio_alm_granjas_empresa($conn, (int) $actor['empresa_id'], $todas);
}

function bio_alm_puede_granja($cod, array $visibles, $rol)
{
    if ($cod === '') {
        return false;
    }
    if (!$visibles && $rol === 'grs') {
        return true;
    }
    foreach ($visibles as $g) {
        if ($g['codigo'] === $cod) {
            return true;
        }
    }

    return false;
}

function bio_alm_ropa()
{
    return array(
        array('codigo' => 1, 'nombre' => 'Ropa de transito'),
        array('codigo' => 2, 'nombre' => 'Ropa para el proceso'),
    );
}

function bio_alm_nombre_ropa($item)
{
    return (string) $item === '1' ? 'Ropa de transito' : 'Ropa para el proceso';
}

function bio_alm_clase_insumo(mysqli $conn, $id)
{
    if ($id <= 0 || !bio_alm_tabla($conn, 'bio_insumo')) {
        return '';
    }
    $rows = bio_fetch_rows(
        $conn,
        "SELECT categoria FROM bio_insumo WHERE id = ? AND estado = 'ACTIVO' LIMIT 1",
        'i',
        array((int) $id)
    );
    if (!$rows) {
        return '';
    }
    $cat = (string) $rows[0]['categoria'];
    if ($cat === 'EPP' || $cat === 'INDUMENTARIA') {
        return 'IMPLEMENTO';
    }
    if ($cat === 'DESINFECTANTE' || $cat === 'OTRO') {
        return 'INSUMO';
    }

    return '';
}

function bio_alm_saldos(mysqli $conn, $granja)
{
    if (!bio_alm_tabla($conn, 'bio_almacen_mov')) {
        return array();
    }
    $join = bio_alm_tabla($conn, 'bio_insumo')
        ? "LEFT JOIN bio_insumo i ON (m.frente = 'INSUMOS' OR m.frente = 'IMPLEMENTOS') AND i.id = m.item"
        : '';
    $cols = $join === ''
        ? "'' AS codigo, '' AS nombre, '' AS unidad, '' AS categoria"
        : "IFNULL(i.codigo, '') AS codigo, IFNULL(i.nombre, '') AS nombre, IFNULL(i.unidad, '') AS unidad, IFNULL(i.categoria, '') AS categoria";
    $group = $join === ''
        ? 'm.granja_cod, m.frente, m.item'
        : 'm.granja_cod, m.frente, m.item, i.codigo, i.nombre, i.unidad, i.categoria';
    $sql = "SELECT m.granja_cod, m.frente, m.item,
                   SUM(CASE WHEN m.tipo = 'S' THEN -m.cantidad ELSE m.cantidad END) AS stock,
                   $cols
              FROM bio_almacen_mov m
              $join
             WHERE (? = '' OR m.granja_cod = ?)
             GROUP BY $group";

    return bio_fetch_rows($conn, $sql, 'ss', array($granja, $granja));
}

function bio_alm_saldo(mysqli $conn, $granja, $frente, $item)
{
    $rows = bio_fetch_rows(
        $conn,
        "SELECT IFNULL(SUM(CASE WHEN tipo = 'S' THEN -cantidad ELSE cantidad END), 0) AS stock
           FROM bio_almacen_mov
          WHERE granja_cod = ? AND frente = ? AND item = ?",
        'sss',
        array($granja, $frente, $item)
    );
    if (!$rows) {
        return 0.0;
    }

    return bio_alm_num($rows[0]['stock']);
}

function bio_alm_stock(mysqli $conn, array $actor, $granja)
{
    $visibles = bio_alm_granjas_visibles($conn, $actor);
    if ($granja !== '' && !bio_alm_puede_granja($granja, $visibles, $actor['rol'])) {
        return array('ok' => false, 'http' => 403, 'message' => 'No autorizado');
    }
    if ($actor['rol'] === 'grs' && !$visibles && $granja !== '') {
        $visibles = array(array('codigo' => $granja, 'nombre' => $granja));
    }
    $nombres = array();
    foreach ($visibles as $g) {
        $nombres[$g['codigo']] = $g['nombre'];
    }
    $lista = $granja === '' ? $visibles : array(
        array('codigo' => $granja, 'nombre' => isset($nombres[$granja]) ? $nombres[$granja] : $granja),
    );
    $permitidos = array();
    foreach ($lista as $g) {
        $permitidos[$g['codigo']] = true;
    }
    $sumas = array();
    $implementos = array();
    $insumos = array();
    foreach (bio_alm_saldos($conn, $granja) as $row) {
        $gc = (string) $row['granja_cod'];
        if (!isset($permitidos[$gc])) {
            continue;
        }
        $frente = (string) $row['frente'];
        $item = (string) $row['item'];
        $stock = bio_alm_num($row['stock']);
        $sumas[$gc . '|' . $frente . '|' . $item] = $stock;
        if ($frente === 'IMPLEMENTOS' || $frente === 'INSUMOS') {
            $fila = array(
                'granja_cod' => $gc,
                'granja_nombre' => isset($nombres[$gc]) ? $nombres[$gc] : $gc,
                'insumo_id' => (int) $item,
                'codigo' => (string) $row['codigo'],
                'nombre' => (string) $row['nombre'],
                'unidad' => (string) $row['unidad'],
                'categoria' => (string) $row['categoria'],
                'stock' => $stock,
                'item' => $item,
            );
            if ($frente === 'IMPLEMENTOS') {
                $implementos[] = $fila;
            } else {
                $insumos[] = $fila;
            }
        }
    }
    $uniformes = array();
    $resumen = array();
    foreach ($lista as $g) {
        $gc = $g['codigo'];
        $gn = $g['nombre'];
        $limpio = isset($sumas[$gc . '|LIMPIO|2']) ? $sumas[$gc . '|LIMPIO|2'] : 0.0;
        $lavadero = isset($sumas[$gc . '|LAVADERO|2']) ? $sumas[$gc . '|LAVADERO|2'] : 0.0;
        $resumen[] = array(
            'granja_cod' => $gc,
            'granja_nombre' => $gn,
            'limpio' => $limpio,
            'lavadero' => $lavadero,
        );
        $uniformes[] = bio_alm_fila_uniforme($gc, $gn, 2, 'LIMPIO', $limpio);
        $uniformes[] = bio_alm_fila_uniforme($gc, $gn, 2, 'LAVADERO', $lavadero);
        foreach (array('LIMPIO', 'LAVADERO') as $frente) {
            $clave = $gc . '|' . $frente . '|1';
            if (isset($sumas[$clave]) && abs($sumas[$clave]) > 0.001) {
                $uniformes[] = bio_alm_fila_uniforme($gc, $gn, 1, $frente, $sumas[$clave]);
            }
        }
    }

    if ($granja !== '') {
        bio_alm_completar_catalogo($conn, $granja, isset($nombres[$granja]) ? $nombres[$granja] : $granja, $implementos, $insumos);
    }

    return array(
        'ok' => true,
        'rol' => $actor['rol'],
        'acciones' => bio_alm_acciones($actor['rol']),
        'granja_cod' => $granja,
        'granjas' => $visibles,
        'resumen' => $resumen,
        'uniformes' => $uniformes,
        'implementos' => $implementos,
        'insumos' => $insumos,
        'ropa_tipos' => bio_alm_ropa(),
    );
}

function bio_alm_completar_catalogo(mysqli $conn, $granja, $nombre, array &$implementos, array &$insumos)
{
    if (!bio_alm_tabla($conn, 'bio_insumo')) {
        return;
    }
    $rows = bio_fetch_rows(
        $conn,
        "SELECT id, codigo, nombre, unidad, categoria FROM bio_insumo WHERE estado = 'ACTIVO' ORDER BY nombre",
        '',
        array()
    );
    $yaImp = array();
    $yaIns = array();
    foreach ($implementos as $f) {
        $yaImp[(string) $f['item']] = true;
    }
    foreach ($insumos as $f) {
        $yaIns[(string) $f['item']] = true;
    }
    foreach ($rows as $r) {
        $clase = bio_alm_clase_insumo($conn, (int) $r['id']);
        $item = (string) (int) $r['id'];
        $fila = array(
            'granja_cod' => $granja,
            'granja_nombre' => $nombre,
            'insumo_id' => (int) $r['id'],
            'codigo' => (string) $r['codigo'],
            'nombre' => (string) $r['nombre'],
            'unidad' => (string) $r['unidad'],
            'categoria' => (string) $r['categoria'],
            'stock' => 0,
            'item' => $item,
        );
        if ($clase === 'IMPLEMENTO' && !isset($yaImp[$item])) {
            $implementos[] = $fila;
        }
        if ($clase === 'INSUMO' && !isset($yaIns[$item])) {
            $insumos[] = $fila;
        }
    }
}

function bio_alm_fila_uniforme($granja, $nombre, $ropa, $frente, $stock)
{
    return array(
        'granja_cod' => $granja,
        'granja_nombre' => $nombre,
        'ropa_tipo' => $ropa,
        'ropa_nombre' => bio_alm_nombre_ropa((string) $ropa),
        'frente' => $frente,
        'categoria' => 'UNIFORME',
        'item' => (string) $ropa,
        'nombre' => bio_alm_nombre_ropa((string) $ropa),
        'stock' => bio_alm_num($stock),
    );
}

function bio_alm_kardex(mysqli $conn, array $actor, $granja, $categoria, $desde, $hasta)
{
    $visibles = bio_alm_granjas_visibles($conn, $actor);
    if ($granja !== '' && !bio_alm_puede_granja($granja, $visibles, $actor['rol'])) {
        return array('ok' => false, 'http' => 403, 'message' => 'No autorizado');
    }
    if (!bio_alm_tabla($conn, 'bio_almacen_mov')) {
        return array('ok' => true, 'items' => array());
    }
    $nombres = array();
    $codigos = array();
    foreach ($visibles as $g) {
        $nombres[$g['codigo']] = $g['nombre'];
        $codigos[] = $g['codigo'];
    }
    $where = '1=1';
    $types = '';
    $params = array();
    if ($granja !== '') {
        $where = 'm.granja_cod = ?';
        $types = 's';
        $params = array($granja);
    } elseif ($actor['rol'] !== 'grs') {
        if (!$codigos) {
            return array('ok' => true, 'items' => array());
        }
        $marks = implode(',', array_fill(0, count($codigos), '?'));
        $where = 'm.granja_cod IN (' . $marks . ')';
        $types = str_repeat('s', count($codigos));
        $params = $codigos;
    }
    $joinIns = bio_alm_tabla($conn, 'bio_insumo')
        ? "LEFT JOIN bio_insumo i ON (m.frente = 'INSUMOS' OR m.frente = 'IMPLEMENTOS') AND i.id = m.item"
        : '';
    $joinPer = bio_alm_tabla($conn, 'bio_personal')
        ? 'LEFT JOIN bio_personal p ON p.id = m.personal_id'
        : '';
    $nomIns = $joinIns === '' ? "'' AS insumo_nombre, '' AS unidad" : "IFNULL(i.nombre, '') AS insumo_nombre, IFNULL(i.unidad, '') AS unidad";
    $nomPer = $joinPer === '' ? "'' AS trabajador" : "IFNULL(TRIM(CONCAT(p.nombres, ' ', p.apellidos)), '') AS trabajador";
    $sql = "SELECT m.id, m.frente, m.tipo, m.granja_cod, m.item, m.cantidad, m.operacion,
                   m.par_id, m.personal_id, m.dni, m.usuario_registro, m.origen, m.fecha, m.observacion,
                   $nomIns, $nomPer
              FROM bio_almacen_mov m
              $joinIns
              $joinPer
             WHERE $where
             ORDER BY m.fecha, m.id";
    $rows = bio_fetch_rows($conn, $sql, $types, $params);
    $run = array();
    $out = array();
    $categoria = strtoupper(trim($categoria));
    foreach ($rows as $row) {
        $frente = (string) $row['frente'];
        $item = (string) $row['item'];
        $gc = (string) $row['granja_cod'];
        $cat = 'UNIFORME';
        if ($frente === 'IMPLEMENTOS') {
            $cat = 'IMPLEMENTO';
        } elseif ($frente === 'INSUMOS') {
            $cat = 'INSUMO';
        }
        $key = $gc . '|' . $frente . '|' . $item;
        if (!isset($run[$key])) {
            $run[$key] = 0.0;
        }
        $sign = $row['tipo'] === 'S' ? -1 : 1;
        $run[$key] = bio_alm_num($run[$key] + $sign * (float) $row['cantidad']);
        $fecha = (string) $row['fecha'];
        if ($categoria !== '' && $cat !== $categoria) {
            continue;
        }
        if ($desde !== '' && $fecha < $desde) {
            continue;
        }
        if ($hasta !== '' && $fecha > $hasta) {
            continue;
        }
        $esRopa = $frente === 'LIMPIO' || $frente === 'LAVADERO';
        $out[] = array(
            'id' => (int) $row['id'],
            'frente' => $frente,
            'categoria' => $cat,
            'tipo' => (string) $row['tipo'],
            'granja_cod' => $gc,
            'granja_nombre' => isset($nombres[$gc]) ? $nombres[$gc] : $gc,
            'item' => $item,
            'item_nombre' => $esRopa ? bio_alm_nombre_ropa($item) : (string) $row['insumo_nombre'],
            'nombre' => $esRopa ? bio_alm_nombre_ropa($item) : (string) $row['insumo_nombre'],
            'operacion' => (string) $row['operacion'],
            'cantidad' => bio_alm_num($row['cantidad']),
            'par_id' => $row['par_id'] !== null ? (int) $row['par_id'] : 0,
            'personal_id' => $row['personal_id'] !== null ? (int) $row['personal_id'] : 0,
            'dni' => (string) $row['dni'],
            'trabajador' => (string) $row['trabajador'],
            'fecha' => $fecha,
            'unidad' => $esRopa ? 'und' : (string) $row['unidad'],
            'stock' => $run[$key],
            'si' => $row['tipo'] === 'SI' ? bio_alm_num($row['cantidad']) : 0,
            'e' => $row['tipo'] === 'E' ? bio_alm_num($row['cantidad']) : 0,
            's' => $row['tipo'] === 'S' ? bio_alm_num($row['cantidad']) : 0,
        );
    }

    return array('ok' => true, 'items' => $out);
}

function bio_alm_personal_granja(mysqli $conn, $granja, $empresaId)
{
    if ($granja === '' || !bio_alm_tabla($conn, 'bio_personal')) {
        return array();
    }
    $extra = '';
    if (bio_alm_tabla($conn, 'bio_asignacion') && bio_alm_tabla($conn, 'bio_puntos')) {
        $extra = " OR p.id IN (
            SELECT a.personal_id FROM bio_asignacion a
              INNER JOIN bio_puntos pt ON pt.id = a.punto_id
             WHERE TRIM(pt.granja_cod) = ?
        )";
    }
    $sql = "SELECT p.id, p.dni, TRIM(CONCAT(p.nombres, ' ', p.apellidos)) AS nombre
              FROM bio_personal p
             WHERE p.estado = 'ACTIVO'
               AND (? = 0 OR p.empresa_id = ?)
               AND (TRIM(p.granja_base_cod) = ? $extra)
             ORDER BY p.dni";
    if ($extra === '') {
        $rows = bio_fetch_rows($conn, $sql, 'iis', array($empresaId, $empresaId, $granja));
    } else {
        $rows = bio_fetch_rows($conn, $sql, 'iiss', array($empresaId, $empresaId, $granja, $granja));
    }
    $out = array();
    foreach ($rows as $r) {
        $out[] = array(
            'id' => (int) $r['id'],
            'dni' => (string) $r['dni'],
            'nombre' => trim((string) $r['nombre']),
        );
    }

    return $out;
}

function bio_alm_persona(mysqli $conn, $granja, $empresaId, $id, $dni)
{
    $id = (int) $id;
    $dni = bio_alm_cortar($dni, 15);
    if ($id <= 0 && $dni === '') {
        return null;
    }
    $lista = bio_alm_personal_granja($conn, $granja, $empresaId);
    foreach ($lista as $p) {
        if ($id > 0 && (int) $p['id'] === $id) {
            return $p;
        }
        if ($dni !== '' && $p['dni'] === $dni) {
            return $p;
        }
    }

    return null;
}

function bio_alm_insertar(mysqli $conn, array $f)
{
    $sql = 'INSERT INTO bio_almacen_mov
        (frente, tipo, granja_cod, item, cantidad, operacion, par_id, personal_id, dni, usuario_registro, origen, fecha, observacion)
        VALUES (?, ?, ?, ?, ?, ?, NULLIF(?, 0), NULLIF(?, 0), ?, ?, ?, ?, ?)';
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        return 0;
    }
    $frente = $f['frente'];
    $tipo = $f['tipo'];
    $granja = $f['granja_cod'];
    $item = $f['item'];
    $cantidad = (float) $f['cantidad'];
    $operacion = $f['operacion'];
    $par = (int) $f['par_id'];
    $personal = (int) $f['personal_id'];
    $dni = $f['dni'];
    $usuario = $f['usuario_registro'];
    $origen = $f['origen'];
    $fecha = $f['fecha'];
    $obs = $f['observacion'];
    $stmt->bind_param(
        'ssssdsiisssss',
        $frente,
        $tipo,
        $granja,
        $item,
        $cantidad,
        $operacion,
        $par,
        $personal,
        $dni,
        $usuario,
        $origen,
        $fecha,
        $obs
    );
    $ok = $stmt->execute();
    $id = $ok ? (int) $stmt->insert_id : 0;
    $stmt->close();

    return $id;
}

function bio_alm_fijar_par(mysqli $conn, $id)
{
    $st = $conn->prepare('UPDATE bio_almacen_mov SET par_id = ? WHERE id = ?');
    if (!$st) {
        return;
    }
    $st->bind_param('ii', $id, $id);
    $st->execute();
    $st->close();
}

function bio_alm_error($http, $message, $uuid)
{
    return array('ok' => false, 'http' => $http, 'message' => $message, 'uuid' => $uuid);
}

function bio_alm_guardar(mysqli $conn, array $op, $usuario)
{
    $uuid = bio_alm_cortar(isset($op['uuid']) ? $op['uuid'] : '', 40);
    if (!bio_alm_tabla($conn, 'bio_almacen_mov')) {
        return bio_alm_error(200, 'Migración 015 no aplicada', $uuid);
    }
    $actor = bio_alm_actor($conn, $usuario);
    if ($actor['rol'] !== 'grs' && $actor['rol'] !== 'empresa') {
        return bio_alm_error(403, 'No autorizado', $uuid);
    }
    $operacion = strtoupper(trim((string) (isset($op['operacion']) ? $op['operacion'] : '')));
    $conocidas = array('ENVIO', 'SI', 'CONSUMO', 'ENTREGA', 'DEVOLUCION', 'LAVADO', 'RELEVO');
    if (!in_array($operacion, $conocidas, true)) {
        return bio_alm_error(200, 'Operación inválida', $uuid);
    }
    $permitidas = bio_alm_acciones($actor['rol']);
    if (!in_array($operacion, $permitidas, true)) {
        return bio_alm_error(403, 'No autorizado', $uuid);
    }
    $granja = bio_alm_cortar(isset($op['granja_cod']) ? $op['granja_cod'] : (isset($op['granja']) ? $op['granja'] : ''), 20);
    $visibles = bio_alm_granjas_visibles($conn, $actor);
    if ($granja === '' || !bio_alm_puede_granja($granja, $visibles, $actor['rol'])) {
        return bio_alm_error($granja === '' ? 200 : 403, $granja === '' ? 'Granja requerida' : 'No autorizado', $uuid);
    }
    $fecha = bio_alm_fecha(isset($op['fecha']) ? $op['fecha'] : '');
    if ($fecha === '') {
        return bio_alm_error(200, 'Fecha inválida', $uuid);
    }
    $cant = isset($op['cantidad']) && is_numeric($op['cantidad']) ? bio_alm_num($op['cantidad']) : ($operacion === 'RELEVO' ? 1.0 : 0.0);
    if ($operacion !== 'RELEVO' && $cant <= 0) {
        return bio_alm_error(200, 'Cantidad inválida', $uuid);
    }
    $cat = strtoupper(trim((string) (isset($op['categoria']) ? $op['categoria'] : '')));
    if ($operacion === 'CONSUMO') {
        $cat = 'INSUMO';
    } elseif ($operacion === 'LAVADO' || $operacion === 'RELEVO') {
        $cat = 'UNIFORME';
    }
    if (!in_array($cat, array('UNIFORME', 'IMPLEMENTO', 'INSUMO'), true)) {
        return bio_alm_error(200, 'Categoría inválida', $uuid);
    }
    if (($operacion === 'ENTREGA' || $operacion === 'DEVOLUCION') && $cat === 'INSUMO') {
        return bio_alm_error(200, 'Categoría inválida', $uuid);
    }
    $item = trim((string) (isset($op['item']) ? $op['item'] : ''));
    if ($cat === 'UNIFORME') {
        if ($item === '' || $item === '0') {
            $item = (string) (int) (isset($op['ropa_tipo']) ? $op['ropa_tipo'] : 2);
        }
        if ($item === '0') {
            $item = '2';
        }
        if ($item !== '1' && $item !== '2') {
            return bio_alm_error(200, 'Tipo de ropa inválido', $uuid);
        }
    } else {
        if ($item === '') {
            $item = (string) (int) (isset($op['insumo_id']) ? $op['insumo_id'] : 0);
        }
        $clase = bio_alm_clase_insumo($conn, (int) $item);
        if ($clase === '' || $clase !== $cat) {
            return bio_alm_error(200, $cat === 'IMPLEMENTO' ? 'Implemento requerido' : 'Insumo requerido', $uuid);
        }
        $item = (string) (int) $item;
    }
    $obs = bio_alm_cortar(isset($op['observacion']) ? $op['observacion'] : '', 255);
    $origen = isset($op['origen']) && $op['origen'] === 'web' ? 'web' : 'app';
    $eid = $actor['rol'] === 'grs' ? 0 : (int) $actor['empresa_id'];
    $base = array(
        'granja_cod' => $granja,
        'item' => $item,
        'cantidad' => $cant,
        'operacion' => $operacion,
        'par_id' => 0,
        'personal_id' => 0,
        'dni' => '',
        'usuario_registro' => bio_alm_cortar($usuario, 30),
        'origen' => $origen,
        'fecha' => $fecha,
        'observacion' => $obs,
    );
    if ($operacion === 'RELEVO') {
        return bio_alm_relevo($conn, $op, $base, $granja, $eid, $uuid);
    }
    if ($operacion === 'ENTREGA' || $operacion === 'DEVOLUCION') {
        $persona = bio_alm_persona(
            $conn,
            $granja,
            $eid,
            isset($op['personal_id']) ? $op['personal_id'] : 0,
            isset($op['dni']) ? $op['dni'] : ''
        );
        if ($persona === null) {
            return bio_alm_error(200, 'Personal inválido', $uuid);
        }
        $base['personal_id'] = $persona['id'];
        $base['dni'] = bio_alm_cortar($persona['dni'], 15);
    }
    if ($operacion === 'ENVIO' || $operacion === 'SI') {
        $frente = 'INSUMOS';
        if ($cat === 'UNIFORME') {
            $frente = 'LIMPIO';
        } elseif ($cat === 'IMPLEMENTO') {
            $frente = 'IMPLEMENTOS';
        }
        $base['frente'] = $frente;
        $base['tipo'] = $operacion === 'SI' ? 'SI' : 'E';
        $id = bio_alm_insertar($conn, $base);
        if ($id < 1) {
            return bio_alm_error(200, 'No se guardó', $uuid);
        }

        return array('ok' => true, 'uuid' => $uuid, 'id' => $id);
    }
    if ($operacion === 'CONSUMO') {
        if (bio_alm_saldo($conn, $granja, 'INSUMOS', $item) + 0.001 < $cant) {
            return bio_alm_error(200, 'Stock insuficiente', $uuid);
        }
        $base['frente'] = 'INSUMOS';
        $base['tipo'] = 'S';
        $id = bio_alm_insertar($conn, $base);
        if ($id < 1) {
            return bio_alm_error(200, 'No se guardó', $uuid);
        }

        return array('ok' => true, 'uuid' => $uuid, 'id' => $id);
    }
    if ($operacion === 'ENTREGA') {
        $frente = $cat === 'UNIFORME' ? 'LIMPIO' : 'IMPLEMENTOS';
        if (bio_alm_saldo($conn, $granja, $frente, $item) + 0.001 < $cant) {
            return bio_alm_error(200, 'Stock insuficiente', $uuid);
        }
        $base['frente'] = $frente;
        $base['tipo'] = 'S';
        $id = bio_alm_insertar($conn, $base);
        if ($id < 1) {
            return bio_alm_error(200, 'No se guardó', $uuid);
        }

        return array('ok' => true, 'uuid' => $uuid, 'id' => $id);
    }
    if ($operacion === 'DEVOLUCION') {
        $base['frente'] = $cat === 'UNIFORME' ? 'LAVADERO' : 'IMPLEMENTOS';
        $base['tipo'] = 'E';
        $id = bio_alm_insertar($conn, $base);
        if ($id < 1) {
            return bio_alm_error(200, 'No se guardó', $uuid);
        }

        return array('ok' => true, 'uuid' => $uuid, 'id' => $id);
    }
    if (bio_alm_saldo($conn, $granja, 'LAVADERO', $item) + 0.001 < $cant) {
        return bio_alm_error(200, 'Stock insuficiente', $uuid);
    }
    $sale = $base;
    $sale['frente'] = 'LAVADERO';
    $sale['tipo'] = 'S';
    $idS = bio_alm_insertar($conn, $sale);
    if ($idS < 1) {
        return bio_alm_error(200, 'No se guardó', $uuid);
    }
    bio_alm_fijar_par($conn, $idS);
    $entra = $base;
    $entra['frente'] = 'LIMPIO';
    $entra['tipo'] = 'E';
    $entra['par_id'] = $idS;
    $idE = bio_alm_insertar($conn, $entra);
    if ($idE < 1) {
        return bio_alm_error(200, 'No se guardó', $uuid);
    }

    return array('ok' => true, 'uuid' => $uuid, 'id' => $idS, 'par_id' => $idS);
}

function bio_alm_relevo(mysqli $conn, array $op, array $base, $granja, $empresaId, $uuid)
{
    $sale = bio_alm_persona(
        $conn,
        $granja,
        $empresaId,
        isset($op['personal_id_sale']) ? $op['personal_id_sale'] : 0,
        isset($op['dni_sale']) ? $op['dni_sale'] : ''
    );
    $entra = bio_alm_persona(
        $conn,
        $granja,
        $empresaId,
        isset($op['personal_id_entra']) ? $op['personal_id_entra'] : 0,
        isset($op['dni_entra']) ? $op['dni_entra'] : ''
    );
    if ($sale === null || $entra === null || (int) $sale['id'] === (int) $entra['id']) {
        return bio_alm_error(200, 'Personal inválido', $uuid);
    }
    if (bio_alm_saldo($conn, $granja, 'LIMPIO', '2') + 0.001 < 1) {
        return bio_alm_error(200, 'Stock insuficiente', $uuid);
    }
    $filas = array();
    $filas[] = array_merge($base, array(
        'frente' => 'LAVADERO',
        'tipo' => 'E',
        'item' => '2',
        'cantidad' => 1,
        'personal_id' => $sale['id'],
        'dni' => bio_alm_cortar($sale['dni'], 15),
    ));
    $filas[] = array_merge($base, array(
        'frente' => 'LIMPIO',
        'tipo' => 'S',
        'item' => '2',
        'cantidad' => 1,
        'personal_id' => $entra['id'],
        'dni' => bio_alm_cortar($entra['dni'], 15),
    ));
    foreach (bio_alm_saldos($conn, $granja) as $row) {
        if ((string) $row['frente'] !== 'IMPLEMENTOS' || (string) $row['granja_cod'] !== $granja) {
            continue;
        }
        $stock = bio_alm_num($row['stock']);
        if ($stock + 0.001 < 1) {
            continue;
        }
        $imp = (string) (int) $row['item'];
        $filas[] = array_merge($base, array(
            'frente' => 'IMPLEMENTOS',
            'tipo' => 'S',
            'item' => $imp,
            'cantidad' => 1,
            'personal_id' => $sale['id'],
            'dni' => bio_alm_cortar($sale['dni'], 15),
        ));
        $filas[] = array_merge($base, array(
            'frente' => 'IMPLEMENTOS',
            'tipo' => 'E',
            'item' => $imp,
            'cantidad' => 1,
            'personal_id' => $entra['id'],
            'dni' => bio_alm_cortar($entra['dni'], 15),
        ));
    }
    $primero = 0;
    foreach ($filas as $fila) {
        if ($primero > 0) {
            $fila['par_id'] = $primero;
        }
        $id = bio_alm_insertar($conn, $fila);
        if ($id < 1) {
            return bio_alm_error(200, 'No se guardó', $uuid);
        }
        if ($primero === 0) {
            $primero = $id;
            bio_alm_fijar_par($conn, $id);
        }
    }

    return array('ok' => true, 'uuid' => $uuid, 'id' => $primero, 'par_id' => $primero);
}
