,45<?php
declare(strict_types=1);

/**
 * Migración Bioseguridad — script único (repo  sanidad/flutter/bioseguridad/).
 *
 * URL: .../migracion_bioseguridad_app.php
 *      ?omitir_san_fact=1   solo ALTER rgarita / rcercoelectrico / rfomites
 *
 * Ingreso app  `san_fact_ingresogranja_cab`.`galpon` varchar(120): **línea 65**
 * (entre `numPersonas` y `areaProveedor` dentro del CREATE que empieza ~línea 57).
 */

header('Content-Type: text/plain; charset=utf-8');
include_once __DIR__ . '/../../../conexion_grs/conexion.php';

mysqli_report(MYSQLI_REPORT_OFF);
$conn = conectar_joya_mysqli();
if (!$conn) {
    echo 'ERROR conexion: ' . mysqli_connect_error() . "\n";
    exit(1);
}

/** @return list<string> */
function bio_app_alter_reportes_fisica(): array
{
    return [
        'ALTER TABLE `rgarita` ADD COLUMN `imagenes` TEXT NULL',
        'ALTER TABLE `rcercoelectrico` ADD COLUMN `imagenes` TEXT NULL',
        'ALTER TABLE `rfomites` ADD COLUMN `imagenes` TEXT NULL',
        'ALTER TABLE `rgarita` MODIFY COLUMN `descripcion` VARCHAR(200) NOT NULL',
        'ALTER TABLE `rgarita` MODIFY COLUMN `agentecausal` VARCHAR(200) NOT NULL',
        'ALTER TABLE `rcercoelectrico` MODIFY COLUMN `descripcion` VARCHAR(200) NOT NULL',
        'ALTER TABLE `rgarita` ADD COLUMN `instalacion` VARCHAR(20) NOT NULL DEFAULT \'Garita\'',
        'ALTER TABLE `rgarita` ADD COLUMN `bioseguridad` VARCHAR(30) NOT NULL DEFAULT \'Bioseguridad fisica\' AFTER `instalacion`',
        'ALTER TABLE `rgarita` DROP PRIMARY KEY, ADD PRIMARY KEY (`fecha`, `cencos`, `turno`, `numfiltro`, `instalacion`, `bioseguridad`)',
        'ALTER TABLE `rgarita` ADD COLUMN `uuid` VARCHAR(36) NOT NULL DEFAULT \'\'',
        'ALTER TABLE `rcercoelectrico` ADD COLUMN `uuid` VARCHAR(36) NOT NULL DEFAULT \'\'',
        'ALTER TABLE `rfomites` ADD COLUMN `uuid` VARCHAR(36) NOT NULL DEFAULT \'\'',
        'ALTER TABLE `rcercoelectrico` ADD COLUMN `observacion` VARCHAR(200) NOT NULL DEFAULT \'\' AFTER `descripcion`',
    ];
}

/** DROP + CREATE san_fact_* (control personal + plan visita). */
function bio_app_sentencias_san_fact(): array
{
    return [
        'DROP TABLE IF EXISTS `san_fact_ingresogranja_veh`',
        'DROP TABLE IF EXISTS `san_fact_ingresogranja_det`',
        'DROP TABLE IF EXISTS `san_fact_ingresogranja_cab`',
        'DROP TABLE IF EXISTS `san_fact_salidagranja_det`',
        'DROP TABLE IF EXISTS `san_fact_salidagranja_cab`',
        'DROP TABLE IF EXISTS `san_fact_planvisita_veh`',
        'DROP TABLE IF EXISTS `san_fact_planvisita_det`',
        'DROP TABLE IF EXISTS `san_fact_planvisita_cab`',

        'CREATE TABLE `san_fact_ingresogranja_cab` (
            `id` varchar(36) NOT NULL,
            `fecha` date NOT NULL,
            `granja` varchar(10) NOT NULL DEFAULT \'\',
            `campania` varchar(10) NOT NULL DEFAULT \'\',
            `turno` varchar(10) NOT NULL DEFAULT \'\',
            `hora` time NOT NULL,
            `numPersonas` int(11) NOT NULL DEFAULT 0,
            `galpon` varchar(120) NOT NULL DEFAULT \'\',
            `areaProveedor` varchar(10) NOT NULL DEFAULT \'\',
            `motivo` varchar(60) NOT NULL DEFAULT \'\',
            `observacion` varchar(200) NOT NULL DEFAULT \'\',
            `proveedor` varchar(120) NOT NULL DEFAULT \'\',
            `proveedorRuc` varchar(15) NOT NULL DEFAULT \'\',
            `planVisitaId` int(11) NOT NULL DEFAULT 0,
            `imagenes` text NULL,
            `usuarioRegistrador` varchar(25) NOT NULL DEFAULT \'\',
            `fechaHoraRegistro` datetime NULL DEFAULT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci',

        'CREATE TABLE `san_fact_ingresogranja_det` (
            `id` varchar(36) NOT NULL,
            `idCab` varchar(36) NOT NULL,
            `posicion` int(11) NOT NULL DEFAULT 1,
            `dni` varchar(15) NOT NULL,
            `nombre` varchar(60) NOT NULL DEFAULT \'\',
            PRIMARY KEY (`id`)
        ) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci',

        'CREATE TABLE `san_fact_ingresogranja_veh` (
            `id` varchar(36) NOT NULL,
            `idCab` varchar(36) NOT NULL,
            `posicion` int(11) NOT NULL DEFAULT 1,
            `placa` varchar(15) NOT NULL DEFAULT \'\',
            `ingresa` tinyint(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`)
        ) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci',

        'CREATE TABLE `san_fact_salidagranja_cab` (
            `id` varchar(36) NOT NULL,
            `fecha` date NOT NULL,
            `granja` varchar(10) NOT NULL DEFAULT \'\',
            `campania` varchar(10) NOT NULL DEFAULT \'\',
            `turno` varchar(10) NOT NULL DEFAULT \'\',
            `hora` time NOT NULL,
            `movimiento` varchar(12) NOT NULL DEFAULT \'salida\',
            `tipoSalida` varchar(12) NOT NULL DEFAULT \'definitiva\',
            `grupoId` varchar(80) NOT NULL DEFAULT \'\',
            `proveedor` varchar(120) NOT NULL DEFAULT \'\',
            `motivo` varchar(60) NOT NULL DEFAULT \'\',
            `usuarioRegistrador` varchar(25) NOT NULL DEFAULT \'\',
            `fechaHoraRegistro` datetime NULL DEFAULT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci',

        'CREATE TABLE `san_fact_salidagranja_det` (
            `id` varchar(36) NOT NULL,
            `idCab` varchar(36) NOT NULL,
            `posicion` int(11) NOT NULL DEFAULT 1,
            `dni` varchar(15) NOT NULL,
            `nombre` varchar(60) NOT NULL DEFAULT \'\',
            PRIMARY KEY (`id`)
        ) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci',

        'CREATE TABLE `san_fact_planvisita_cab` (
            `id` int(11) NOT NULL,
            `fecha` date NOT NULL,
            `granja` varchar(10) NOT NULL DEFAULT \'\',
            `campania` varchar(10) NOT NULL DEFAULT \'\',
            `numPersonas` int(11) NOT NULL DEFAULT 0,
            `proveedorRuc` varchar(15) NOT NULL DEFAULT \'\',
            `proveedor` varchar(120) NOT NULL DEFAULT \'\',
            `areaProveedor` varchar(10) NOT NULL DEFAULT \'\',
            `motivo` varchar(60) NOT NULL DEFAULT \'\',
            `observacion` varchar(200) NOT NULL DEFAULT \'\',
            `galpon` varchar(120) NOT NULL DEFAULT \'\',
            `usuarioRegistrador` varchar(25) NOT NULL DEFAULT \'\',
            `fechaHoraRegistro` datetime NULL DEFAULT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci',

        'CREATE TABLE `san_fact_planvisita_det` (
            `id` varchar(36) NOT NULL,
            `idCab` int(11) NOT NULL,
            `posicion` int(11) NOT NULL DEFAULT 1,
            `dni` varchar(15) NOT NULL,
            `nombre` varchar(60) NOT NULL DEFAULT \'\',
            PRIMARY KEY (`id`)
        ) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci',

        'CREATE TABLE `san_fact_planvisita_veh` (
            `id` varchar(36) NOT NULL,
            `idCab` int(11) NOT NULL,
            `posicion` int(11) NOT NULL DEFAULT 1,
            `placa` varchar(15) NOT NULL DEFAULT \'\',
            `ingresa` tinyint(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`)
        ) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci',
    ];
}

$omitirSanFact = isset($_GET['omitir_san_fact']) && (string) $_GET['omitir_san_fact'] !== '0';
$sentencias = bio_app_alter_reportes_fisica();
if (!$omitirSanFact) {
    $sentencias = array_merge($sentencias, bio_app_sentencias_san_fact());
} else {
    echo "(san_fact omitido: quitar ?omitir_san_fact=1)\n\n";
}

echo "Migración bioseguridad app\n==========================\n\n";

$i = 0;
foreach ($sentencias as $sql) {
    $i++;
    $titulo = preg_replace('/\s+/', ' ', strtok($sql, '(') ?: $sql);
    if ($conn->query($sql)) {
        echo $i . '. OK: ' . trim($titulo) . "\n";
    } else {
        echo $i . '. ERROR: ' . trim($titulo) . ' - ' . $conn->error . "\n";
    }
}

$conn->close();
