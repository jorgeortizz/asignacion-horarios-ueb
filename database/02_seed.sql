-- =============================================================================
-- 02_seed.sql
-- Datos de prueba FICTICIOS para el Módulo de Asignación de Horarios.
-- Ningún nombre, código, cifra ni horario corresponde a datos reales de la
-- Universidad El Bosque. Se usan únicamente para probar el esquema.
--
-- Requiere: 01_schema.sql ejecutado previamente.
-- Contenido:
--   * Periodo 2026-1 (histórico) con un horario PUBLICADO completo.
--   * Periodo 2026-2 (en planeación) con un horario BORRADOR que deja,
--     a propósito, un grupo sin completar su frecuencia (curso no ubicado)
--     y un grupo de 4 sesiones con días consecutivos (advertencia).
--   * 6 docentes con las cuatro vinculaciones, especialidades y restricciones.
--   * 9 cursos con frecuencias de 1 a 4 y necesidad de aula especial.
--   * Grupos con inscritos que cubren: normal, candidato a cierre (9),
--     límite exacto del mínimo (10) y cerca del tope (43 de 44).
-- Los identificadores se fijan explícitamente para que 03_queries.sql y
-- 04_tests.sql sean reproducibles.
-- =============================================================================

USE horarios_ueb;
SET NAMES utf8mb4;

START TRANSACTION;

-- -----------------------------------------------------------------------------
-- Periodos académicos (parámetros iniciales documentados: DEFAULT del esquema)
-- -----------------------------------------------------------------------------
INSERT INTO periodo_academico (id, nombre, fecha_inicio, fecha_fin) VALUES
  (1, '2026-1', '2026-01-26', '2026-06-06'),
  (2, '2026-2', '2026-07-27', '2026-11-28');

-- -----------------------------------------------------------------------------
-- Docentes (ficticios)
-- -----------------------------------------------------------------------------
INSERT INTO docente (id, nombre, tipo_vinculacion) VALUES
  (1, 'Ana María Rojas Prieto',      'TC'),
  (2, 'Carlos Eduardo Méndez Lara',  'TRES_CUARTOS'),
  (3, 'Diana Patricia Suárez Gil',   'MEDIO_TIEMPO'),
  (4, 'Jorge Iván Castaño Ruiz',     'CUARTO_TIEMPO'),
  (5, 'Luisa Fernanda Ortiz Vega',   'TC'),
  (6, 'Mateo Herrera Pineda',        'MEDIO_TIEMPO');

INSERT INTO docente_especialidad (docente_id, especialidad) VALUES
  (1, 'Bases de datos'),
  (1, 'Ingeniería de software'),
  (2, 'Redes de computadores'),
  (2, 'Sistemas operativos'),
  (3, 'Matemáticas discretas'),
  (4, 'Inteligencia artificial'),
  (5, 'Programación'),
  (5, 'Estructuras de datos'),
  (6, 'Arquitectura de computadores');

-- -----------------------------------------------------------------------------
-- Restricciones horarias
--   dia: 1=lunes 2=martes 3=miércoles 4=jueves 5=viernes 6=sábado
--   Docentes 1, 2 y 3: sin restricciones (disponibles en toda la franja).
--   Docente 4: solo puede después de las 6 p. m. entre semana
--              (caso de la prueba 2 de la Tabla 26).
--   Docente 5: no disponible el martes de 7 a 11 (cruce con otra facultad,
--              vacío 9) y prefiere no dictar el viernes por la tarde.
--   Docente 6: prefiere dictar en la mañana.
-- -----------------------------------------------------------------------------
INSERT INTO restriccion_horaria (id, docente_id, dia, hora_inicio, hora_fin, tipo, sentido) VALUES
  (1, 4, 1, '18:00:00', '22:00:00', 'FIRME',       'DISPONIBLE'),
  (2, 4, 2, '18:00:00', '22:00:00', 'FIRME',       'DISPONIBLE'),
  (3, 4, 3, '18:00:00', '22:00:00', 'FIRME',       'DISPONIBLE'),
  (4, 4, 4, '18:00:00', '22:00:00', 'FIRME',       'DISPONIBLE'),
  (5, 4, 5, '18:00:00', '22:00:00', 'FIRME',       'DISPONIBLE'),
  (6, 5, 2, '07:00:00', '11:00:00', 'FIRME',       'NO_DISPONIBLE'),
  (7, 5, 5, '15:00:00', '22:00:00', 'PREFERENCIA', 'NO_DISPONIBLE'),
  (8, 6, 1, '07:00:00', '12:00:00', 'PREFERENCIA', 'DISPONIBLE'),
  (9, 6, 2, '07:00:00', '12:00:00', 'PREFERENCIA', 'DISPONIBLE'),
  (10, 6, 3, '07:00:00', '12:00:00', 'PREFERENCIA', 'DISPONIBLE'),
  (11, 6, 4, '07:00:00', '12:00:00', 'PREFERENCIA', 'DISPONIBLE'),
  (12, 6, 5, '07:00:00', '12:00:00', 'PREFERENCIA', 'DISPONIBLE');

-- -----------------------------------------------------------------------------
-- Cursos (códigos ficticios)
-- -----------------------------------------------------------------------------
INSERT INTO curso (id, codigo, nombre, sesiones_semanales, duracion_sesion_min, necesita_aula_especial) VALUES
  (1, 'FIC-101', 'Programación I',                3, 120, TRUE),
  (2, 'FIC-201', 'Estructuras de datos',          2, 120, TRUE),
  (3, 'FIC-301', 'Bases de datos I',              2, 120, TRUE),
  (4, 'FIC-150', 'Matemáticas discretas',         2, 120, FALSE),
  (5, 'FIC-401', 'Redes de computadores',         2, 120, TRUE),
  (6, 'FIC-501', 'Inteligencia artificial',       1, 120, FALSE),
  (7, 'FIC-350', 'Ingeniería de software I',      2, 120, FALSE),
  (8, 'FIC-450', 'Sistemas operativos',           4, 120, FALSE),
  (9, 'FIC-120', 'Arquitectura de computadores',  2, 120, FALSE);

-- -----------------------------------------------------------------------------
-- Grupos. cupo_maximo y cupo_minimo se copian de los parámetros del periodo,
-- como lo hará el backend al crear un grupo.
-- -----------------------------------------------------------------------------
-- Periodo 2026-1 (histórico)
INSERT INTO grupo (id, periodo_id, curso_id, docente_id, codigo, cupo_maximo, cupo_minimo, inscritos)
SELECT v.id, 1, v.curso_id, v.docente_id, v.codigo, p.cupo_maximo_base, p.cupo_minimo, v.inscritos
  FROM (SELECT 1 AS id, 1 AS curso_id, 5 AS docente_id, '01' AS codigo, 35 AS inscritos
        UNION ALL SELECT 2, 3, 1, '01', 28
        UNION ALL SELECT 3, 5, 2, '01', 20
        UNION ALL SELECT 4, 6, 4, '01', 15) v
  JOIN periodo_academico p ON p.id = 1;

-- Periodo 2026-2 (en planeación)
INSERT INTO grupo (id, periodo_id, curso_id, docente_id, codigo, cupo_maximo, cupo_minimo, inscritos)
SELECT v.id, 2, v.curso_id, v.docente_id, v.codigo, p.cupo_maximo_base, p.cupo_minimo, v.inscritos
  FROM (SELECT 11 AS id, 1 AS curso_id, 5 AS docente_id, '01' AS codigo, 38 AS inscritos
        UNION ALL SELECT 12, 1, 1, '02', 43   -- cerca del tope (44): prueba 4 de la Tabla 26
        UNION ALL SELECT 13, 2, 5, '01', 30
        UNION ALL SELECT 14, 3, 1, '01', 25
        UNION ALL SELECT 15, 4, 3, '01',  9   -- candidato a cierre: prueba 5
        UNION ALL SELECT 16, 4, 3, '02', 10   -- justo en el mínimo: NO es candidato
        UNION ALL SELECT 17, 5, 2, '01', 22
        UNION ALL SELECT 18, 6, 4, '01', 18
        UNION ALL SELECT 19, 8, 2, '01', 15
        UNION ALL SELECT 20, 9, 6, '01', 20
        UNION ALL SELECT 21, 7, 1, '01', 12) v
  JOIN periodo_academico p ON p.id = 2;

-- -----------------------------------------------------------------------------
-- Horarios
--   1: 2026-1 PUBLICADO (histórico). Se inserta primero como BORRADOR,
--      se cargan sus sesiones y luego se publica, igual que el flujo real
--      (la publicación ocurre después de validar, Sección 6.7 del prompt).
--   2: 2026-2 BORRADOR (propuesta en revisión del Comité).
-- -----------------------------------------------------------------------------
INSERT INTO horario (id, periodo_id, estado, fecha_creacion) VALUES
  (1, 1, 'BORRADOR', '2026-01-12 08:00:00'),
  (2, 2, 'BORRADOR', '2026-10-13 09:30:00');

-- Sesiones del horario 1 (2026-1): todas válidas y con frecuencia completa.
INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES
  (1, 1, 1, '07:00:00', '09:00:00'),  -- Programación I · lunes
  (1, 1, 3, '07:00:00', '09:00:00'),  -- Programación I · miércoles
  (1, 1, 5, '07:00:00', '09:00:00'),  -- Programación I · viernes
  (1, 2, 2, '09:00:00', '11:00:00'),  -- Bases de datos I · martes
  (1, 2, 4, '09:00:00', '11:00:00'),  -- Bases de datos I · jueves
  (1, 3, 1, '13:00:00', '15:00:00'),  -- Redes · lunes
  (1, 3, 3, '13:00:00', '15:00:00'),  -- Redes · miércoles
  (1, 4, 4, '19:00:00', '21:00:00');  -- Inteligencia artificial · jueves

-- Publicación del horario histórico (el Comité lo aprobó; no es automática).
UPDATE horario
   SET estado = 'PUBLICADO', fecha_publicacion = '2026-01-20 17:00:00', version = version + 1
 WHERE id = 1;

-- Sesiones del horario 2 (2026-2, BORRADOR)
INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES
  -- Grupo 11 · Programación I-01 · Luisa (3 sesiones, días no consecutivos)
  (2, 11, 1, '07:00:00', '09:00:00'),
  (2, 11, 3, '07:00:00', '09:00:00'),
  (2, 11, 5, '07:00:00', '09:00:00'),
  -- Grupo 12 · Programación I-02 · Ana (en horas distintas al grupo 01, vacío 6)
  (2, 12, 1, '13:00:00', '15:00:00'),
  (2, 12, 3, '13:00:00', '15:00:00'),
  (2, 12, 5, '13:00:00', '15:00:00'),
  -- Grupo 13 · Estructuras de datos-01 · Luisa
  (2, 13, 1, '09:00:00', '11:00:00'),
  (2, 13, 4, '09:00:00', '11:00:00'),
  -- Grupo 14 · Bases de datos I-01 · Ana
  (2, 14, 2, '09:00:00', '11:00:00'),
  (2, 14, 4, '13:00:00', '15:00:00'),
  -- Grupo 15 · Matemáticas discretas-01 · Diana
  (2, 15, 2, '07:00:00', '09:00:00'),
  (2, 15, 4, '07:00:00', '09:00:00'),
  -- Grupo 16 · Matemáticas discretas-02 · Diana
  (2, 16, 1, '15:00:00', '17:00:00'),
  (2, 16, 3, '15:00:00', '17:00:00'),
  -- Grupo 17 · Redes-01 · Carlos
  (2, 17, 2, '13:00:00', '15:00:00'),
  (2, 17, 4, '15:00:00', '17:00:00'),
  -- Grupo 18 · Inteligencia artificial-01 · Jorge (solo después de las 18:00)
  (2, 18, 3, '19:00:00', '21:00:00'),
  -- Grupo 19 · Sistemas operativos-01 · Carlos (4 sesiones: viernes y sábado
  -- quedan consecutivos -> advertencia, no bloqueo)
  (2, 19, 1, '17:00:00', '19:00:00'),
  (2, 19, 3, '17:00:00', '19:00:00'),
  (2, 19, 5, '17:00:00', '19:00:00'),
  (2, 19, 6, '09:00:00', '11:00:00'),
  -- Grupo 20 · Arquitectura de computadores-01 · Mateo (en su preferencia: mañanas)
  (2, 20, 2, '07:00:00', '09:00:00'),
  (2, 20, 4, '09:00:00', '11:00:00'),
  -- Grupo 21 · Ingeniería de software I-01 · Ana: solo 1 de 2 sesiones
  -- ubicada (simula un curso que el generador no pudo completar, EF03)
  (2, 21, 2, '15:00:00', '17:00:00');

COMMIT;

-- Resumen de carga
SELECT 'periodo_academico' AS tabla, COUNT(*) AS filas FROM periodo_academico
UNION ALL SELECT 'docente',              COUNT(*) FROM docente
UNION ALL SELECT 'docente_especialidad', COUNT(*) FROM docente_especialidad
UNION ALL SELECT 'restriccion_horaria',  COUNT(*) FROM restriccion_horaria
UNION ALL SELECT 'curso',                COUNT(*) FROM curso
UNION ALL SELECT 'grupo',                COUNT(*) FROM grupo
UNION ALL SELECT 'horario',              COUNT(*) FROM horario
UNION ALL SELECT 'sesion',               COUNT(*) FROM sesion;

-- Fin de 02_seed.sql
