-- Módulo Aulas UEB. No elimina ni modifica horarios existentes.
CREATE TABLE aula (
    id BIGINT NOT NULL AUTO_INCREMENT,
    codigo VARCHAR(32) NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    tipo VARCHAR(30) NOT NULL,
    edificio VARCHAR(80) NOT NULL,
    piso VARCHAR(20) NOT NULL,
    capacidad INT NOT NULL,
    activa BOOLEAN NOT NULL DEFAULT TRUE,
    observaciones VARCHAR(255) NULL,
    PRIMARY KEY (id),
    CONSTRAINT uk_aula_codigo UNIQUE (codigo),
    CONSTRAINT ck_aula_capacidad CHECK (capacidad > 0)
);

CREATE TABLE curso_tipo_aula (
    curso_id BIGINT NOT NULL PRIMARY KEY,
    tipo VARCHAR(30) NOT NULL,
    CONSTRAINT fk_tipo_aula_curso FOREIGN KEY (curso_id) REFERENCES curso(id)
);

CREATE TABLE sesion_aula (
    sesion_id BIGINT NOT NULL PRIMARY KEY,
    aula_id BIGINT NOT NULL,
    CONSTRAINT fk_sesion_aula_sesion FOREIGN KEY (sesion_id) REFERENCES sesion(id),
    CONSTRAINT fk_sesion_aula_aula FOREIGN KEY (aula_id) REFERENCES aula(id)
);
CREATE INDEX ix_sesion_aula_aula ON sesion_aula(aula_id);
