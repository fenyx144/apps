-- NO ejecutar desde la app ni desde migracion_bioseguridad_app.php.
-- Aplicar a mano en el servidor si se quieren las columnas tipadas.
-- Hoy la doble escritura ya entra con las columnas existentes
-- (tareaKey = bioseguridad_fisica|quimica|biologica, archivo = rgarita:<uuid>).
-- InnoDB hace falta para que el rollback de la transacción sea real
-- (rgarita y esta tabla suelen ser MyISAM).

ALTER TABLE `san_agentes_causales`
  ADD COLUMN `uuid` varchar(36) NOT NULL DEFAULT '',
  ADD COLUMN `rgarita_id` int unsigned DEFAULT NULL,
  ADD COLUMN `fecha` date DEFAULT NULL,
  ADD COLUMN `cencos` varchar(20) NOT NULL DEFAULT '',
  ADD COLUMN `turno` varchar(10) NOT NULL DEFAULT '',
  ADD COLUMN `instalacion` varchar(20) NOT NULL DEFAULT '',
  ADD COLUMN `bioseguridad` varchar(30) NOT NULL DEFAULT '',
  ADD COLUMN `fisico` tinyint(1) NOT NULL DEFAULT 0,
  ADD COLUMN `quimico` tinyint(1) NOT NULL DEFAULT 0,
  ADD COLUMN `biologico` tinyint(1) NOT NULL DEFAULT 0,
  ADD COLUMN `numfiltro` int NOT NULL DEFAULT 0,
  ADD COLUMN `anomalia` varchar(30) NOT NULL DEFAULT '',
  ADD COLUMN `hora` varchar(8) NOT NULL DEFAULT '',
  ADD COLUMN `descripcion` varchar(200) NOT NULL DEFAULT '',
  ADD COLUMN `agentecausal` varchar(200) NOT NULL DEFAULT '',
  ADD COLUMN `imagenes` text NULL,
  ADD KEY `idx_agc_uuid` (`uuid`);

ALTER TABLE `rgarita` ENGINE=InnoDB;
ALTER TABLE `san_agentes_causales` ENGINE=InnoDB;
