<?php
/**
 * Anomalía de control de artículos: rgarita + san_agentes_causales.
 * PHP 7. anomalia y agenteCausal son opcionales; si vienen vacíos se usan
 * los textos por defecto del artículo.
 */
require_once __DIR__ . '/php7_compat.php';

function bio_art_norm3($valor)
{
    $d = preg_replace('/\D/', '', trim((string) $valor));
    if (!is_string($d) || $d === '') {
        return '000';
    }
    while (strlen($d) < 3) {
        $d = '0' . $d;
    }

    return substr($d, -3);
}

function bio_art_texto($data)
{
    $articulo = trim((string) (isset($data['articulo']) ? $data['articulo'] : 'artículo'));
    if ($articulo === '') {
        $articulo = 'artículo';
    }
    $esDes = stripos($articulo, 'desinf') !== false;
    if ($esDes) {
        return array(
            'anomalia' => 'Artículo sin desinfección al ingreso: ' . $articulo . '.',
            'agente' => 'Falta de desinfección de material en control de ingreso.',
            'accion' => 'Aplicar desinfección o restringir el ingreso.',
        );
    }

    return array(
        'anomalia' => 'Ingreso con artículo no permitido: ' . $articulo . '.',
        'agente' => 'Artículo no autorizado según política de ingreso (' . $articulo . ').',
        'accion' => 'Retener o rechazar el artículo.',
    );
}

function bio_art_insertar_rgarita(mysqli $conn, array $ctx)
{
    $sql = 'INSERT INTO `rgarita` (`id`,`tuser`,`tdate`,`ttime`,`fecha`,`cencos`,`nomcolaborador`,`turno`,'
        . '`numfiltro`,`anomalia`,`hora`,`descripcion`,`agentecausal`,`instalacion`,`bioseguridad`,'
        . '`uuid`,`imagenes`)'
        . ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)';
    $st = $conn->prepare($sql);
    if (!$st) {
        return 0;
    }
    $id = function_exists('bio_next_id') ? bio_next_id($conn, 'rgarita') : 1;
    $tuser = substr((string) $ctx['tuser'], 0, 6);
    $hoy = date('Y-m-d');
    $ahora = date('H:i:s');
    $fecha = (string) $ctx['fecha'];
    $cencos = (string) $ctx['cencos'];
    $colaborador = substr((string) $ctx['colaborador'], 0, 30);
    $turno = 'Dia';
    $numfiltro = 1;
    $anomalia = substr((string) $ctx['anomalia'], 0, 30);
    $hora = $ahora;
    $descripcion = substr((string) $ctx['descripcion'], 0, 200);
    $agente = substr((string) $ctx['agentecausal'], 0, 200);
    $instalacion = 'Articulos';
    $bioseguridad = 'Bioseguridad fisica';
    $uuid = (string) $ctx['uuid'];
    $imagenes = (string) $ctx['imagenes'];
    $st->bind_param(
        'isssssssissssssss',
        $id,
        $tuser,
        $hoy,
        $ahora,
        $fecha,
        $cencos,
        $colaborador,
        $turno,
        $numfiltro,
        $anomalia,
        $hora,
        $descripcion,
        $agente,
        $instalacion,
        $bioseguridad,
        $uuid,
        $imagenes
    );
    $ok = $st->execute();
    $st->close();

    return $ok ? $id : 0;
}

/**
 * @param array<string,mixed> $data
 * @return array{ok:bool,message?:string,id?:string}
 */
function bio_art_agc_guardar(mysqli $conn, array $data)
{
    if (!function_exists('bio_agc_insertar') || !function_exists('bio_nuevo_uuid')) {
        return array('ok' => false, 'message' => 'Doble escritura no disponible');
    }
    $def = bio_art_texto($data);
    $anomalia = trim((string) (isset($data['anomalia']) ? $data['anomalia'] : ''));
    $agente = trim((string) (isset($data['agenteCausal']) ? $data['agenteCausal'] : (isset($data['agente_causal']) ? $data['agente_causal'] : '')));
    $accion = trim((string) (isset($data['accion']) ? $data['accion'] : ''));
    if ($anomalia === '') {
        $anomalia = $def['anomalia'];
    }
    if ($agente === '') {
        $agente = $def['agente'];
    }
    if ($accion === '') {
        $accion = $def['accion'];
    }
    $granja = bio_art_norm3(isset($data['granja']) ? $data['granja'] : '');
    $campania = bio_art_norm3(isset($data['campania']) ? $data['campania'] : '');
    $fecha = trim((string) (isset($data['fecha']) ? $data['fecha'] : ''));
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $fecha)) {
        $fecha = date('Y-m-d');
    }
    $usuario = substr(trim((string) (isset($data['usuario']) ? $data['usuario'] : 'MOVIL')), 0, 60);
    $uuid = bio_nuevo_uuid();
    $ctx = array(
        'uuid' => $uuid,
        'cencos' => $granja . $campania,
        'fecha' => $fecha,
        'tuser' => $usuario,
        'colaborador' => substr(trim((string) (isset($data['nombre']) ? $data['nombre'] : $usuario)), 0, 30),
        'anomalia' => $anomalia,
        'agentecausal' => $agente,
        'descripcion' => $accion,
        'bioseguridad' => 'Bioseguridad fisica',
        'imagenes' => '',
    );
    $tx = $conn->begin_transaction();
    $rid = bio_art_insertar_rgarita($conn, $ctx);
    $agc = $rid > 0 && bio_agc_insertar($conn, $ctx, '');
    if (!$agc) {
        if ($tx) {
            $conn->rollback();
        }

        return array('ok' => false, 'message' => 'No se pudo guardar la anomalía');
    }
    if ($tx) {
        $conn->commit();
    }

    return array('ok' => true, 'id' => $uuid);
}
