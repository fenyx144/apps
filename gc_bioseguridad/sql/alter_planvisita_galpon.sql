-- Galpones planificados en la visita (misma idea que ingreso: códigos separados por coma).
ALTER TABLE `san_fact_planvisita_cab`
  ADD COLUMN `galpon` varchar(120) NOT NULL DEFAULT '' AFTER `observacion`;
