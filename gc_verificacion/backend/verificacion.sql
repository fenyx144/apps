-- Verificación facial de ingreso: tablas nuevas.
-- Ejecutar en la base JOYA (la misma de usuario y regnewdispositivosandroid).
-- No modifica ninguna tabla existente. Las personas son las plantillas
-- enroladas: no depende de ningún otro módulo.

CREATE TABLE IF NOT EXISTS veri_plantilla (
  dni CHAR(8) NOT NULL,
  nombre VARCHAR(120) NOT NULL DEFAULT '',
  vector MEDIUMTEXT NOT NULL,
  miniatura MEDIUMTEXT NULL,
  modelo VARCHAR(40) NOT NULL DEFAULT 'arcface-w600k_mbf',
  estado CHAR(1) NOT NULL DEFAULT 'A',
  usuario VARCHAR(30) NOT NULL DEFAULT '',
  tidandroid VARCHAR(80) NOT NULL DEFAULT '',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (dni),
  KEY ix_veri_plantilla_estado (estado)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS veri_evento (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  uuid CHAR(36) NOT NULL,
  dni CHAR(8) NOT NULL DEFAULT '',
  fecha DATE NOT NULL,
  hora TIME NOT NULL,
  resultado CHAR(1) NOT NULL DEFAULT 'A',
  similitud DECIMAL(5,4) NULL,
  modo VARCHAR(3) NOT NULL DEFAULT '1N',
  tidandroid VARCHAR(80) NOT NULL DEFAULT '',
  usuario VARCHAR(30) NOT NULL DEFAULT '',
  created_app DATETIME NULL,
  dia_serv DATE NOT NULL,
  hora_serv TIME NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_veri_evento_uuid (uuid),
  KEY ix_veri_evento_dni_fecha (dni, fecha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS veri_nomina_snap (
  dni CHAR(8) NOT NULL,
  huella CHAR(32) NOT NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (dni)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS veri_nomina_cambio (
  seq BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dni CHAR(8) NOT NULL,
  accion CHAR(1) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (seq),
  KEY ix_veri_nomina_cambio_dni (dni)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Control de versión de la app (opcional; sin estas filas la app trabaja
-- igual pero sin avisos de actualización). Descomentar para activar:
-- INSERT INTO g_app (tcod, tdescripcion) VALUES ('PROD_VERIFICACION', 'Verificación facial de ingreso');
-- INSERT INTO g_app_det (tcod, tversion, tdescripcion, testado, tpublicacion, tdiasgracia)
-- VALUES ('PROD_VERIFICACION', '1.0.0', 'Piloto', 'A', CURDATE(), 4);

CREATE TABLE IF NOT EXISTS veri_enrolador (
  usuario VARCHAR(30) NOT NULL,
  estado CHAR(1) NOT NULL DEFAULT 'A',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (usuario)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Autoriza al operador que enrolará (reemplaza CODIGO por su usuario):
-- INSERT INTO veri_enrolador (usuario) VALUES ('CODIGO');
