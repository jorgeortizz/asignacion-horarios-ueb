-- Propuestas de reubicación del borrador 2026-2, SIN modificar datos.
-- MySQL 8.0.45. Seleccionar horarios_ueb antes de ejecutar este archivo.
-- Los IDs y las restricciones se consultan en la BD; no se asumen los del seed.
-- Revisar también preflight_V3.sql para el esquema, las rutinas y los publicados.
-- INDIVIDUAL: opciones contra las sesiones actuales, excluyendo la que se mueve.
-- PLAN: verifica simultáneamente TODAS las sesiones, reemplazando las afectadas
--       por 15:00-17:00 en sus mismos días (duración tomada del periodo).
-- No combinar opciones INDIVIDUAL sin volver a verificar el conjunto elegido.
-- Este análisis no publica horarios ni asigna aulas especiales.

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY;

SET @reubicacion_periodo := '2026-2';
SET @reubicacion_horario := 2;
SET @reubicacion_alm_inicio := CAST('13:00:00' AS TIME);
SET @reubicacion_alm_fin := CAST('14:00:00' AS TIME);
SET @reubicacion_plan_inicio := CAST('15:00:00' AS TIME);

-- 1. Contexto y condiciones de la operación propuesta. Debe aparecer una fila,
--    horario BORRADOR, cinco afectadas y cero publicados en el periodo objetivo.
SELECT p.id AS periodo_id, p.nombre AS periodo, h.id AS horario_id, h.estado,
       p.almuerzo_inicio, p.almuerzo_fin, p.duracion_bloque_min,
       COUNT(s.id) AS sesiones_actuales,
       COALESCE(SUM(s.hora_inicio < @reubicacion_alm_fin
                    AND s.hora_fin > @reubicacion_alm_inicio), 0) AS afectadas,
       (SELECT COUNT(*) FROM horario hp
         WHERE hp.periodo_id = p.id AND hp.estado = 'PUBLICADO') AS publicados_del_periodo
  FROM periodo_academico p
  JOIN horario h ON h.periodo_id = p.id AND h.id = @reubicacion_horario
  LEFT JOIN sesion s ON s.horario_id = h.id
 WHERE p.nombre = @reubicacion_periodo
 GROUP BY p.id, p.nombre, h.id, h.estado,
          p.almuerzo_inicio, p.almuerzo_fin, p.duracion_bloque_min;

-- Lista exacta solicitada: no inferir IDs reales a partir del orden del seed.
SELECT s.id AS sesion_id, h.id AS horario_id, h.estado,
       c.id AS curso_id, c.codigo AS curso_codigo, c.nombre AS curso,
       g.id AS grupo_id, g.codigo AS grupo,
       d.id AS docente_id, d.nombre AS docente,
       s.dia, ELT(s.dia, 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado') AS dia_nombre,
       s.hora_inicio, s.hora_fin
  FROM sesion s
  JOIN horario h ON h.id = s.horario_id
  JOIN periodo_academico p ON p.id = h.periodo_id
  JOIN grupo g ON g.id = s.grupo_id
  JOIN curso c ON c.id = g.curso_id
  JOIN docente d ON d.id = g.docente_id
 WHERE p.nombre = @reubicacion_periodo AND h.id = @reubicacion_horario
   AND s.hora_inicio < @reubicacion_alm_fin
   AND s.hora_fin > @reubicacion_alm_inicio
 ORDER BY s.id;

-- 2. Candidatos y verificación conjunta. La vista vigente conserva su ancla
--    franja_inicio + k * duración. Filtrar además el almuerzo nuevo obtiene
--    bloques comunes con ambas reglas; 11-13 queda fuera mientras rija 12-13.
WITH
actuales AS (
    SELECT s.id AS sesion_id, s.grupo_id, s.dia, s.hora_inicio, s.hora_fin,
           h.id AS horario_id, h.estado, h.periodo_id,
           g.periodo_id AS periodo_grupo_id, g.codigo AS grupo, g.docente_id,
           d.nombre AS docente, c.id AS curso_id, c.nombre AS curso,
           c.duracion_sesion_min, c.sesiones_semanales, c.necesita_aula_especial,
           g.inscritos, g.cupo_maximo, g.cupo_minimo,
           p.duracion_bloque_min, p.max_sesiones_semana, p.tolerancia_cupo_pct,
           p.hora_inicio_semana, p.hora_fin_semana,
           p.hora_inicio_sabado, p.hora_fin_sabado,
           p.almuerzo_inicio, p.almuerzo_fin,
           (s.hora_inicio < @reubicacion_alm_fin
            AND s.hora_fin > @reubicacion_alm_inicio) AS afectada,
           (SELECT COUNT(*) FROM sesion sg
             WHERE sg.horario_id = h.id AND sg.grupo_id = g.id) AS frecuencia_actual
      FROM sesion s
      JOIN horario h ON h.id = s.horario_id
      JOIN periodo_academico p ON p.id = h.periodo_id
      JOIN grupo g ON g.id = s.grupo_id
      JOIN curso c ON c.id = g.curso_id
      JOIN docente d ON d.id = g.docente_id
     WHERE p.nombre = @reubicacion_periodo AND h.id = @reubicacion_horario
),
planeadas AS (
    SELECT sesion_id, grupo_id, docente_id, dia,
           IF(afectada, @reubicacion_plan_inicio, hora_inicio) AS hora_inicio,
           IF(afectada, ADDTIME(@reubicacion_plan_inicio,
                                SEC_TO_TIME(duracion_bloque_min * 60)), hora_fin) AS hora_fin
      FROM actuales
),
comparacion AS (
    SELECT 'INDIVIDUAL' AS escenario, sesion_id, grupo_id, docente_id, dia, hora_inicio, hora_fin
      FROM actuales
    UNION ALL
    SELECT 'PLAN', sesion_id, grupo_id, docente_id, dia, hora_inicio, hora_fin
      FROM planeadas
),
opciones AS (
    SELECT 'INDIVIDUAL' AS escenario, a.sesion_id,
           b.dia AS dia_nuevo, b.hora_inicio AS inicio_nuevo, b.hora_fin AS fin_nuevo
      FROM actuales a
      JOIN v_bloque_valido b ON b.periodo_id = a.periodo_id
     WHERE a.afectada
       AND NOT (b.hora_inicio < @reubicacion_alm_fin AND b.hora_fin > @reubicacion_alm_inicio)
    UNION ALL
    SELECT 'PLAN', sesion_id, dia, hora_inicio, hora_fin
      FROM planeadas
),
evaluadas AS (
    SELECT o.*, a.grupo_id, a.grupo, a.docente_id, a.docente,
           a.curso_id, a.curso, a.dia AS dia_anterior,
           a.hora_inicio AS inicio_anterior, a.hora_fin AS fin_anterior,
           a.afectada, a.frecuencia_actual, a.sesiones_semanales,
           FLOOR(a.cupo_maximo * (1 + a.tolerancia_cupo_pct / 100)) AS limite_operativo,
           a.inscritos,
           CONCAT_WS(',',
             IF(a.estado <> 'BORRADOR', 'HORARIO_NO_BORRADOR', NULL),
             IF(EXISTS(SELECT 1 FROM horario hp
                        WHERE hp.periodo_id = a.periodo_id AND hp.estado = 'PUBLICADO'),
                'PERIODO_CON_PUBLICADO', NULL),
             IF(a.periodo_grupo_id <> a.periodo_id, 'PERIODO_DISTINTO', NULL),
             IF(o.dia_nuevo NOT BETWEEN 1 AND 6
                OR o.inicio_nuevo < IF(o.dia_nuevo = 6, a.hora_inicio_sabado, a.hora_inicio_semana)
                OR o.fin_nuevo > IF(o.dia_nuevo = 6, a.hora_fin_sabado, a.hora_fin_semana),
                'FRANJA', NULL),
             IF(TIME_TO_SEC(TIMEDIFF(o.fin_nuevo, o.inicio_nuevo)) <> a.duracion_sesion_min * 60
                OR a.duracion_sesion_min <> a.duracion_bloque_min, 'DURACION', NULL),
             IF(NOT EXISTS(SELECT 1 FROM v_bloque_valido b
                            WHERE b.periodo_id = a.periodo_id AND b.dia = o.dia_nuevo
                              AND b.hora_inicio = o.inicio_nuevo AND b.hora_fin = o.fin_nuevo),
                'CUADRICULA_ACTUAL', NULL),
             IF(o.inicio_nuevo < a.almuerzo_fin AND o.fin_nuevo > a.almuerzo_inicio,
                'ALMUERZO_ACTUAL', NULL),
             IF(o.inicio_nuevo < @reubicacion_alm_fin AND o.fin_nuevo > @reubicacion_alm_inicio,
                'ALMUERZO_NUEVO', NULL),
             IF(EXISTS(SELECT 1 FROM comparacion x
                        WHERE x.escenario = o.escenario AND x.sesion_id <> a.sesion_id
                          AND x.docente_id = a.docente_id AND x.dia = o.dia_nuevo
                          AND o.inicio_nuevo < x.hora_fin AND o.fin_nuevo > x.hora_inicio),
                'CHOQUE_DOCENTE', NULL),
             IF(EXISTS(SELECT 1 FROM comparacion x
                        WHERE x.escenario = o.escenario AND x.sesion_id <> a.sesion_id
                          AND x.grupo_id = a.grupo_id AND x.dia = o.dia_nuevo
                          AND o.inicio_nuevo < x.hora_fin AND o.fin_nuevo > x.hora_inicio),
                'CHOQUE_GRUPO', NULL),
             IF(EXISTS(SELECT 1 FROM restriccion_horaria r
                        WHERE r.docente_id = a.docente_id AND r.tipo = 'FIRME'
                          AND r.sentido = 'DISPONIBLE')
                AND NOT EXISTS(SELECT 1 FROM restriccion_horaria r
                                WHERE r.docente_id = a.docente_id AND r.tipo = 'FIRME'
                                  AND r.sentido = 'DISPONIBLE' AND r.dia = o.dia_nuevo
                                  AND r.hora_inicio <= o.inicio_nuevo AND r.hora_fin >= o.fin_nuevo),
                'FUERA_DISPONIBILIDAD', NULL),
             IF(EXISTS(SELECT 1 FROM restriccion_horaria r
                        WHERE r.docente_id = a.docente_id AND r.tipo = 'FIRME'
                          AND r.sentido = 'NO_DISPONIBLE' AND r.dia = o.dia_nuevo
                          AND o.inicio_nuevo < r.hora_fin AND o.fin_nuevo > r.hora_inicio),
                'DOCENTE_NO_DISPONIBLE', NULL),
             IF(a.sesiones_semanales > a.max_sesiones_semana, 'FRECUENCIA_MAXIMA', NULL),
             IF(a.frecuencia_actual > a.sesiones_semanales, 'FRECUENCIA_EXCEDIDA_PREEXISTENTE', NULL),
             IF(a.inscritos > FLOOR(a.cupo_maximo * (1 + a.tolerancia_cupo_pct / 100)),
                'CUPO_EXCEDIDO', NULL)
           ) AS bloqueos,
           CONCAT_WS(',',
             IF(EXISTS(SELECT 1 FROM restriccion_horaria r
                        WHERE r.docente_id = a.docente_id AND r.tipo = 'PREFERENCIA'
                          AND r.sentido = 'DISPONIBLE')
                AND NOT EXISTS(SELECT 1 FROM restriccion_horaria r
                                WHERE r.docente_id = a.docente_id AND r.tipo = 'PREFERENCIA'
                                  AND r.sentido = 'DISPONIBLE' AND r.dia = o.dia_nuevo
                                  AND r.hora_inicio <= o.inicio_nuevo AND r.hora_fin >= o.fin_nuevo),
                'PREFERENCIA_DISPONIBILIDAD', NULL),
             IF(EXISTS(SELECT 1 FROM restriccion_horaria r
                        WHERE r.docente_id = a.docente_id AND r.tipo = 'PREFERENCIA'
                          AND r.sentido = 'NO_DISPONIBLE' AND r.dia = o.dia_nuevo
                          AND o.inicio_nuevo < r.hora_fin AND o.fin_nuevo > r.hora_inicio),
                'PREFERENCIA_NO_DISPONIBLE', NULL),
             IF(EXISTS(SELECT 1 FROM comparacion x
                        WHERE x.escenario = o.escenario AND x.sesion_id <> a.sesion_id
                          AND x.grupo_id = a.grupo_id AND ABS(x.dia - o.dia_nuevo) = 1),
                'DIAS_CONSECUTIVOS', NULL),
             IF(a.inscritos < a.cupo_minimo, 'CANDIDATO_CIERRE', NULL),
             IF(a.frecuencia_actual < a.sesiones_semanales, 'FRECUENCIA_INCOMPLETA_PREEXISTENTE', NULL),
             IF(a.necesita_aula_especial, 'AULA_ESPECIAL_PENDIENTE_ASIGNACION', NULL)
           ) AS advertencias
      FROM opciones o JOIN actuales a ON a.sesion_id = o.sesion_id
)
SELECT escenario, sesion_id, curso_id, curso, grupo_id, grupo, docente_id, docente,
       dia_anterior, inicio_anterior, fin_anterior,
       dia_nuevo, inicio_nuevo, fin_nuevo, afectada,
       (bloqueos = '') AS permitido, bloqueos, advertencias,
       frecuencia_actual, sesiones_semanales, inscritos, limite_operativo
  FROM evaluadas
 WHERE escenario = 'PLAN' OR bloqueos = ''
 ORDER BY escenario, sesion_id, (dia_nuevo <> dia_anterior), dia_nuevo, inicio_nuevo;

-- 3. Frecuencia del horario completo: el plan solo cambia horas, así que
--    conserva estos conteos. Una falta previa (p. ej. grupo 21) NO queda resuelta
--    al corregir el almuerzo y sigue impidiendo publicar el horario completo.
SELECT g.id AS grupo_id, g.codigo AS grupo, c.id AS curso_id, c.nombre AS curso,
       c.sesiones_semanales AS requeridas, COUNT(s.id) AS programadas,
       p.max_sesiones_semana,
       CASE WHEN c.sesiones_semanales > p.max_sesiones_semana THEN 'SUPERA_MAXIMO'
            WHEN COUNT(s.id) < c.sesiones_semanales THEN 'FALTAN_SESIONES'
            WHEN COUNT(s.id) > c.sesiones_semanales THEN 'SOBRAN_SESIONES'
            ELSE 'COMPLETA' END AS frecuencia,
       g.inscritos, FLOOR(g.cupo_maximo * (1 + p.tolerancia_cupo_pct / 100)) AS limite_operativo,
       (g.inscritos < g.cupo_minimo) AS candidato_cierre
  FROM periodo_academico p
  JOIN horario h ON h.periodo_id = p.id AND h.id = @reubicacion_horario
  JOIN grupo g ON g.periodo_id = p.id
  JOIN curso c ON c.id = g.curso_id
  LEFT JOIN sesion s ON s.horario_id = h.id AND s.grupo_id = g.id
 WHERE p.nombre = @reubicacion_periodo
 GROUP BY g.id, g.codigo, c.id, c.nombre, c.sesiones_semanales,
          p.max_sesiones_semana, g.inscritos, g.cupo_maximo,
          p.tolerancia_cupo_pct, g.cupo_minimo
 ORDER BY g.id;

-- 4. TEXTO para revisar después del análisis: no se prepara ni ejecuta.
-- Estos UPDATE solo se usarían tras aprobar un plan conjunto sin bloqueos,
-- dentro de una transacción que bloquee periodo/horarios/sesiones y compruebe
-- exactamente cinco filas. No ejecutar individualmente ni usar contra otro estado.
SELECT s.id AS sesion_id,
       CONCAT('UPDATE sesion SET hora_inicio = ''15:00:00'', hora_fin = ''',
              TIME_FORMAT(ADDTIME(@reubicacion_plan_inicio,
                                 SEC_TO_TIME(p.duracion_bloque_min * 60)), '%H:%i:%s'), '''',
              ' WHERE id = ', s.id, ' AND horario_id = ', h.id,
              ' AND grupo_id = ', s.grupo_id, ' AND dia = ', s.dia,
              ' AND hora_inicio = ''', TIME_FORMAT(s.hora_inicio, '%H:%i:%s'),
              ''' AND hora_fin = ''', TIME_FORMAT(s.hora_fin, '%H:%i:%s'), '''',
              ' AND EXISTS (SELECT 1 FROM horario h WHERE h.id = ', h.id,
              ' AND h.estado = ''BORRADOR'');') AS propuesta_sql_no_ejecutada
  FROM sesion s
  JOIN horario h ON h.id = s.horario_id
  JOIN periodo_academico p ON p.id = h.periodo_id
 WHERE p.nombre = @reubicacion_periodo AND h.id = @reubicacion_horario
   AND s.hora_inicio < @reubicacion_alm_fin
   AND s.hora_fin > @reubicacion_alm_inicio
 ORDER BY s.id;

-- Cambio de parámetros propuesto DESPUÉS de verificar los cinco movimientos.
-- La guarda considera todos los horarios del periodo, no solo el borrador 2.
-- Exigir una fila modificada, comprobar el histórico contra la instantánea y
-- revisar todos los resultados antes del COMMIT; cualquier diferencia exige ROLLBACK.
SELECT CONCAT('UPDATE periodo_academico p SET almuerzo_inicio = ''',
              TIME_FORMAT(@reubicacion_alm_inicio, '%H:%i:%s'),
              ''', almuerzo_fin = ''', TIME_FORMAT(@reubicacion_alm_fin, '%H:%i:%s'),
              ''' WHERE p.id = ', p.id, ' AND p.nombre = ''2026-2''',
              ' AND p.almuerzo_inicio = ''', TIME_FORMAT(p.almuerzo_inicio, '%H:%i:%s'),
              ''' AND p.almuerzo_fin = ''', TIME_FORMAT(p.almuerzo_fin, '%H:%i:%s'), '''',
              ' AND NOT EXISTS (SELECT 1 FROM horario h WHERE h.periodo_id = p.id',
              ' AND h.estado = ''PUBLICADO'')',
              ' AND NOT EXISTS (SELECT 1 FROM sesion s JOIN horario h ON h.id = s.horario_id',
              ' WHERE h.periodo_id = p.id AND s.hora_inicio < ''',
              TIME_FORMAT(@reubicacion_alm_fin, '%H:%i:%s'), ''' AND s.hora_fin > ''',
              TIME_FORMAT(@reubicacion_alm_inicio, '%H:%i:%s'), ''');')
         AS propuesta_parametros_sql_no_ejecutada
  FROM periodo_academico p
 WHERE p.nombre = @reubicacion_periodo;

ROLLBACK;
