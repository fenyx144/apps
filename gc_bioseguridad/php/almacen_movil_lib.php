<?php
/**
 * Kardex de almacén por granja. No usa imov ni movi_zonas.
 *
 * El portal crea la misma tabla en su migración. Este script la asegura
 * (CREATE TABLE IF NOT EXISTS) para que el PHP móvil funcione con ese modelo:
 *
 * bio_insumo          catálogo (migración 007 del portal)
 * bio_almacen_mov     movimientos SI / E / S
 *   stock = SI + E - S, por granja, insumo y almacén LIMPIO o LAVADERO
 *
 * CONSUMO y ENTREGA: salida de LIMPIO.
 * DEVOLUCION: entrada a LAVADERO.
 * LAVADO: salida de LAVADERO y entrada a LIMPIO.
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

function bio_alm_asegurar(mysqli $conn)
{
    $conn->query(
        'CREATE TABLE IF NOT EXISTS `bio_insumo` (
          `id` int unsigned NOT NULL AUTO_INCREMENT,
          `codigo` varchar(20) NOT NULL,
          `nombre` varchar(120) NOT NULL,
          `categoria` varchar(20) NOT NULL DEFAULT \'INDUMENTARIA\',
          `unidad` varchar(20) NOT NULL DEFAULT \'UND\',
          `estado` varchar(10) NOT NULL DEFAULT \'ACTIVO\',
          `creado_en` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uk_bio_insumo_codigo` (`codigo`)
        ) ENGINE=MyISAM DEFAULT CHARSET=latin1'
    );
    $conn->query(
        "INSERT IGNORE INTO `bio_insumo` (`codigo`, `nombre`, `categoria`, `unidad`) VALUES
        ('IND-001', 'Overol', 'INDUMENTARIA', 'UND'),
        ('IND-002', 'Botas de jebe', 'INDUMENTARIA', 'PAR'),
        ('IND-003', 'Gorro descartable', 'INDUMENTARIA', 'UND'),
        ('EPP-001', 'Mascarilla', 'EPP', 'UND'),
        ('EPP-002', 'Guantes de nitrilo', 'EPP', 'PAR'),
        ('DES-001', 'Desinfectante (amonio cuaternario)', 'DESINFECTANTE', 'L'),
        ('DES-002', 'Alcohol 70%', 'DESINFECTANTE', 'L')"
    );
    $conn->query(
        'CREATE TABLE IF NOT EXISTS `bio_almacen_mov` (
          `id` int unsigned NOT NULL AUTO_INCREMENT,
          `uuid` varchar(40) NOT NULL,
          `grupo` varchar(40) NOT NULL DEFAULT \'\',
          `granja_cod` varchar(20) NOT NULL DEFAULT \'\',
          `insumo_id` int unsigned NOT NULL DEFAULT 0,
          `almacen` varchar(10) NOT NULL DEFAULT \'\',
          `tipo` varchar(2) NOT NULL DEFAULT \'\',
          `cantidad` decimal(10,2) NOT NULL DEFAULT 0.00,
          `operacion` varchar(20) NOT NULL DEFAULT \'\',
          `dni` varchar(15) NOT NULL DEFAULT \'\',
          `nombre` varchar(120) NOT NULL DEFAULT \'\',
          `fecha` date NOT NULL,
          `usuario_registro` varchar(30) NOT NULL DEFAULT \'\',
          `creado_en` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uk_bio_amov_uuid` (`uuid`),
          KEY `idx_bio_amov_grupo` (`grupo`),
          KEY `idx_bio_amov_granja` (`granja_cod`, `insumo_id`, `almacen`)
        ) ENGINE=MyISAM DEFAULT CHARSET=latin1'
    );
}

function bio_alm_insumos(mysqli $conn)
{
    $rows = bio_fetch_rows(
        $conn,
        "SELECT id, codigo, nombre, categoria, unidad FROM bio_insumo WHERE estado = 'ACTIVO' ORDER BY categoria, nombre",
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

function bio_alm_insumo(mysqli $conn, $id, $codigo)
{
    if ((int) $id > 0) {
        $rows = bio_fetch_rows($conn, 'SELECT id, codigo, nombre, categoria, unidad FROM bio_insumo WHERE id = ? LIMIT 1', 'i', array((int) $id));
    } else {
        $cod = substr(trim((string) $codigo), 0, 20);
        if ($cod === '') {
            return null;
        }
        $rows = bio_fetch_rows($conn, 'SELECT id, codigo, nombre, categoria, unidad FROM bio_insumo WHERE codigo = ? LIMIT 1', 's', array($cod));
    }
    if (!$rows) {
        return null;
    }
    $r = $rows[0];

    return array(
        'id' => (int) $r['id'],
        'codigo' => (string) $r['codigo'],
        'nombre' => (string) $r['nombre'],
        'categoria' => (string) $r['categoria'],
        'unidad' => (string) $r['unidad'],
    );
}

function bio_alm_num($v)
{
    return round((float) $v, 2);
}

function bio_alm_kardex(mysqli $conn, $granja)
{
    $insumos = bio_alm_insumos($conn);
    $porId = array();
    foreach ($insumos as $i) {
        $porId[$i['id']] = $i;
    }
    $sumas = array();
    if ($granja !== '') {
        $movs = bio_fetch_rows(
            $conn,
            'SELECT insumo_id, almacen, tipo, SUM(cantidad) AS cant
             FROM bio_almacen_mov WHERE granja_cod = ? GROUP BY insumo_id, almacen, tipo',
            's',
            array($granja)
        );
        foreach ($movs as $m) {
            $iid = (int) $m['insumo_id'];
            $alm = (string) $m['almacen'];
            $tipo = (string) $m['tipo'];
            $k = $iid . '|' . $alm;
            if (!isset($sumas[$k])) {
                $sumas[$k] = array('si' => 0.0, 'e' => 0.0, 's' => 0.0);
            }
            if ($tipo === 'SI') {
                $sumas[$k]['si'] += (float) $m['cant'];
            } elseif ($tipo === 'E') {
                $sumas[$k]['e'] += (float) $m['cant'];
            } elseif ($tipo === 'S') {
                $sumas[$k]['s'] += (float) $m['cant'];
            }
        }
    }
    $ver = array();
    foreach ($insumos as $i) {
        if ($i['categoria'] === 'INDUMENTARIA') {
            $ver[$i['id'] . '|LIMPIO'] = true;
            $ver[$i['id'] . '|LAVADERO'] = true;
        }
    }
    foreach ($sumas as $k => $_) {
        $ver[$k] = true;
    }
    $out = array();
    foreach ($ver as $k => $_) {
        $partes = explode('|', $k);
        $iid = (int) $partes[0];
        $alm = isset($partes[1]) ? $partes[1] : '';
        if (!isset($porId[$iid])) {
            continue;
        }
        $i = $porId[$iid];
        $si = isset($sumas[$k]) ? $sumas[$k]['si'] : 0.0;
        $e = isset($sumas[$k]) ? $sumas[$k]['e'] : 0.0;
        $s = isset($sumas[$k]) ? $sumas[$k]['s'] : 0.0;
        $out[] = array(
            'insumo_id' => $iid,
            'codigo' => $i['codigo'],
            'nombre' => $i['nombre'],
            'categoria' => $i['categoria'],
            'unidad' => $i['unidad'],
            'almacen' => $alm,
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
    if ($granja === '') {
        return array();
    }
    $rows = bio_fetch_rows(
        $conn,
        "SELECT dni, MAX(nombre) AS nombre, insumo_id,
                SUM(CASE WHEN operacion = 'ENTREGA' THEN cantidad ELSE 0 END) AS entregado,
                SUM(CASE WHEN operacion = 'DEVOLUCION' THEN cantidad ELSE 0 END) AS devuelto
         FROM bio_almacen_mov
         WHERE granja_cod = ? AND operacion IN ('ENTREGA','DEVOLUCION') AND dni <> ''
         GROUP BY dni, insumo_id",
        's',
        array($granja)
    );
    $out = array();
    foreach ($rows as $r) {
        $fuera = bio_alm_num((float) $r['entregado'] - (float) $r['devuelto']);
        if ($fuera <= 0) {
            continue;
        }
        $out[] = array(
            'dni' => (string) $r['dni'],
            'nombre' => (string) $r['nombre'],
            'insumo_id' => (int) $r['insumo_id'],
            'cantidad' => $fuera,
        );
    }

    return $out;
}

function bio_alm_grupo_existe(mysqli $conn, $grupo)
{
    $rows = bio_fetch_rows($conn, 'SELECT id FROM bio_almacen_mov WHERE grupo = ? LIMIT 1', 's', array($grupo));

    return count($rows) > 0;
}

function bio_alm_insertar(mysqli $conn, array $f)
{
    $sql = 'INSERT INTO bio_almacen_mov
        (uuid, grupo, granja_cod, insumo_id, almacen, tipo, cantidad, operacion, dni, nombre, fecha, usuario_registro)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        return false;
    }
    $uuid = $f['uuid'];
    $grupo = $f['grupo'];
    $granja = $f['granja_cod'];
    $insumo = (int) $f['insumo_id'];
    $almacen = $f['almacen'];
    $tipo = $f['tipo'];
    $cantidad = (float) $f['cantidad'];
    $operacion = $f['operacion'];
    $dni = $f['dni'];
    $nombre = $f['nombre'];
    $fecha = $f['fecha'];
    $usuario = $f['usuario_registro'];
    $stmt->bind_param(
        'sssissdsssss',
        $uuid,
        $grupo,
        $granja,
        $insumo,
        $almacen,
        $tipo,
        $cantidad,
        $operacion,
        $dni,
        $nombre,
        $fecha,
        $usuario
    );
    $ok = $stmt->execute();
    $stmt->close();

    return $ok;
}

function bio_alm_filas(array $op, $usuario)
{
    $uuid = substr(trim((string) (isset($op['uuid']) ? $op['uuid'] : (isset($op['id']) ? $op['id'] : ''))), 0, 40);
    $operacion = strtoupper(trim((string) (isset($op['operacion']) ? $op['operacion'] : '')));
    $granja = substr(trim((string) (isset($op['granja']) ? $op['granja'] : (isset($op['granja_cod']) ? $op['granja_cod'] : ''))), 0, 20);
    $fecha = trim((string) (isset($op['fecha']) ? $op['fecha'] : ''));
    $cant = isset($op['cantidad']) && is_numeric($op['cantidad']) ? round((float) $op['cantidad'], 2) : 0.0;
    $dni = substr(preg_replace('/\D/', '', (string) (isset($op['dni']) ? $op['dni'] : '')), 0, 15);
    $nombre = substr(trim((string) (isset($op['nombre']) ? $op['nombre'] : '')), 0, 120);
    if ($uuid === '' || $granja === '' || $cant <= 0 || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $fecha)) {
        return array('error' => 'Datos incompletos');
    }
    if ($operacion !== 'CONSUMO' && $operacion !== 'ENTREGA' && $operacion !== 'DEVOLUCION' && $operacion !== 'LAVADO') {
        return array('error' => 'Operación inválida');
    }
    if (($operacion === 'ENTREGA' || $operacion === 'DEVOLUCION') && strlen($dni) < 6) {
        return array('error' => 'DNI');
    }
    $base = array(
        'grupo' => $uuid,
        'granja_cod' => $granja,
        'insumo_id' => 0,
        'cantidad' => $cant,
        'operacion' => $operacion,
        'dni' => $dni,
        'nombre' => $nombre,
        'fecha' => $fecha,
        'usuario_registro' => $usuario,
    );
    if ($operacion === 'CONSUMO' || $operacion === 'ENTREGA') {
        $base['uuid'] = $uuid;
        $base['almacen'] = 'LIMPIO';
        $base['tipo'] = 'S';

        return array($base);
    }
    if ($operacion === 'DEVOLUCION') {
        $base['uuid'] = $uuid;
        $base['almacen'] = 'LAVADERO';
        $base['tipo'] = 'E';

        return array($base);
    }
    $sale = $base;
    $sale['uuid'] = $uuid . ':S';
    $sale['almacen'] = 'LAVADERO';
    $sale['tipo'] = 'S';
    $entra = $base;
    $entra['uuid'] = $uuid . ':E';
    $entra['almacen'] = 'LIMPIO';
    $entra['tipo'] = 'E';

    return array($sale, $entra);
}

function bio_alm_guardar(mysqli $conn, array $op, $usuario)
{
    $filas = bio_alm_filas($op, $usuario);
    if (isset($filas['error'])) {
        return array('ok' => false, 'message' => $filas['error']);
    }
    $grupo = $filas[0]['grupo'];
    if (bio_alm_grupo_existe($conn, $grupo)) {
        return array('ok' => true, 'uuid' => $grupo, 'duplicado' => true);
    }
    $ins = bio_alm_insumo(
        $conn,
        isset($op['insumo_id']) ? $op['insumo_id'] : 0,
        isset($op['insumo_codigo']) ? $op['insumo_codigo'] : (isset($op['codigo']) ? $op['codigo'] : '')
    );
    if ($ins === null) {
        return array('ok' => false, 'message' => 'Insumo');
    }
    foreach ($filas as $f) {
        $f['insumo_id'] = $ins['id'];
        if (!bio_alm_insertar($conn, $f)) {
            return array('ok' => false, 'message' => 'No se guardó');
        }
    }

    return array('ok' => true, 'uuid' => $grupo, 'duplicado' => false);
}
