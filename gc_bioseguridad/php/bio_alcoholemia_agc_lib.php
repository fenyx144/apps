<?php
/**
 * Anomalía de alcoholemia hacia san_agentes_causales.
 * PHP 7.x. El umbral es el de esta librería (g/L): por encima se registra.
 */

/** Umbral en g/L. Una lectura mayor genera anomalía. */
function bio_alc_umbral_gl()
{
    return 0.0;
}

function bio_alc_agente_def()
{
    return 'Alcohol en aliento detectado en control de alcoholemia';
}

function bio_alc_accion_def()
{
    return 'Negar ingreso. Comunicar al supervisor de bioseguridad.';
}

/**
 * Mismo texto que AnomaliaContexto.alcoholemia en la app.
 */
function bio_alc_texto_anomalia($grado, $umbral, $nombre, $dni)
{
    $g = number_format((float) $grado, 3, '.', '');
    $u = number_format((float) $umbral, 3, '.', '');
    $quien = trim((string) $nombre);
    if ($quien === '') {
        $doc = trim((string) $dni);
        $quien = $doc !== '' ? 'DNI ' . $doc : 'Persona';
    }

    return $g . ' g/L supera umbral ' . $u . ' g/L · ' . $quien;
}

function bio_alc_norm3($valor)
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

function bio_alc_fecha($valor)
{
    $d = trim((string) $valor);
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $d)) {
        return '';
    }

    return $d;
}

/**
 * Guarda la anomalía si el grado supera el umbral.
 * anomalia y agenteCausal son opcionales: si vienen vacíos se usan los textos por defecto.
 *
 * @param array<string,mixed> $data
 * @return array{ok:bool,omitido?:bool,message?:string}
 */
function bio_alc_guardar(mysqli $conn, array $data)
{
    $gradoRaw = str_replace(',', '.', trim((string) ($data['grado_g_l'] ?? $data['gradoGl'] ?? '')));
    if ($gradoRaw === '' || !is_numeric($gradoRaw)) {
        return array('ok' => false, 'message' => 'Grado inválido');
    }
    $grado = (float) $gradoRaw;
    $umbralDato = $data['umbral_g_l'] ?? $data['umbralGl'] ?? null;
    if ($umbralDato === null || $umbralDato === '') {
        $umbral = (float) bio_alc_umbral_gl();
    } else {
        $umbral = (float) str_replace(',', '.', (string) $umbralDato);
    }
    if ($grado <= $umbral + 0.000000001) {
        return array('ok' => true, 'omitido' => true);
    }

    $nombre = (string) ($data['nombre'] ?? '');
    $dni = (string) ($data['dni'] ?? '');
    $anomalia = trim((string) ($data['anomalia'] ?? ''));
    $agente = trim((string) ($data['agenteCausal'] ?? $data['agente_causal'] ?? ''));
    $accion = trim((string) ($data['accion'] ?? ''));
    if ($anomalia === '') {
        $anomalia = bio_alc_texto_anomalia($grado, $umbral, $nombre, $dni);
    }
    if ($agente === '') {
        $agente = bio_alc_agente_def();
    }
    if ($accion === '') {
        $accion = bio_alc_accion_def();
    }

    $fecha = bio_alc_fecha($data['fecha'] ?? '');
    if ($fecha === '') {
        $fecha = date('Y-m-d');
    }
    $granja = bio_alc_norm3($data['granja'] ?? '');
    $campania = bio_alc_norm3($data['campania'] ?? '');
    $usuario = substr(trim((string) ($data['usuario'] ?? '')), 0, 60);
    $uuid = function_exists('bio_nuevo_uuid') ? bio_nuevo_uuid() : bio_alc_uuid();

    $ctx = array(
        'uuid' => $uuid,
        'cencos' => $granja . $campania,
        'bioseguridad' => 'quimica',
        'fecha' => $fecha,
        'anomalia' => $anomalia,
        'agentecausal' => $agente,
        'descripcion' => $accion,
        'tuser' => $usuario,
    );
    if (!function_exists('bio_agc_insertar') || !bio_agc_insertar($conn, $ctx, '')) {
        return array('ok' => false, 'message' => 'No se pudo guardar la anomalía');
    }

    return array('ok' => true, 'id' => $uuid);
}

function bio_alc_uuid()
{
    $bytes = random_bytes(16);
    $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
    $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
    $hex = bin2hex($bytes);

    return sprintf(
        '%s-%s-%s-%s-%s',
        substr($hex, 0, 8),
        substr($hex, 8, 4),
        substr($hex, 12, 4),
        substr($hex, 16, 4),
        substr($hex, 20, 12)
    );
}
