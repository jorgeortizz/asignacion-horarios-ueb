-- =============================================================================
-- preflight_V2.sql  — Verificación previa a V2__revision_tecnica.sql
-- SOLO LECTURA: no modifica datos. Ejecútelo sobre la base que se va a migrar
-- (después del respaldo y antes de aplicar V2).
--
-- Resultado: una fila por comprobación. Si alguna fila tiene
-- bloquea = 1, V2 fallará en ese punto: corrija los datos indicados antes de
-- migrar. Las filas con bloquea = 0 son informativas.
-- =============================================================================

USE horarios_ueb;

SELECT 'P01' AS codigo,
       'Periodos cuya franja L-V es más corta que un bloque (rompería ck_periodo_academico_franja_bloque)' AS comprobacion,
       COUNT(*) AS filas,
       (COUNT(*) > 0) AS bloquea
  FROM periodo_academico
 WHERE TIME_TO_SEC(TIMEDIFF(hora_fin_semana, hora_inicio_semana)) < duracion_bloque_min * 60
UNION ALL
SELECT 'P02', 'Objetos que V2 crea y ya existen (V2 aplicada antes o creados a mano)',
       COUNT(*), (COUNT(*) > 0)
  FROM (SELECT trigger_name AS n FROM information_schema.triggers
         WHERE trigger_schema = DATABASE() AND trigger_name IN ('trg_sesion_bd', 'trg_horario_bi', 'trg_curso_bu')
        UNION ALL
        SELECT routine_name FROM information_schema.routines
         WHERE routine_schema = DATABASE() AND routine_name = 'sp_verificar_horario_editable'
        UNION ALL
        SELECT table_name FROM information_schema.views
         WHERE table_schema = DATABASE() AND table_name IN ('v_horario_vigente', 'v_sesion_conflicto_parametros')
        UNION ALL
        SELECT constraint_name FROM information_schema.table_constraints
         WHERE constraint_schema = DATABASE() AND constraint_name = 'ck_periodo_academico_franja_bloque') t
UNION ALL
SELECT 'P03', 'Objetos de V1 que V2 reemplaza y deben existir (6 esperados)',
       COUNT(*), (COUNT(*) <> 6)
  FROM (SELECT trigger_name AS n FROM information_schema.triggers
         WHERE trigger_schema = DATABASE() AND trigger_name IN ('trg_sesion_bi', 'trg_sesion_bu', 'trg_horario_bu', 'trg_grupo_bu', 'trg_horario_bd')
        UNION ALL
        SELECT routine_name FROM information_schema.routines
         WHERE routine_schema = DATABASE() AND routine_name = 'sp_validar_sesion') t
UNION ALL
SELECT p04.codigo, p04.comprobacion, p04.filas, (p04.filas > 0)
  FROM (SELECT 'P04' AS codigo,
               'Valores enum no canónicos (minúsculas o variantes) que R09 rechazaría. Corrección: UPDATE ... SET col = UPPER(col)' AS comprobacion,
       (SELECT COUNT(*) FROM docente
         WHERE CAST(tipo_vinculacion AS BINARY) NOT IN (CAST('TC' AS BINARY), CAST('TRES_CUARTOS' AS BINARY), CAST('MEDIO_TIEMPO' AS BINARY), CAST('CUARTO_TIEMPO' AS BINARY)))
     + (SELECT COUNT(*) FROM restriccion_horaria
         WHERE CAST(tipo AS BINARY) NOT IN (CAST('FIRME' AS BINARY), CAST('PREFERENCIA' AS BINARY))
            OR CAST(sentido AS BINARY) NOT IN (CAST('DISPONIBLE' AS BINARY), CAST('NO_DISPONIBLE' AS BINARY)))
     + (SELECT COUNT(*) FROM horario
         WHERE CAST(estado AS BINARY) NOT IN (CAST('BORRADOR' AS BINARY), CAST('PUBLICADO' AS BINARY))) AS filas) AS p04
UNION ALL
SELECT 'P05', 'Cursos con necesita_aula_especial distinto de 0 o 1 (rompería ck_curso_aula_especial)',
       COUNT(*), (COUNT(*) > 0)
  FROM curso WHERE necesita_aula_especial NOT IN (0, 1)
UNION ALL
SELECT 'I01', 'Horarios PUBLICADOS sin sesiones (quedan como están; BD-12 solo actúa al publicar)',
       COUNT(*), 0
  FROM horario h
 WHERE h.estado = 'PUBLICADO'
   AND NOT EXISTS (SELECT 1 FROM sesion s WHERE s.horario_id = h.id)
UNION ALL
SELECT 'I02', 'Sesiones en horarios PUBLICADOS (después de V2 quedan protegidas por BD-08)',
       COUNT(*), 0
  FROM sesion s JOIN horario h ON h.id = s.horario_id
 WHERE h.estado = 'PUBLICADO'
UNION ALL
SELECT 'I03', 'Sesiones que hoy no cumplen la franja o el almuerzo de su periodo (se listarán en v_sesion_conflicto_parametros)',
       COUNT(*), 0
  FROM sesion s
  JOIN horario h ON h.id = s.horario_id
  JOIN periodo_academico p ON p.id = h.periodo_id
 WHERE s.hora_inicio < IF(s.dia = 6, p.hora_inicio_sabado, p.hora_inicio_semana)
    OR s.hora_fin    > IF(s.dia = 6, p.hora_fin_sabado, p.hora_fin_semana)
    OR (s.hora_inicio < p.almuerzo_fin AND s.hora_fin > p.almuerzo_inicio)
UNION ALL
SELECT 'I04', 'Filas por tabla antes de migrar (comparar con la verificación posterior)',
       (SELECT COUNT(*) FROM periodo_academico) + (SELECT COUNT(*) FROM docente)
     + (SELECT COUNT(*) FROM docente_especialidad) + (SELECT COUNT(*) FROM restriccion_horaria)
     + (SELECT COUNT(*) FROM curso) + (SELECT COUNT(*) FROM grupo)
     + (SELECT COUNT(*) FROM horario) + (SELECT COUNT(*) FROM sesion), 0;

-- Huella de los datos para comparar antes y después de la migración
-- (debe ser idéntica: V2 no modifica filas).
CHECKSUM TABLE periodo_academico, docente, docente_especialidad, restriccion_horaria,
               curso, grupo, horario, sesion;

-- Fin de preflight_V2.sql
