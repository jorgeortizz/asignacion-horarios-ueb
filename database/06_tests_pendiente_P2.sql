-- =============================================================================
-- 06_tests_pendiente_P2.sql
-- Pruebas de la migración PENDIENTE alternativa P2 (D1-c: copia nueva).
-- Requiere una base de DESARROLLO preparada así:
--   00_reset_dev.sql -> 01_schema.sql
--   -> migraciones/pendientes/P2_D1c_copia_nueva.sql -> 02_seed.sql
-- Todo termina en ROLLBACK. Categorías: ver 04_tests.sql.
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

START TRANSACTION;

CALL tst_esperar_error_bd('P2-01', 'SQL', 'Un horario PUBLICADO no vuelve a BORRADOR', '[BD-15]',
  'UPDATE horario SET estado = ''BORRADOR'' WHERE id = 1');
CALL tst_esperar_exito('P2-02', 'SQL', 'Crear el borrador 80 en 2026-1 para la nueva versión',
  'INSERT INTO horario (id, periodo_id) VALUES (80, 1)');
CALL tst_esperar_exito('P2-03', 'SQL', 'Copiar las sesiones del publicado al borrador 80',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) SELECT 80, grupo_id, dia, hora_inicio, hora_fin FROM sesion WHERE horario_id = 1');
CALL tst_esperar_exito('P2-04', 'SQL', 'Ajustar la copia: mover Redes del lunes al martes',
  'UPDATE sesion SET dia = 2 WHERE horario_id = 80 AND grupo_id = 3 AND dia = 1');
CALL tst_esperar_exito('P2-05', 'SQL', 'Publicar la nueva versión',
  'UPDATE horario SET estado = ''PUBLICADO'', fecha_publicacion = ''2026-10-22 09:00:00'' WHERE id = 80');
CALL tst_verificar('P2-06', 'SQL', 'v_horario_vigente: 2026-1 apunta a la versión nueva (80)',
  'SELECT horario_id FROM v_horario_vigente WHERE periodo = ''2026-1''', '80');
CALL tst_verificar('P2-07', 'SQL', 'La versión anterior (1) sigue PUBLICADA con Redes el lunes (historial)',
  'SELECT COUNT(*) FROM sesion s JOIN horario h ON h.id = s.horario_id WHERE h.id = 1 AND h.estado = ''PUBLICADO'' AND s.grupo_id = 3 AND s.dia = 1', '1');
CALL tst_esperar_error_bd('P2-08', 'SQL', 'La versión anterior sigue protegida', '[BD-08]',
  'UPDATE sesion SET dia = 4 WHERE horario_id = 1 AND grupo_id = 3 AND dia = 1');
CALL tst_esperar_exito('P2-09', 'LIMITE', 'Cambiar el docente del grupo 3 se permite (el grupo es compartido por ambas versiones)',
  'UPDATE grupo SET docente_id = 6 WHERE id = 3');
CALL tst_verificar('P2-10', 'LIMITE', 'Limitación de D1-c: la versión anterior también muestra el docente nuevo',
  'SELECT COUNT(*) FROM v_sesion_detalle WHERE horario_id = 1 AND grupo_id = 3 AND docente_id = 6', '2');

ROLLBACK;

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

-- Fin de 06_tests_pendiente_P2.sql
