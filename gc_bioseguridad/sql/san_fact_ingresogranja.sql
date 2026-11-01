-- Control de personal ingreso/salida (san_fact_*). Entorno prueba: DROP + CREATE.

DROP TABLE IF EXISTS `san_fact_ingresogranja_veh`;
DROP TABLE IF EXISTS `san_fact_ingresogranja_det`;
DROP TABLE IF EXISTS `san_fact_ingresogranja_cab`;
DROP TABLE IF EXISTS `san_fact_salidagranja_det`;
DROP TABLE IF EXISTS `san_fact_salidagranja_cab`;

CREATE TABLE `san_fact_ingresogranja_cab` (
    `id` varchar(36) NOT NULL,
    `fecha` date NOT NULL,
    `granja` varchar(10) NOT NULL DEFAULT '',
    `campania` varchar(10) NOT NULL DEFAULT '',
    `turno` varchar(10) NOT NULL DEFAULT '',
    `hora` time NOT NULL,
    `numPersonas` int(11) NOT NULL DEFAULT 0,
    `galpon` varchar(120) NOT NULL DEFAULT '',
    `areaProveedor` varchar(10) NOT NULL DEFAULT '',
    `motivo` varchar(60) NOT NULL DEFAULT '',
    `observacion` varchar(200) NOT NULL DEFAULT '',
    `proveedor` varchar(120) NOT NULL DEFAULT '',
    `proveedorRuc` varchar(15) NOT NULL DEFAULT '',
    `planVisitaId` int(11) NOT NULL DEFAULT 0,
    `imagenes` text NULL,
    `usuarioRegistrador` varchar(25) NOT NULL DEFAULT '',
    `fechaHoraRegistro` datetime NULL DEFAULT NULL,
    PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `san_fact_ingresogranja_det` (
    `id` varchar(36) NOT NULL,
    `idCab` varchar(36) NOT NULL,
    `posicion` int(11) NOT NULL DEFAULT 1,
    `dni` varchar(15) NOT NULL,
    `nombre` varchar(60) NOT NULL DEFAULT '',
    PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `san_fact_ingresogranja_veh` (
    `id` varchar(36) NOT NULL,
    `idCab` varchar(36) NOT NULL,
    `posicion` int(11) NOT NULL DEFAULT 1,
    `placa` varchar(15) NOT NULL DEFAULT '',
    `ingresa` tinyint(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `san_fact_salidagranja_cab` (
    `id` varchar(36) NOT NULL,
    `fecha` date NOT NULL,
    `granja` varchar(10) NOT NULL DEFAULT '',
    `campania` varchar(10) NOT NULL DEFAULT '',
    `turno` varchar(10) NOT NULL DEFAULT '',
    `hora` time NOT NULL,
    `movimiento` varchar(12) NOT NULL DEFAULT 'salida',
    `tipoSalida` varchar(12) NOT NULL DEFAULT 'definitiva',
    `grupoId` varchar(80) NOT NULL DEFAULT '',
    `proveedor` varchar(120) NOT NULL DEFAULT '',
    `motivo` varchar(60) NOT NULL DEFAULT '',
    `usuarioRegistrador` varchar(25) NOT NULL DEFAULT '',
    `fechaHoraRegistro` datetime NULL DEFAULT NULL,
    PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `san_fact_salidagranja_det` (
    `id` varchar(36) NOT NULL,
    `idCab` varchar(36) NOT NULL,
    `posicion` int(11) NOT NULL DEFAULT 1,
    `dni` varchar(15) NOT NULL,
    `nombre` varchar(60) NOT NULL DEFAULT '',
    PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;
