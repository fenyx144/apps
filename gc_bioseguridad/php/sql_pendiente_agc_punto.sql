-- Ubicación de la anomalía de bioseguridad.
-- Granja y campaña ya se guardan. El galpón, cuando existe, va en `galpon`.
-- El punto de control (Garita, tranquera, pozo, etc.) no tiene columna:
-- rgarita.instalacion ya lo guarda. Esta columna lo copia a san_agentes_causales.
-- No ejecutar desde la app. Aplicar a mano en ciajoya.

ALTER TABLE `san_agentes_causales`
  ADD COLUMN `punto` varchar(30) NOT NULL DEFAULT '' AFTER `galpon`;
