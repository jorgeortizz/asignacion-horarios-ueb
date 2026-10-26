-- =============================================================================
-- V2__revision_tecnica.sql  (migración Flyway)
-- Segunda revisión técnica de la base de datos (2026-10-21).
--
-- Solo contiene cambios que NO dependen de decisiones pendientes del Comité
-- Táctico. Las reglas que sí dependen de esas decisiones están redactadas y
-- probadas en migraciones/pendientes/ y NO se aplican hasta su aprobación.
--
-- Cambios (ver INFORME_REVISION_TECNICA.md):
--   R00 [V2-PRE] Verificación de precondiciones: si hay datos que impiden V2,
--               se detiene ANTES de cualquier DDL (fallo atómico).
--   R01 [BD-08] Sesiones de un horario PUBLICADO: no se insertan, modifican
--               ni eliminan. Compatible con la suposición vigente del vacío 5
--               ("modifica y republica"): todo cambio pasa por republicar.
--   R02 [BD-11] Un horario no puede crearse directamente como PUBLICADO.
--   R03 [BD-12] Un horario sin sesiones no puede publicarse (Fig. 4, 1..*).
--   R04 [BD-09] No se cambia la duración de un curso que ya tiene sesiones.
--   R05 [BD-10] No se cambia el curso de un grupo que ya tiene sesiones.
--   R06 CHECK: la franja de lunes a viernes debe admitir al menos un bloque.
--   R07 Vista v_horario_vigente (último PUBLICADO por periodo).
--   R08 Vista v_sesion_conflicto_parametros (vacío 4: marcar, no corregir).
--   R09 Columnas enum con collation binaria utf8mb4_0900_bin: el CHECK
--       acepta solo el valor exacto del enum Java ('tc' o 'Tc' se rechazan).
--   R10 CHECK: necesita_aula_especial solo admite 0 o 1.
--
-- Seguridad de datos: no elimina ni modifica filas. R00 se detiene antes de
-- cualquier cambio si hay datos incompatibles (ejecute antes preflight_V2.sql).
-- MySQL no permite DDL transaccional: si V2 falla a la mitad, Flyway la marca
-- como fallida; restaure el respaldo o corrija y repare (flyway repair).
-- Entre DROP TRIGGER y CREATE TRIGGER hay un instante sin trigger: aplique
-- la migración con la aplicación detenida (ventana de mantenimiento).
-- =============================================================================

SET NAMES utf8mb4;
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,ONLY_FULL_GROUP_BY';

-- R00 Precondiciones ----------------------------------------------------------
-- MySQL no ejecuta DDL dentro de una transacción. Esta verificación corre
-- ANTES de cualquier cambio: si los datos impiden V2, la migración se detiene
-- sin haber modificado nada. Es indispensable para R09: al cambiar la
-- collation de una columna, MySQL NO vuelve a evaluar los CHECK sobre las
-- filas existentes, y un valor 'tc' quedaría guardado sin error.
-- Los mismos casos se listan en preflight_V2.sql (P01, P04, P05).
DROP PROCEDURE IF EXISTS tmp_v2_precondiciones;

DELIMITER $$
CREATE PROCEDURE tmp_v2_precondiciones ()
BEGIN
  IF EXISTS (SELECT 1 FROM docente
              WHERE CAST(tipo_vinculacion AS BINARY) NOT IN
                    (CAST('TC' AS BINARY), CAST('TRES_CUARTOS' AS BINARY), CAST('MEDIO_TIEMPO' AS BINARY), CAST('CUARTO_TIEMPO' AS BINARY)))
     OR EXISTS (SELECT 1 FROM restriccion_horaria
              WHERE CAST(tipo AS BINARY) NOT IN (CAST('FIRME' AS BINARY), CAST('PREFERENCIA' AS BINARY))
                 OR CAST(sentido AS BINARY) NOT IN (CAST('DISPONIBLE' AS BINARY), CAST('NO_DISPONIBLE' AS BINARY)))
     OR EXISTS (SELECT 1 FROM horario
              WHERE CAST(estado AS BINARY) NOT IN (CAST('BORRADOR' AS BINARY), CAST('PUBLICADO' AS BINARY))) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[V2-PRE] Hay valores enum no canónicos (p. ej. tc). Ejecute preflight_V2.sql (P04) y corríjalos.';
  END IF;
  IF EXISTS (SELECT 1 FROM curso WHERE necesita_aula_especial NOT IN (0, 1)) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[V2-PRE] Hay cursos con necesita_aula_especial distinto de 0 o 1. Ver preflight_V2.sql (P05).';
  END IF;
  IF EXISTS (SELECT 1 FROM periodo_academico
              WHERE TIME_TO_SEC(TIMEDIFF(hora_fin_semana, hora_inicio_semana)) < duracion_bloque_min * 60) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[V2-PRE] Hay periodos con franja L-V más corta que un bloque. Ver preflight_V2.sql (P01).';
  END IF;
END$$
DELIMITER ;

CALL tmp_v2_precondiciones();
DROP PROCEDURE tmp_v2_precondiciones;

-- R09 -------------------------------------------------------------------------
-- Con utf8mb4_0900_ai_ci, CHECK (x IN ('TC', ...)) aceptaba 'tc' o 'Tc', que
-- @Enumerated(EnumType.STRING) no puede leer. Si existen valores no canónicos,
-- este ALTER falla sin cambios: preflight_V2.sql (P04) los lista.
ALTER TABLE docente
  MODIFY tipo_vinculacion VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin NOT NULL;

ALTER TABLE restriccion_horaria
  MODIFY tipo    VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin NOT NULL COMMENT 'FIRME | PREFERENCIA',
  MODIFY sentido VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin NOT NULL COMMENT 'DISPONIBLE | NO_DISPONIBLE (propuesta)';

ALTER TABLE horario
  MODIFY estado VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin NOT NULL DEFAULT 'BORRADOR';

-- R10 -------------------------------------------------------------------------
ALTER TABLE curso
  ADD CONSTRAINT ck_curso_aula_especial CHECK (necesita_aula_especial IN (0, 1));

-- R06 -------------------------------------------------------------------------
ALTER TABLE periodo_academico
  ADD CONSTRAINT ck_periodo_academico_franja_bloque
  CHECK (TIME_TO_SEC(TIMEDIFF(hora_fin_semana, hora_inicio_semana)) >= duracion_bloque_min * 60);

DELIMITER $$

-- R01 -------------------------------------------------------------------------
CREATE PROCEDURE sp_verificar_horario_editable (IN p_horario_id BIGINT)
  READS SQL DATA
  COMMENT 'Impide cambiar sesiones de un horario PUBLICADO'
BEGIN
  IF EXISTS (SELECT 1 FROM horario WHERE id = p_horario_id AND estado = 'PUBLICADO') THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-08] Horario PUBLICADO: sus sesiones no se insertan, modifican ni eliminan; use el flujo de republicación.';
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_sesion_bi$$
CREATE TRIGGER trg_sesion_bi
BEFORE INSERT ON sesion
FOR EACH ROW
BEGIN
  CALL sp_verificar_horario_editable(NEW.horario_id);
  CALL sp_validar_sesion(NEW.horario_id, NEW.grupo_id, NEW.dia, NEW.hora_inicio, NEW.hora_fin);
END$$

DROP TRIGGER IF EXISTS trg_sesion_bu$$
CREATE TRIGGER trg_sesion_bu
BEFORE UPDATE ON sesion
FOR EACH ROW
BEGIN
  CALL sp_verificar_horario_editable(OLD.horario_id);
  IF NEW.horario_id <> OLD.horario_id THEN
    CALL sp_verificar_horario_editable(NEW.horario_id);
  END IF;
  CALL sp_validar_sesion(NEW.horario_id, NEW.grupo_id, NEW.dia, NEW.hora_inicio, NEW.hora_fin);
END$$

CREATE TRIGGER trg_sesion_bd
BEFORE DELETE ON sesion
FOR EACH ROW
BEGIN
  CALL sp_verificar_horario_editable(OLD.horario_id);
END$$

-- R02 -------------------------------------------------------------------------
CREATE TRIGGER trg_horario_bi
BEFORE INSERT ON horario
FOR EACH ROW
BEGIN
  IF NEW.estado = 'PUBLICADO' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-11] Un horario se crea en BORRADOR; publicarlo es una acción posterior del Comité.';
  END IF;
END$$

-- R03 (y se conserva BD-06) ----------------------------------------------------
DROP TRIGGER IF EXISTS trg_horario_bu$$
CREATE TRIGGER trg_horario_bu
BEFORE UPDATE ON horario
FOR EACH ROW
BEGIN
  IF NEW.periodo_id <> OLD.periodo_id
     AND EXISTS (SELECT 1 FROM sesion WHERE horario_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-06] No se puede cambiar el periodo de un horario que ya tiene sesiones.';
  END IF;
  IF NEW.estado = 'PUBLICADO' AND OLD.estado <> 'PUBLICADO'
     AND NOT EXISTS (SELECT 1 FROM sesion WHERE horario_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-12] No se puede publicar un horario sin sesiones.';
  END IF;
END$$

-- R04 -------------------------------------------------------------------------
CREATE TRIGGER trg_curso_bu
BEFORE UPDATE ON curso
FOR EACH ROW
BEGIN
  IF NEW.duracion_sesion_min <> OLD.duracion_sesion_min
     AND EXISTS (SELECT 1 FROM sesion s JOIN grupo g ON g.id = s.grupo_id WHERE g.curso_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-09] No se puede cambiar la duración de un curso que ya tiene sesiones programadas.';
  END IF;
END$$

-- R05 (y se conserva BD-05) ----------------------------------------------------
DROP TRIGGER IF EXISTS trg_grupo_bu$$
CREATE TRIGGER trg_grupo_bu
BEFORE UPDATE ON grupo
FOR EACH ROW
BEGIN
  IF NEW.periodo_id <> OLD.periodo_id
     AND EXISTS (SELECT 1 FROM sesion WHERE grupo_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-05] No se puede cambiar el periodo de un grupo que ya tiene sesiones.';
  END IF;
  IF NEW.curso_id <> OLD.curso_id
     AND EXISTS (SELECT 1 FROM sesion WHERE grupo_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-10] No se puede cambiar el curso de un grupo que ya tiene sesiones.';
  END IF;
END$$

DELIMITER ;

-- R07 -------------------------------------------------------------------------
-- Horario vigente de cada periodo: el PUBLICADO más reciente. Con un solo
-- publicado por periodo coincide con él; si el Comité adopta la estrategia de
-- "copia nueva" (decisión D1-c), distingue la versión vigente de las
-- anteriores sin agregar estados.
CREATE VIEW v_horario_vigente AS
SELECT h.periodo_id,
       p.nombre AS periodo,
       h.id     AS horario_id,
       h.fecha_publicacion
  FROM horario h
  JOIN periodo_academico p ON p.id = h.periodo_id
 WHERE h.estado = 'PUBLICADO'
   AND NOT EXISTS (
         SELECT 1
           FROM horario h2
          WHERE h2.periodo_id = h.periodo_id
            AND h2.estado = 'PUBLICADO'
            AND (h2.fecha_publicacion > h.fecha_publicacion
                 OR (h2.fecha_publicacion = h.fecha_publicacion AND h2.id > h.id)));

-- R08 -------------------------------------------------------------------------
-- Sesiones existentes que no cumplen los parámetros ACTUALES de su periodo.
-- Una fila por (sesión, motivo). Uso: después de cambiar parámetros, el
-- backend muestra estas sesiones como "en conflicto" (vacío 4). La vista no
-- corrige nada ni bloquea el cambio de parámetros.
--   FRANJA          fuera de la franja del día
--   ALMUERZO        se solapa con el almuerzo
--   CUADRICULA      no coincide con un bloque de v_bloque_valido
--   DURACION_BLOQUE la duración del curso difiere del bloque del periodo
CREATE VIEW v_sesion_conflicto_parametros AS
SELECT s.id AS sesion_id, s.horario_id, h.estado AS estado_horario, h.periodo_id,
       s.grupo_id, s.dia, s.hora_inicio, s.hora_fin, 'FRANJA' AS motivo
  FROM sesion s
  JOIN horario h           ON h.id = s.horario_id
  JOIN periodo_academico p ON p.id = h.periodo_id
 WHERE s.hora_inicio < IF(s.dia = 6, p.hora_inicio_sabado, p.hora_inicio_semana)
    OR s.hora_fin    > IF(s.dia = 6, p.hora_fin_sabado,    p.hora_fin_semana)
UNION ALL
SELECT s.id, s.horario_id, h.estado, h.periodo_id,
       s.grupo_id, s.dia, s.hora_inicio, s.hora_fin, 'ALMUERZO'
  FROM sesion s
  JOIN horario h           ON h.id = s.horario_id
  JOIN periodo_academico p ON p.id = h.periodo_id
 WHERE s.hora_inicio < p.almuerzo_fin
   AND s.hora_fin    > p.almuerzo_inicio
UNION ALL
SELECT s.id, s.horario_id, h.estado, h.periodo_id,
       s.grupo_id, s.dia, s.hora_inicio, s.hora_fin, 'CUADRICULA'
  FROM sesion s
  JOIN horario h ON h.id = s.horario_id
 WHERE NOT EXISTS (SELECT 1
                     FROM v_bloque_valido b
                    WHERE b.periodo_id  = h.periodo_id
                      AND b.dia         = s.dia
                      AND b.hora_inicio = s.hora_inicio
                      AND b.hora_fin    = s.hora_fin)
UNION ALL
SELECT s.id, s.horario_id, h.estado, h.periodo_id,
       s.grupo_id, s.dia, s.hora_inicio, s.hora_fin, 'DURACION_BLOQUE'
  FROM sesion s
  JOIN horario h           ON h.id = s.horario_id
  JOIN periodo_academico p ON p.id = h.periodo_id
  JOIN grupo g             ON g.id = s.grupo_id
  JOIN curso c             ON c.id = g.curso_id
 WHERE c.duracion_sesion_min <> p.duracion_bloque_min;

-- Fin de V2__revision_tecnica.sql
