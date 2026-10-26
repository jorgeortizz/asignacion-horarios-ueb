-- Almuerzo institucional inicial: [13:00,14:00). Sintaxis MySQL 8.0.45.
-- Esquema real, triggers, procedimientos e historial V1/V2 inspeccionados
-- en horarios_ueb (MySQL 8.0.45). Pendiente de aprobación y aplicación;
-- resolver y verificar antes el plan separado del borrador 2026-2.
--
-- SOLO cambia DEFAULT de columnas existentes. No modifica filas de
-- periodo_academico, horarios, sesiones, triggers ni procedimientos.
-- El periodo 2026-1 conserva íntegros sus parámetros y su publicado.
-- El almuerzo de 2026-2 se actualiza mediante el procedimiento controlado
-- separado, después de resolver sus cinco sesiones y revisar los resultados.
-- No mezclar ese DML con este DDL: ALTER TABLE hace commit implícito.

ALTER TABLE periodo_academico
  ALTER COLUMN almuerzo_inicio SET DEFAULT '13:00:00',
  ALTER COLUMN almuerzo_fin SET DEFAULT '14:00:00';
