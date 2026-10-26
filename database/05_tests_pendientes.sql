-- =============================================================================
-- 05_tests_pendientes.sql
-- Pruebas de las migraciones PENDIENTES de decisión del Comité, en la
-- combinación recomendada: P1 (D1-b y D3) + P3 (D2).
-- Requiere una base de DESARROLLO preparada así:
--   00_reset_dev.sql -> 01_schema.sql
--   -> migraciones/pendientes/P1_D1b_republicar_mismo_horario.sql
--   -> migraciones/pendientes/P3_D2_parametros_con_publicado.sql
--   -> 02_seed.sql
-- (tools/ejecutar_todo.sh lo hace automáticamente). Todo termina en ROLLBACK.
-- Categorías: ver 04_tests.sql.
-- =============================================================================

USE horarios_ueb;

-- -----------------------------------------------------------------------------
-- Utilidades de prueba (se crean al inicio y se eliminan al final del archivo)
-- Los resultados se acumulan en la variable de sesión @tst_log (JSON). Las
-- variables de sesión no son transaccionales: sobreviven a cada ROLLBACK,
-- por lo que cada sección puede revertir sus cambios sin perder resultados.
-- -----------------------------------------------------------------------------
SET SESSION group_concat_max_len = 1000000;
SET @tst_log := JSON_ARRAY();

DROP PROCEDURE IF EXISTS tst_registrar;
DROP PROCEDURE IF EXISTS tst_esperar_error;
DROP PROCEDURE IF EXISTS tst_esperar_error_bd;
DROP PROCEDURE IF EXISTS tst_esperar_exito;
DROP PROCEDURE IF EXISTS tst_verificar;

DELIMITER $$

CREATE PROCEDURE tst_registrar (
  IN p_codigo VARCHAR(12), IN p_cat VARCHAR(8), IN p_desc VARCHAR(255),
  IN p_esperado TEXT, IN p_obtenido TEXT, IN p_ok BOOLEAN)
BEGIN
  SET @tst_log := JSON_ARRAY_APPEND(@tst_log, '$', JSON_OBJECT(
    'n', JSON_LENGTH(@tst_log) + 1, 'codigo', p_codigo, 'categoria', p_cat,
    'descripcion', p_desc, 'esperado', p_esperado, 'obtenido', p_obtenido,
    'resultado', IF(p_ok, 'OK', 'FALLA')));
END$$

-- La sentencia DEBE fallar con el errno indicado.
CREATE PROCEDURE tst_esperar_error (
  IN p_codigo VARCHAR(12), IN p_cat VARCHAR(8), IN p_desc VARCHAR(255),
  IN p_errno INT, IN p_sql TEXT)
BEGIN
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_msg   VARCHAR(500) DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
    END;
  SET @tst_sql := p_sql;
  PREPARE stmt FROM @tst_sql;
  EXECUTE stmt;
  DEALLOCATE PREPARE stmt;
  CALL tst_registrar(p_codigo, p_cat, p_desc, CONCAT('error ', p_errno),
       IF(v_errno = 0, 'sin error (se aceptó)', CONCAT('error ', v_errno, ': ', v_msg)),
       v_errno = p_errno);
END$$

-- La sentencia DEBE fallar con un error propio de la BD (errno 1644) cuyo
-- mensaje empieza por el código indicado, p. ej. '[BD-08]'.
CREATE PROCEDURE tst_esperar_error_bd (
  IN p_codigo VARCHAR(12), IN p_cat VARCHAR(8), IN p_desc VARCHAR(255),
  IN p_prefijo VARCHAR(10), IN p_sql TEXT)
BEGIN
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_msg   VARCHAR(500) DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
    END;
  SET @tst_sql := p_sql;
  PREPARE stmt FROM @tst_sql;
  EXECUTE stmt;
  DEALLOCATE PREPARE stmt;
  CALL tst_registrar(p_codigo, p_cat, p_desc, CONCAT('error 1644 ', p_prefijo),
       IF(v_errno = 0, 'sin error (se aceptó)', CONCAT('error ', v_errno, ': ', v_msg)),
       v_errno = 1644 AND v_msg LIKE CONCAT(p_prefijo, '%'));
END$$

-- La sentencia DEBE aceptarse.
CREATE PROCEDURE tst_esperar_exito (
  IN p_codigo VARCHAR(12), IN p_cat VARCHAR(8), IN p_desc VARCHAR(255), IN p_sql TEXT)
BEGIN
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_msg   VARCHAR(500) DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
    END;
  SET @tst_sql := p_sql;
  PREPARE stmt FROM @tst_sql;
  EXECUTE stmt;
  DEALLOCATE PREPARE stmt;
  CALL tst_registrar(p_codigo, p_cat, p_desc, 'aceptada',
       IF(v_errno = 0, 'aceptada', CONCAT('error ', v_errno, ': ', v_msg)),
       v_errno = 0);
END$$

-- Evalúa una consulta escalar y la compara con el valor esperado (texto).
CREATE PROCEDURE tst_verificar (
  IN p_codigo VARCHAR(12), IN p_cat VARCHAR(8), IN p_desc VARCHAR(255),
  IN p_consulta TEXT, IN p_esperado TEXT)
BEGIN
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_msg   VARCHAR(500) DEFAULT '';
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
    END;
  SET @tst_valor := NULL;
  SET @tst_sql := CONCAT('SELECT CAST((', p_consulta, ') AS CHAR) INTO @tst_valor');
  PREPARE stmt FROM @tst_sql;
  EXECUTE stmt;
  DEALLOCATE PREPARE stmt;
  CALL tst_registrar(p_codigo, p_cat, p_desc, p_esperado,
       IF(v_errno = 0, COALESCE(@tst_valor, 'NULL'), CONCAT('error ', v_errno, ': ', v_msg)),
       v_errno = 0 AND @tst_valor = p_esperado);
END$$

DELIMITER ;

-- =============================================================================
-- P1. D1-b: un solo PUBLICADO por periodo; republicar el mismo horario.
--     D3: el docente de un grupo publicado no cambia sin despublicar.
-- =============================================================================
START TRANSACTION;

CALL tst_esperar_exito('P1-01', 'SQL', 'Crear un segundo horario (borrador) en 2026-1',
  'INSERT INTO horario (id, periodo_id) VALUES (70, 1)');
CALL tst_esperar_exito('P1-02', 'SQL', 'Copiar las sesiones del publicado al borrador 70',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) SELECT 70, grupo_id, dia, hora_inicio, hora_fin FROM sesion WHERE horario_id = 1');
CALL tst_esperar_error('P1-03', 'SQL', 'Publicar un segundo horario en el mismo periodo se rechaza (índice único)', 1062,
  'UPDATE horario SET estado = ''PUBLICADO'', fecha_publicacion = ''2026-10-22 09:00:00'' WHERE id = 70');
CALL tst_esperar_error_bd('P1-04', 'SQL', 'Cambiar el docente de un grupo con sesiones PUBLICADAS', '[BD-14]',
  'UPDATE grupo SET docente_id = 6 WHERE id = 3');
CALL tst_esperar_exito('P1-05', 'SQL', 'Despublicar el horario 1 (flujo D1-b)',
  'UPDATE horario SET estado = ''BORRADOR'', version = version + 1 WHERE id = 1');
CALL tst_esperar_exito('P1-06', 'SQL', 'Con el horario despublicado, el cambio de docente se permite',
  'UPDATE grupo SET docente_id = 6 WHERE id = 3');
CALL tst_esperar_exito('P1-07', 'SQL', 'Republicar el horario 1',
  'UPDATE horario SET estado = ''PUBLICADO'', fecha_publicacion = ''2026-10-21 11:00:00'', version = version + 1 WHERE id = 1');
CALL tst_verificar('P1-08', 'SQL', 'v_horario_vigente: 2026-1 sigue siendo el horario 1, con la fecha nueva',
  'SELECT CONCAT(horario_id, '' '', fecha_publicacion) FROM v_horario_vigente WHERE periodo = ''2026-1''', '1 2026-10-21 11:00:00');
CALL tst_esperar_exito('P1-09', 'SQL', 'Cambiar el docente de un grupo que solo está en borradores se permite',
  'UPDATE grupo SET docente_id = 6 WHERE id = 17');
CALL tst_esperar_exito('P1-10', 'SQL', 'Publicar 2026-2 (su primer publicado) se permite',
  'UPDATE horario SET estado = ''PUBLICADO'', fecha_publicacion = ''2026-10-21 12:00:00'' WHERE id = 2');

ROLLBACK;

-- =============================================================================
-- P3. D2: parámetros de forma congelados en periodos con horario PUBLICADO.
-- =============================================================================
START TRANSACTION;

CALL tst_esperar_error_bd('P3-01', 'SQL', 'Cambiar el almuerzo de 2026-1 (tiene horario PUBLICADO)', '[BD-16]',
  'UPDATE periodo_academico SET almuerzo_fin = ''14:00:00'' WHERE id = 1');
CALL tst_esperar_error_bd('P3-02', 'SQL', 'Cambiar la duración del bloque de 2026-1', '[BD-16]',
  'UPDATE periodo_academico SET duracion_bloque_min = 90 WHERE id = 1');
CALL tst_esperar_error_bd('P3-03', 'SQL', 'Cambiar la franja del sábado de 2026-1', '[BD-16]',
  'UPDATE periodo_academico SET hora_fin_sabado = ''12:00:00'' WHERE id = 1');
CALL tst_esperar_error_bd('P3-04', 'SQL', 'Cambiar el máximo de sesiones de 2026-1', '[BD-16]',
  'UPDATE periodo_academico SET max_sesiones_semana = 3 WHERE id = 1');
CALL tst_esperar_exito('P3-05', 'SQL', 'Los parámetros de cupo no se congelan (tolerancia y mínimo de 2026-1)',
  'UPDATE periodo_academico SET tolerancia_cupo_pct = 5.00, cupo_minimo = 8 WHERE id = 1');
CALL tst_esperar_exito('P3-06', 'SQL', 'En 2026-2 (solo borrador) el almuerzo sí se puede cambiar',
  'UPDATE periodo_academico SET almuerzo_fin = ''14:00:00'' WHERE id = 2');
CALL tst_verificar('P3-07', 'SQL', 'Las sesiones afectadas del borrador quedan marcadas (vacío 4)',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 2 AND motivo = ''ALMUERZO''', '5');
CALL tst_esperar_exito('P3-08', 'LIMITE', 'Límite de la BD: publicar 2026-2 con 5 sesiones en conflicto se ACEPTA; la validación previa es Java (BK07)',
  'UPDATE horario SET estado = ''PUBLICADO'', fecha_publicacion = ''2026-10-21 12:00:00'' WHERE id = 2');
CALL tst_esperar_exito('P3-09', 'SQL', 'Despublicar 2026-1 (D1-b) libera sus parámetros',
  'UPDATE horario SET estado = ''BORRADOR'' WHERE id = 1');
CALL tst_esperar_exito('P3-10', 'SQL', 'Sin publicado, el almuerzo de 2026-1 se puede cambiar',
  'UPDATE periodo_academico SET almuerzo_fin = ''14:00:00'' WHERE id = 1');
CALL tst_verificar('P3-11', 'INSUMO', 'Las 2 sesiones afectadas del horario 1 quedan marcadas antes de republicar',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 1 AND motivo = ''ALMUERZO''', '2');

ROLLBACK;

CALL tst_verificar('P3-12', 'SQL', 'Tras ROLLBACK, 2026-1 vuelve a tener su horario PUBLICADO y su almuerzo original',
  'SELECT CONCAT(h.estado, '' '', p.almuerzo_fin) FROM horario h JOIN periodo_academico p ON p.id = h.periodo_id WHERE h.id = 1', 'PUBLICADO 13:00:00');

-- -----------------------------------------------------------------------------
-- Resultados
-- -----------------------------------------------------------------------------
SELECT jt.n, jt.codigo, jt.categoria, jt.resultado, jt.descripcion, jt.esperado, jt.obtenido
  FROM JSON_TABLE(@tst_log, '$[*]' COLUMNS (
         n           INT           PATH '$.n',
         codigo      VARCHAR(12)   PATH '$.codigo',
         categoria   VARCHAR(8)    PATH '$.categoria',
         resultado   VARCHAR(5)    PATH '$.resultado',
         descripcion VARCHAR(255)  PATH '$.descripcion',
         esperado    VARCHAR(1000) PATH '$.esperado',
         obtenido    VARCHAR(1000) PATH '$.obtenido')) AS jt
 ORDER BY jt.n;

SELECT IF(GROUPING(jt.categoria) = 1, 'TOTAL', jt.categoria) AS categoria,
       COUNT(*)                   AS pruebas,
       SUM(jt.resultado = 'OK')   AS correctas,
       SUM(jt.resultado <> 'OK')  AS fallidas
  FROM JSON_TABLE(@tst_log, '$[*]' COLUMNS (
         categoria VARCHAR(8) PATH '$.categoria',
         resultado VARCHAR(5) PATH '$.resultado')) AS jt
 GROUP BY jt.categoria WITH ROLLUP;

SELECT VERSION() AS mysql_version,
       JSON_LENGTH(@tst_log) AS total_pruebas,
       (SELECT COUNT(*) FROM JSON_TABLE(@tst_log, '$[*]' COLUMNS (r VARCHAR(5) PATH '$.resultado')) t WHERE r <> 'OK') AS fallidas;

DROP PROCEDURE IF EXISTS tst_registrar;
DROP PROCEDURE IF EXISTS tst_esperar_error;
DROP PROCEDURE IF EXISTS tst_esperar_error_bd;
DROP PROCEDURE IF EXISTS tst_esperar_exito;
DROP PROCEDURE IF EXISTS tst_verificar;

-- Fin de 05_tests_pendientes.sql
