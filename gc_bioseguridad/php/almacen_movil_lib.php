<?php
/**
 * Kardex móvil sobre bio_almacen_mov (portal, migración 015, commit df1bf5c).
 * No crea tablas. frente: LIMPIO, LAVADERO, INSUMOS. tipo: SI, E, S.
 * item: ropa 1 o 2 en LIMPIO/LAVADERO; id de bio_insumo si frente es INSUMOS.
 * LAVADO: S en LAVADERO y E en LIMPIO con el mismo par_id.
 * Stock = SI + E - S. ENTREGA no pasa de LIMPIO; LAVADO no pasa de LAVADERO;
 * CONSUMO solo resta INSUMOS.
 */
require_once __DIR__ . '/php7_compat.php';

function bio_alm_usuario()
{
    $h = '';
    if (isset($_SERVER['HTTP_X_USUARIO_CODIGO'])) {
        $h = (string) $_SERVER['HTTP_X_USUARIO_CODIGO'];
    }

    return substr(trim($h), 0, 30);
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

function bio_alm_insumos(mysqli $conn)
{
    if (!bio_alm_tabla($conn, 'bio_insumo')) {
        return array();
    }
    $rows = bio_fetch_rows(
        $conn,
        "SELECT id, codigo, nombre, categoria, unidad FROM bio_insumo WHERE estado = 'ACTIVO' ORDER BY nombre",
        '',
        array()
    );
    $out = array();
    foreach ($rows as $r) {
        $out[] = array(
            'id' => (int) $r['id'],
            'codigo' => (string) $r['codigo'],
            'nombre' => (string) $r['nombre'],
            'categoria' => (string) $r['categoria'],
            'unidad' => (string) $r['unidad'],
        );
    }

    return $out;
}

function bio_alm_ropa(mysqli $conn)
{
    $out = array();
    if (bio_alm_tabla($conn, 'bio_ropa_tipo')) {
        $rows = bio_fetch_rows($conn, 'SELECT codigo, nombre FROM bio_ropa_tipo ORDER BY codigo', '', array());
        foreach ($rows as $r) {
            $out[] = array('codigo' => (int) $r['codigo'], 'nombre' => (string) $r['nombre']);
        }
    }
    if (!$out) {
        $out[] = array('codigo' => 1, 'nombre' => 'Ropa de transito');
        $out[] = array('codigo' => 2, 'nombre' => 'Ropa para el proceso');
    }

    return $out;
}

function bio_alm_nombre_ropa($item, array $ropa)
{
    foreach ($ropa as $r) {
        if ((string) $r['codigo'] === (string) $item) {
            return $r['nombre'];
        }
    }

    return $item === '1' ? 'Ropa de transito' : 'Ropa para el proceso';
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

function bio_alm_kardex(mysqli $conn, $granja)
{
    $ropa = bio_alm_ropa($conn);
    $insumos = bio_alm_insumos($conn);
    $porInsumo = array();
    foreach ($insumos as $i) {
        $porInsumo[(string) $i['id']] = $i;
    }
    $sumas = array();
    if ($granja !== '' && bio_alm_tabla($conn, 'bio_almacen_mov')) {
        $movs = bio_fetch_rows(
            $conn,
            'SELECT frente, item, tipo, SUM(cantidad) AS cant
               FROM bio_almacen_mov
              WHERE granja_cod = ?
              GROUP BY frente, item, tipo',
            's',
            array($granja)
        );
        foreach ($movs as $m) {
            $k = $m['frente'] . '|' . $m['item'];
            if (!isset($sumas[$k])) {
                $sumas[$k] = array(
                    'frente' => (string) $m['frente'],
                    'item' => (string) $m['item'],
                    'si' => 0.0,
                    'e' => 0.0,
                    's' => 0.0,
                );
            }
            if ($m['tipo'] === 'SI') {
                $sumas[$k]['si'] += (float) $m['cant'];
            } elseif ($m['tipo'] === 'E') {
                $sumas[$k]['e'] += (float) $m['cant'];
            } elseif ($m['tipo'] === 'S') {
                $sumas[$k]['s'] += (float) $m['cant'];
            }
        }
    }
    $ver = array('LIMPIO|2' => true, 'LAVADERO|2' => true);
    foreach ($sumas as $k => $_) {
        $ver[$k] = true;
    }
    $out = array();
    foreach ($ver as $k => $_) {
        $p = explode('|', $k);
        $frente = $p[0];
        $item = isset($p[1]) ? $p[1] : '';
        $si = isset($sumas[$k]) ? $sumas[$k]['si'] : 0.0;
        $e = isset($sumas[$k]) ? $sumas[$k]['e'] : 0.0;
        $s = isset($sumas[$k]) ? $sumas[$k]['s'] : 0.0;
        if ($frente !== 'LIMPIO' && $frente !== 'LAVADERO' && $frente !== 'INSUMOS') {
            continue;
        }
        if ($frente !== 'INSUMOS' && $item === '1' && abs($si + $e - $s) < 0.001 && $si == 0 && $e == 0 && $s == 0) {
            continue;
        }
        $nombre = bio_alm_nombre_ropa($item, $ropa);
        $unidad = 'und';
        if ($frente === 'INSUMOS' && isset($porInsumo[$item])) {
            $nombre = $porInsumo[$item]['nombre'];
            $unidad = $porInsumo[$item]['unidad'];
        }
        $out[] = array(
            'frente' => $frente,
            'item' => $item,
            'nombre' => $nombre,
            'unidad' => $unidad,
            'si' => bio_alm_num($si),
            'e' => bio_alm_num($e),
            's' => bio_alm_num($s),
            'stock' => bio_alm_num($si + $e - $s),
        );
    }

    return $out;
}

function bio_alm_prestamos(mysqli $conn, $granja)
{
    if ($granja === '' || !bio_alm_tabla($conn, 'bio_almacen_mov')) {
        return array();
    }
    $rows = bio_fetch_rows(
        $conn,
        "SELECT dni, item,
                SUM(CASE WHEN operacion = 'ENTREGA' THEN cantidad ELSE 0 END) AS entregado,
                SUM(CASE WHEN operacion = 'RECEPCION' THEN cantidad ELSE 0 END) AS recibido
           FROM bio_almacen_mov
          WHERE granja_cod = ? AND operacion IN ('ENTREGA','RECEPCION') AND dni <> ''
          GROUP BY dni, item",
        's',
        array($granja)
    );
    $out = array();
    foreach ($rows as $r) {
        $fuera = bio_alm_num((float) $r['entregado'] - (float) $r['recibido']);
        if ($fuera <= 0) {
            continue;
        }
        $out[] = array(
            'dni' => (string) $r['dni'],
            'item' => (string) $r['item'],
            'cantidad' => $fuera,
        );
    }

    return $out;
}

function bio_alm_personal(mysqli $conn, $id, $dni)
{
    if ($id <= 0 && $dni === '') {
        return null;
    }
    $st = $conn->prepare(
        'SELECT id, dni FROM bio_personal WHERE (? > 0 AND id = ?) OR (? <> \'\' AND dni = ?) LIMIT 1'
    );
    if (!$st) {
        return null;
    }
    $st->bind_param('iiss', $id, $id, $dni, $dni);
    if (!$st->execute()) {
        $st->close();

        return null;
    }
    $rs = $st->get_result();
    $row = $rs ? $rs->fetch_assoc() : null;
    $st->close();
    if (!$row) {
        return null;
    }

    return array('id' => (int) $row['id'], 'dni' => (string) $row['dni']);
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

function bio_alm_par(mysqli $conn, $a, $b)
{
    $st = $conn->prepare('UPDATE bio_almacen_mov SET par_id = ? WHERE id = ? OR id = ?');
    if (!$st) {
        return;
    }
    $st->bind_param('iii', $a, $a, $b);
    $st->execute();
    $st->close();
}

function bio_alm_insumo_existe(mysqli $conn, $id)
{
    $rows = bio_fetch_rows($conn, 'SELECT id FROM bio_insumo WHERE id = ? LIMIT 1', 'i', array((int) $id));

    return count($rows) > 0;
}

function bio_alm_guardar(mysqli $conn, array $op, $usuario)
{
    if (!bio_alm_tabla($conn, 'bio_almacen_mov')) {
        return array('ok' => false, 'message' => 'Migración 015 no aplicada');
    }
    $operacion = strtoupper(trim((string) (isset($op['operacion']) ? $op['operacion'] : '')));
    $granja = substr(trim((string) (isset($op['granja_cod']) ? $op['granja_cod'] : (isset($op['granja']) ? $op['granja'] : ''))), 0, 20);
    $fecha = trim((string) (isset($op['fecha']) ? $op['fecha'] : ''));
    $cant = isset($op['cantidad']) && is_numeric($op['cantidad']) ? round((float) $op['cantidad'], 2) : 0.0;
    $obs = substr(trim((string) (isset($op['observacion']) ? $op['observacion'] : '')), 0, 255);
    if ($granja === '' || $cant <= 0 || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $fecha)) {
        return array('ok' => false, 'message' => 'Datos incompletos');
    }
    $esInsumo = $operacion === 'SI_INSUMO' || $operacion === 'CARGA_INSUMO' || $operacion === 'CONSUMO';
    $item = trim((string) (isset($op['item']) ? $op['item'] : ''));
    if ($item === '') {
        $item = $esInsumo
            ? (string) (int) (isset($op['insumo_id']) ? $op['insumo_id'] : 0)
            : (string) (int) (isset($op['ropa_tipo']) ? $op['ropa_tipo'] : 2);
    }
    if ($item === '0' || $item === '') {
        $item = $esInsumo ? '' : '2';
    }
    $dni = substr(preg_replace('/\D/', '', (string) (isset($op['dni']) ? $op['dni'] : '')), 0, 15);
    $personalId = (int) (isset($op['personal_id']) ? $op['personal_id'] : 0);
    $hallado = bio_alm_personal($conn, $personalId, $dni);
    if ($hallado !== null) {
        $personalId = $hallado['id'];
        if ($hallado['dni'] !== '') {
            $dni = substr($hallado['dni'], 0, 15);
        }
    }
    $uuid = substr(trim((string) (isset($op['uuid']) ? $op['uuid'] : '')), 0, 40);
    $base = array(
        'granja_cod' => $granja,
        'item' => $item,
        'cantidad' => $cant,
        'operacion' => $operacion,
        'par_id' => 0,
        'personal_id' => $personalId,
        'dni' => $dni,
        'usuario_registro' => substr($usuario, 0, 30),
        'origen' => 'app',
        'fecha' => $fecha,
        'observacion' => $obs,
    );

    $uniforme = $operacion === 'SI_UNIFORME' || $operacion === 'CARGA_UNIFORME'
        || $operacion === 'ENTREGA' || $operacion === 'RECEPCION' || $operacion === 'LAVADO';
    if ($uniforme) {
        if ($item !== '1' && $item !== '2') {
            return array('ok' => false, 'uuid' => $uuid, 'message' => 'Tipo de ropa inválido');
        }
        if (($operacion === 'ENTREGA' || $operacion === 'RECEPCION') && strlen($dni) < 6) {
            return array('ok' => false, 'uuid' => $uuid, 'message' => 'DNI');
        }
        if ($operacion === 'ENTREGA' && bio_alm_saldo($conn, $granja, 'LIMPIO', $item) + 0.001 < $cant) {
            return array('ok' => false, 'uuid' => $uuid, 'message' => 'Stock insuficiente');
        }
        if ($operacion === 'LAVADO' && bio_alm_saldo($conn, $granja, 'LAVADERO', $item) + 0.001 < $cant) {
            return array('ok' => false, 'uuid' => $uuid, 'message' => 'Stock insuficiente');
        }
        if ($operacion === 'LAVADO') {
            $sale = $base;
            $sale['frente'] = 'LAVADERO';
            $sale['tipo'] = 'S';
            $idS = bio_alm_insertar($conn, $sale);
            $entra = $base;
            $entra['frente'] = 'LIMPIO';
            $entra['tipo'] = 'E';
            $idE = bio_alm_insertar($conn, $entra);
            if ($idS < 1 || $idE < 1) {
                return array('ok' => false, 'uuid' => $uuid, 'message' => 'No se guardó');
            }
            bio_alm_par($conn, $idS, $idE);

            return array('ok' => true, 'uuid' => $uuid, 'id' => $idS, 'par_id' => $idS);
        }
        $frente = 'LIMPIO';
        $tipo = 'E';
        if ($operacion === 'SI_UNIFORME') {
            $tipo = 'SI';
            $frenteIn = strtoupper(trim((string) (isset($op['frente']) ? $op['frente'] : 'LIMPIO')));
            if ($frenteIn === 'LAVADERO' || $frenteIn === 'LIMPIO') {
                $frente = $frenteIn;
            }
        } elseif ($operacion === 'CARGA_UNIFORME') {
            $frenteIn = strtoupper(trim((string) (isset($op['frente']) ? $op['frente'] : 'LIMPIO')));
            $frente = $frenteIn === 'LAVADERO' ? 'LAVADERO' : 'LIMPIO';
        } elseif ($operacion === 'ENTREGA') {
            $frente = 'LIMPIO';
            $tipo = 'S';
        } else {
            $frente = 'LAVADERO';
            $tipo = 'E';
        }
        $base['frente'] = $frente;
        $base['tipo'] = $tipo;
        $id = bio_alm_insertar($conn, $base);
        if ($id < 1) {
            return array('ok' => false, 'uuid' => $uuid, 'message' => 'No se guardó');
        }

        return array('ok' => true, 'uuid' => $uuid, 'id' => $id);
    }

    if ($esInsumo) {
        $insumoId = (int) $item;
        if ($insumoId <= 0 || !bio_alm_insumo_existe($conn, $insumoId)) {
            return array('ok' => false, 'uuid' => $uuid, 'message' => 'Insumo');
        }
        $item = (string) $insumoId;
        $base['item'] = $item;
        $base['frente'] = 'INSUMOS';
        if ($operacion === 'SI_INSUMO') {
            $base['tipo'] = 'SI';
        } elseif ($operacion === 'CONSUMO') {
            $base['tipo'] = 'S';
            if (bio_alm_saldo($conn, $granja, 'INSUMOS', $item) + 0.001 < $cant) {
                return array('ok' => false, 'uuid' => $uuid, 'message' => 'Stock insuficiente');
            }
        } else {
            $base['tipo'] = 'E';
        }
        $id = bio_alm_insertar($conn, $base);
        if ($id < 1) {
            return array('ok' => false, 'uuid' => $uuid, 'message' => 'No se guardó');
        }

        return array('ok' => true, 'uuid' => $uuid, 'id' => $id);
    }

    return array('ok' => false, 'uuid' => $uuid, 'message' => 'Operación inválida');
}
