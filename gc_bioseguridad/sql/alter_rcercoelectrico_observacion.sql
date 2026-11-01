-- Observaciones generales del cerco eléctrico (app móvil Flutter).
-- Mismo criterio que rfomites: el texto viaja en registro.observacion y se
-- guarda en cada fila de métrica del grupo (fecha + cencos + turno).
--
-- También se aplica con migracion_bioseguridad_app.php (condicional).

ALTER TABLE `rcercoelectrico`
  ADD COLUMN `observacion` VARCHAR(200) NOT NULL DEFAULT '' AFTER `descripcion`;
