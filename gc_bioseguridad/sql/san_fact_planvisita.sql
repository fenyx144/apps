-- Planificación de visitas (portal; id entero del portal, no UUID de app).

DROP TABLE IF EXISTS `san_fact_planvisita_veh`;
DROP TABLE IF EXISTS `san_fact_planvisita_det`;
DROP TABLE IF EXISTS `san_fact_planvisita_cab`;

CREATE TABLE `san_fact_planvisita_cab` (
    `id` int(11) NOT NULL,
    `fecha` date NOT NULL,
    `granja` varchar(10) NOT NULL DEFAULT '',
    `campania` varchar(10) NOT NULL DEFAULT '',
    `numPersonas` int(11) NOT NULL DEFAULT 0,
    `proveedorRuc` varchar(15) NOT NULL DEFAULT '',
    `proveedor` varchar(120) NOT NULL DEFAULT '',
    `areaProveedor` varchar(10) NOT NULL DEFAULT '',
    `motivo` varchar(60) NOT NULL DEFAULT '',
    `observacion` varchar(200) NOT NULL DEFAULT '',
    `galpon` varchar(120) NOT NULL DEFAULT '',
    `usuarioRegistrador` varchar(25) NOT NULL DEFAULT '',
    `fechaHoraRegistro` datetime NULL DEFAULT NULL,
    PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `san_fact_planvisita_det` (
    `id` varchar(36) NOT NULL,
    `idCab` int(11) NOT NULL,
    `posicion` int(11) NOT NULL DEFAULT 1,
    `dni` varchar(15) NOT NULL,
    `nombre` varchar(60) NOT NULL DEFAULT '',
    PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;

CREATE TABLE `san_fact_planvisita_veh` (
    `id` varchar(36) NOT NULL,
    `idCab` int(11) NOT NULL,
    `posicion` int(11) NOT NULL DEFAULT 1,
    `placa` varchar(15) NOT NULL DEFAULT '',
    `ingresa` tinyint(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci;
