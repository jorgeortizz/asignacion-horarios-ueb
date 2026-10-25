-- Auditoría previa al cambio institucional de almuerzo a [13:00, 14:00).
-- SOLO LECTURA. Ejecutar con el esquema objetivo ya seleccionado.
-- No aplica V3 ni cambia parámetros, sesiones o estados de publicación.
-- Revisar el resultado antes de preparar/aplicar V3 o actualizar un periodo.
-- Las consultas de datos comparten una instantánea InnoDB de solo lectura.

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY;

SET @preflight_v3_alm_inicio := CAST('13:00:00' AS TIME);
SET @preflight_v3_alm_fin := CAST('14:00:00' AS TIME);

-- 1. Esquema REAL: tipos, nulabilidad, defaults y restricciones vigentes.
SELECT DATABASE() AS esquema, VERSION() AS mysql_version,
       @preflight_v3_alm_inicio AS almuerzo_propuesto_inicio,
       @preflight_v3_alm_fin AS almuerzo_propuesto_fin;

SHOW CREATE TABLE periodo_academico;

SELECT column_name, column_type, is_nullable, column_default, extra
  FROM information_schema.columns
 WHERE table_schema = DATABASE()
   AND table_name = 'periodo_academico'
 ORDER BY ordinal_position;

-- Contrato y protecciones REALES, además de las versiones del repositorio.
SHOW CREATE TABLE horario;
SHOW CREATE TABLE sesion;
SHOW CREATE TABLE grupo;
SHOW CREATE TABLE curso;
SHOW CREATE TABLE restriccion_horaria;

SELECT trigger_name, event_object_table, action_timing, event_manipulation,
       action_statement, sql_mode
  FROM information_schema.triggers
 WHERE trigger_schema = DATABASE()
 ORDER BY event_object_table, trigger_name;

SELECT routine_name, routine_type, sql_data_access, security_type,
       routine_definition, sql_mode
  FROM information_schema.routines
 WHERE routine_schema = DATABASE()
   AND routine_name IN ('sp_validar_sesion', 'sp_verificar_horario_editable')
 ORDER BY routine_name;

-- Si las definiciones están vacías/NULL, falta visibilidad de metadatos:
-- pedir al administrador SHOW TRIGGERS y SHOW CREATE PROCEDURE de ambas rutinas.
SELECT table_name, view_definition
  FROM information_schema.views
 WHERE table_schema = DATABASE()
   AND table_name IN ('v_bloque_valido', 'v_sesion_conflicto_parametros')
 ORDER BY table_name;

-- La ausencia de historial se informa sin asumir que Flyway ya gestionó la BD.
SET @preflight_v3_historial_sql := IF(
  EXISTS (SELECT 1 FROM information_schema.tables
           WHERE table_schema = DATABASE() AND table_name = 'flyway_schema_history'),
  'SELECT installed_rank, version, description, type, script, checksum, installed_on, success FROM flyway_schema_history ORDER BY installed_rank',
  'SELECT ''No existe flyway_schema_history en el esquema seleccionado'' AS historial_flyway');
PREPARE preflight_v3_historial FROM @preflight_v3_historial_sql;
EXECUTE preflight_v3_historial;
DEALLOCATE PREPARE preflight_v3_historial;

-- 2. Parámetros de TODOS los periodos, con número de horarios publicados.
-- Se conserva el contexto histórico: el almuerzo propuesto no se guarda.
SELECT p.*,
       (SELECT COUNT(*) FROM horario h WHERE h.periodo_id = p.id) AS horarios,
       (SELECT COUNT(*) FROM horario h
         WHERE h.periodo_id = p.id AND h.estado = 'PUBLICADO') AS horarios_publicados
  FROM periodo_academico p
 ORDER BY p.id;

-- Instantánea del histórico que el plan debe preservar sin ningún cambio.
SELECT p.* FROM periodo_academico p WHERE p.nombre = '2026-1';
SELECT h.* FROM horario h JOIN periodo_academico p ON p.id = h.periodo_id
 WHERE p.nombre = '2026-1' ORDER BY h.id;
SELECT s.* FROM sesion s JOIN horario h ON h.id = s.horario_id
 JOIN periodo_academico p ON p.id = h.periodo_id
 WHERE p.nombre = '2026-1' ORDER BY s.id;

-- Todos los publicados, incluidos los que no son el vigente del periodo.
SELECT p.id AS periodo_id, p.nombre AS periodo, h.id AS horario_id,
       h.estado, h.fecha_publicacion, COUNT(s.id) AS sesiones,
       COALESCE(SUM(s.hora_inicio < @preflight_v3_alm_fin
                    AND s.hora_fin > @preflight_v3_alm_inicio), 0)
         AS sesiones_afectadas_por_almuerzo_propuesto
  FROM periodo_academico p
  JOIN horario h ON h.periodo_id = p.id AND h.estado = 'PUBLICADO'
  LEFT JOIN sesion s ON s.horario_id = h.id
 GROUP BY p.id, p.nombre, h.id, h.estado, h.fecha_publicacion
 ORDER BY p.id, h.fecha_publicacion, h.id;

-- 3. Detalle del impacto HIPOTÉTICO de [13:00,14:00), sin actualizar filas.
-- Terminar exactamente a las 13:00 o empezar a las 14:00 no se solapa.
SELECT p.id AS periodo_id, p.nombre AS periodo,
       p.almuerzo_inicio AS almuerzo_actual_inicio,
       p.almuerzo_fin AS almuerzo_actual_fin,
       h.id AS horario_id, h.estado AS estado_horario, h.fecha_publicacion,
       s.id AS sesion_id, s.grupo_id, g.codigo AS grupo,
       g.docente_id, d.nombre AS docente, g.curso_id, c.nombre AS curso,
       s.dia, s.hora_inicio, s.hora_fin,
       (s.hora_inicio < p.almuerzo_fin AND s.hora_fin > p.almuerzo_inicio)
         AS conflicto_con_almuerzo_actual,
       NOT (s.hora_inicio < p.almuerzo_fin AND s.hora_fin > p.almuerzo_inicio)
         AS conflicto_nuevo_de_almuerzo
  FROM sesion s
  JOIN horario h ON h.id = s.horario_id
  JOIN periodo_academico p ON p.id = h.periodo_id
  JOIN grupo g ON g.id = s.grupo_id
  JOIN docente d ON d.id = g.docente_id
  JOIN curso c ON c.id = g.curso_id
 WHERE s.hora_inicio < @preflight_v3_alm_fin
   AND s.hora_fin > @preflight_v3_alm_inicio
 ORDER BY p.id, h.estado, h.id, s.dia, s.hora_inicio, s.id;

-- Conteos por periodo, horario y estado: incluye horarios sin afectados.
SELECT p.id AS periodo_id, p.nombre AS periodo, h.id AS horario_id,
       h.estado AS estado_horario, COUNT(s.id) AS sesiones,
       COALESCE(SUM(s.hora_inicio < @preflight_v3_alm_fin
                    AND s.hora_fin > @preflight_v3_alm_inicio), 0)
         AS sesiones_afectadas,
       COALESCE(SUM(s.hora_inicio < @preflight_v3_alm_fin
                    AND s.hora_fin > @preflight_v3_alm_inicio
                    AND NOT (s.hora_inicio < p.almuerzo_fin
                             AND s.hora_fin > p.almuerzo_inicio)), 0)
         AS conflictos_nuevos_de_almuerzo
  FROM periodo_academico p
  LEFT JOIN horario h ON h.periodo_id = p.id
  LEFT JOIN sesion s ON s.horario_id = h.id
 GROUP BY p.id, p.nombre, h.id, h.estado
 ORDER BY p.id, h.estado, h.id;

-- Resumen por periodo y estado; un periodo sin horarios también aparece.
SELECT p.id AS periodo_id, p.nombre AS periodo, h.estado AS estado_horario,
       COUNT(DISTINCT h.id) AS horarios, COUNT(s.id) AS sesiones,
       COALESCE(SUM(s.hora_inicio < @preflight_v3_alm_fin
                    AND s.hora_fin > @preflight_v3_alm_inicio), 0)
         AS sesiones_afectadas
  FROM periodo_academico p
  LEFT JOIN horario h ON h.periodo_id = p.id
  LEFT JOIN sesion s ON s.horario_id = h.id
 GROUP BY p.id, p.nombre, h.estado
 ORDER BY p.id, h.estado;

-- 4. Conflictos YA EXISTENTES con los parámetros actuales, por separado.
-- Una sesión puede aparecer varias veces porque incumple reglas diferentes.
SELECT v.periodo_id, p.nombre AS periodo, v.horario_id, v.estado_horario,
       v.sesion_id, v.grupo_id, v.dia, v.hora_inicio, v.hora_fin, v.motivo
  FROM v_sesion_conflicto_parametros v
  JOIN periodo_academico p ON p.id = v.periodo_id
 ORDER BY v.periodo_id, v.horario_id, v.sesion_id, v.motivo;

-- 5. Cuadrícula ACTUAL calculada con cada periodo, sin reanclar el almuerzo.
-- Con los nuevos defaults: L-V 07,09,11,15,17,19 y sábado 07,09,11 (33).
SELECT b.periodo_id, p.nombre AS periodo, b.dia, b.hora_inicio, b.hora_fin,
       p.duracion_bloque_min, p.almuerzo_inicio, p.almuerzo_fin
  FROM v_bloque_valido b
  JOIN periodo_academico p ON p.id = b.periodo_id
 ORDER BY b.periodo_id, b.dia, b.hora_inicio;

SELECT p.id AS periodo_id, p.nombre AS periodo, COUNT(b.periodo_id) AS bloques_semanales
  FROM periodo_academico p
  LEFT JOIN v_bloque_valido b ON b.periodo_id = p.id
 GROUP BY p.id, p.nombre
 ORDER BY p.id;

ROLLBACK;
