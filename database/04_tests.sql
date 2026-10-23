-- =============================================================================
-- 04_tests.sql
-- Validación técnica de la base de datos (pruebas SQL) · esquema V2.
-- Requiere: 01_schema.sql (o migraciones V1+V2) y 02_seed.sql recién
-- ejecutados, SIN las migraciones pendientes (para esas: 05 y 06).
-- Ejecutar SOLO en desarrollo o pruebas: crea procedimientos tst_* temporales.
--
-- Cómo funciona:
--   * Cada prueba se ejecuta como SQL dinámico dentro de un procedimiento con
--     manejador de errores: un error esperado se captura, se registra y el
--     script continúa con los demás casos.
--   * Las secciones A-G corren en una transacción; H, I, J y K en una
--     transacción propia cada una. Todas terminan en ROLLBACK, por lo que los
--     datos de 02_seed.sql quedan intactos y el archivo se puede repetir.
--   * Los errores de trigger se verifican por errno 1644 Y por el código
--     [BD-xx] del mensaje, para no confundir una regla con otra.
--   * Resultado esperado: fallidas = 0 en el resumen final.
--
-- Categorías (qué demuestra cada prueba y qué NO):
--   SQL     garantía propia de la base de datos (FK, UNIQUE, CHECK, NOT NULL,
--           triggers estructurales, vistas, contrato de nombres y tipos).
--   RED     red de seguridad de una regla que Spring Boot valida primero y
--           explica al usuario (franja, almuerzo, duración). Pasar aquí NO
--           reemplaza la prueba Java.
--   DATOS   verificación de que los datos de prueba cumplen reglas de negocio.
--   INSUMO  la BD entrega el dato que Java necesita para decidir; la decisión
--           (bloquear, advertir, reportar) se prueba en JUnit (BK01-BK13).
--   LIMITE  comportamiento vigente que documenta una limitación conocida o
--           una decisión pendiente del Comité (ver INFORME_REVISION_TECNICA).
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

-- =============================================================================
-- A. Integridad y estructura del esquema
-- =============================================================================
CALL tst_verificar('A01', 'SQL', 'Existen las 7 tablas de entidades principales',
  'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ''horarios_ueb'' AND table_type = ''BASE TABLE'' AND table_name IN (''docente'',''restriccion_horaria'',''curso'',''grupo'',''sesion'',''horario'',''periodo_academico'')', '7');
CALL tst_verificar('A02', 'SQL', 'Solo existe 1 tabla auxiliar adicional (docente_especialidad); se excluye flyway_schema_history',
  'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ''horarios_ueb'' AND table_type = ''BASE TABLE'' AND table_name <> ''flyway_schema_history''', '8');
CALL tst_verificar('A03', 'SQL', 'Todas las tablas usan InnoDB',
  'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ''horarios_ueb'' AND table_type = ''BASE TABLE'' AND engine <> ''InnoDB''', '0');
CALL tst_verificar('A04', 'SQL', 'Todas las tablas usan collation utf8mb4',
  'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ''horarios_ueb'' AND table_type = ''BASE TABLE'' AND table_collation NOT LIKE ''utf8mb4%''', '0');
CALL tst_verificar('A05', 'SQL', 'Número de claves foráneas declaradas',
  'SELECT COUNT(*) FROM information_schema.referential_constraints WHERE constraint_schema = ''horarios_ueb''', '8');
CALL tst_verificar('A06', 'SQL', 'Ninguna FK de historial usa ON DELETE CASCADE (solo las 2 de colecciones del docente)',
  'SELECT GROUP_CONCAT(constraint_name ORDER BY constraint_name) FROM information_schema.referential_constraints WHERE constraint_schema = ''horarios_ueb'' AND delete_rule = ''CASCADE''',
  'fk_docente_especialidad_docente,fk_restriccion_horaria_docente');
CALL tst_verificar('A07', 'SQL', 'Bloques válidos por semana derivados de los parámetros (Sección 4.4)',
  'SELECT COUNT(*) FROM v_bloque_valido WHERE periodo_id = 2', '32');
CALL tst_verificar('A08', 'SQL', 'Bloques válidos de lunes a viernes por día',
  'SELECT COUNT(*) FROM v_bloque_valido WHERE periodo_id = 2 AND dia = 3', '6');
CALL tst_verificar('A09', 'SQL', 'Bloques válidos del sábado: 07-09 y 09-11',
  'SELECT GROUP_CONCAT(TIME_FORMAT(hora_inicio, ''%H'') ORDER BY hora_inicio) FROM v_bloque_valido WHERE periodo_id = 2 AND dia = 6', '07,09');
CALL tst_verificar('A10', 'SQL', 'El bloque de 11 a 13 (almuerzo) no es válido',
  'SELECT COUNT(*) FROM v_bloque_valido WHERE hora_inicio = ''11:00:00''', '0');

-- =============================================================================
-- B. Verificación de los datos de prueba (reglas del backend sobre el seed)
-- =============================================================================
CALL tst_verificar('B01', 'DATOS', 'Ninguna sesión une grupo y horario de periodos distintos',
  'SELECT COUNT(*) FROM sesion s JOIN grupo g ON g.id = s.grupo_id JOIN horario h ON h.id = s.horario_id WHERE g.periodo_id <> h.periodo_id', '0');
CALL tst_verificar('B02', 'DATOS', 'Todas las sesiones caen en un bloque válido de la cuadrícula',
  'SELECT COUNT(*) FROM sesion s JOIN horario h ON h.id = s.horario_id LEFT JOIN v_bloque_valido b ON b.periodo_id = h.periodo_id AND b.dia = s.dia AND b.hora_inicio = s.hora_inicio AND b.hora_fin = s.hora_fin WHERE b.periodo_id IS NULL', '0');
CALL tst_verificar('B03', 'DATOS', 'Ningún docente tiene dos sesiones solapadas en un mismo horario',
  'SELECT COUNT(*) FROM sesion s1 JOIN grupo g1 ON g1.id = s1.grupo_id JOIN sesion s2 ON s2.horario_id = s1.horario_id AND s2.dia = s1.dia AND s2.id > s1.id JOIN grupo g2 ON g2.id = s2.grupo_id AND g2.docente_id = g1.docente_id WHERE s1.hora_inicio < s2.hora_fin AND s2.hora_inicio < s1.hora_fin', '0');
CALL tst_verificar('B04', 'DATOS', 'Ninguna sesión pisa una restricción FIRME/NO_DISPONIBLE',
  'SELECT COUNT(*) FROM sesion s JOIN grupo g ON g.id = s.grupo_id JOIN restriccion_horaria r ON r.docente_id = g.docente_id AND r.dia = s.dia AND r.tipo = ''FIRME'' AND r.sentido = ''NO_DISPONIBLE'' WHERE r.hora_inicio < s.hora_fin AND s.hora_inicio < r.hora_fin', '0');
CALL tst_verificar('B05', 'DATOS', 'Toda sesión de un docente con franjas FIRME/DISPONIBLE cae dentro de alguna',
  'SELECT COUNT(*) FROM sesion s JOIN grupo g ON g.id = s.grupo_id WHERE EXISTS (SELECT 1 FROM restriccion_horaria r WHERE r.docente_id = g.docente_id AND r.tipo = ''FIRME'' AND r.sentido = ''DISPONIBLE'') AND NOT EXISTS (SELECT 1 FROM restriccion_horaria r WHERE r.docente_id = g.docente_id AND r.tipo = ''FIRME'' AND r.sentido = ''DISPONIBLE'' AND r.dia = s.dia AND r.hora_inicio <= s.hora_inicio AND r.hora_fin >= s.hora_fin)', '0');
CALL tst_verificar('B06', 'DATOS', 'El horario publicado tiene la frecuencia completa de todos sus grupos',
  'SELECT COUNT(*) FROM (SELECT g.id FROM horario h JOIN grupo g ON g.periodo_id = h.periodo_id JOIN curso c ON c.id = g.curso_id LEFT JOIN sesion s ON s.grupo_id = g.id AND s.horario_id = h.id WHERE h.estado = ''PUBLICADO'' GROUP BY h.id, g.id, c.sesiones_semanales HAVING COUNT(s.id) <> c.sesiones_semanales) t', '0');
CALL tst_verificar('B07', 'DATOS', 'El borrador reporta 1 grupo no ubicado por completo (grupo 21)',
  'SELECT GROUP_CONCAT(t.id) FROM (SELECT g.id FROM grupo g JOIN curso c ON c.id = g.curso_id LEFT JOIN sesion s ON s.grupo_id = g.id AND s.horario_id = 2 WHERE g.periodo_id = 2 GROUP BY g.id, c.sesiones_semanales HAVING COUNT(s.id) <> c.sesiones_semanales) t', '21');
CALL tst_verificar('B08', 'DATOS', 'Ningún grupo supera el límite operativo con la tolerancia vigente',
  'SELECT COUNT(*) FROM v_grupo_cupo WHERE excede_limite = 1', '0');
CALL tst_verificar('B09', 'DATOS', 'Ningún curso supera el máximo de sesiones semanales parametrizado',
  'SELECT COUNT(*) FROM curso c JOIN grupo g ON g.curso_id = c.id JOIN periodo_academico p ON p.id = g.periodo_id WHERE c.sesiones_semanales > p.max_sesiones_semana', '0');
CALL tst_verificar('B10', 'DATOS', 'Existe exactamente 1 horario publicado y 1 en borrador',
  'SELECT CONCAT(SUM(estado = ''PUBLICADO''), ''/'', SUM(estado = ''BORRADOR'')) FROM horario', '1/1');

-- =============================================================================
-- C. Restricciones de rango y dominio (CHECK -> error 3819)
-- =============================================================================
CALL tst_esperar_error('C01', 'SQL', 'Tipo de vinculación fuera del dominio', 3819,
  'INSERT INTO docente (nombre, tipo_vinculacion) VALUES (''Docente X'', ''CATEDRA'')');
CALL tst_esperar_error('C02', 'SQL', 'Nombre de docente vacío', 3819,
  'INSERT INTO docente (nombre, tipo_vinculacion) VALUES (''   '', ''TC'')');
CALL tst_esperar_error('C03', 'SQL', 'Restricción en domingo (día 7)', 3819,
  'INSERT INTO restriccion_horaria (docente_id, dia, hora_inicio, hora_fin, tipo, sentido) VALUES (1, 7, ''08:00'', ''10:00'', ''FIRME'', ''NO_DISPONIBLE'')');
CALL tst_esperar_error('C04', 'SQL', 'Restricción con hora fin anterior al inicio', 3819,
  'INSERT INTO restriccion_horaria (docente_id, dia, hora_inicio, hora_fin, tipo, sentido) VALUES (1, 1, ''10:00'', ''08:00'', ''FIRME'', ''NO_DISPONIBLE'')');
CALL tst_esperar_error('C05', 'SQL', 'Restricción con tipo inválido', 3819,
  'INSERT INTO restriccion_horaria (docente_id, dia, hora_inicio, hora_fin, tipo, sentido) VALUES (1, 1, ''08:00'', ''10:00'', ''OBLIGATORIA'', ''NO_DISPONIBLE'')');
CALL tst_esperar_error('C06', 'SQL', 'Curso con 0 sesiones semanales', 3819,
  'INSERT INTO curso (nombre, sesiones_semanales) VALUES (''Curso X'', 0)');
CALL tst_esperar_error('C07', 'SQL', 'Grupo con inscritos negativos', 3819,
  'INSERT INTO grupo (periodo_id, curso_id, docente_id, codigo, cupo_maximo, cupo_minimo, inscritos) VALUES (2, 1, 1, ''99'', 40, 10, -1)');
CALL tst_esperar_error('C08', 'SQL', 'Grupo con cupo mínimo mayor que el máximo', 3819,
  'INSERT INTO grupo (periodo_id, curso_id, docente_id, codigo, cupo_maximo, cupo_minimo, inscritos) VALUES (2, 1, 1, ''99'', 10, 40, 5)');
CALL tst_esperar_error('C09', 'SQL', 'Horario con estado no permitido', 3819,
  'INSERT INTO horario (periodo_id, estado) VALUES (2, ''ARCHIVADO'')');
CALL tst_esperar_error('C10', 'SQL', 'Horario PUBLICADO sin fecha de publicación', 3819,
  'UPDATE horario SET estado = ''PUBLICADO'' WHERE id = 2');
CALL tst_esperar_error('C11', 'SQL', 'Periodo con fecha fin anterior al inicio', 3819,
  'INSERT INTO periodo_academico (nombre, fecha_inicio, fecha_fin) VALUES (''2027-1'', ''2027-06-01'', ''2027-01-01'')');
CALL tst_esperar_error('C12', 'SQL', 'Tolerancia de cupo mayor que 100 %', 3819,
  'UPDATE periodo_academico SET tolerancia_cupo_pct = 150 WHERE id = 2');
CALL tst_esperar_error('C13', 'SQL', 'Almuerzo con fin anterior al inicio', 3819,
  'UPDATE periodo_academico SET almuerzo_fin = ''11:00:00'' WHERE id = 2');
CALL tst_esperar_error('C14', 'SQL', 'Sesión en domingo', 3819,
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 21, 7, ''15:00'', ''17:00'')');

-- =============================================================================
-- D. NOT NULL y UNIQUE (errores 1048 y 1062)
-- =============================================================================
CALL tst_esperar_error('D01', 'SQL', 'Docente sin nombre (NULL)', 1048,
  'INSERT INTO docente (nombre, tipo_vinculacion) VALUES (NULL, ''TC'')');
CALL tst_esperar_error('D02', 'SQL', 'Grupo sin docente (Figura 4: multiplicidad 1)', 1048,
  'INSERT INTO grupo (periodo_id, curso_id, docente_id, codigo, cupo_maximo, cupo_minimo) VALUES (2, 1, NULL, ''99'', 40, 10)');
CALL tst_esperar_error('D03', 'SQL', 'Periodo académico con nombre repetido', 1062,
  'INSERT INTO periodo_academico (nombre, fecha_inicio, fecha_fin) VALUES (''2026-2'', ''2026-07-01'', ''2026-12-01'')');
CALL tst_esperar_error('D04', 'SQL', 'Grupo repetido (mismo periodo, curso y código)', 1062,
  'INSERT INTO grupo (periodo_id, curso_id, docente_id, codigo, cupo_maximo, cupo_minimo) VALUES (2, 1, 3, ''01'', 40, 10)');
CALL tst_esperar_error('D05', 'SQL', 'Sesión duplicada del mismo grupo en la misma casilla', 1062,
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 11, 1, ''07:00'', ''09:00'')');
CALL tst_esperar_error('D06', 'SQL', 'Código de curso repetido', 1062,
  'INSERT INTO curso (codigo, nombre, sesiones_semanales) VALUES (''FIC-101'', ''Copia'', 2)');
CALL tst_esperar_error('D07', 'SQL', 'Especialidad repetida para el mismo docente', 1062,
  'INSERT INTO docente_especialidad (docente_id, especialidad) VALUES (1, ''Bases de datos'')');

-- =============================================================================
-- E. Claves foráneas y política de eliminación (errores 1452 y 1451)
-- =============================================================================
CALL tst_esperar_error('E01', 'SQL', 'Grupo con curso inexistente', 1452,
  'INSERT INTO grupo (periodo_id, curso_id, docente_id, codigo, cupo_maximo, cupo_minimo) VALUES (2, 999, 1, ''99'', 40, 10)');
CALL tst_esperar_error('E02', 'SQL', 'Restricción de un docente inexistente', 1452,
  'INSERT INTO restriccion_horaria (docente_id, dia, hora_inicio, hora_fin, tipo, sentido) VALUES (999, 1, ''08:00'', ''10:00'', ''FIRME'', ''NO_DISPONIBLE'')');
CALL tst_esperar_error('E03', 'SQL', 'Sesión con horario inexistente', 1452,
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (999, 21, 4, ''15:00'', ''17:00'')');
CALL tst_esperar_error('E04', 'SQL', 'Horario de un periodo inexistente', 1452,
  'INSERT INTO horario (periodo_id) VALUES (999)');
CALL tst_esperar_error('E05', 'SQL', 'Eliminar curso con grupos (RESTRICT)', 1451,
  'DELETE FROM curso WHERE id = 1');
CALL tst_esperar_error('E06', 'SQL', 'Eliminar docente con grupos (RESTRICT)', 1451,
  'DELETE FROM docente WHERE id = 1');
CALL tst_esperar_error('E07', 'SQL', 'Eliminar periodo con horarios y grupos (RESTRICT)', 1451,
  'DELETE FROM periodo_academico WHERE id = 1');
CALL tst_esperar_error('E08', 'SQL', 'Eliminar grupo con sesiones (RESTRICT)', 1451,
  'DELETE FROM grupo WHERE id = 11');
CALL tst_esperar_error('E09', 'SQL', 'Eliminar horario BORRADOR con sesiones (RESTRICT)', 1451,
  'DELETE FROM horario WHERE id = 2');
-- Positivo: un docente sin grupos sí puede eliminarse y arrastra sus colecciones.
CALL tst_esperar_exito('E10', 'SQL', 'Crear docente temporal con especialidad y restricción',
  'INSERT INTO docente (id, nombre, tipo_vinculacion) VALUES (900, ''Docente temporal'', ''CUARTO_TIEMPO'')');
CALL tst_esperar_exito('E11', 'SQL', 'Agregar especialidad al docente temporal',
  'INSERT INTO docente_especialidad (docente_id, especialidad) VALUES (900, ''Prueba'')');
CALL tst_esperar_exito('E12', 'SQL', 'Agregar restricción al docente temporal',
  'INSERT INTO restriccion_horaria (docente_id, dia, hora_inicio, hora_fin, tipo, sentido) VALUES (900, 1, ''07:00'', ''09:00'', ''PREFERENCIA'', ''DISPONIBLE'')');
CALL tst_esperar_exito('E13', 'SQL', 'Eliminar docente sin grupos',
  'DELETE FROM docente WHERE id = 900');
CALL tst_verificar('E14', 'SQL', 'Sus especialidades y restricciones se eliminaron en cascada',
  'SELECT (SELECT COUNT(*) FROM docente_especialidad WHERE docente_id = 900) + (SELECT COUNT(*) FROM restriccion_horaria WHERE docente_id = 900)', '0');

-- =============================================================================
-- F. Sesiones: franja, almuerzo, duración y periodo (triggers -> error 1644)
--    Incluye la prueba 1 de la Tabla 26 (almuerzo).
-- =============================================================================
CALL tst_esperar_error_bd('F01', 'RED', 'Red de seguridad para T26-1: la BD rechaza 11 a 13 (la prueba de aceptación con mensaje es Java)', '[BD-04]',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 21, 4, ''11:00'', ''13:00'')');
CALL tst_esperar_exito('F02', 'RED', 'Red de seguridad para T26-1: la BD acepta 9 a 11',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 21, 5, ''09:00'', ''11:00'')');
CALL tst_esperar_exito('F03', 'RED', 'Red de seguridad para T26-1: la BD acepta 13 a 15',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 21, 2, ''13:00'', ''15:00'')');
CALL tst_esperar_error_bd('F04', 'RED', 'Sesión de 21 a 23 excede la franja entre semana', '[BD-03]',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 21, 1, ''21:00'', ''23:00'')');
CALL tst_esperar_error_bd('F05', 'RED', 'Sesión del sábado de 13 a 15 excede la franja', '[BD-03]',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 21, 6, ''13:00'', ''15:00'')');
CALL tst_esperar_error_bd('F06', 'RED', 'Sesión antes de las 7:00', '[BD-03]',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 21, 1, ''05:00'', ''07:00'')');
CALL tst_esperar_error_bd('F07', 'RED', 'Sesión de 3 horas en un curso de 2 horas', '[BD-02]',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 21, 1, ''13:00'', ''16:00'')');
CALL tst_esperar_error_bd('F08', 'SQL', 'Sesión que une grupo de 2026-1 con horario de 2026-2', '[BD-01]',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 1, 2, ''15:00'', ''17:00'')');
CALL tst_esperar_error_bd('F09', 'RED', 'Mover una sesión existente al almuerzo (UPDATE)', '[BD-04]',
  'UPDATE sesion SET hora_inicio = ''11:00'', hora_fin = ''13:00'' WHERE horario_id = 2 AND grupo_id = 18');
CALL tst_esperar_exito('F10', 'SQL', 'Mover una sesión existente a otro bloque válido (UPDATE)',
  'UPDATE sesion SET dia = 4, hora_inicio = ''19:00'', hora_fin = ''21:00'' WHERE horario_id = 2 AND grupo_id = 18');
CALL tst_esperar_error_bd('F11', 'SQL', 'Cambiar de periodo un grupo con sesiones', '[BD-05]',
  'UPDATE grupo SET periodo_id = 1 WHERE id = 11');
CALL tst_esperar_error_bd('F12', 'SQL', 'Cambiar de periodo un horario con sesiones', '[BD-06]',
  'UPDATE horario SET periodo_id = 1 WHERE id = 2');
CALL tst_esperar_error_bd('F13', 'SQL', 'Eliminar un horario PUBLICADO (historial)', '[BD-07]',
  'DELETE FROM horario WHERE id = 1');

-- =============================================================================
-- G. Parámetros (Tabla 26, pruebas 4 y 5) y reglas de consulta
-- =============================================================================
CALL tst_verificar('G01', 'SQL', 'Cálculo de BD para T26-4: con tolerancia 10 % el límite del grupo 12 es 44',
  'SELECT limite_operativo FROM v_grupo_cupo WHERE grupo_id = 12', '44');
CALL tst_verificar('G02', 'SQL', 'Cálculo de BD para T26-4: con tolerancia 10 % el grupo de 43 inscritos no excede',
  'SELECT excede_limite FROM v_grupo_cupo WHERE grupo_id = 12', '0');
CALL tst_esperar_exito('G03', 'SQL', 'Cálculo de BD para T26-4: cambiar la tolerancia a 5 % sin tocar código',
  'UPDATE periodo_academico SET tolerancia_cupo_pct = 5.00 WHERE id = 2');
CALL tst_verificar('G04', 'SQL', 'Cálculo de BD para T26-4: con 5 % el límite baja a 42 y el grupo de 43 excede',
  'SELECT CONCAT(limite_operativo, ''/'', excede_limite) FROM v_grupo_cupo WHERE grupo_id = 12', '42/1');
CALL tst_esperar_exito('G05', 'SQL', 'Cálculo de BD para T26-4: volver la tolerancia a 10 %',
  'UPDATE periodo_academico SET tolerancia_cupo_pct = 10.00 WHERE id = 2');
CALL tst_verificar('G06', 'SQL', 'Cálculo de BD para T26-4: con 10 % el grupo de 43 vuelve a ser aceptable',
  'SELECT excede_limite FROM v_grupo_cupo WHERE grupo_id = 12', '0');
CALL tst_verificar('G07', 'SQL', 'Cálculo de BD para T26-5: el grupo con 9 inscritos es candidato a cierre',
  'SELECT candidato_cierre FROM v_grupo_cupo WHERE grupo_id = 15', '1');
CALL tst_verificar('G08', 'SQL', 'Cálculo de BD para T26-5: el grupo con 10 inscritos NO es candidato a cierre',
  'SELECT candidato_cierre FROM v_grupo_cupo WHERE grupo_id = 16', '0');
CALL tst_verificar('G09', 'SQL', 'Cálculo de BD para T26-5: ningún grupo se cierra ni se borra solo',
  'SELECT COUNT(*) FROM grupo WHERE id IN (15, 16)', '2');
CALL tst_esperar_exito('G10', 'SQL', 'Ampliar el almuerzo a 12:00-14:00 desde la configuración',
  'UPDATE periodo_academico SET almuerzo_fin = ''14:00:00'' WHERE id = 2');
CALL tst_verificar('G11', 'SQL', 'Con almuerzo 12-14 la cuadrícula se recalcula (13-15 deja de ser válido)',
  'SELECT COUNT(*) FROM v_bloque_valido WHERE periodo_id = 2 AND hora_inicio = ''13:00:00''', '0');
CALL tst_verificar('G12', 'INSUMO', 'Vacío 4: las sesiones ya armadas que quedan en conflicto se pueden listar',
  'SELECT COUNT(*) FROM sesion s JOIN horario h ON h.id = s.horario_id JOIN periodo_academico p ON p.id = h.periodo_id WHERE h.id = 2 AND s.grupo_id <> 21 AND s.hora_inicio < p.almuerzo_fin AND s.hora_fin > p.almuerzo_inicio', '5');
CALL tst_esperar_error_bd('G13', 'RED', 'Con almuerzo 12-14 una sesión nueva de 13 a 15 se rechaza', '[BD-04]',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 20, 1, ''13:00'', ''15:00'')');
CALL tst_esperar_exito('G14', 'SQL', 'Restaurar almuerzo 12:00-13:00',
  'UPDATE periodo_academico SET almuerzo_fin = ''13:00:00'' WHERE id = 2');
CALL tst_verificar('G15', 'INSUMO', 'Insumo de T26-3 (BK03 en Java): el grupo 19 tiene 1 par de días consecutivos',
  'SELECT COUNT(*) FROM sesion s1 JOIN sesion s2 ON s2.horario_id = s1.horario_id AND s2.grupo_id = s1.grupo_id AND s2.dia = s1.dia + 1 WHERE s1.horario_id = 2 AND s1.grupo_id = 19', '1');
CALL tst_verificar('G16', 'INSUMO', 'Insumo de T26-2 (BK02 en Java): lunes 15-17 queda fuera de la disponibilidad del docente 4',
  'SELECT COUNT(*) FROM restriccion_horaria r WHERE r.docente_id = 4 AND r.dia = 1 AND r.tipo = ''FIRME'' AND r.sentido = ''DISPONIBLE'' AND r.hora_inicio <= ''15:00'' AND r.hora_fin >= ''17:00''', '0');
CALL tst_verificar('G17', 'INSUMO', 'Insumo de T26-2 (BK01 en Java): el docente 4 ya ocupa el jueves 19-21 en el horario 2',
  'SELECT COUNT(*) FROM sesion s JOIN grupo g ON g.id = s.grupo_id WHERE s.horario_id = 2 AND g.docente_id = 4 AND s.dia = 4 AND s.hora_inicio < ''21:00'' AND s.hora_fin > ''19:00''', '1');
CALL tst_verificar('G18', 'INSUMO', 'Insumo de T26-6: cursos con aula especial en el borrador (no se asigna salón)',
  'SELECT COUNT(DISTINCT curso_id) FROM v_sesion_detalle WHERE horario_id = 2 AND necesita_aula_especial = 1', '4');

ROLLBACK;

CALL tst_verificar('Z01', 'SQL', 'Tras ROLLBACK de A-G, el número de sesiones vuelve a 32',
  'SELECT COUNT(*) FROM sesion', '32');
CALL tst_verificar('Z02', 'SQL', 'Tras ROLLBACK de A-G, la tolerancia del periodo 2 vuelve a 10.00',
  'SELECT tolerancia_cupo_pct FROM periodo_academico WHERE id = 2', '10.00');

-- =============================================================================
-- H. Horarios publicados y protección del historial (V2: BD-07, BD-08, BD-11,
--    BD-12). Comportamiento vigente mientras el Comité decide D1.
-- =============================================================================
START TRANSACTION;

CALL tst_esperar_error_bd('H01', 'SQL', 'Insertar una sesión en un horario PUBLICADO', '[BD-08]',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (1, 1, 2, ''15:00'', ''17:00'')');
CALL tst_esperar_error_bd('H02', 'SQL', 'Mover (UPDATE) una sesión de un horario PUBLICADO', '[BD-08]',
  'UPDATE sesion SET hora_inicio = ''09:00'', hora_fin = ''11:00'' WHERE horario_id = 1 AND grupo_id = 1 AND dia = 1');
CALL tst_esperar_error_bd('H03', 'SQL', 'Eliminar una sesión de un horario PUBLICADO', '[BD-08]',
  'DELETE FROM sesion WHERE horario_id = 1 AND grupo_id = 4');
CALL tst_esperar_error_bd('H04', 'SQL', 'Trasladar una sesión de un borrador a un horario PUBLICADO', '[BD-08]',
  'UPDATE sesion SET horario_id = 1 WHERE horario_id = 2 AND grupo_id = 18');
CALL tst_esperar_error_bd('H05', 'SQL', 'Vaciar el horario PUBLICADO para luego borrarlo (DELETE masivo)', '[BD-08]',
  'DELETE FROM sesion WHERE horario_id = 1');
CALL tst_verificar('H06', 'SQL', 'El horario PUBLICADO conserva sus 8 sesiones',
  'SELECT COUNT(*) FROM sesion WHERE horario_id = 1', '8');
CALL tst_esperar_error_bd('H07', 'SQL', 'Crear un horario directamente como PUBLICADO', '[BD-11]',
  'INSERT INTO horario (periodo_id, estado, fecha_publicacion) VALUES (2, ''PUBLICADO'', ''2026-10-21 08:00:00'')');
CALL tst_esperar_exito('H08', 'SQL', 'Crear un borrador vacío en 2026-2',
  'INSERT INTO horario (id, periodo_id) VALUES (50, 2)');
CALL tst_esperar_error_bd('H09', 'SQL', 'Publicar un horario sin sesiones', '[BD-12]',
  'UPDATE horario SET estado = ''PUBLICADO'', fecha_publicacion = ''2026-10-21 08:00:00'' WHERE id = 50');
CALL tst_esperar_exito('H10', 'SQL', 'Eliminar un borrador vacío',
  'DELETE FROM horario WHERE id = 50');
CALL tst_esperar_error_bd('H11', 'SQL', 'Eliminar el horario PUBLICADO', '[BD-07]',
  'DELETE FROM horario WHERE id = 1');
CALL tst_verificar('H12', 'SQL', 'v_horario_vigente: 2026-1 -> horario 1; 2026-2 sin publicado',
  'SELECT GROUP_CONCAT(CONCAT(periodo, '':'', horario_id) ORDER BY periodo) FROM v_horario_vigente', '2026-1:1');
-- Flujo de republicación compatible con la suposición vigente (D1-b).
CALL tst_esperar_exito('H13', 'SQL', 'D1 pendiente (vigente): despublicar el horario 1 se permite',
  'UPDATE horario SET estado = ''BORRADOR'', version = version + 1 WHERE id = 1');
CALL tst_esperar_exito('H14', 'SQL', 'En BORRADOR la sesión sí se puede mover',
  'UPDATE sesion SET dia = 2 WHERE horario_id = 1 AND grupo_id = 3 AND dia = 1');
CALL tst_esperar_exito('H15', 'SQL', 'Republicar el horario 1 (acción explícita del Comité)',
  'UPDATE horario SET estado = ''PUBLICADO'', fecha_publicacion = ''2026-10-21 10:00:00'', version = version + 1 WHERE id = 1');
CALL tst_esperar_error_bd('H16', 'SQL', 'Republicado, vuelve a quedar protegido', '[BD-08]',
  'UPDATE sesion SET dia = 4 WHERE horario_id = 1 AND grupo_id = 3 AND dia = 2');
CALL tst_verificar('H17', 'SQL', 'v_horario_vigente refleja la nueva fecha de publicación',
  'SELECT fecha_publicacion FROM v_horario_vigente WHERE horario_id = 1', '2026-10-21 10:00:00');
-- Flujo alternativo (D1-c): el esquema permite copiar a un borrador nuevo.
CALL tst_esperar_exito('H18', 'SQL', 'D1-c posible: crear borrador 60 en 2026-1',
  'INSERT INTO horario (id, periodo_id) VALUES (60, 1)');
CALL tst_esperar_exito('H19', 'SQL', 'D1-c posible: copiar las sesiones del publicado al borrador 60',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) SELECT 60, grupo_id, dia, hora_inicio, hora_fin FROM sesion WHERE horario_id = 1');
CALL tst_verificar('H20', 'SQL', 'El borrador 60 tiene las 8 sesiones copiadas',
  'SELECT COUNT(*) FROM sesion WHERE horario_id = 60', '8');
CALL tst_esperar_exito('H21', 'SQL', 'D1 pendiente (vigente): hoy se permite un segundo PUBLICADO en el periodo',
  'UPDATE horario SET estado = ''PUBLICADO'', fecha_publicacion = ''2026-10-22 09:00:00'' WHERE id = 60');
CALL tst_verificar('H22', 'SQL', 'Con dos publicados, v_horario_vigente elige el más reciente (60)',
  'SELECT horario_id FROM v_horario_vigente WHERE periodo = ''2026-1''', '60');

ROLLBACK;

CALL tst_verificar('H23', 'SQL', 'Tras ROLLBACK de H, el horario 1 sigue PUBLICADO con su fecha original',
  'SELECT CONCAT(estado, '' '', fecha_publicacion) FROM horario WHERE id = 1', 'PUBLICADO 2026-01-20 17:00:00');

-- =============================================================================
-- I. Cambios de parámetros con horarios existentes (vacío 4).
--    La BD no bloquea el cambio (decisión D2 pendiente); lo hace visible en
--    v_sesion_conflicto_parametros y vuelve a validar cada sesión que se mueva.
-- =============================================================================
START TRANSACTION;

CALL tst_verificar('I01', 'SQL', 'Con los datos de prueba no hay sesiones en conflicto con los parámetros',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros', '0');
-- Almuerzo
CALL tst_esperar_exito('I02', 'SQL', 'Ampliar el almuerzo de 2026-2 a 12:00-14:00',
  'UPDATE periodo_academico SET almuerzo_fin = ''14:00:00'' WHERE id = 2');
CALL tst_verificar('I03', 'SQL', 'Se marcan 5 sesiones del borrador por ALMUERZO',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 2 AND motivo = ''ALMUERZO''', '5');
CALL tst_verificar('I04', 'SQL', 'Las mismas 5 quedan fuera de la CUADRICULA recalculada',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 2 AND motivo = ''CUADRICULA''', '5');
CALL tst_esperar_exito('I05', 'RED', 'Mover una sesión en conflicto a un bloque válido se acepta',
  'UPDATE sesion SET hora_inicio = ''17:00'', hora_fin = ''19:00'' WHERE horario_id = 2 AND grupo_id = 17 AND dia = 2');
CALL tst_esperar_error_bd('I06', 'RED', 'Mover una sesión en conflicto a otro bloque que pisa el almuerzo nuevo', '[BD-04]',
  'UPDATE sesion SET dia = 3 WHERE horario_id = 2 AND grupo_id = 14 AND dia = 4');
CALL tst_verificar('I07', 'SQL', 'Quedan 4 sesiones marcadas por ALMUERZO',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 2 AND motivo = ''ALMUERZO''', '4');
CALL tst_esperar_exito('I08', 'SQL', 'Restaurar el almuerzo 12:00-13:00',
  'UPDATE periodo_academico SET almuerzo_fin = ''13:00:00'' WHERE id = 2');
-- Franja
CALL tst_esperar_exito('I09', 'SQL', 'Mover el inicio de la franja L-V de 2026-2 a las 08:00',
  'UPDATE periodo_academico SET hora_inicio_semana = ''08:00:00'' WHERE id = 2');
CALL tst_verificar('I10', 'SQL', 'Se marcan por FRANJA las 6 sesiones L-V que empiezan a las 07:00',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 2 AND motivo = ''FRANJA''', '6');
CALL tst_verificar('I11', 'SQL', 'La sesión del sábado no se afecta (franja propia)',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 2 AND dia = 6', '0');
CALL tst_esperar_error_bd('I12', 'RED', 'Una sesión nueva a las 07:00 entre semana se rechaza', '[BD-03]',
  'INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES (2, 21, 4, ''07:00'', ''09:00'')');
CALL tst_esperar_exito('I13', 'SQL', 'Restaurar la franja 07:00',
  'UPDATE periodo_academico SET hora_inicio_semana = ''07:00:00'' WHERE id = 2');
-- Duración del bloque
CALL tst_esperar_exito('I14', 'SQL', 'Cambiar el bloque de 2026-2 a 90 minutos',
  'UPDATE periodo_academico SET duracion_bloque_min = 90 WHERE id = 2');
CALL tst_verificar('I15', 'SQL', 'Las 24 sesiones del borrador se marcan por DURACION_BLOQUE (curso de 120 frente a bloque de 90)',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 2 AND motivo = ''DURACION_BLOQUE''', '24');
CALL tst_verificar('I16', 'SQL', 'Las 24 quedan fuera de la CUADRICULA de 90 minutos',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 2 AND motivo = ''CUADRICULA''', '24');
CALL tst_verificar('I17', 'SQL', 'El horario 1 (otro periodo) no se afecta',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 1', '0');
CALL tst_esperar_error('I18', 'SQL', 'CHECK nuevo: la franja L-V no puede ser más corta que un bloque', 3819,
  'UPDATE periodo_academico SET duracion_bloque_min = 120, hora_fin_semana = ''08:00:00'' WHERE id = 2');
CALL tst_esperar_exito('I19', 'SQL', 'Restaurar el bloque de 120 minutos',
  'UPDATE periodo_academico SET duracion_bloque_min = 120 WHERE id = 2');
-- Máximo de sesiones y cupos
CALL tst_esperar_exito('I20', 'SQL', 'Bajar el máximo de sesiones semanales de 2026-2 a 3',
  'UPDATE periodo_academico SET max_sesiones_semana = 3 WHERE id = 2');
CALL tst_verificar('I21', 'INSUMO', 'Insumo para Java: 1 curso con grupos en 2026-2 supera el nuevo máximo (Sistemas operativos)',
  'SELECT COUNT(DISTINCT c.id) FROM curso c JOIN grupo g ON g.curso_id = c.id JOIN periodo_academico p ON p.id = g.periodo_id WHERE p.id = 2 AND c.sesiones_semanales > p.max_sesiones_semana', '1');
CALL tst_esperar_exito('I22', 'SQL', 'Cambiar el cupo base de 2026-2 a 30',
  'UPDATE periodo_academico SET cupo_maximo_base = 30, max_sesiones_semana = 4 WHERE id = 2');
CALL tst_verificar('I23', 'SQL', 'El cupo base no se propaga a los grupos existentes (grupo 12 sigue en 40)',
  'SELECT cupo_maximo FROM grupo WHERE id = 12', '40');
-- Periodo con horario PUBLICADO (riesgo que cubre la decisión D2)
CALL tst_esperar_exito('I24', 'SQL', 'D2 pendiente (vigente): se permite cambiar el almuerzo de un periodo con horario PUBLICADO',
  'UPDATE periodo_academico SET almuerzo_fin = ''14:00:00'' WHERE id = 1');
CALL tst_verificar('I25', 'SQL', 'Consecuencia: 2 sesiones del horario PUBLICADO quedan en conflicto con su propio periodo',
  'SELECT COUNT(*) FROM v_sesion_conflicto_parametros WHERE horario_id = 1 AND estado_horario = ''PUBLICADO'' AND motivo = ''ALMUERZO''', '2');

ROLLBACK;

CALL tst_verificar('I26', 'SQL', 'Tras ROLLBACK de I, los parámetros vuelven a sus valores iniciales',
  'SELECT CONCAT(almuerzo_fin, '' '', hora_inicio_semana, '' '', duracion_bloque_min, '' '', max_sesiones_semana, '' '', cupo_maximo_base) FROM periodo_academico WHERE id = 2', '13:00:00 07:00:00 120 4 40');

-- =============================================================================
-- J. Integridad histórica al cambiar docentes, cursos y restricciones
-- =============================================================================
START TRANSACTION;

CALL tst_esperar_error_bd('J01', 'SQL', 'Cambiar la duración de un curso con sesiones', '[BD-09]',
  'UPDATE curso SET duracion_sesion_min = 90 WHERE id = 1');
CALL tst_esperar_exito('J02', 'SQL', 'Crear un curso sin grupos',
  'INSERT INTO curso (id, codigo, nombre, sesiones_semanales) VALUES (50, ''FIC-999'', ''Curso de prueba'', 2)');
CALL tst_esperar_exito('J03', 'SQL', 'Un curso sin sesiones sí puede cambiar de duración',
  'UPDATE curso SET duracion_sesion_min = 90 WHERE id = 50');
CALL tst_esperar_error_bd('J04', 'SQL', 'Cambiar el curso de un grupo con sesiones', '[BD-10]',
  'UPDATE grupo SET curso_id = 2 WHERE id = 11');
CALL tst_esperar_exito('J05', 'SQL', 'Crear un grupo sin sesiones',
  'INSERT INTO grupo (id, periodo_id, curso_id, docente_id, codigo, cupo_maximo, cupo_minimo) VALUES (50, 2, 7, 1, ''02'', 40, 10)');
CALL tst_esperar_exito('J06', 'SQL', 'Un grupo sin sesiones sí puede cambiar de curso',
  'UPDATE grupo SET curso_id = 9 WHERE id = 50');
CALL tst_esperar_exito('J07', 'LIMITE', 'D3 pendiente (vigente): se permite cambiar el docente de un grupo con sesiones PUBLICADAS',
  'UPDATE grupo SET docente_id = 6 WHERE id = 3');
CALL tst_verificar('J08', 'LIMITE', 'Limitación: el horario PUBLICADO de 2026-1 muestra ahora al docente nuevo',
  'SELECT COUNT(*) FROM v_sesion_detalle WHERE horario_id = 1 AND grupo_id = 3 AND docente_id = 6', '2');
CALL tst_esperar_exito('J09', 'SQL', 'Actualizar inscritos de un grupo publicado se permite (la inscripción es posterior a publicar)',
  'UPDATE grupo SET inscritos = 33 WHERE id = 1');
CALL tst_esperar_exito('J10', 'LIMITE', 'Renombrar un curso se permite (corrección de datos)',
  'UPDATE curso SET nombre = ''Programación I (renombrado)'' WHERE id = 1');
CALL tst_verificar('J11', 'LIMITE', 'Limitación: el horario PUBLICADO muestra el nombre nuevo',
  'SELECT COUNT(*) FROM v_sesion_detalle WHERE horario_id = 1 AND curso LIKE ''%renombrado%''', '3');
CALL tst_esperar_exito('J12', 'LIMITE', 'Cambiar la frecuencia de un curso con historial se permite',
  'UPDATE curso SET sesiones_semanales = 4 WHERE id = 1');
CALL tst_verificar('J13', 'INSUMO', 'Insumo para Java: el horario PUBLICADO parece incompleto si se reevalúa con la frecuencia nueva',
  'SELECT COUNT(*) FROM (SELECT g.id FROM grupo g JOIN curso c ON c.id = g.curso_id LEFT JOIN sesion s ON s.grupo_id = g.id AND s.horario_id = 1 WHERE g.periodo_id = 1 GROUP BY g.id, c.sesiones_semanales HAVING COUNT(s.id) <> c.sesiones_semanales) t', '1');
CALL tst_esperar_exito('J14', 'SQL', 'Agregar una restricción FIRME que choca con sesiones ya programadas se permite',
  'INSERT INTO restriccion_horaria (docente_id, dia, hora_inicio, hora_fin, tipo, sentido) VALUES (5, 1, ''07:00'', ''09:00'', ''FIRME'', ''NO_DISPONIBLE'')');
CALL tst_verificar('J15', 'INSUMO', 'Insumo para Java: sesiones (borrador y publicado) que ahora pisan esa restricción',
  'SELECT COUNT(*) FROM sesion s JOIN grupo g ON g.id = s.grupo_id JOIN restriccion_horaria r ON r.docente_id = g.docente_id AND r.dia = s.dia AND r.tipo = ''FIRME'' AND r.sentido = ''NO_DISPONIBLE'' WHERE r.hora_inicio < s.hora_fin AND s.hora_inicio < r.hora_fin', '2');
CALL tst_esperar_error('J16', 'SQL', 'Eliminar un docente con grupos sigue bloqueado aunque se quiera reasignar', 1451,
  'DELETE FROM docente WHERE id = 2');

ROLLBACK;

-- =============================================================================
-- K. Contrato JPA (CONTRATO_JPA.md). Si alguna de estas pruebas falla, el
--    esquema cambió: actualice el contrato y las entidades antes de integrar.
-- =============================================================================
START TRANSACTION;

CALL tst_verificar('K01', 'SQL', 'Huella SHA-256 de columnas (tabla, columna, tipo, nulabilidad, default, collation)',
  'SELECT SHA2(GROUP_CONCAT(CONCAT_WS(''|'', table_name, ordinal_position, column_name, column_type, is_nullable, IFNULL(column_default, ''-''), IFNULL(collation_name, ''-'')) ORDER BY table_name, ordinal_position SEPARATOR '';''), 256) FROM information_schema.columns WHERE table_schema = ''horarios_ueb'' AND table_name IN (''periodo_academico'',''docente'',''docente_especialidad'',''restriccion_horaria'',''curso'',''grupo'',''horario'',''sesion'')',
  '3cad7286b09207d269d78c2a7604e8049d4b8ac133f5b2b583a18a7850ae4299');
CALL tst_verificar('K02', 'SQL', 'Nombres exactos de las 8 claves foráneas y sus columnas',
  'SELECT GROUP_CONCAT(CONCAT(constraint_name, '':'', table_name, ''.'', column_name, ''->'', referenced_table_name, ''.'', referenced_column_name) ORDER BY constraint_name SEPARATOR '','') FROM information_schema.key_column_usage WHERE table_schema = ''horarios_ueb'' AND referenced_table_name IS NOT NULL',
  'fk_docente_especialidad_docente:docente_especialidad.docente_id->docente.id,fk_grupo_curso:grupo.curso_id->curso.id,fk_grupo_docente:grupo.docente_id->docente.id,fk_grupo_periodo_academico:grupo.periodo_id->periodo_academico.id,fk_horario_periodo_academico:horario.periodo_id->periodo_academico.id,fk_restriccion_horaria_docente:restriccion_horaria.docente_id->docente.id,fk_sesion_grupo:sesion.grupo_id->grupo.id,fk_sesion_horario:sesion.horario_id->horario.id');
CALL tst_verificar('K03', 'SQL', 'Objetos de programa: 8 triggers / 2 procedimientos / 5 vistas',
  'SELECT CONCAT((SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema = ''horarios_ueb''), ''/'', (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = ''horarios_ueb'' AND routine_name NOT LIKE ''tst\\_%''), ''/'', (SELECT COUNT(*) FROM information_schema.views WHERE table_schema = ''horarios_ueb''))',
  '8/2/5');
CALL tst_esperar_exito('K04', 'SQL', 'Enum TipoVinculacion: los 4 valores Java se aceptan',
  'INSERT INTO docente (nombre, tipo_vinculacion) VALUES (''K a'', ''TC''), (''K b'', ''TRES_CUARTOS''), (''K c'', ''MEDIO_TIEMPO''), (''K d'', ''CUARTO_TIEMPO'')');
CALL tst_esperar_exito('K05', 'SQL', 'Enums TipoRestriccion y SentidoRestriccion: las 4 combinaciones se aceptan',
  'INSERT INTO restriccion_horaria (docente_id, dia, hora_inicio, hora_fin, tipo, sentido) VALUES (1, 6, ''07:00'', ''08:00'', ''FIRME'', ''DISPONIBLE''), (1, 6, ''07:00'', ''08:00'', ''FIRME'', ''NO_DISPONIBLE''), (1, 6, ''07:00'', ''08:00'', ''PREFERENCIA'', ''DISPONIBLE''), (1, 6, ''07:00'', ''08:00'', ''PREFERENCIA'', ''NO_DISPONIBLE'')');
CALL tst_esperar_error('K06', 'SQL', 'Enum en minúsculas (tc) se rechaza: Hibernate no podría leerlo', 3819,
  'INSERT INTO docente (nombre, tipo_vinculacion) VALUES (''K e'', ''tc'')');
CALL tst_esperar_error('K07', 'SQL', 'Enum con mayúsculas mezcladas (Firme) se rechaza', 3819,
  'INSERT INTO restriccion_horaria (docente_id, dia, hora_inicio, hora_fin, tipo, sentido) VALUES (1, 6, ''09:00'', ''10:00'', ''Firme'', ''DISPONIBLE'')');
CALL tst_esperar_error('K08', 'SQL', 'Enum EstadoHorario en minúsculas (borrador) se rechaza', 3819,
  'INSERT INTO horario (periodo_id, estado) VALUES (2, ''borrador'')');
CALL tst_esperar_error('K09', 'SQL', 'Enum con espacio final (TC ) se rechaza', 3819,
  'INSERT INTO docente (nombre, tipo_vinculacion) VALUES (''K f'', ''TC '')');
CALL tst_esperar_error('K10', 'SQL', 'Boolean necesita_aula_especial = 2 se rechaza', 3819,
  'INSERT INTO curso (nombre, sesiones_semanales, necesita_aula_especial) VALUES (''K curso'', 1, 2)');
CALL tst_esperar_exito('K11', 'SQL', 'DiaSemanaConverter: los días 1 (lunes) a 6 (sábado) se aceptan',
  'INSERT INTO restriccion_horaria (docente_id, dia, hora_inicio, hora_fin, tipo, sentido) VALUES (2, 1, ''07:00'', ''08:00'', ''FIRME'', ''DISPONIBLE''), (2, 6, ''07:00'', ''08:00'', ''FIRME'', ''DISPONIBLE'')');
CALL tst_verificar('K12', 'SQL', 'Las columnas enum usan la collation binaria utf8mb4_0900_bin',
  'SELECT GROUP_CONCAT(CONCAT(table_name, ''.'', column_name) ORDER BY table_name, column_name) FROM information_schema.columns WHERE table_schema = ''horarios_ueb'' AND collation_name = ''utf8mb4_0900_bin'' AND table_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema = ''horarios_ueb'' AND table_type = ''BASE TABLE'')',
  'docente.tipo_vinculacion,horario.estado,restriccion_horaria.sentido,restriccion_horaria.tipo');

ROLLBACK;

-- =============================================================================
-- [BACKEND] Pruebas que NO corresponden a SQL y deben implementarse en
-- JUnit 5 / Mockito / Spring Boot Test (paquete validation, Sección 6.3).
-- Ninguna prueba de este archivo las sustituye: las categorías RED e INSUMO
-- solo comprueban la red de seguridad de la BD o los datos que Java consulta.
--
--  BK01  Choque de docente al soltar una sesión: rechazo con docente, franja
--        y motivo (Tabla 19 rev. 3; Tabla 26 prueba 2, segundo caso).
--  BK02  Disponibilidad: interpretación FIRME/PREFERENCIA y DISPONIBLE/
--        NO_DISPONIBLE (Tabla 19 rev. 4; Tabla 26 prueba 2, primer caso).
--  BK03  Días consecutivos: aviso amarillo, no bloqueo; sábado-lunes no son
--        consecutivos (Tabla 19 rev. 5; Tabla 26 prueba 3).
--  BK04  Alineación con la cuadrícula de bloques fijos (v_bloque_valido) y
--        excepciones autorizadas por el Comité (vacío 12).
--  BK05  Rechazo de grupos con inscritos > límite operativo y de cursos con
--        frecuencia > max_sesiones_semana (Tabla 26 prueba 4; EF02).
--  BK06  Generador: propuesta o reporte de cursos no ubicados (EF03); grupos
--        del mismo curso en horas distintas (vacío 6).
--  BK07  Publicación: solo por acción del Comité y tras validar el horario
--        completo con todas las reglas (la BD acepta publicar un horario con
--        conflictos de docente o de parámetros; ver 05_tests P3-07).
--  BK08  Concurrencia: dos editores moviendo sesiones del mismo horario
--        (PESSIMISTIC_WRITE sobre horario y @Version).
--  BK09  Traducción de los errores [BD-01]..[BD-12] (y [BD-14]..[BD-16] si se
--        aprueban) a mensajes de la interfaz.
--  BK10  Ajuste en 3 interacciones y deshacer el último movimiento (ENF01).
--  BK11  Flujo de republicación según la decisión D1 (b o c), incluida la
--        revalidación completa antes de volver a publicar.
--  BK12  Cambio de parámetros: mostrar el impacto (v_sesion_conflicto_parametros)
--        y pedir confirmación antes de guardar; nunca mover sesiones solo.
--  BK13  Cambio de docente, curso o restricciones: revalidar los horarios en
--        BORRADOR del periodo; no reevaluar como error los PUBLICADOS de
--        periodos cerrados (J13, J15).
-- =============================================================================

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

-- Fin de 04_tests.sql
