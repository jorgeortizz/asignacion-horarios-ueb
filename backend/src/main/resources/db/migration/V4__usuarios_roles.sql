-- Modelo de cuentas UEB. Migración aditiva; V1, V2 y V3 permanecen intactas.
-- No crea cuentas ni contraseñas; solo instala los cuatro roles oficiales.
-- Las cuentas se provisionarán en una etapa posterior con PasswordEncoder.

CREATE TABLE rol (
    id BIGINT NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(32) COLLATE utf8mb4_bin NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    CONSTRAINT pk_rol PRIMARY KEY (id),
    CONSTRAINT uk_rol_codigo UNIQUE (codigo),
    CONSTRAINT ck_rol_codigo CHECK (codigo IN
      ('COMITE_TACTICO','COORDINACION_ACADEMICA','DOCENTE','ESTUDIANTE'))
) ENGINE = InnoDB;

CREATE TABLE usuario (
    id BIGINT NOT NULL AUTO_INCREMENT,
    identificador VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    activo TINYINT(1) NOT NULL DEFAULT 1,
    rol_id BIGINT NOT NULL,
    docente_id BIGINT NULL,
    CONSTRAINT pk_usuario PRIMARY KEY (id),
    CONSTRAINT uk_usuario_identificador UNIQUE (identificador),
    CONSTRAINT uk_usuario_docente UNIQUE (docente_id),
    CONSTRAINT fk_usuario_rol FOREIGN KEY (rol_id) REFERENCES rol(id)
      ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_usuario_docente FOREIGN KEY (docente_id) REFERENCES docente(id)
      ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_usuario_identificador CHECK (CHAR_LENGTH(TRIM(identificador)) > 0),
    CONSTRAINT ck_usuario_activo CHECK (activo IN (0,1))
) ENGINE = InnoDB;

INSERT INTO rol (codigo, nombre) VALUES
  ('COMITE_TACTICO', 'Comité Táctico'),
  ('COORDINACION_ACADEMICA', 'Coordinación Académica'),
  ('DOCENTE', 'Docente'),
  ('ESTUDIANTE', 'Estudiante');
