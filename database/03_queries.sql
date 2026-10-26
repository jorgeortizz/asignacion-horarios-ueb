-- =============================================================================
-- 03_queries.sql
-- Consultas de referencia del Módulo de Asignación de Horarios.
-- Requiere: 01_schema.sql y 02_seed.sql.
--
-- Las consultas usan variables de sesión (@...) como parámetros. En Spring
-- Data JPA se convierten en parámetros con nombre (:periodoId, :docenteId...)
-- de consultas @Query nativas o JPQL.
-- Los resultados esperados indicados en comentarios corresponden a los datos
-- de 02_seed.sql.
-- =============================================================================

USE horarios_ueb;

-- Parámetros de ejemplo
SET @periodo_nombre := '2026-2';
SET @periodo_id     := (SELECT id FROM periodo_academico WHERE nombre = @periodo_nombre);
SET @horario_id     := 2;   -- horario BORRADOR de 2026-2
SET @docente_id     := 1;   -- Ana María Rojas Prieto
SET @curso_id       := 1;   -- Programación I

-- -----------------------------------------------------------------------------
-- Q01. Listar docentes con su vinculación y especialidades.
--      (GROUP_CONCAT solo para presentar; el dato se guarda normalizado.)
--      Esperado: 6 filas.
-- -----------------------------------------------------------------------------
SELECT d.id,
       d.nombre,
       d.tipo_vinculacion,
       GROUP_CONCAT(e.especialidad ORDER BY e.especialidad SEPARATOR ', ') AS especialidades
  FROM docente d
  LEFT JOIN docente_especialidad e ON e.docente_id = d.id
 GROUP BY d.id, d.nombre, d.tipo_vinculacion
 ORDER BY d.nombre;

-- -----------------------------------------------------------------------------
-- Q02. Restricciones horarias de un docente.
--      Esperado para docente 4: 5 filas FIRME/DISPONIBLE de 18:00 a 22:00.
-- -----------------------------------------------------------------------------
SELECT r.id,
       ELT(r.dia, 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado') AS dia,
       r.hora_inicio, r.hora_fin, r.tipo, r.sentido
  FROM restriccion_horaria r
 WHERE r.docente_id = 4
 ORDER BY r.dia, r.hora_inicio;

-- -----------------------------------------------------------------------------
-- Q03. Grupos de un curso en un periodo, con su estado de cupo.
--      Esperado (curso 1, 2026-2): grupos 01 (38) y 02 (43, límite 44).
-- -----------------------------------------------------------------------------
SELECT v.grupo_id, v.grupo, v.docente, v.cupo_maximo, v.limite_operativo,
       v.cupo_minimo, v.inscritos, v.candidato_cierre, v.excede_limite
  FROM v_grupo_cupo v
 WHERE v.curso_id = @curso_id
   AND v.periodo_id = @periodo_id
 ORDER BY v.grupo;

-- -----------------------------------------------------------------------------
-- Q04. Grupos asignados a un docente en un periodo.
--      Esperado (docente 1, 2026-2): 3 grupos.
-- -----------------------------------------------------------------------------
SELECT g.id AS grupo_id, c.codigo, c.nombre AS curso, g.codigo AS grupo,
       c.sesiones_semanales, g.inscritos
  FROM grupo g
  JOIN curso c ON c.id = g.curso_id
 WHERE g.docente_id = @docente_id
   AND g.periodo_id = @periodo_id
 ORDER BY c.nombre, g.codigo;

-- -----------------------------------------------------------------------------
-- Q05. Sesiones de un periodo (todas sus propuestas y publicaciones).
--      Esperado (2026-2): 24 sesiones del horario 2.
-- -----------------------------------------------------------------------------
SELECT v.horario_id, v.estado_horario, v.dia_nombre, v.hora_inicio, v.hora_fin,
       v.curso, v.grupo, v.docente
  FROM v_sesion_detalle v
 WHERE v.periodo_id = @periodo_id
 ORDER BY v.horario_id, v.dia, v.hora_inicio, v.curso;

-- -----------------------------------------------------------------------------
-- Q06. Horario de un docente (en un horario dado).
--      Esperado (docente 1, horario 2): 6 sesiones.
--      Para la vista del docente (RF08) use el horario de Q13 (vigente).
-- -----------------------------------------------------------------------------
SELECT v.dia_nombre, v.hora_inicio, v.hora_fin, v.curso_codigo, v.curso, v.grupo
  FROM v_sesion_detalle v
 WHERE v.docente_id = @docente_id
   AND v.horario_id = @horario_id
 ORDER BY v.dia, v.hora_inicio;

-- -----------------------------------------------------------------------------
-- Q07. Horario de un curso (todos sus grupos) en un horario dado.
--      Esperado (curso 1, horario 2): 6 sesiones (3 por grupo).
-- -----------------------------------------------------------------------------
SELECT v.grupo, v.docente, v.dia_nombre, v.hora_inicio, v.hora_fin,
       IF(v.necesita_aula_especial, 'Necesita aula especial, por confirmar', '') AS nota_aula
  FROM v_sesion_detalle v
 WHERE v.curso_id = @curso_id
   AND v.horario_id = @horario_id
 ORDER BY v.grupo, v.dia, v.hora_inicio;

-- -----------------------------------------------------------------------------
-- Q08. Horarios publicados (todas las versiones publicadas).
--      Para lo que ven estudiantes y docentes use Q13 (horario vigente).
--      Esperado: 1 fila (horario 1, 2026-1, 8 sesiones).
-- -----------------------------------------------------------------------------
SELECT h.id AS horario_id, p.nombre AS periodo, h.fecha_publicacion,
       COUNT(s.id) AS sesiones
  FROM horario h
  JOIN periodo_academico p ON p.id = h.periodo_id
  LEFT JOIN sesion s ON s.horario_id = h.id
 WHERE h.estado = 'PUBLICADO'
 GROUP BY h.id, p.nombre, h.fecha_publicacion
 ORDER BY p.fecha_inicio DESC;

-- -----------------------------------------------------------------------------
-- Q09. Horarios históricos: periodos ya terminados respecto de una fecha de
--      corte (por defecto, hoy). Esperado con corte 2026-10-21: periodo 2026-1.
-- -----------------------------------------------------------------------------
SET @fecha_corte := CURDATE();

SELECT p.nombre AS periodo, p.fecha_inicio, p.fecha_fin,
       h.id AS horario_id, h.estado, h.fecha_publicacion,
       COUNT(s.id) AS sesiones
  FROM periodo_academico p
  JOIN horario h ON h.periodo_id = p.id
  LEFT JOIN sesion s ON s.horario_id = h.id
 WHERE p.fecha_fin < @fecha_corte
 GROUP BY p.nombre, p.fecha_inicio, p.fecha_fin, h.id, h.estado, h.fecha_publicacion
 ORDER BY p.fecha_inicio DESC, h.id;

-- -----------------------------------------------------------------------------
-- Q10. Grupos candidatos a cierre (inscritos < cupo mínimo). Solo informa;
--      la decisión de cerrar la toma una persona del Comité.
--      Esperado (2026-2): grupo 15 (Matemáticas discretas-01, 9 inscritos).
--      El grupo 16 (10 inscritos) NO aparece.
-- -----------------------------------------------------------------------------
SELECT v.grupo_id, v.curso, v.grupo, v.docente, v.inscritos, v.cupo_minimo
  FROM v_grupo_cupo v
 WHERE v.periodo_id = @periodo_id
   AND v.candidato_cierre = 1
 ORDER BY v.curso, v.grupo;

-- -----------------------------------------------------------------------------
-- Q11. Cursos que requieren aula especial y sus grupos en el periodo.
--      No se asigna salón: solo se informa la necesidad.
--      Esperado (2026-2): 4 cursos, 5 grupos.
-- -----------------------------------------------------------------------------
SELECT c.codigo, c.nombre AS curso, COUNT(g.id) AS grupos_en_periodo
  FROM curso c
  LEFT JOIN grupo g ON g.curso_id = c.id AND g.periodo_id = @periodo_id
 WHERE c.necesita_aula_especial = TRUE
 GROUP BY c.id, c.codigo, c.nombre
 ORDER BY c.nombre;

-- -----------------------------------------------------------------------------
-- Q12. Datos para verificar conflictos (los usa el backend; ninguna de estas
--      consultas sustituye la validación en Java, Sección 5.6).
-- -----------------------------------------------------------------------------

-- Q12a. Casilla propuesta (para validar un arrastre o una propuesta).
SET @p_grupo_id    := 18;          -- IA-01, docente 4 (solo después de 18:00)
SET @p_dia         := 1;           -- lunes
SET @p_hora_inicio := '15:00:00';
SET @p_hora_fin    := '17:00:00';
SET @p_sesion_id   := NULL;        -- id de la sesión que se mueve (NULL si es nueva)
SET @p_docente_id  := (SELECT docente_id FROM grupo WHERE id = @p_grupo_id);

-- Q12b. ¿El docente ya tiene otra clase que se solapa en ese horario? (Tabla 19, rev. 3)
--       Esperado: 0 filas para la casilla de ejemplo.
SELECT s.id AS sesion_en_conflicto, c.nombre AS curso, g.codigo AS grupo,
       s.dia, s.hora_inicio, s.hora_fin
  FROM sesion s
  JOIN grupo g ON g.id = s.grupo_id
  JOIN curso c ON c.id = g.curso_id
 WHERE s.horario_id = @horario_id
   AND g.docente_id = @p_docente_id
   AND s.dia = @p_dia
   AND s.hora_inicio < @p_hora_fin
   AND s.hora_fin    > @p_hora_inicio
   AND (@p_sesion_id IS NULL OR s.id <> @p_sesion_id);

-- Q12c. Restricciones del docente relevantes para la casilla (Tabla 19, rev. 4).
--       El backend aplica la interpretación documentada en 01_schema.sql.
--       Esperado: 1 fila FIRME/DISPONIBLE 18:00-22:00 que NO contiene la
--       casilla -> fuera de disponibilidad -> el backend debe rechazar.
SELECT r.id, r.tipo, r.sentido, r.hora_inicio, r.hora_fin,
       (r.hora_inicio <= @p_hora_inicio AND r.hora_fin >= @p_hora_fin) AS contiene_casilla,
       (r.hora_inicio <  @p_hora_fin    AND r.hora_fin >  @p_hora_inicio) AS se_solapa
  FROM restriccion_horaria r
 WHERE r.docente_id = @p_docente_id
   AND r.dia = @p_dia;

-- Q12d. ¿La casilla está en la cuadrícula de bloques válidos del periodo?
--       (Tabla 19, rev. 1 y 2). Esperado: 1 fila (15:00-17:00 es válido).
SELECT b.*
  FROM v_bloque_valido b
  JOIN horario h ON h.periodo_id = b.periodo_id
 WHERE h.id = @horario_id
   AND b.dia = @p_dia
   AND b.hora_inicio = @p_hora_inicio
   AND b.hora_fin = @p_hora_fin;

-- Q12e. Días en que el mismo grupo ya tiene clase (días consecutivos, rev. 5).
--       Consecutivo = |día1 - día2| = 1 dentro de la semana (sábado-lunes no).
SELECT s.dia, ABS(s.dia - @p_dia) = 1 AS consecutivo
  FROM sesion s
 WHERE s.horario_id = @horario_id
   AND s.grupo_id = @p_grupo_id
   AND (@p_sesion_id IS NULL OR s.id <> @p_sesion_id);

-- Q12f. Pares de sesiones del mismo docente que se solapan en un horario.
--       Esperado: 0 filas en los horarios 1 y 2.
SELECT s1.horario_id, d.nombre AS docente, s1.id AS sesion_1, s2.id AS sesion_2,
       s1.dia, s1.hora_inicio, s1.hora_fin, s2.hora_inicio AS inicio_2, s2.hora_fin AS fin_2
  FROM sesion s1
  JOIN grupo g1 ON g1.id = s1.grupo_id
  JOIN sesion s2 ON s2.horario_id = s1.horario_id AND s2.dia = s1.dia AND s2.id > s1.id
  JOIN grupo g2 ON g2.id = s2.grupo_id AND g2.docente_id = g1.docente_id
  JOIN docente d ON d.id = g1.docente_id
 WHERE s1.hora_inicio < s2.hora_fin
   AND s2.hora_inicio < s1.hora_fin;

-- Q12g. Frecuencia: grupos cuyo número de sesiones no coincide con el curso
--       (cursos no ubicados por completo, EF03).
--       Esperado (horario 2): grupo 21 (Ingeniería de software I) con 1 de 2.
SELECT g.id AS grupo_id, c.nombre AS curso, g.codigo AS grupo,
       c.sesiones_semanales AS requeridas, COUNT(s.id) AS programadas
  FROM grupo g
  JOIN curso c   ON c.id = g.curso_id
  JOIN horario h ON h.periodo_id = g.periodo_id AND h.id = @horario_id
  LEFT JOIN sesion s ON s.grupo_id = g.id AND s.horario_id = h.id
 GROUP BY g.id, c.nombre, g.codigo, c.sesiones_semanales
HAVING COUNT(s.id) <> c.sesiones_semanales
 ORDER BY c.nombre;

-- Q12h. Advertencias de días consecutivos por grupo en un horario.
--       Esperado (horario 2): grupo 19 (Sistemas operativos) viernes-sábado.
SELECT g.id AS grupo_id, c.nombre AS curso, g.codigo AS grupo,
       s1.dia AS dia_1, s2.dia AS dia_2
  FROM sesion s1
  JOIN sesion s2 ON s2.horario_id = s1.horario_id
                AND s2.grupo_id = s1.grupo_id
                AND s2.dia = s1.dia + 1
  JOIN grupo g ON g.id = s1.grupo_id
  JOIN curso c ON c.id = g.curso_id
 WHERE s1.horario_id = @horario_id;

-- Q12i. Bloques válidos libres para un docente en un horario (insumo del
--       generador; las restricciones se filtran luego en Java).
--       Esperado (docente 4, horario 2): 32 bloques (33 menos miércoles 19-21).
SELECT b.dia, b.hora_inicio, b.hora_fin
  FROM v_bloque_valido b
  JOIN horario h ON h.periodo_id = b.periodo_id AND h.id = @horario_id
 WHERE NOT EXISTS (
         SELECT 1
           FROM sesion s
           JOIN grupo g ON g.id = s.grupo_id
          WHERE s.horario_id = h.id
            AND g.docente_id = @p_docente_id
            AND s.dia = b.dia
            AND s.hora_inicio < b.hora_fin
            AND s.hora_fin > b.hora_inicio)
 ORDER BY b.dia, b.hora_inicio;


-- =============================================================================
-- Consultas agregadas en la segunda revisión técnica (V2)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q13. Horario vigente de cada periodo (lo que consultan estudiantes y
--      docentes, RF08). Esperado: 2026-1 -> horario 1; 2026-2 sin publicado.
-- -----------------------------------------------------------------------------
SELECT v.periodo, v.horario_id, v.fecha_publicacion
  FROM v_horario_vigente v
 ORDER BY v.periodo;

-- Horario vigente de un docente en un periodo (vista del docente, HU06).
SELECT d.dia_nombre, d.hora_inicio, d.hora_fin, d.curso, d.grupo
  FROM v_sesion_detalle d
  JOIN v_horario_vigente v ON v.horario_id = d.horario_id
 WHERE d.docente_id = 5
   AND v.periodo = '2026-1'
 ORDER BY d.dia, d.hora_inicio;

-- -----------------------------------------------------------------------------
-- Q14. Sesiones en conflicto con los parámetros ACTUALES de su periodo
--      (vacío 4: el sistema marca y el Comité corrige). Esperado: 0 filas.
-- -----------------------------------------------------------------------------
SELECT c.horario_id, c.estado_horario, c.motivo, d.dia_nombre, c.hora_inicio, c.hora_fin,
       d.curso, d.grupo, d.docente
  FROM v_sesion_conflicto_parametros c
  JOIN v_sesion_detalle d ON d.sesion_id = c.sesion_id
 ORDER BY c.horario_id, c.motivo, d.dia, c.hora_inicio;

-- -----------------------------------------------------------------------------
-- Q15. Impacto de un cambio de parámetros ANTES de guardarlo (BK12): cuántas
--      sesiones quedarían en conflicto con un almuerzo propuesto.
--      Esperado con el seed nuevo (2026-2, almuerzo 13:00-14:00): 0 sesiones.
--      Los datos existentes pueden tener conflictos; esta consulta no los cambia.
-- -----------------------------------------------------------------------------
SET @q15_periodo := 2;
SET @q15_alm_ini := '13:00:00';
SET @q15_alm_fin := '14:00:00';

SELECT h.estado AS estado_horario, COUNT(*) AS sesiones_afectadas
  FROM sesion s
  JOIN horario h ON h.id = s.horario_id
 WHERE h.periodo_id = @q15_periodo
   AND s.hora_inicio < @q15_alm_fin
   AND s.hora_fin    > @q15_alm_ini
 GROUP BY h.estado;

-- -----------------------------------------------------------------------------
-- Q16. (Referencia, NO se ejecuta) Copiar un horario a un borrador nuevo del
--      mismo periodo. Es el paso base de la opción D1-c y también sirve para
--      partir de una propuesta anterior. El backend lo ejecuta en una sola
--      transacción; los triggers revalidan cada sesión copiada con los
--      parámetros actuales (si alguna ya no cumple, la copia completa falla).
--
--   START TRANSACTION;
--   INSERT INTO horario (periodo_id) SELECT periodo_id FROM horario WHERE id = :origen;
--   SET @nuevo := LAST_INSERT_ID();
--   INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin)
--   SELECT @nuevo, grupo_id, dia, hora_inicio, hora_fin FROM sesion WHERE horario_id = :origen;
--   COMMIT;
-- -----------------------------------------------------------------------------

-- Fin de 03_queries.sql
