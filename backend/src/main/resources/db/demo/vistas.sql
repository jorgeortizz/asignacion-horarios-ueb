-- Solo H2 demo: misma seleccion de vigente que V2. No modifica las migraciones.
CREATE VIEW v_horario_vigente AS
SELECT h.periodo_id, p.nombre AS periodo, h.id AS horario_id, h.fecha_publicacion
FROM horario h
JOIN periodo_academico p ON p.id = h.periodo_id
WHERE h.estado = 'PUBLICADO'
  AND NOT EXISTS (
    SELECT 1 FROM horario h2
    WHERE h2.periodo_id = h.periodo_id
      AND h2.estado = 'PUBLICADO'
      AND (h2.fecha_publicacion > h.fecha_publicacion
        OR (h2.fecha_publicacion = h.fecha_publicacion AND h2.id > h.id))
  );
