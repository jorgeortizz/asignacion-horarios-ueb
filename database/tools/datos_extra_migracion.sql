-- Datos adicionales para simular una base "en uso" antes de migrar de V1 a V2.
-- Solo para la prueba de migración (tools/ejecutar_todo.sh). Ficticios.
USE horarios_ueb;
START TRANSACTION;
INSERT INTO horario (id, periodo_id, estado, fecha_creacion) VALUES (3, 2, 'BORRADOR', '2026-10-15 10:00:00');
INSERT INTO sesion (horario_id, grupo_id, dia, hora_inicio, hora_fin) VALUES
  (3, 11, 2, '11:00:00', '13:00:00'),
  (3, 11, 4, '11:00:00', '13:00:00'),
  (3, 11, 6, '07:00:00', '09:00:00');
UPDATE grupo SET inscritos = inscritos + 1 WHERE periodo_id = 2;
INSERT INTO docente (id, nombre, tipo_vinculacion) VALUES (7, 'Docente adicional ficticio', 'MEDIO_TIEMPO');
INSERT INTO docente_especialidad (docente_id, especialidad) VALUES (7, 'Computación gráfica');
COMMIT;
