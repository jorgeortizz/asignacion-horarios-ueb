-- =============================================================================
-- 00_reset_dev.sql   *** SOLO PARA DESARROLLO ***
-- Borra la base horarios_ueb y la deja vacía para volver a ejecutar
-- 01_schema.sql y 02_seed.sql (o las migraciones Flyway).
--
-- Protección: el script se detiene antes del DROP si la sesión no confirmó
-- de forma explícita. Para confirmar:
--
--   Línea de comandos:
--     mysql -u root -p --init-command="SET @confirmar_reinicio_dev = 'BORRAR horarios_ueb'" < 00_reset_dev.sql
--
--   MySQL Workbench (misma pestaña de consulta):
--     1) ejecute a mano:  SET @confirmar_reinicio_dev = 'BORRAR horarios_ueb';
--     2) ejecute este archivo completo (con "Stop script execution on errors"
--        activado, que es el valor por defecto).
--
-- Sin la confirmación, la siguiente sentencia falla con
-- "ERROR 1242: Subquery returns more than 1 row" y el script no continúa.
-- No incorpore la línea SET a este archivo ni a ningún script automático.
-- Nunca lo ejecute contra un servidor compartido o de producción; allí el
-- esquema se gestiona solo con migraciones (README_BD.md, sección 6).
-- =============================================================================

SELECT 'Reinicio de DESARROLLO de horarios_ueb: se requiere @confirmar_reinicio_dev' AS aviso,
       COALESCE(@confirmar_reinicio_dev, '(no definida)') AS confirmacion_recibida;

-- Guardia: devuelve 2 filas (error 1242) si la confirmación no es exacta.
SET @guardia_reinicio := (
  SELECT 1
    FROM (SELECT 1 AS x UNION ALL SELECT 2) AS t
   WHERE COALESCE(@confirmar_reinicio_dev, '') <> 'BORRAR horarios_ueb'
);

DROP DATABASE IF EXISTS horarios_ueb;

CREATE DATABASE horarios_ueb
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;

-- La confirmación se consume para que no quede activa en la sesión.
SET @confirmar_reinicio_dev := NULL;

SELECT 'horarios_ueb reiniciada (vacía). Siguiente paso: 01_schema.sql y 02_seed.sql' AS resultado;

-- Fin de 00_reset_dev.sql
