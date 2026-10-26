-- =============================================================================
-- V1__esquema_inicial.sql  (migración Flyway)
-- Esquema de la primera versión de la Fase 2 (entregado el 2026-10-21),
-- sin DROP DATABASE / CREATE DATABASE / USE: Flyway ejecuta sobre el esquema
-- configurado en spring.flyway / spring.datasource.
-- NO EDITAR: una migración aplicada no se modifica; los cambios van en V2+.
-- =============================================================================

SET NAMES utf8mb4;
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,ONLY_FULL_GROUP_BY';

-- -----------------------------------------------------------------------------
-- 1. periodo_academico  (entidad principal: PeriodoAcademico)
--    Guarda el semestre y, como atributos propios, los parámetros
--    institucionales configurables que se aplican a ese periodo (RF09, EF08).
--    Los valores DEFAULT son las cifras iniciales documentadas (Tabla 10 y
--    Sección 4.4 del informe); cada periodo conserva sus propios valores, de
--    modo que cambiar una cifra es un UPDATE, no un cambio de código.
-- -----------------------------------------------------------------------------
CREATE TABLE periodo_academico (
  id                   BIGINT        NOT NULL AUTO_INCREMENT,
  nombre               VARCHAR(20)   NOT NULL COMMENT 'Código del periodo, p. ej. 2026-2',
  fecha_inicio         DATE          NOT NULL,
  fecha_fin            DATE          NOT NULL,
  -- Franja institucional
  hora_inicio_semana   TIME          NOT NULL DEFAULT '07:00:00' COMMENT 'Inicio de la franja de lunes a viernes',
  hora_fin_semana      TIME          NOT NULL DEFAULT '22:00:00' COMMENT 'Fin de la franja de lunes a viernes',
  hora_inicio_sabado   TIME          NOT NULL DEFAULT '07:00:00',
  hora_fin_sabado      TIME          NOT NULL DEFAULT '13:00:00',
  -- Bloqueo de almuerzo (aplica todos los días)
  almuerzo_inicio      TIME          NOT NULL DEFAULT '12:00:00',
  almuerzo_fin         TIME          NOT NULL DEFAULT '13:00:00',
  -- Cuadrícula de bloques fijos y frecuencia
  duracion_bloque_min  SMALLINT      NOT NULL DEFAULT 120 COMMENT 'Duración del bloque fijo en minutos',
  max_sesiones_semana  TINYINT       NOT NULL DEFAULT 4   COMMENT 'Máximo de sesiones semanales por curso',
  -- Cupos
  cupo_maximo_base     SMALLINT      NOT NULL DEFAULT 40  COMMENT 'Valor inicial de grupo.cupo_maximo',
  tolerancia_cupo_pct  DECIMAL(5,2)  NOT NULL DEFAULT 10.00 COMMENT 'Tolerancia sobre el cupo máximo, en %',
  cupo_minimo          SMALLINT      NOT NULL DEFAULT 10  COMMENT 'Valor inicial de grupo.cupo_minimo',
  CONSTRAINT pk_periodo_academico PRIMARY KEY (id),
  CONSTRAINT uk_periodo_academico_nombre UNIQUE (nombre),
  CONSTRAINT ck_periodo_academico_nombre      CHECK (CHAR_LENGTH(TRIM(nombre)) > 0),
  CONSTRAINT ck_periodo_academico_fechas      CHECK (fecha_fin > fecha_inicio),
  CONSTRAINT ck_periodo_academico_franja_sem  CHECK (hora_fin_semana > hora_inicio_semana),
  CONSTRAINT ck_periodo_academico_franja_sab  CHECK (hora_fin_sabado > hora_inicio_sabado),
  CONSTRAINT ck_periodo_academico_almuerzo    CHECK (almuerzo_fin > almuerzo_inicio),
  CONSTRAINT ck_periodo_academico_duracion    CHECK (duracion_bloque_min BETWEEN 30 AND 240),
  CONSTRAINT ck_periodo_academico_max_ses     CHECK (max_sesiones_semana BETWEEN 1 AND 10),
  CONSTRAINT ck_periodo_academico_cupo_max    CHECK (cupo_maximo_base > 0),
  CONSTRAINT ck_periodo_academico_tolerancia  CHECK (tolerancia_cupo_pct BETWEEN 0 AND 100),
  CONSTRAINT ck_periodo_academico_cupo_min    CHECK (cupo_minimo >= 0 AND cupo_minimo <= cupo_maximo_base)
) ENGINE = InnoDB COMMENT = 'Entidad PeriodoAcademico: semestre y parámetros institucionales';

-- -----------------------------------------------------------------------------
-- 2. docente  (entidad principal: Docente)
--    tipo_vinculacion es un atributo enumerado (Sección 5.3.1), no una entidad.
--    Valores almacenados = nombres del enum Java TipoVinculacion:
--      TC = tiempo completo · TRES_CUARTOS = 3/4 · MEDIO_TIEMPO = 1/2 ·
--      CUARTO_TIEMPO = 1/4
-- -----------------------------------------------------------------------------
CREATE TABLE docente (
  id                BIGINT        NOT NULL AUTO_INCREMENT,
  nombre            VARCHAR(150)  NOT NULL,
  tipo_vinculacion  VARCHAR(15)   NOT NULL,
  CONSTRAINT pk_docente PRIMARY KEY (id),
  CONSTRAINT ck_docente_nombre CHECK (CHAR_LENGTH(TRIM(nombre)) > 0),
  CONSTRAINT ck_docente_tipo_vinculacion
    CHECK (tipo_vinculacion IN ('TC', 'TRES_CUARTOS', 'MEDIO_TIEMPO', 'CUARTO_TIEMPO')),
  INDEX idx_docente_nombre (nombre)
) ENGINE = InnoDB COMMENT = 'Entidad Docente';

-- -----------------------------------------------------------------------------
-- 3. docente_especialidad  (ESTRUCTURA AUXILIAR, no es entidad de dominio)
--    RF01 pide registrar especialidades. Una columna con valores separados
--    por comas violaría la 1FN; esta tabla es una colección de valores del
--    docente (@ElementCollection en JPA): no tiene identidad propia ni
--    relaciones con otras entidades. ON DELETE CASCADE es seguro porque
--    estos valores no existen sin su docente y no forman parte del historial
--    de horarios.
-- -----------------------------------------------------------------------------
CREATE TABLE docente_especialidad (
  docente_id    BIGINT        NOT NULL,
  especialidad  VARCHAR(100)  NOT NULL,
  CONSTRAINT pk_docente_especialidad PRIMARY KEY (docente_id, especialidad),
  CONSTRAINT ck_docente_especialidad_valor CHECK (CHAR_LENGTH(TRIM(especialidad)) > 0),
  CONSTRAINT fk_docente_especialidad_docente
    FOREIGN KEY (docente_id) REFERENCES docente (id)
    ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE = InnoDB COMMENT = 'Auxiliar: especialidades del docente (colección de valores)';

-- -----------------------------------------------------------------------------
-- 4. restriccion_horaria  (entidad principal: RestriccionHoraria)
--    dia: 1 = lunes ... 6 = sábado (numeración ISO-8601, igual a
--         java.time.DayOfWeek.getValue()). El domingo no es día lectivo.
--    tipo: FIRME (bloquea) | PREFERENCIA (solo orienta / advierte).
--    sentido (PROPUESTA TÉCNICA, pendiente de validación):
--         DISPONIBLE    -> franja en la que el docente SÍ puede dictar.
--         NO_DISPONIBLE -> franja en la que el docente NO puede dictar.
--      Se hace explícito para no fijar una convención irreversible.
--      Interpretación (la aplica el backend, Tabla 19 revisión 4):
--        * Sin restricciones registradas: disponible en toda la franja.
--        * Con al menos una FIRME/DISPONIBLE: la sesión debe caer
--          completa dentro de alguna de esas franjas.
--        * FIRME/NO_DISPONIBLE: la sesión no puede solaparse con la franja.
--        * PREFERENCIA: el generador intenta respetarla; si no, advierte.
--    ON DELETE CASCADE desde docente: las restricciones son parte del
--    docente; borrar un docente con grupos sigue bloqueado por fk_grupo_docente,
--    así que el historial de horarios no puede perderse por esta vía.
-- -----------------------------------------------------------------------------
CREATE TABLE restriccion_horaria (
  id           BIGINT       NOT NULL AUTO_INCREMENT,
  docente_id   BIGINT       NOT NULL,
  dia          TINYINT      NOT NULL COMMENT '1=lunes ... 6=sábado',
  hora_inicio  TIME         NOT NULL,
  hora_fin     TIME         NOT NULL,
  tipo         VARCHAR(12)  NOT NULL COMMENT 'FIRME | PREFERENCIA',
  sentido      VARCHAR(15)  NOT NULL COMMENT 'DISPONIBLE | NO_DISPONIBLE (propuesta)',
  CONSTRAINT pk_restriccion_horaria PRIMARY KEY (id),
  CONSTRAINT uk_restriccion_horaria_franja
    UNIQUE (docente_id, dia, hora_inicio, hora_fin, tipo, sentido),
  CONSTRAINT ck_restriccion_horaria_dia   CHECK (dia BETWEEN 1 AND 6),
  CONSTRAINT ck_restriccion_horaria_horas CHECK (hora_fin > hora_inicio),
  CONSTRAINT ck_restriccion_horaria_tipo  CHECK (tipo IN ('FIRME', 'PREFERENCIA')),
  CONSTRAINT ck_restriccion_horaria_sentido CHECK (sentido IN ('DISPONIBLE', 'NO_DISPONIBLE')),
  CONSTRAINT fk_restriccion_horaria_docente
    FOREIGN KEY (docente_id) REFERENCES docente (id)
    ON DELETE CASCADE ON UPDATE RESTRICT,
  INDEX idx_restriccion_horaria_docente_dia (docente_id, dia, hora_inicio)
) ENGINE = InnoDB COMMENT = 'Entidad RestriccionHoraria';

-- -----------------------------------------------------------------------------
-- 5. curso  (entidad principal: Curso)
--    sesiones_semanales: el CHECK impone solo el rango físico (1 a 10); el
--      máximo operativo (4 al inicio) es periodo_academico.max_sesiones_semana
--      y lo valida el backend (EF02), porque un CHECK no puede leer otra tabla.
--    duracion_sesion_min: 120 min según RF02.
--    codigo (PROPUESTA): la hoja actual identifica los cursos por código;
--      es opcional y único cuando existe.
-- -----------------------------------------------------------------------------
CREATE TABLE curso (
  id                      BIGINT        NOT NULL AUTO_INCREMENT,
  codigo                  VARCHAR(20)   NULL COMMENT 'Código institucional del curso (propuesta, opcional)',
  nombre                  VARCHAR(150)  NOT NULL,
  sesiones_semanales      TINYINT       NOT NULL,
  duracion_sesion_min     SMALLINT      NOT NULL DEFAULT 120,
  necesita_aula_especial  BOOLEAN       NOT NULL DEFAULT FALSE,
  CONSTRAINT pk_curso PRIMARY KEY (id),
  CONSTRAINT uk_curso_codigo UNIQUE (codigo),
  CONSTRAINT ck_curso_nombre    CHECK (CHAR_LENGTH(TRIM(nombre)) > 0),
  CONSTRAINT ck_curso_sesiones  CHECK (sesiones_semanales BETWEEN 1 AND 10),
  CONSTRAINT ck_curso_duracion  CHECK (duracion_sesion_min BETWEEN 30 AND 240),
  INDEX idx_curso_nombre (nombre),
  INDEX idx_curso_aula_especial (necesita_aula_especial)
) ENGINE = InnoDB COMMENT = 'Entidad Curso';

-- -----------------------------------------------------------------------------
-- 6. grupo  (entidad principal: Grupo)
--    Figura 4: Curso 1 -- 1..* Grupo ; Docente 1 -- 0..* Grupo.
--    docente_id NOT NULL porque la multiplicidad del lado Grupo hacia Docente
--    es 1 (un grupo siempre tiene docente).
--    periodo_id (PROPUESTA ESTRUCTURAL, pendiente de confirmación):
--      sin él no se puede saber a qué semestre pertenecen los inscritos ni
--      qué grupos debe programar el generador en un periodo, y los grupos de
--      semestres distintos quedarían mezclados (RF10, ENF05).
--    codigo (PROPUESTA): etiqueta del grupo dentro del curso ("01", "02").
--    cupo_maximo / cupo_minimo: sin DEFAULT a propósito; el backend los
--      inicializa desde periodo_academico (cupo_maximo_base, cupo_minimo),
--      para que las cifras no queden fijas en el esquema ni en el código.
--    El límite operativo (cupo_maximo * (1 + tolerancia)) NO se persiste:
--      se calcula (vista v_grupo_cupo) porque depende de la tolerancia
--      vigente del periodo.
-- -----------------------------------------------------------------------------
CREATE TABLE grupo (
  id           BIGINT       NOT NULL AUTO_INCREMENT,
  periodo_id   BIGINT       NOT NULL COMMENT 'Propuesta: periodo al que pertenece el grupo',
  curso_id     BIGINT       NOT NULL,
  docente_id   BIGINT       NOT NULL,
  codigo       VARCHAR(10)  NOT NULL COMMENT 'Propuesta: identificador del grupo dentro del curso',
  cupo_maximo  SMALLINT     NOT NULL,
  cupo_minimo  SMALLINT     NOT NULL,
  inscritos    SMALLINT     NOT NULL DEFAULT 0,
  CONSTRAINT pk_grupo PRIMARY KEY (id),
  CONSTRAINT uk_grupo_periodo_curso_codigo UNIQUE (periodo_id, curso_id, codigo),
  CONSTRAINT ck_grupo_codigo      CHECK (CHAR_LENGTH(TRIM(codigo)) > 0),
  CONSTRAINT ck_grupo_cupo_maximo CHECK (cupo_maximo > 0),
  CONSTRAINT ck_grupo_cupo_minimo CHECK (cupo_minimo >= 0),
  CONSTRAINT ck_grupo_cupos       CHECK (cupo_minimo <= cupo_maximo),
  CONSTRAINT ck_grupo_inscritos   CHECK (inscritos >= 0),
  CONSTRAINT fk_grupo_periodo_academico
    FOREIGN KEY (periodo_id) REFERENCES periodo_academico (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_grupo_curso
    FOREIGN KEY (curso_id) REFERENCES curso (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_grupo_docente
    FOREIGN KEY (docente_id) REFERENCES docente (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  INDEX idx_grupo_curso_periodo (curso_id, periodo_id),
  INDEX idx_grupo_docente_periodo (docente_id, periodo_id)
) ENGINE = InnoDB COMMENT = 'Entidad Grupo';

-- -----------------------------------------------------------------------------
-- 7. horario  (entidad principal: Horario)
--    Figura 4: PeriodoAcademico 1 -- 1..* Horario. Se admiten varios horarios
--    por periodo (propuestas alternativas, borradores y publicado).
--    estado: solo BORRADOR | PUBLICADO (Sección 5.3.1).
--    fecha_creacion / fecha_publicacion (PROPUESTA): distinguen propuestas
--      del mismo periodo y fechan la publicación. No son una bitácora.
--    version (PROPUESTA): control de concurrencia optimista (@Version).
-- -----------------------------------------------------------------------------
CREATE TABLE horario (
  id                 BIGINT       NOT NULL AUTO_INCREMENT,
  periodo_id         BIGINT       NOT NULL,
  estado             VARCHAR(10)  NOT NULL DEFAULT 'BORRADOR',
  fecha_creacion     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_publicacion  DATETIME     NULL,
  version            INT          NOT NULL DEFAULT 0,
  CONSTRAINT pk_horario PRIMARY KEY (id),
  CONSTRAINT ck_horario_estado CHECK (estado IN ('BORRADOR', 'PUBLICADO')),
  CONSTRAINT ck_horario_publicacion CHECK (estado = 'BORRADOR' OR fecha_publicacion IS NOT NULL),
  CONSTRAINT ck_horario_version CHECK (version >= 0),
  CONSTRAINT fk_horario_periodo_academico
    FOREIGN KEY (periodo_id) REFERENCES periodo_academico (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  INDEX idx_horario_periodo_estado (periodo_id, estado)
) ENGINE = InnoDB COMMENT = 'Entidad Horario';

-- Regla pendiente de decisión del Comité (NO activada): un solo horario
-- PUBLICADO por periodo. Si se aprueba, ejecutar:
--   ALTER TABLE horario
--     ADD COLUMN periodo_publicado BIGINT
--       GENERATED ALWAYS AS (IF(estado = 'PUBLICADO', periodo_id, NULL)) STORED,
--     ADD CONSTRAINT uk_horario_un_publicado_por_periodo UNIQUE (periodo_publicado);

-- -----------------------------------------------------------------------------
-- 8. sesion  (entidad principal: Sesion)
--    Figura 4: Grupo 1 -- 1..* Sesion ; Horario 1 -- 1..* Sesion.
--    Bloque = (dia, hora_inicio, hora_fin), intervalo semiabierto
--    [hora_inicio, hora_fin). Se guarda la hora real y no un número de
--    bloque, para que el historial no cambie de significado si mañana cambia
--    la franja o el almuerzo. hora_fin se guarda (aunque sea derivable de la
--    duración del curso) para que cada sesión histórica sea autocontenida y
--    los solapamientos se consulten con una comparación simple; el trigger
--    trg_sesion_* garantiza que coincida con curso.duracion_sesion_min.
--    No se copian docente ni curso: se obtienen por grupo_id.
-- -----------------------------------------------------------------------------
CREATE TABLE sesion (
  id           BIGINT   NOT NULL AUTO_INCREMENT,
  horario_id   BIGINT   NOT NULL,
  grupo_id     BIGINT   NOT NULL,
  dia          TINYINT  NOT NULL COMMENT '1=lunes ... 6=sábado',
  hora_inicio  TIME     NOT NULL,
  hora_fin     TIME     NOT NULL,
  CONSTRAINT pk_sesion PRIMARY KEY (id),
  CONSTRAINT uk_sesion_horario_grupo_casilla UNIQUE (horario_id, grupo_id, dia, hora_inicio),
  CONSTRAINT ck_sesion_dia   CHECK (dia BETWEEN 1 AND 6),
  CONSTRAINT ck_sesion_horas CHECK (hora_fin > hora_inicio),
  CONSTRAINT fk_sesion_horario
    FOREIGN KEY (horario_id) REFERENCES horario (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_sesion_grupo
    FOREIGN KEY (grupo_id) REFERENCES grupo (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  INDEX idx_sesion_horario_casilla (horario_id, dia, hora_inicio),
  INDEX idx_sesion_grupo_horario (grupo_id, horario_id)
) ENGINE = InnoDB COMMENT = 'Entidad Sesion';

-- =============================================================================
-- REGLAS QUE LA BASE DE DATOS GARANTIZA MEDIANTE TRIGGERS
-- Son una red de seguridad: el backend valida primero y explica el motivo
-- al usuario (Tabla 19). Los triggers solo impiden que un error del backend
-- o una carga manual deje datos que rompan reglas firmes y simples.
-- Lo que NO hacen (queda en Spring Boot): choque de docente, disponibilidad
-- y preferencias del docente, días consecutivos, frecuencia completa,
-- alineación con la cuadrícula de bloques, cupos y publicación.
-- Código de error: SQLSTATE '45000' (MySQL errno 1644) con prefijo [BD-xx].
-- =============================================================================

DELIMITER $$

CREATE PROCEDURE sp_validar_sesion (
  IN p_horario_id   BIGINT,
  IN p_grupo_id     BIGINT,
  IN p_dia          TINYINT,
  IN p_hora_inicio  TIME,
  IN p_hora_fin     TIME
)
  READS SQL DATA
  COMMENT 'Valida coherencia de periodo, duración, franja y almuerzo de una sesión'
BEGIN
  DECLARE v_periodo_horario BIGINT;
  DECLARE v_periodo_grupo   BIGINT;
  DECLARE v_duracion_min    SMALLINT;
  DECLARE v_franja_ini      TIME;
  DECLARE v_franja_fin      TIME;
  DECLARE v_alm_ini         TIME;
  DECLARE v_alm_fin         TIME;

  SELECT periodo_id INTO v_periodo_horario FROM horario WHERE id = p_horario_id;

  SELECT g.periodo_id, c.duracion_sesion_min
    INTO v_periodo_grupo, v_duracion_min
    FROM grupo g JOIN curso c ON c.id = g.curso_id
   WHERE g.id = p_grupo_id;

  -- Si el horario o el grupo no existen, se deja actuar a la clave foránea
  -- (error 1452), que es el mensaje correcto para ese caso.
  IF v_periodo_horario IS NOT NULL AND v_periodo_grupo IS NOT NULL THEN

    IF v_periodo_horario <> v_periodo_grupo THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '[BD-01] La sesión une un grupo y un horario de periodos académicos distintos.';
    END IF;

    IF TIME_TO_SEC(TIMEDIFF(p_hora_fin, p_hora_inicio)) <> v_duracion_min * 60 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '[BD-02] La duración de la sesión no coincide con la duración del curso.';
    END IF;

    SELECT IF(p_dia = 6, hora_inicio_sabado, hora_inicio_semana),
           IF(p_dia = 6, hora_fin_sabado,    hora_fin_semana),
           almuerzo_inicio, almuerzo_fin
      INTO v_franja_ini, v_franja_fin, v_alm_ini, v_alm_fin
      FROM periodo_academico
     WHERE id = v_periodo_horario;

    IF p_hora_inicio < v_franja_ini OR p_hora_fin > v_franja_fin THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '[BD-03] La sesión excede la franja horaria institucional del periodo.';
    END IF;

    IF p_hora_inicio < v_alm_fin AND p_hora_fin > v_alm_ini THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '[BD-04] La sesión se solapa con el bloqueo de almuerzo.';
    END IF;

  END IF;
END$$

CREATE TRIGGER trg_sesion_bi
BEFORE INSERT ON sesion
FOR EACH ROW
BEGIN
  CALL sp_validar_sesion(NEW.horario_id, NEW.grupo_id, NEW.dia, NEW.hora_inicio, NEW.hora_fin);
END$$

CREATE TRIGGER trg_sesion_bu
BEFORE UPDATE ON sesion
FOR EACH ROW
BEGIN
  CALL sp_validar_sesion(NEW.horario_id, NEW.grupo_id, NEW.dia, NEW.hora_inicio, NEW.hora_fin);
END$$

-- Un grupo con sesiones no puede cambiar de periodo (rompería BD-01).
CREATE TRIGGER trg_grupo_bu
BEFORE UPDATE ON grupo
FOR EACH ROW
BEGIN
  IF NEW.periodo_id <> OLD.periodo_id
     AND EXISTS (SELECT 1 FROM sesion WHERE grupo_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-05] No se puede cambiar el periodo de un grupo que ya tiene sesiones.';
  END IF;
END$$

-- Un horario con sesiones no puede cambiar de periodo (rompería BD-01).
CREATE TRIGGER trg_horario_bu
BEFORE UPDATE ON horario
FOR EACH ROW
BEGIN
  IF NEW.periodo_id <> OLD.periodo_id
     AND EXISTS (SELECT 1 FROM sesion WHERE horario_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-06] No se puede cambiar el periodo de un horario que ya tiene sesiones.';
  END IF;
END$$

-- Protección del historial: un horario PUBLICADO no se elimina.
CREATE TRIGGER trg_horario_bd
BEFORE DELETE ON horario
FOR EACH ROW
BEGIN
  IF OLD.estado = 'PUBLICADO' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-07] Un horario publicado no puede eliminarse; forma parte del historial.';
  END IF;
END$$

DELIMITER ;

-- =============================================================================
-- VISTAS DE APOYO (solo lectura; no persisten datos calculados)
-- =============================================================================

-- Bloques fijos válidos por periodo y día, derivados de los parámetros
-- (Sección 4.4): inicios = franja_inicio + k * duración, descartando los que
-- exceden la franja o pisan el almuerzo. Con los valores iniciales resultan
-- 6 bloques por día de lunes a viernes y 2 el sábado (32 por semana).
CREATE VIEW v_bloque_valido AS
WITH RECURSIVE
  dias (dia) AS (
    SELECT 1 UNION ALL SELECT dia + 1 FROM dias WHERE dia < 6
  ),
  bloques (periodo_id, dia, hora_inicio, hora_fin, franja_fin, alm_ini, alm_fin, dur_seg) AS (
    SELECT p.id,
           d.dia,
           IF(d.dia = 6, p.hora_inicio_sabado, p.hora_inicio_semana),
           ADDTIME(IF(d.dia = 6, p.hora_inicio_sabado, p.hora_inicio_semana),
                   SEC_TO_TIME(p.duracion_bloque_min * 60)),
           IF(d.dia = 6, p.hora_fin_sabado, p.hora_fin_semana),
           p.almuerzo_inicio,
           p.almuerzo_fin,
           p.duracion_bloque_min * 60
      FROM periodo_academico p CROSS JOIN dias d
    UNION ALL
    SELECT periodo_id, dia,
           hora_fin,
           ADDTIME(hora_fin, SEC_TO_TIME(dur_seg)),
           franja_fin, alm_ini, alm_fin, dur_seg
      FROM bloques
     WHERE ADDTIME(hora_fin, SEC_TO_TIME(dur_seg)) <= franja_fin
  )
SELECT periodo_id, dia, hora_inicio, hora_fin
  FROM bloques
 WHERE hora_fin <= franja_fin
   AND NOT (hora_inicio < alm_fin AND hora_fin > alm_ini);

-- Estado de cupo de cada grupo: límite operativo calculado con la
-- tolerancia vigente del periodo, candidato a cierre y exceso de cupo.
CREATE VIEW v_grupo_cupo AS
SELECT g.id                                   AS grupo_id,
       g.periodo_id,
       p.nombre                               AS periodo,
       g.curso_id,
       c.nombre                               AS curso,
       g.codigo                               AS grupo,
       g.docente_id,
       d.nombre                               AS docente,
       g.cupo_maximo,
       p.tolerancia_cupo_pct,
       FLOOR(g.cupo_maximo * (1 + p.tolerancia_cupo_pct / 100)) AS limite_operativo,
       g.cupo_minimo,
       g.inscritos,
       (g.inscritos < g.cupo_minimo)          AS candidato_cierre,
       (g.inscritos > FLOOR(g.cupo_maximo * (1 + p.tolerancia_cupo_pct / 100))) AS excede_limite
  FROM grupo g
  JOIN periodo_academico p ON p.id = g.periodo_id
  JOIN curso c             ON c.id = g.curso_id
  JOIN docente d           ON d.id = g.docente_id;

-- Sesiones con sus datos descriptivos (para consultas por docente/curso).
CREATE VIEW v_sesion_detalle AS
SELECT s.id            AS sesion_id,
       h.id            AS horario_id,
       h.estado        AS estado_horario,
       p.id            AS periodo_id,
       p.nombre        AS periodo,
       s.dia,
       ELT(s.dia, 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado') AS dia_nombre,
       s.hora_inicio,
       s.hora_fin,
       g.id            AS grupo_id,
       g.codigo        AS grupo,
       c.id            AS curso_id,
       c.codigo        AS curso_codigo,
       c.nombre        AS curso,
       c.necesita_aula_especial,
       d.id            AS docente_id,
       d.nombre        AS docente
  FROM sesion s
  JOIN horario h           ON h.id = s.horario_id
  JOIN periodo_academico p ON p.id = h.periodo_id
  JOIN grupo g             ON g.id = s.grupo_id
  JOIN curso c             ON c.id = g.curso_id
  JOIN docente d           ON d.id = g.docente_id;

-- Fin de V1__esquema_inicial.sql
