<?php
declare(strict_types=1);

/**
 * Lógica compartida de los endpoints móviles de Bioseguridad.
 *
 * Reportes soportados:
 *   garita  -> rgarita          (fecha, cencos, turno, numfiltro, instalacion, bioseguridad)
 *   cerco   -> rcercoelectrico  (fecha, cencos, turno, componente)
 *   fomites -> rfomites         (fecha, cencos, turno, referencia, proceso, depredador)
 *   ingreso -> san_fact_ingresogranja_cab / _det / _veh
 *   salida  -> san_fact_salidagranja_cab / _det
 *   articulos -> san_fact_articulos_cab / _det
 *
 * Las tablas legacy (garita, cerco, fomites) son de producción: conservan su
 * `id` numérico y su nomenclatura, y solo reciben una columna aditiva `uuid`
 * para deduplicar la subida. Control de ingreso usa el esquema nuevo: llave
 * `id` varchar(36) con uuid, granja/campaña separados, detalle por `idCab` y
 * auditoría mínima en cabecera (usuarioRegistrador / fechaHoraRegistro).
 *
 * «instalacion» es el punto inspeccionado de la sección Instalaciones (garita,
 * tranquera o pozo séptico). Solo la garita tiene filtros numerados, así que
 * fuera de ella `numfiltro` va con un valor de relleno.
 *
 * «bioseguridad» es el tipo de bioseguridad que se inspecciona (física, química
 * o biológica). Forma parte de la llave: la misma instalación puede revisarse
 * para física y para química el mismo día/turno.
 */

const BIO_REPORTES_VALIDOS = ['garita', 'cerco', 'fomites', 'ingreso', 'salida', 'articulos'];

/**
 * Métricas del tablero de cerco eléctrico agrupadas por bloque, con su valor
 * estándar (STD). Es la única fuente de la lista: de acá salen el orden, el
 * bloque y el STD que descarga la app.
 *
 * Los tres bloques son:
 *   - Verificación del tablero: estado operativo (+ tres alertas sin STD).
 *   - Verificación del cerco: estado físico del circuito y sus componentes.
 *   - Verificación del perímetro: puertas y accesos.
 *
 * Las métricas sin estándar van con ''.
 *
 * Se mantiene sincronizado con el reporte web (bio_cerco_bloques() en
 * bioseguridad_lib.php). El orden importa: es el orden en que la app lista los
 * componentes.
 *
 * @return array<string, array<string, string>>
 */
if (!function_exists('bio_cerco_bloques')) {
function bio_cerco_bloques(): array
{
    return [
        'Verificación del tablero' => [
            'Verificación del voltaje' => '>11',
            'Cerco Operativo' => 'Luz encendida',
            'Voltaje Operativo' => 'Luz encendida',
            'Sirena Operativo' => 'Luz encendida',
            'Nivel de Batería' => '',
            'Cerco Bloqueado/sin energía' => '',
            'Cerco Apagado/No se active' => '',
            'La sirena está sonando alerta' => '',
        ],
        'Verificación del cerco' => [
            'Verificación de voltaje' => '',
            // «Cable Conectado» va segundo: es el chequeo básico del tramo y se
            // lee antes que el resto de los componentes.
            'Cable Conectado' => 'Conectado',
            'Argolla Pegada' => 'No pegada',
            'Argolla caída' => 'Completo',
            'Puente pegado' => 'No Pegado',
            'Puente caído (línea abierta)' => 'Completo',
            'Línea enterrada (humedad)' => '',
            'Línea con bolsa (basura)' => 'Sin basura',
            'Templador/aislador suelto' => 'Conectado',
            'Aislador suelto intermedio' => 'Conectado',
        ],
        'Verificación del perímetro' => [
            'Puerta Vehicular abierta' => 'Cerrado',
            'Puerta Vehicular desactivada' => 'Cerrada',
            'Puerta del personal abierta' => 'Cerrado',
            'Puerta pozo séptico abierta' => 'Cerrado',
            'Pozo séptico desactivado' => 'Cerrado',
        ],
    ];
}
}

/**
 * Métricas del tablero de cerco eléctrico (métrica => STD), aplanadas y en el
 * mismo orden que bio_cerco_bloques(). Se usa para validar y ordenar lo que
 * sube la app.
 *
 * @return array<string, string>
 */
function bio_cerco_metricas(): array
{
    $out = [];
    foreach (bio_cerco_bloques() as $filas) {
        foreach ($filas as $metrica => $std) {
            $out[$metrica] = $std;
        }
    }

    return $out;
}

/**
 * Métricas cuyo dato es un valor medido: además de la falla, la app pide una
 * observación siempre (voltaje y nivel de batería). El resto de filas se
 * responden solo con el switch.
 *
 * @return list<string>
 */
function bio_cerco_metricas_obs(): array
{
    return ['Verificación del voltaje', 'Nivel de Batería'];
}

/**
 * Las dos respuestas con que el formato físico contesta una fila del cerco.
 *
 * Casi todas las filas se contestan CT (controlado: está como debe) o FALLA.
 * Las tres últimas del tablero no: ahí la pregunta es si la alerta está
 * presente, y se contestan No o SI («¿la sirena está sonando? SI»). Por eso el
 * par de respuestas es un dato de la métrica y no del bloque: en el tablero se
 * mezclan las dos formas.
 *
 * @return array{ok:string,falla:string}
 */
function bio_cerco_respuestas(string $metrica): array
{
    static $alertas = [
        'Cerco Bloqueado/sin energía',
        'Cerco Apagado/No se active',
        'La sirena está sonando alerta',
    ];

    // Filas que son una pregunta de sí/no («¿la argolla está pegada?»): lo
    // correcto es «No» (no está la anomalía) y «SI» la falla. El resto del
    // formato se contesta CT/FALLA (controlado / falla). Se resuelve acá, en el
    // servidor, para poder retocar el par de respuestas sin publicar la app.
    static $siNo = [
        // Verificación del cerco
        'Argolla Pegada',
        'Argolla caída',
        'Puente pegado',
        'Puente caído (línea abierta)',
        'Línea enterrada (humedad)',
        'Línea con bolsa (basura)',
        'Templador/aislador suelto',
        'Aislador suelto intermedio',
        // Verificación del perímetro
        'Puerta Vehicular abierta',
        'Puerta Vehicular desactivada',
        'Puerta del personal abierta',
        'Puerta pozo séptico abierta',
        'Pozo séptico desactivado',
    ];

    return in_array($metrica, $alertas, true) || in_array($metrica, $siNo, true)
        ? ['ok' => 'No', 'falla' => 'SI']
        : ['ok' => 'CT', 'falla' => 'FALLA'];
}

/**
 * Catálogo de métricas del cerco tal como lo consume la app: una entrada por
 * métrica con su bloque, si pide observación y con qué se contesta.
 *
 * Así la app no necesita conocer de antemano ni los bloques, ni qué filas
 * llevan observación, ni qué filas se contestan CT/FALLA y cuáles No/SI.
 *
 * @return list<array{metrica:string,std:string,bloque:string,obs:bool,ok:string,falla:string}>
 */
function bio_cerco_metricas_catalogo(): array
{
    $conObs = bio_cerco_metricas_obs();
    $out = [];
    foreach (bio_cerco_bloques() as $bloque => $filas) {
        foreach ($filas as $metrica => $std) {
            $out[] = [
                'metrica' => $metrica,
                'std' => $std,
                'bloque' => $bloque,
                'obs' => in_array($metrica, $conObs, true),
            ] + bio_cerco_respuestas($metrica);
        }
    }

    return $out;
}

/** Tablas san_fact_* (camelCase). Legacy sin tocar: rgarita, rfomites, rcercoelectrico. */
function bio_tabla_ingreso_cab(): string
{
    return 'san_fact_ingresogranja_cab';
}

function bio_tabla_ingreso_det(): string
{
    return 'san_fact_ingresogranja_det';
}

function bio_tabla_ingreso_veh(): string
{
    return 'san_fact_ingresogranja_veh';
}

function bio_tabla_salida_cab(): string
{
    return 'san_fact_salidagranja_cab';
}

function bio_tabla_salida_det(): string
{
    return 'san_fact_salidagranja_det';
}

function bio_tabla_articulos_cab(): string
{
    return 'san_fact_articulos_cab';
}

function bio_tabla_articulos_det(): string
{
    return 'san_fact_articulos_det';
}

function bio_tabla_reporte(string $reporte): string
{
    switch ($reporte) {
        case 'garita':
            return 'rgarita';
        case 'cerco':
            return 'rcercoelectrico';
        case 'fomites':
            return 'rfomites';
        case 'ingreso':
            return bio_tabla_ingreso_cab();
        case 'salida':
            return bio_tabla_salida_cab();
        case 'articulos':
            return bio_tabla_articulos_cab();
    }
    return '';
}

/** Tabla de detalle del reporte (ingreso y salida llevan DNIs). */
function bio_tabla_reporte_det(string $reporte): string
{
    if ($reporte === 'ingreso') {
        return bio_tabla_ingreso_det();
    }
    if ($reporte === 'salida') {
        return bio_tabla_salida_det();
    }
    if ($reporte === 'articulos') {
        return bio_tabla_articulos_det();
    }
    return '';
}

/** ¿El reporte usa el esquema nuevo (llave uuid, granja/campaña, auditoría)? */
function bio_reporte_moderno(string $reporte): bool
{
    return $reporte === 'ingreso' || $reporte === 'salida' || $reporte === 'articulos';
}

if (!function_exists('bio_col_exists')) {
function bio_col_exists(mysqli $conn, string $tabla, string $columna): bool
{
    $tabla = $conn->real_escape_string($tabla);
    $columna = $conn->real_escape_string($columna);
    $rs = $conn->query("SHOW COLUMNS FROM `{$tabla}` LIKE '{$columna}'");
    if (!$rs) {
        return false;
    }
    $exists = $rs->num_rows > 0;
    $rs->free();
    return $exists;
}
}

/** Garantiza la columna imagenes en las tablas de reportes (mismo patrón que hc_obs_ensure_extra_cols). */
function bio_ensure_imagenes_col(mysqli $conn): void
{
    foreach (['rgarita', 'rcercoelectrico', 'rfomites', bio_tabla_ingreso_cab(), bio_tabla_articulos_cab()] as $tabla) {
        if (!bio_col_exists($conn, $tabla, 'imagenes')) {
            @$conn->query("ALTER TABLE `{$tabla}` ADD COLUMN `imagenes` TEXT NULL");
        }
    }
}

/**
 * Garantiza la columna aditiva `uuid` en las tablas legacy.
 *
 * `rgarita`, `rcercoelectrico` y `rfomites` son de producción y conservan su
 * `id` numérico; `uuid` guarda el identificador que genera la app para poder
 * verificar por uuid si un registro ya se insertó (deduplicación de la subida).
 */
function bio_ensure_uuid_col(mysqli $conn): void
{
    foreach (['rgarita', 'rcercoelectrico', 'rfomites'] as $tabla) {
        if (!bio_col_exists($conn, $tabla, 'uuid')) {
            @$conn->query("ALTER TABLE `{$tabla}` ADD COLUMN `uuid` VARCHAR(36) NOT NULL DEFAULT ''");
        }
    }
}

/**
 * Instalaciones válidas (punto inspeccionado), leídas del catálogo.
 *
 * @return list<string>
 */
function bio_instalaciones(mysqli $conn): array
{
    // Lista fija mientras la tabla instalaciongarita no exista (misma que la app).
    return ['Garita', 'Tranquera', 'Pozo septico'];
}

/**
 * Normaliza el punto inspeccionado contra el catálogo. Devuelve '' si no es
 * válido; vacío se interpreta como «Garita» (registros anteriores al cambio).
 */
function bio_normalizar_instalacion(mysqli $conn, string $valor): string
{
    $v = trim($valor);
    if ($v === '') {
        return 'Garita';
    }
    foreach (bio_instalaciones($conn) as $valida) {
        if (strcasecmp($valida, $v) === 0) {
            return $valida;
        }
    }

    return '';
}

/** Garantiza rgarita.instalacion y que forme parte de la PRIMARY KEY. */
function bio_ensure_instalacion_col(mysqli $conn): void
{
    if (!bio_col_exists($conn, 'rgarita', 'instalacion')) {
        @$conn->query("ALTER TABLE `rgarita` ADD COLUMN `instalacion` VARCHAR(20) NOT NULL DEFAULT 'Garita'");
    }

    // Sin la columna dentro de la PK, la garita filtro 1 y el pozo séptico del
    // mismo día/granja/turno chocarían y el segundo registro no se guardaría.
    $rs = @$conn->query("SELECT COUNT(*) AS c FROM information_schema.STATISTICS
                         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'rgarita'
                           AND INDEX_NAME = 'PRIMARY' AND COLUMN_NAME = 'instalacion'");
    $enPk = 0;
    if ($rs) {
        $row = $rs->fetch_assoc();
        $enPk = (int) ($row['c'] ?? 0);
        $rs->free();
    }
    if ($enPk === 0) {
        @$conn->query('ALTER TABLE `rgarita` DROP PRIMARY KEY, '
            . 'ADD PRIMARY KEY (`fecha`, `cencos`, `turno`, `numfiltro`, `instalacion`, `bioseguridad`)');
    }
}

/**
 * Tipos de bioseguridad del reporte, en el orden de las pestañas del dashboard:
 * física, química y biológica. Cada pestaña es estructural (el HTML del
 * dashboard y los filtros del front las declaran una por una), así que la lista
 * vive en código y no en un catálogo de base de datos.
 */
const BIO_BIOSEGURIDADES = ['Bioseguridad fisica', 'Bioseguridad quimica', 'Bioseguridad biologica'];

/**
 * Tipos de bioseguridad válidos.
 *
 * @return list<string>
 */
function bio_bioseguridades(): array
{
    return BIO_BIOSEGURIDADES;
}

/**
 * Normaliza el tipo de bioseguridad. Vacío se interpreta como «Bioseguridad
 * fisica» (registros de apps anteriores al cambio).
 */
function bio_normalizar_bioseguridad(string $valor): string
{
    $v = trim($valor);
    if ($v === '') {
        return 'Bioseguridad fisica';
    }
    foreach (bio_bioseguridades() as $valida) {
        if (strcasecmp($valida, $v) === 0) {
            return $valida;
        }
    }

    return '';
}

/* El área o proveedor de la visita (de qué lista salió el motivo y con qué
   valores válidos) vive en includes/bioseguridad/areaproveedor_catalogo.php:
   la comparte la planificación de visitas de la web, que ahora también pide el
   dato al programar. Acá queda disponible `bio_normalizar_areaproveedor()`. */
require_once __DIR__ . '/../../includes/bioseguridad/areaproveedor_catalogo.php';

/** Garantiza rgarita.bioseguridad y que forme parte de la PRIMARY KEY. */
function bio_ensure_bioseguridad_col(mysqli $conn): void
{
    if (!bio_col_exists($conn, 'rgarita', 'bioseguridad')) {
        @$conn->query("ALTER TABLE `rgarita` ADD COLUMN `bioseguridad` VARCHAR(30) NOT NULL DEFAULT 'Bioseguridad fisica' AFTER `instalacion`");
    }

    // La misma instalación puede inspeccionarse para física y para química el
    // mismo día/turno: sin la columna en la PK el segundo registro pisaría al
    // primero (la app lo tomaría como «ya existe» y lo actualizaría).
    $rs = @$conn->query("SELECT COUNT(*) AS c FROM information_schema.STATISTICS
                         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'rgarita'
                           AND INDEX_NAME = 'PRIMARY' AND COLUMN_NAME = 'bioseguridad'");
    $enPk = 0;
    if ($rs) {
        $row = $rs->fetch_assoc();
        $enPk = (int) ($row['c'] ?? 0);
        $rs->free();
    }
    if ($enPk === 0) {
        @$conn->query('ALTER TABLE `rgarita` DROP PRIMARY KEY, '
            . 'ADD PRIMARY KEY (`fecha`, `cencos`, `turno`, `numfiltro`, `instalacion`, `bioseguridad`)');
    }
}

/**
 * Garantiza la columna `nombre` en el detalle de DNIs de control de ingreso.
 *
 * El nombre se obtiene al escanear el DNI (API Factiliza) y se guarda junto al
 * documento para que el reporte web lo muestre sin volver a consultar.
 */
function bio_ensure_dni_nombre_col(mysqli $conn): void
{
    unset($conn);
}

function bio_ensure_visitante_col(mysqli $conn): void
{
    unset($conn);
}

/** @deprecated use bio_tabla_ingreso_veh() */
function bio_tabla_ingreso_vehiculos(): string
{
    return bio_tabla_ingreso_veh();
}

/** Esquema san_fact_* vía migracion_bioseguridad_app.php (prod ya migrado). */
function bio_ensure_ingreso_tablas(mysqli $conn): bool
{
    unset($conn);

    return true;
}

function bio_ensure_articulos_tablas(mysqli $conn): bool
{
    $sqlCab = <<<'SQL'
CREATE TABLE IF NOT EXISTS `san_fact_articulos_cab` (
    `id` varchar(36) NOT NULL,
    `fecha` date NOT NULL,
    `granja` varchar(10) NOT NULL DEFAULT '',
    `campania` varchar(10) NOT NULL DEFAULT '',
    `turno` varchar(10) NOT NULL DEFAULT '',
    `dni` varchar(15) NOT NULL DEFAULT '',
    `nombre` varchar(120) NOT NULL DEFAULT '',
    `imagenes` text NULL,
    `usuarioRegistrador` varchar(25) NOT NULL DEFAULT '',
    `fechaHoraRegistro` datetime NULL DEFAULT NULL,
    PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
SQL;
    $sqlDet = <<<'SQL'
CREATE TABLE IF NOT EXISTS `san_fact_articulos_det` (
    `id` varchar(36) NOT NULL,
    `idCab` varchar(36) NOT NULL,
    `posicion` int(11) NOT NULL DEFAULT 1,
    `codigo` varchar(10) NOT NULL DEFAULT '',
    `descripcion` varchar(120) NOT NULL DEFAULT '',
    `permitido` tinyint(1) NOT NULL DEFAULT 1,
    `desinfectado` tinyint(1) NOT NULL DEFAULT 1,
    `desinfectante` varchar(80) NOT NULL DEFAULT '',
    `anomalia_permitido` text NULL,
    `agente_causal_permitido` varchar(255) NOT NULL DEFAULT '',
    `accion_permitido` varchar(255) NOT NULL DEFAULT '',
    `anomalia_desinfeccion` text NULL,
    `agente_causal_desinfeccion` varchar(255) NOT NULL DEFAULT '',
    `accion_desinfeccion` varchar(255) NOT NULL DEFAULT '',
    `imagenes` text NULL,
    PRIMARY KEY (`id`),
    KEY `idx_articulos_det_cab` (`idCab`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
SQL;
    if (!$conn->query($sqlCab)) {
        return false;
    }

    return (bool) $conn->query($sqlDet);
}

function bio_ensure_ingreso_vehiculos(mysqli $conn): bool
{
    return bio_ensure_ingreso_tablas($conn);
}

/** 1 si el valor representa «ingresa» (true, 1, «si»), 0 si «no ingresa». */
function bio_ingresa_flag($valor): int
{
    if (is_bool($valor)) {
        return $valor ? 1 : 0;
    }
    if (is_numeric($valor)) {
        return ((int) $valor) === 0 ? 0 : 1;
    }
    $s = strtolower(trim((string) $valor));

    return in_array($s, ['0', 'no', 'false', 'n'], true) ? 0 : 1;
}

/**
 * Vehículos del registro de ingreso normalizados a [{placa, ingresa}].
 *
 * Acepta la lista nueva `vehiculos` ([{placa, ingresa}]), la lista de placas
 * `placas` o la `placa` suelta de las apps anteriores. Sin repetidos.
 *
 * @param array<string,mixed> $reg
 * @return list<array{placa:string,ingresa:int}>
 */
function bio_ingreso_vehiculos(array $reg): array
{
    $items = [];
    if (isset($reg['vehiculos']) && is_array($reg['vehiculos']) && $reg['vehiculos'] !== []) {
        foreach ($reg['vehiculos'] as $v) {
            $items[] = is_array($v)
                ? ['placa' => (string) ($v['placa'] ?? ''), 'ingresa' => bio_ingresa_flag($v['ingresa'] ?? 1)]
                : ['placa' => (string) $v, 'ingresa' => 1];
        }
    } else {
        $raw = $reg['placas'] ?? ($reg['placa'] ?? '');
        if (is_string($raw)) {
            $raw = preg_split('/[\s,;]+/', $raw) ?: [];
        }
        foreach ((array) $raw as $p) {
            $items[] = ['placa' => (string) $p, 'ingresa' => 1];
        }
    }

    $out = [];
    $vistas = [];
    foreach ($items as $it) {
        $placa = strtoupper((string) preg_replace('/\s+/', '', trim($it['placa'])));
        if ($placa === '') {
            continue;
        }
        $placa = bio_cut($placa, 15);
        if (isset($vistas[$placa])) {
            continue;
        }
        $vistas[$placa] = true;
        $out[] = ['placa' => $placa, 'ingresa' => $it['ingresa']];
    }

    return $out;
}

/**
 * Credenciales de la API de consulta de DNI.
 *
 * @return array{token:string,base_url:string}
 */
function bio_factiliza_config(): array
{
    $token = '';
    $baseUrl = 'https://api.factiliza.com/v1';
    // __DIR__ es sanidad/flutter/bioseguridad: el config vive en sanidad/config.
    $configPath = dirname(__DIR__, 2) . '/config/factiliza.php';
    if (is_file($configPath)) {
        require_once $configPath;
    }
    if (defined('FACTILIZA_API_TOKEN')) {
        $token = trim((string) FACTILIZA_API_TOKEN);
    }
    if (defined('FACTILIZA_API_BASE_URL')) {
        $baseUrl = trim((string) FACTILIZA_API_BASE_URL);
    }

    return ['token' => $token, 'base_url' => rtrim($baseUrl, '/')];
}

/**
 * Arma «Nombres ApellidoPaterno ApellidoMaterno» con la respuesta de Factiliza.
 *
 * @param array<string,mixed> $data
 */
function bio_nombre_desde_datos_dni(array $data): string
{
    $partes = array_values(array_filter([
        trim((string) ($data['nombres'] ?? '')),
        trim((string) ($data['apellido_paterno'] ?? '')),
        trim((string) ($data['apellido_materno'] ?? '')),
    ], static function (string $p): bool {
        return $p !== '';
    }));
    $nombre = implode(' ', $partes);

    if ($nombre === '') {
        // Algunos proveedores devuelven «APELLIDOS, NOMBRES».
        $nombre = trim((string) ($data['nombre_completo'] ?? ''));
        if (strpos($nombre, ',') !== false) {
            $chunks = array_map('trim', explode(',', $nombre, 2));
            $nombre = trim(($chunks[1] ?? '') . ' ' . ($chunks[0] ?? ''));
        }
    }

    $nombre = preg_replace('/\s+/', ' ', trim($nombre)) ?? '';

    return bio_cut($nombre, 60);
}

/**
 * Consulta el nombre de un DNI contra la API Factiliza.
 *
 * @return array{success:bool,message?:string,nombre?:string}
 */
function bio_consultar_dni_factiliza(string $dni): array
{
    $dni = preg_replace('/\D+/', '', trim($dni)) ?? '';
    if (!preg_match('/^\d{8}$/', $dni)) {
        return ['success' => false, 'message' => 'Ingrese un DNI de 8 dígitos.'];
    }

    $cfg = bio_factiliza_config();
    if ($cfg['token'] === '') {
        return ['success' => false, 'message' => 'Consulta DNI no configurada en el servidor.'];
    }
    if (!function_exists('curl_init')) {
        return ['success' => false, 'message' => 'El servidor no tiene cURL habilitado.'];
    }

    $ch = curl_init($cfg['base_url'] . '/dni/info/' . rawurlencode($dni));
    if ($ch === false) {
        return ['success' => false, 'message' => 'No se pudo consultar el DNI.'];
    }

    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $cfg['token'],
            'Accept: application/json',
        ],
        CURLOPT_TIMEOUT => 15,
        CURLOPT_CONNECTTIMEOUT => 8,
    ]);

    $body = curl_exec($ch);
    $httpCode = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlErr = curl_error($ch);
    curl_close($ch);

    if ($body === false || $curlErr !== '') {
        return ['success' => false, 'message' => 'No se pudo consultar el DNI.'];
    }
    if ($httpCode === 401 || $httpCode === 403) {
        return ['success' => false, 'message' => 'Consulta DNI no autorizada.'];
    }

    $json = json_decode((string) $body, true);
    if (!is_array($json) || empty($json['success'])) {
        $msg = is_array($json) ? trim((string) ($json['message'] ?? '')) : '';
        if ($msg === '') {
            $msg = $httpCode === 404 || $httpCode === 400
                ? 'DNI no encontrado.'
                : ($httpCode >= 500 ? 'El servicio de consulta DNI no está disponible.' : 'DNI no encontrado.');
        }
        return ['success' => false, 'message' => $msg];
    }

    $nombre = bio_nombre_desde_datos_dni(is_array($json['data'] ?? null) ? $json['data'] : []);
    if ($nombre === '') {
        return ['success' => false, 'message' => 'No se obtuvo nombre para el DNI.'];
    }

    return ['success' => true, 'nombre' => $nombre];
}

/**
 * Consulta carné de extranjería (CEE) contra Factiliza (`/cee/info/{cee}`).
 *
 * @return array{success:bool,message?:string,nombre?:string,cee?:string}
 */
function bio_consultar_cee_factiliza(string $cee): array
{
    $cee = strtoupper(preg_replace('/[^A-Z0-9]/', '', trim($cee)) ?? '');
    if ($cee === '' || strlen($cee) < 6 || strlen($cee) > 15) {
        return ['success' => false, 'message' => 'Ingrese un carné de extranjería válido.'];
    }
    if (preg_match('/^\d{8}$/', $cee)) {
        return ['success' => false, 'message' => 'Use consulta DNI para documentos de 8 dígitos.'];
    }

    $cfg = bio_factiliza_config();
    if ($cfg['token'] === '') {
        return ['success' => false, 'message' => 'Consulta CEE no configurada en el servidor.'];
    }
    if (!function_exists('curl_init')) {
        return ['success' => false, 'message' => 'El servidor no tiene cURL habilitado.'];
    }

    $ch = curl_init($cfg['base_url'] . '/cee/info/' . rawurlencode($cee));
    if ($ch === false) {
        return ['success' => false, 'message' => 'No se pudo consultar el carné.'];
    }

    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $cfg['token'],
            'Accept: application/json',
        ],
        CURLOPT_TIMEOUT => 15,
        CURLOPT_CONNECTTIMEOUT => 8,
    ]);

    $body = curl_exec($ch);
    $httpCode = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlErr = curl_error($ch);
    curl_close($ch);

    if ($body === false || $curlErr !== '') {
        return ['success' => false, 'message' => 'No se pudo consultar el carné.'];
    }
    if ($httpCode === 401 || $httpCode === 403) {
        return ['success' => false, 'message' => 'Consulta CEE no autorizada.'];
    }

    $json = json_decode((string) $body, true);
    if (!is_array($json) || empty($json['success'])) {
        $msg = is_array($json) ? trim((string) ($json['message'] ?? '')) : '';
        if ($msg === '') {
            $msg = $httpCode === 404 || $httpCode === 400
                ? 'Carné no encontrado.'
                : ($httpCode >= 500 ? 'El servicio de consulta no está disponible.' : 'Carné no encontrado.');
        }
        return ['success' => false, 'message' => $msg];
    }

    $data = is_array($json['data'] ?? null) ? $json['data'] : [];
    $nombre = bio_nombre_desde_datos_dni($data);
    if ($nombre === '') {
        $nombre = bio_cut(trim((string) ($data['nombre_completo'] ?? '')), 60);
    }
    if ($nombre === '') {
        return ['success' => false, 'message' => 'No se obtuvo nombre para el carné.'];
    }

    return ['success' => true, 'nombre' => $nombre, 'cee' => $cee];
}

/**
 * DNI (8 dígitos) o CEE (alfanumérico) según el valor enviado.
 *
 * @return array{success:bool,message?:string,nombre?:string,documento?:string,tipo?:string}
 */
function bio_consultar_documento_factiliza(string $raw): array
{
    $digits = preg_replace('/\D+/', '', trim($raw)) ?? '';
    if (preg_match('/^\d{8}$/', $digits)) {
        $r = bio_consultar_dni_factiliza($digits);
        if (!$r['success']) {
            return $r;
        }

        return [
            'success' => true,
            'nombre' => (string) ($r['nombre'] ?? ''),
            'documento' => $digits,
            'tipo' => 'dni',
        ];
    }

    $r = bio_consultar_cee_factiliza($raw);
    if (!$r['success']) {
        return $r;
    }

    return [
        'success' => true,
        'nombre' => (string) ($r['nombre'] ?? ''),
        'documento' => (string) ($r['cee'] ?? ''),
        'tipo' => 'cee',
    ];
}

/**
 * Razón social que devuelve Factiliza para un RUC, sin depender del nombre
 * exacto de la clave (los proveedores no la rotulan igual).
 *
 * @param array<string,mixed> $data
 */
function bio_razonsocial_desde_datos_ruc(array $data): string
{
    foreach (['razon_social', 'nombre_o_razon_social', 'nombre', 'razonSocial'] as $clave) {
        $valor = trim((string) ($data[$clave] ?? ''));
        if ($valor !== '') {
            return bio_cut(preg_replace('/\s+/', ' ', $valor) ?? $valor, 120);
        }
    }

    return '';
}

/**
 * Consulta la razón social de un RUC contra la API Factiliza.
 *
 * Es la misma que usa la web al elegir un proveedor: el guardia escribe los 11
 * dígitos y la app solo devuelve el nombre, sin guardar el token.
 *
 * @return array{success:bool,message?:string,ruc?:string,razonsocial?:string}
 */
function bio_consultar_ruc_factiliza(string $ruc): array
{
    $ruc = preg_replace('/\D+/', '', trim($ruc)) ?? '';
    if (!preg_match('/^\d{11}$/', $ruc)) {
        return ['success' => false, 'message' => 'Ingrese un RUC de 11 dígitos.'];
    }

    $cfg = bio_factiliza_config();
    if ($cfg['token'] === '') {
        return ['success' => false, 'message' => 'Consulta RUC no configurada en el servidor.'];
    }
    if (!function_exists('curl_init')) {
        return ['success' => false, 'message' => 'El servidor no tiene cURL habilitado.'];
    }

    $ch = curl_init($cfg['base_url'] . '/ruc/info/' . rawurlencode($ruc));
    if ($ch === false) {
        return ['success' => false, 'message' => 'No se pudo consultar el RUC.'];
    }

    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $cfg['token'],
            'Accept: application/json',
        ],
        CURLOPT_TIMEOUT => 15,
        CURLOPT_CONNECTTIMEOUT => 8,
    ]);

    $body = curl_exec($ch);
    $httpCode = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlErr = curl_error($ch);
    curl_close($ch);

    if ($body === false || $curlErr !== '') {
        return ['success' => false, 'message' => 'No se pudo consultar el RUC.'];
    }
    if ($httpCode === 401 || $httpCode === 403) {
        return ['success' => false, 'message' => 'Consulta RUC no autorizada.'];
    }

    $json = json_decode((string) $body, true);
    if (!is_array($json) || empty($json['success'])) {
        $msg = is_array($json) ? trim((string) ($json['message'] ?? '')) : '';
        if ($msg === '') {
            $msg = $httpCode === 404 || $httpCode === 400
                ? 'RUC no encontrado.'
                : ($httpCode >= 500 ? 'El servicio de consulta RUC no está disponible.' : 'RUC no encontrado.');
        }
        return ['success' => false, 'message' => $msg];
    }

    $razonsocial = bio_razonsocial_desde_datos_ruc(is_array($json['data'] ?? null) ? $json['data'] : []);
    if ($razonsocial === '') {
        return ['success' => false, 'message' => 'No se obtuvo razón social para el RUC.'];
    }

    return ['success' => true, 'ruc' => $ruc, 'razonsocial' => $razonsocial];
}

/**
 * Normaliza la lista de DNIs del request a pares documento + nombre.
 *
 * Acepta el formato plano de la primera versión (`["12345678", ...]`) y el
 * actual, donde cada elemento es `{dni, nombre}`.
 *
 * @param mixed $dnis
 * @return list<array{dni:string,nombre:string}>
 */
function bio_dnis_normalizados($dnis): array
{
    $out = [];
    $vistos = [];
    foreach ((array) $dnis as $item) {
        if (is_array($item)) {
            $dni = (string) ($item['dni'] ?? '');
            $nombre = (string) ($item['nombre'] ?? '');
        } else {
            $dni = (string) $item;
            $nombre = '';
        }
        $dni = bio_cut(strtoupper(preg_replace('/[^0-9A-Za-z]/', '', $dni) ?? ''), 15);
        if ($dni === '' || isset($vistos[$dni])) {
            continue;
        }
        $vistos[$dni] = true;
        $out[] = ['dni' => $dni, 'nombre' => bio_cut($nombre, 60)];
    }

    return $out;
}

/** Siguiente id de la tabla (las tablas legacy no usan AUTO_INCREMENT). */
function bio_next_id(mysqli $conn, string $tabla): int
{
    $rs = $conn->query("SELECT IFNULL(MAX(ABS(`id`)), 0) + 1 AS nid FROM `{$tabla}`");
    if (!$rs) {
        return 1;
    }
    $row = $rs->fetch_assoc();
    $rs->free();
    return max(1, (int) ($row['nid'] ?? 1));
}

/** Genera un uuid v4 (mismo formato que la app). */
function bio_nuevo_uuid(): string
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

/** Valida y normaliza un uuid. Devuelve '' si no tiene el formato esperado. */
function bio_norm_uuid(string $uuid): string
{
    $uuid = strtolower(trim($uuid));
    return preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/', $uuid) === 1
        ? $uuid
        : '';
}

/**
 * Normaliza un datetime a Y-m-d H:i:s. Acepta ISO 8601 con T y milisegundos
 * (el formato que manda la app). Devuelve '' si no se puede interpretar.
 */
function bio_norm_datetime(string $valor): string
{
    $v = trim($valor);
    if ($v === '') {
        return '';
    }
    $v = str_replace('T', ' ', $v);
    $v = preg_replace('/\.\d+/', '', $v) ?? $v;
    $v = trim(preg_replace('/Z$/', '', $v) ?? $v);
    $ts = strtotime($v);
    return $ts === false ? '' : date('Y-m-d H:i:s', $ts);
}

/** Cantidad de imágenes que llegaron correctamente en la petición. */
function bio_contar_archivos(): int
{
    $n = 0;
    foreach (['imagen1', 'imagen2', 'imagen3'] as $key) {
        if (isset($_FILES[$key]) && is_array($_FILES[$key])
            && (int) ($_FILES[$key]['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_OK) {
            $n++;
        }
    }

    return $n;
}

/**
 * Sube hasta 3 imágenes a uploads/bioseguridad y devuelve el CSV de rutas relativas.
 *
 * @return list<string>
 */
function bio_subir_imagenes(string $reporte, string $cenco, int $maxArchivos = 3): array
{
    if (!function_exists('sanidad_uploads_fs_dir')) {
        return [];
    }

    $carpeta = sanidad_uploads_fs_dir('bioseguridad');
    $rutaRelativaBD = 'uploads/bioseguridad/';
    if (!is_dir($carpeta)) {
        @mkdir($carpeta, 0755, true);
    }

    $fileKeys = ['imagen1', 'imagen2', 'imagen3'];
    $extOk = ['jpg' => true, 'jpeg' => true, 'png' => true, 'gif' => true, 'webp' => true];
    $maxBytes = 6 * 1024 * 1024;
    $stamp = date('Ymd_His');
    $safeRep = preg_replace('/[^0-9a-zA-Z_-]/', '_', $reporte) ?? 'bio';
    $safeCenco = preg_replace('/[^0-9a-zA-Z_-]/', '_', $cenco) ?? 'cenco';

    $uploaded = [];
    foreach ($fileKeys as $key) {
        if (count($uploaded) >= $maxArchivos) {
            break;
        }
        if (!isset($_FILES[$key]) || !is_array($_FILES[$key])) {
            continue;
        }
        $err = $_FILES[$key]['error'] ?? UPLOAD_ERR_NO_FILE;
        if ($err !== UPLOAD_ERR_OK) {
            continue;
        }
        $tmp = (string) ($_FILES[$key]['tmp_name'] ?? '');
        $nombreOriginal = (string) ($_FILES[$key]['name'] ?? '');
        $tam = (int) ($_FILES[$key]['size'] ?? 0);
        if ($tmp === '' || $tam <= 0 || $tam > $maxBytes) {
            continue;
        }
        $ext = strtolower(pathinfo($nombreOriginal, PATHINFO_EXTENSION));
        if (!isset($extOk[$ext])) {
            continue;
        }
        $nombreArchivo = "bio_{$safeRep}_{$safeCenco}_{$stamp}_" . uniqid('', true) . ".{$ext}";
        $nombreArchivo = str_replace(['..', '/', '\\'], '_', $nombreArchivo);
        if (!move_uploaded_file($tmp, $carpeta . $nombreArchivo)) {
            continue;
        }
        $uploaded[] = $rutaRelativaBD . $nombreArchivo;
    }

    return $uploaded;
}

/** Borra del disco las evidencias de un registro reemplazado (solo dentro de uploads/bioseguridad). */
function bio_limpiar_imagenes(?string $csv): void
{
    if ($csv === null || trim($csv) === '' || !function_exists('sanidad_uploads_fs_from_rel')) {
        return;
    }
    foreach (explode(',', $csv) as $ruta) {
        $ruta = trim($ruta);
        if ($ruta === '' || strpos($ruta, 'uploads/bioseguridad/') !== 0) {
            continue;
        }
        $fs = sanidad_uploads_fs_from_rel($ruta);
        if ($fs !== '' && is_file($fs)) {
            @unlink($fs);
        }
    }
}

/**
 * Filas de una consulta preparada (misma firma que bioseguridad_lib.php del portal).
 *
 * @return list<array<string, mixed>>
 */
if (!function_exists('bio_fetch_rows')) {
    function bio_fetch_rows(mysqli $conn, string $sql, string $types, array $params): array
    {
        $stmt = $conn->prepare($sql);
        if (!$stmt) {
            return [];
        }
        if ($types !== '') {
            $stmt->bind_param($types, ...$params);
        }
        if (!$stmt->execute()) {
            $stmt->close();

            return [];
        }
        $rs = $stmt->get_result();
        $out = [];
        if ($rs) {
            while ($row = $rs->fetch_assoc()) {
                $out[] = $row;
            }
            $rs->free();
        }
        $stmt->close();

        return $out;
    }
}

/**
 * ¿Ya existe un registro con ese uuid?
 *
 * En control de ingreso el uuid es la PRIMARY KEY (`id`). En las tablas legacy
 * se guarda en la columna aditiva `uuid`.
 */
function bio_existe_uuid(mysqli $conn, string $reporte, string $uuid): bool
{
    $uuid = trim($uuid);
    if ($uuid === '') {
        return false;
    }
    $tabla = bio_tabla_reporte($reporte);
    if ($tabla === '') {
        return false;
    }
    $col = bio_reporte_moderno($reporte) ? 'id' : 'uuid';
    $sql = "SELECT 1 FROM `{$tabla}` WHERE `{$col}` = ? LIMIT 1";
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        return false;
    }
    $stmt->bind_param('s', $uuid);
    $stmt->execute();
    $rs = $stmt->get_result();
    $existe = $rs && $rs->num_rows > 0;
    $stmt->close();

    return $existe;
}

/**
 * Indica si ya existe el grupo (llave lógica) del registro.
 *
 * Solo aplica a las tablas legacy: en control de ingreso la identidad es el
 * uuid y dos visitas pueden coincidir en fecha/granja/turno.
 *
 * @param array<string, mixed> $ctx
 */
function bio_grupo_existe_logico(mysqli $conn, string $reporte, array $ctx): bool
{
    $tabla = bio_tabla_reporte($reporte);
    if ($tabla === '' || bio_reporte_moderno($reporte)) {
        return false;
    }

    switch ($reporte) {
        case 'garita':
            $sql = "SELECT 1 FROM `rgarita` WHERE `fecha` = ? AND `cencos` = ? AND `turno` = ? AND `numfiltro` = ? AND `instalacion` = ? AND `bioseguridad` = ? LIMIT 1";
            $tipos = 'sssiss';
            $params = [$ctx['fecha'], $ctx['cencos'], $ctx['turno'], (int) $ctx['numfiltro'], (string) $ctx['instalacion'], (string) $ctx['bioseguridad']];
            break;
        case 'cerco':
            $sql = "SELECT 1 FROM `rcercoelectrico` WHERE `fecha` = ? AND `cencos` = ? AND `turno` = ? LIMIT 1";
            $tipos = 'sss';
            $params = [$ctx['fecha'], $ctx['cencos'], $ctx['turno']];
            break;
        case 'fomites':
            $sql = "SELECT 1 FROM `rfomites` WHERE `fecha` = ? AND `cencos` = ? AND `turno` = ? AND `referencia` = ? AND `proceso` = ? LIMIT 1";
            $tipos = 'sssss';
            $params = [$ctx['fecha'], $ctx['cencos'], $ctx['turno'], $ctx['referencia'], $ctx['proceso']];
            break;
        default:
            return false;
    }

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        return false;
    }
    $stmt->bind_param($tipos, ...$params);
    $stmt->execute();
    $rs = $stmt->get_result();
    $existe = $rs && $rs->num_rows > 0;
    $stmt->close();

    return $existe;
}

/** Elimina las filas del grupo (se reinsertan completas: guardado idempotente). */
function bio_borrar_grupo(mysqli $conn, string $reporte, array $ctx): void
{
    switch ($reporte) {
        case 'garita':
            $sql = "DELETE FROM `rgarita` WHERE `fecha` = ? AND `cencos` = ? AND `turno` = ? AND `numfiltro` = ? AND `instalacion` = ? AND `bioseguridad` = ?";
            $tipos = 'sssiss';
            $params = [$ctx['fecha'], $ctx['cencos'], $ctx['turno'], (int) $ctx['numfiltro'], (string) $ctx['instalacion'], (string) $ctx['bioseguridad']];
            break;
        case 'cerco':
            $sql = "DELETE FROM `rcercoelectrico` WHERE `fecha` = ? AND `cencos` = ? AND `turno` = ?";
            $tipos = 'sss';
            $params = [$ctx['fecha'], $ctx['cencos'], $ctx['turno']];
            break;
        case 'fomites':
            $sql = "DELETE FROM `rfomites` WHERE `fecha` = ? AND `cencos` = ? AND `turno` = ? AND `referencia` = ? AND `proceso` = ?";
            $tipos = 'sssss';
            $params = [$ctx['fecha'], $ctx['cencos'], $ctx['turno'], $ctx['referencia'], $ctx['proceso']];
            break;
        case 'salida':
            $detSal = bio_tabla_salida_det();
            $cabSal = bio_tabla_salida_cab();
            $sql = "DELETE FROM `{$detSal}` WHERE `idCab` = ?";
            $stmt = $conn->prepare($sql);
            if ($stmt) {
                $uuid = (string) ($ctx['uuid'] ?? '');
                $stmt->bind_param('s', $uuid);
                $stmt->execute();
                $stmt->close();
            }
            $sql = "DELETE FROM `{$cabSal}` WHERE `id` = ?";
            $tipos = 's';
            $params = [(string) ($ctx['uuid'] ?? '')];
            break;
        case 'ingreso':
            $detIng = bio_tabla_ingreso_det();
            $vehIng = bio_tabla_ingreso_veh();
            $cabIng = bio_tabla_ingreso_cab();
            $sql = "DELETE FROM `{$detIng}` WHERE `idCab` = ?";
            $stmt = $conn->prepare($sql);
            if ($stmt) {
                $uuid = (string) ($ctx['uuid'] ?? '');
                $stmt->bind_param('s', $uuid);
                $stmt->execute();
                $stmt->close();
            }
            $stmt = $conn->prepare("DELETE FROM `{$vehIng}` WHERE `idCab` = ?");
            if ($stmt) {
                $uuid = (string) ($ctx['uuid'] ?? '');
                $stmt->bind_param('s', $uuid);
                $stmt->execute();
                $stmt->close();
            }
            $sql = "DELETE FROM `{$cabIng}` WHERE `id` = ?";
            $tipos = 's';
            $params = [(string) ($ctx['uuid'] ?? '')];
            break;
        case 'articulos':
            $detArt = bio_tabla_articulos_det();
            $cabArt = bio_tabla_articulos_cab();
            $sql = "DELETE FROM `{$detArt}` WHERE `idCab` = ?";
            $stmt = $conn->prepare($sql);
            if ($stmt) {
                $uuid = (string) ($ctx['uuid'] ?? '');
                $stmt->bind_param('s', $uuid);
                $stmt->execute();
                $stmt->close();
            }
            $sql = "DELETE FROM `{$cabArt}` WHERE `id` = ?";
            $tipos = 's';
            $params = [(string) ($ctx['uuid'] ?? '')];
            break;
        default:
            return;
    }

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        return;
    }
    $stmt->bind_param($tipos, ...$params);
    $stmt->execute();
    $stmt->close();
}

/** Devuelve el CSV de imágenes del grupo (para no perderlas al actualizar sin adjuntos). */
function bio_imagenes_grupo(mysqli $conn, string $reporte, array $ctx): string
{
    if (!bio_col_exists($conn, bio_tabla_reporte($reporte), 'imagenes')) {
        return '';
    }
    switch ($reporte) {
        case 'garita':
            $sql = "SELECT `imagenes` FROM `rgarita` WHERE `fecha` = ? AND `cencos` = ? AND `turno` = ? AND `numfiltro` = ? AND `instalacion` = ? AND `bioseguridad` = ? LIMIT 1";
            $tipos = 'sssiss';
            $params = [$ctx['fecha'], $ctx['cencos'], $ctx['turno'], (int) $ctx['numfiltro'], (string) $ctx['instalacion'], (string) $ctx['bioseguridad']];
            break;
        case 'cerco':
            $sql = "SELECT `imagenes` FROM `rcercoelectrico` WHERE `fecha` = ? AND `cencos` = ? AND `turno` = ? LIMIT 1";
            $tipos = 'sss';
            $params = [$ctx['fecha'], $ctx['cencos'], $ctx['turno']];
            break;
        case 'fomites':
            $sql = "SELECT `imagenes` FROM `rfomites` WHERE `fecha` = ? AND `cencos` = ? AND `turno` = ? AND `referencia` = ? AND `proceso` = ? LIMIT 1";
            $tipos = 'sssss';
            $params = [$ctx['fecha'], $ctx['cencos'], $ctx['turno'], $ctx['referencia'], $ctx['proceso']];
            break;
        case 'ingreso':
            $cabIng = bio_tabla_ingreso_cab();
            $sql = "SELECT `imagenes` FROM `{$cabIng}` WHERE `id` = ? LIMIT 1";
            $tipos = 's';
            $params = [(string) ($ctx['uuid'] ?? '')];
            break;
        case 'salida':
            return '';
        case 'articulos':
            $cabArt = bio_tabla_articulos_cab();
            $sql = "SELECT `imagenes` FROM `{$cabArt}` WHERE `id` = ? LIMIT 1";
            $tipos = 's';
            $params = [(string) ($ctx['uuid'] ?? '')];
            break;
        default:
            return '';
    }
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        return '';
    }
    $stmt->bind_param($tipos, ...$params);
    $stmt->execute();
    $rs = $stmt->get_result();
    $csv = '';
    if ($rs && ($row = $rs->fetch_assoc())) {
        $csv = (string) ($row['imagenes'] ?? '');
    }
    $stmt->close();

    return $csv;
}

/**
 * Inserta las filas del reporte. Devuelve la cantidad insertada.
 *
 * @param array<string, mixed> $ctx
 */
function bio_insertar_filas(mysqli $conn, string $reporte, array $ctx, string $imagenesCsv): int
{
    $tuser = bio_cut((string) ($ctx['tuser'] ?? ''), 6);
    $colaborador = bio_cut((string) ($ctx['colaborador'] ?? ''), 30);
    $fecha = (string) $ctx['fecha'];
    $cencos = (string) $ctx['cencos'];
    $turno = (string) $ctx['turno'];
    $hoy = date('Y-m-d');
    $ahora = date('H:i:s');
    $filas = 0;

    if ($reporte === 'garita') {
        $sql = 'INSERT INTO `rgarita` (`id`,`tuser`,`tdate`,`ttime`,`fecha`,`cencos`,`nomcolaborador`,`turno`,'
            . '`numfiltro`,`anomalia`,`hora`,`descripcion`,`agentecausal`,`instalacion`,`bioseguridad`,'
            . '`uuid`,`imagenes`)'
            . ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)';
        $stmt = $conn->prepare($sql);
        if (!$stmt) {
            return 0;
        }
        $id = bio_next_id($conn, 'rgarita');
        // La columna es NOT NULL y forma parte de la PK: nunca puede ir vacía.
        $numfiltro = (int) $ctx['numfiltro'];
        if ($numfiltro < 1) {
            $numfiltro = 1;
        }
        $instalacion = trim((string) ($ctx['instalacion'] ?? ''));
        if ($instalacion === '') {
            $instalacion = 'Garita';
        }
        $bioseguridad = trim((string) ($ctx['bioseguridad'] ?? ''));
        if ($bioseguridad === '') {
            $bioseguridad = 'Bioseguridad fisica';
        }
        $anomalia = bio_cut((string) $ctx['anomalia'], 30);
        $hora = bio_norm_hora((string) $ctx['hora']);
        if ($hora === '') {
            $hora = $ahora;
        }
        $descripcion = bio_cut((string) $ctx['descripcion'], 200);
        $agentecausal = bio_cut((string) $ctx['agentecausal'], 200);
        $stmt->bind_param(
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
            $agentecausal,
            $instalacion,
            $bioseguridad,
            bio_cut((string) ($ctx['uuid'] ?? ''), 36),
            $imagenesCsv
        );
        if ($stmt->execute()) {
            $filas = 1;
        }
        $stmt->close();

        return $filas;
    }

    if ($reporte === 'cerco') {
        $sql = 'INSERT INTO `rcercoelectrico` (`id`,`tuser`,`tdate`,`ttime`,`fecha`,`cencos`,`turno`,`estadoderecho`,'
            . '`descestadoder`,`estadoizquierdo`,`descestadoizq`,`nomevaluador`,`horainicio`,`horafinal`,`componente`,'
            . '`fallo`,`descripcion`,`observacion`,`uuid`,`imagenes`)'
            . ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)';
        $stmt = $conn->prepare($sql);
        if (!$stmt) {
            return 0;
        }
        $evaluador = bio_cut((string) ($ctx['evaluador'] ?? $colaborador), 30);
        $horainicio = bio_norm_hora((string) $ctx['horainicio']);
        $horafinal = bio_norm_hora((string) $ctx['horafinal']);
        if ($horainicio === '') {
            $horainicio = '00:00:00';
        }
        if ($horafinal === '') {
            $horafinal = '00:00:00';
        }
        $observacionGeneral = bio_cut((string) ($ctx['observacion'] ?? ''), 200);
        $metricas = bio_cerco_metricas();
        foreach ((array) $ctx['filas'] as $fila) {
            if (!is_array($fila)) {
                continue;
            }
            $componente = bio_cut((string) ($fila['componente'] ?? ''), 30);
            if ($componente === '' || !isset($metricas[$componente])) {
                continue;
            }
            $l1 = is_array($fila['linea1'] ?? null) ? $fila['linea1'] : [];
            $l2 = is_array($fila['linea2'] ?? null) ? $fila['linea2'] : [];
            $fallo1 = bio_fallo($l1['fallo'] ?? 'No');
            $fallo2 = bio_fallo($l2['fallo'] ?? 'No');
            $obs1 = bio_cut((string) ($l1['obs'] ?? ''), 80);
            $obs2 = bio_cut((string) ($l2['obs'] ?? ''), 80);
            $falloGrupo = ($fallo1 === 'Si' || $fallo2 === 'Si') ? 'Si' : 'No';
            $descripcion = bio_cut(trim($obs1 . ($obs1 !== '' && $obs2 !== '' ? ' | ' : '') . $obs2), 200);
            $id = bio_next_id($conn, 'rcercoelectrico');
            $stmt->bind_param(
                'isssssssssssssssssss',
                $id,
                $tuser,
                $hoy,
                $ahora,
                $fecha,
                $cencos,
                $turno,
                $fallo1,
                $obs1,
                $fallo2,
                $obs2,
                $evaluador,
                $horainicio,
                $horafinal,
                $componente,
                $falloGrupo,
                $descripcion,
                $observacionGeneral,
                bio_cut((string) ($ctx['uuid'] ?? ''), 36),
                $imagenesCsv
            );
            if ($stmt->execute()) {
                $filas++;
            }
        }
        $stmt->close();

        return $filas;
    }

    if ($reporte === 'fomites') {
        $sql = 'INSERT INTO `rfomites` (`id`,`tuser`,`tdate`,`ttime`,`fecha`,`cencos`,`turno`,`referencia`,`proceso`,'
            . '`nomcolaborador`,`depredador`,`tipo`,`cantidad`,`hora`,`dentrocerco`,`observacion`,'
            . '`uuid`,`imagenes`)'
            . ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)';
        $stmt = $conn->prepare($sql);
        if (!$stmt) {
            return 0;
        }
        $referencia = bio_cut((string) $ctx['referencia'], 30);
        $proceso = bio_cut((string) $ctx['proceso'], 30);
        $observacion = bio_cut((string) ($ctx['observacion'] ?? ''), 100);
        foreach ((array) $ctx['filas'] as $fila) {
            if (!is_array($fila)) {
                continue;
            }
            $depredador = bio_cut((string) ($fila['depredador'] ?? ''), 20);
            $tipo = bio_cut((string) ($fila['tipo'] ?? ''), 20);
            if ($depredador === '' || $tipo === '') {
                continue;
            }
            $cantidad = max(0, (int) ($fila['cantidad'] ?? 0));
            $hora = bio_norm_hora((string) ($fila['hora'] ?? ''));
            if ($hora === '') {
                $hora = '00:00:00';
            }
            $dentro = bio_fallo($fila['dentrocerco'] ?? 'No');
            $id = bio_next_id($conn, 'rfomites');
            $stmt->bind_param(
                'isssssssssssisssss',
                $id,
                $tuser,
                $hoy,
                $ahora,
                $fecha,
                $cencos,
                $turno,
                $referencia,
                $proceso,
                $colaborador,
                $depredador,
                $tipo,
                $cantidad,
                $hora,
                $dentro,
                $observacion,
                bio_cut((string) ($ctx['uuid'] ?? ''), 36),
                $imagenesCsv
            );
            if ($stmt->execute()) {
                $filas++;
            }
        }
        $stmt->close();

        return $filas;
    }

    if ($reporte === 'ingreso') {
        if (!bio_ensure_ingreso_tablas($conn)) {
            return 0;
        }
        $cabIng = bio_tabla_ingreso_cab();
        $detIng = bio_tabla_ingreso_det();
        $vehIng = bio_tabla_ingreso_veh();
        $sql = "INSERT INTO `{$cabIng}` (`id`,`fecha`,`granja`,`campania`,`turno`,`hora`,`numPersonas`,"
            . '`galpon`,`areaProveedor`,`motivo`,`observacion`,`proveedor`,`proveedorRuc`,`planVisitaId`,'
            . '`imagenes`,`usuarioRegistrador`,`fechaHoraRegistro`)'
            . ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)';
        $stmt = $conn->prepare($sql);
        if (!$stmt) {
            return 0;
        }
        $uuid = bio_cut((string) ($ctx['uuid'] ?? ''), 36);
        $granja = bio_cut((string) ($ctx['granja'] ?? ''), 10);
        $campania = bio_cut((string) ($ctx['campania'] ?? ''), 10);
        $hora = bio_norm_hora((string) ($ctx['hora'] ?? ''));
        if ($hora === '') {
            $hora = $ahora;
        }
        $numPersonas = max(0, (int) ($ctx['numpersonas'] ?? 0));
        $galpon = bio_cut((string) ($ctx['galpon'] ?? ''), 120);
        $areaProveedor = bio_normalizar_areaproveedor((string) ($ctx['areaproveedor'] ?? ''));
        $motivo = bio_cut((string) ($ctx['motivo'] ?? ''), 60);
        $observacion = bio_cut((string) ($ctx['observacion'] ?? ''), 200);
        $proveedor = bio_cut((string) ($ctx['proveedor'] ?? ''), 120);
        $proveedorRuc = bio_cut((string) ($ctx['proveedorRuc'] ?? ''), 15);
        $planVisitaId = (int) ($ctx['planVisitaId'] ?? 0);
        $usuarioRegistrador = bio_cut((string) ($ctx['usuarioRegistrador'] ?? $tuser), 25);
        $fechaHoraRegistro = (string) ($ctx['fechaHoraRegistro'] ?? '');
        $stmt->bind_param(
            'ssssssisssssssiss',
            $uuid,
            $fecha,
            $granja,
            $campania,
            $turno,
            $hora,
            $numPersonas,
            $galpon,
            $areaProveedor,
            $motivo,
            $observacion,
            $proveedor,
            $proveedorRuc,
            $planVisitaId,
            $imagenesCsv,
            $usuarioRegistrador,
            $fechaHoraRegistro
        );
        if ($stmt->execute()) {
            $filas = 1;
        }
        $stmt->close();

        $det = $conn->prepare("INSERT INTO `{$detIng}` (`id`,`idCab`,`posicion`,`dni`,`nombre`)"
            . ' VALUES (?,?,?,?,?)');
        if ($det) {
            $posicion = 0;
            foreach (bio_dnis_normalizados($ctx['dnis'] ?? []) as $par) {
                $posicion++;
                $idDet = bio_nuevo_uuid();
                $det->bind_param(
                    'ssiss',
                    $idDet,
                    $uuid,
                    $posicion,
                    $par['dni'],
                    $par['nombre']
                );
                $det->execute();
            }
            $det->close();
        }

        $vehiculos = is_array($ctx['vehiculos'] ?? null) ? $ctx['vehiculos'] : [];
        if ($vehiculos !== []) {
            $veh = $conn->prepare("INSERT INTO `{$vehIng}` (`id`,`idCab`,`posicion`,`placa`,`ingresa`)"
                . ' VALUES (?,?,?,?,?)');
            if ($veh) {
                $posVeh = 0;
                foreach ($vehiculos as $v) {
                    $posVeh++;
                    $idVeh = bio_nuevo_uuid();
                    $placaVeh = bio_cut((string) ($v['placa'] ?? ''), 15);
                    $ingresaVeh = bio_ingresa_flag($v['ingresa'] ?? 1);
                    $veh->bind_param(
                        'ssisi',
                        $idVeh,
                        $uuid,
                        $posVeh,
                        $placaVeh,
                        $ingresaVeh
                    );
                    $veh->execute();
                }
                $veh->close();
            }
        }

        return $filas;
    }

    if ($reporte === 'salida') {
        if (!bio_ensure_salida_tablas($conn)) {
            return 0;
        }
        $cabSal = bio_tabla_salida_cab();
        $detSal = bio_tabla_salida_det();
        $sql = "INSERT INTO `{$cabSal}` (`id`,`fecha`,`granja`,`campania`,`turno`,`hora`,`movimiento`,"
            . '`tipoSalida`,`grupoId`,`proveedor`,`motivo`,`usuarioRegistrador`,`fechaHoraRegistro`)'
            . ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)';
        $stmt = $conn->prepare($sql);
        if (!$stmt) {
            return 0;
        }
        $uuid = bio_cut((string) ($ctx['uuid'] ?? ''), 36);
        $granja = bio_cut((string) ($ctx['granja'] ?? ''), 10);
        $campania = bio_cut((string) ($ctx['campania'] ?? ''), 10);
        $hora = bio_norm_hora((string) ($ctx['hora'] ?? ''));
        if ($hora === '') {
            $hora = $ahora;
        }
        $movimiento = bio_cut((string) ($ctx['movimiento'] ?? 'salida'), 12);
        if ($movimiento !== 'regreso') {
            $movimiento = 'salida';
        }
        $tipoSalida = bio_cut((string) ($ctx['tipoSalida'] ?? 'definitiva'), 12);
        if ($tipoSalida !== 'temporal') {
            $tipoSalida = 'definitiva';
        }
        $grupoId = bio_cut((string) ($ctx['grupoId'] ?? ''), 80);
        $proveedor = bio_cut((string) ($ctx['proveedor'] ?? ''), 120);
        $motivo = bio_cut((string) ($ctx['motivo'] ?? ''), 60);
        $usuarioRegistrador = bio_cut((string) ($ctx['usuarioRegistrador'] ?? $tuser), 25);
        $fechaHoraRegistro = (string) ($ctx['fechaHoraRegistro'] ?? '');
        $stmt->bind_param(
            'sssssssssssss',
            $uuid,
            $fecha,
            $granja,
            $campania,
            $turno,
            $hora,
            $movimiento,
            $tipoSalida,
            $grupoId,
            $proveedor,
            $motivo,
            $usuarioRegistrador,
            $fechaHoraRegistro
        );
        if ($stmt->execute()) {
            $filas = 1;
        }
        $stmt->close();

        $det = $conn->prepare("INSERT INTO `{$detSal}` (`id`,`idCab`,`posicion`,`dni`,`nombre`)"
            . ' VALUES (?,?,?,?,?)');
        if ($det) {
            $posicion = 0;
            foreach (bio_dnis_normalizados($ctx['dnis'] ?? []) as $par) {
                $posicion++;
                $idDet = bio_nuevo_uuid();
                $det->bind_param(
                    'ssiss',
                    $idDet,
                    $uuid,
                    $posicion,
                    $par['dni'],
                    $par['nombre']
                );
                $det->execute();
            }
            $det->close();
        }

        return $filas;
    }

    if ($reporte === 'articulos') {
        if (!bio_ensure_articulos_tablas($conn)) {
            return 0;
        }
        $cabArt = bio_tabla_articulos_cab();
        $detArt = bio_tabla_articulos_det();
        $sql = "INSERT INTO `{$cabArt}` (`id`,`fecha`,`granja`,`campania`,`turno`,`dni`,`nombre`,"
            . '`imagenes`,`usuarioRegistrador`,`fechaHoraRegistro`)'
            . ' VALUES (?,?,?,?,?,?,?,?,?,?)';
        $stmt = $conn->prepare($sql);
        if (!$stmt) {
            return 0;
        }
        $uuid = bio_cut((string) ($ctx['uuid'] ?? ''), 36);
        $granja = bio_cut((string) ($ctx['granja'] ?? ''), 10);
        $campania = bio_cut((string) ($ctx['campania'] ?? ''), 10);
        $dni = bio_cut((string) ($ctx['dni'] ?? ''), 15);
        $nombrePersona = bio_cut((string) ($ctx['nombrePersona'] ?? ''), 120);
        $usuarioRegistrador = bio_cut((string) ($ctx['usuarioRegistrador'] ?? $tuser), 25);
        $fechaHoraRegistro = (string) ($ctx['fechaHoraRegistro'] ?? '');
        $stmt->bind_param(
            'ssssssssss',
            $uuid,
            $fecha,
            $granja,
            $campania,
            $turno,
            $dni,
            $nombrePersona,
            $imagenesCsv,
            $usuarioRegistrador,
            $fechaHoraRegistro
        );
        if ($stmt->execute()) {
            $filas = 1;
        }
        $stmt->close();

        $det = $conn->prepare(
            "INSERT INTO `{$detArt}` (`id`,`idCab`,`posicion`,`codigo`,`descripcion`,`permitido`,"
            . '`desinfectado`,`desinfectante`,`anomalia_permitido`,`agente_causal_permitido`,'
            . '`accion_permitido`,`anomalia_desinfeccion`,`agente_causal_desinfeccion`,`accion_desinfeccion`,`imagenes`)'
            . ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)'
        );
        if ($det) {
            $posicion = 0;
            foreach ((array) ($ctx['articulos'] ?? []) as $a) {
                if (!is_array($a)) {
                    continue;
                }
                $desc = trim((string) ($a['descripcion'] ?? ''));
                if ($desc === '') {
                    continue;
                }
                $posicion++;
                $idDet = bio_nuevo_uuid();
                $codigo = bio_cut((string) ($a['codigo'] ?? '99'), 10);
                $descripcion = bio_cut($desc, 120);
                $permitido = bio_ingresa_flag($a['permitido'] ?? true);
                $desinfectado = bio_ingresa_flag($a['desinfectado'] ?? true);
                $desinfectante = bio_cut((string) ($a['desinfectante'] ?? ''), 80);
                $anomaliaPerm = (string) ($a['anomalia_permitido'] ?? '');
                $efectoPerm = trim((string) ($a['efecto_permitido'] ?? ''));
                if ($efectoPerm !== '') {
                    $anomaliaPerm = trim($anomaliaPerm . ($anomaliaPerm !== '' ? "\n" : '') . 'Efecto: ' . $efectoPerm);
                }
                $agentePerm = bio_cut((string) ($a['agente_causal_permitido'] ?? ''), 255);
                $accionPerm = bio_cut((string) ($a['accion_permitido'] ?? ''), 255);
                $anomaliaDes = (string) ($a['anomalia_desinfeccion'] ?? '');
                $efectoDes = trim((string) ($a['efecto_desinfeccion'] ?? ''));
                if ($efectoDes !== '') {
                    $anomaliaDes = trim($anomaliaDes . ($anomaliaDes !== '' ? "\n" : '') . 'Efecto: ' . $efectoDes);
                }
                $agenteDes = bio_cut((string) ($a['agente_causal_desinfeccion'] ?? ''), 255);
                $accionDes = bio_cut((string) ($a['accion_desinfeccion'] ?? ''), 255);
                $imgsLinea = '';
                $imgsRaw = $a['imagenes'] ?? [];
                if (is_array($imgsRaw) && $imgsRaw !== []) {
                    $rutas = [];
                    foreach ($imgsRaw as $img) {
                        if (is_array($img)) {
                            $p = trim((string) ($img['path'] ?? $img['ruta'] ?? ''));
                        } else {
                            $p = trim((string) $img);
                        }
                        if ($p !== '') {
                            $rutas[] = $p;
                        }
                    }
                    $imgsLinea = implode(',', $rutas);
                }
                $det->bind_param(
                    'ssissiissssssss',
                    $idDet,
                    $uuid,
                    $posicion,
                    $codigo,
                    $descripcion,
                    $permitido,
                    $desinfectado,
                    $desinfectante,
                    $anomaliaPerm,
                    $agentePerm,
                    $accionPerm,
                    $anomaliaDes,
                    $agenteDes,
                    $accionDes,
                    $imgsLinea
                );
                $det->execute();
            }
            $det->close();
        }

        return $filas;
    }

    return 0;
}

function bio_ensure_salida_tablas(mysqli $conn): bool
{
    unset($conn);

    return true;
}

/** Normaliza un valor Sí/No (char(2) en las tablas legacy). */
function bio_fallo($valor): string
{
    $s = mb_strtolower(trim((string) $valor), 'UTF-8');
    $s = str_replace('í', 'i', $s);
    return in_array($s, ['si', 's', '1', 'true', 'yes', 'y'], true) ? 'Si' : 'No';
}
