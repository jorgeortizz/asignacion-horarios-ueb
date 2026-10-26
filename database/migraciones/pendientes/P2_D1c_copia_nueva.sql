-- =============================================================================
-- P2_D1c_copia_nueva.sql   *** PENDIENTE DE DECISIÓN D1 (alternativa) ***
--
-- NO se aplica hasta que el Comité Táctico apruebe la opción D1-c: un horario
-- publicado nunca vuelve a BORRADOR; para modificarlo se crea un horario
-- BORRADOR nuevo en el mismo periodo copiando sus sesiones, se ajusta y se
-- publica. La versión vigente es la publicada más reciente
-- (v_horario_vigente) y las anteriores quedan como historial.
-- Incompatible con P1_D1b_republicar_mismo_horario.sql.
--
-- Limitación (ver informe, sección 4): las sesiones copiadas comparten el
-- mismo grupo; si luego cambia el docente o los inscritos del grupo, las
-- versiones anteriores muestran el dato nuevo. Conservar también eso exige
-- versionar grupos o una bitácora (mejora futura).
--
-- Al aprobarse: copiar a db/migration con el siguiente número libre y
-- ejecutar 06_tests_pendiente_P2.sql.
-- =============================================================================

SET NAMES utf8mb4;
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,ONLY_FULL_GROUP_BY';

DELIMITER $$

DROP TRIGGER IF EXISTS trg_horario_bu$$
CREATE TRIGGER trg_horario_bu
BEFORE UPDATE ON horario
FOR EACH ROW
BEGIN
  IF NEW.periodo_id <> OLD.periodo_id
     AND EXISTS (SELECT 1 FROM sesion WHERE horario_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-06] No se puede cambiar el periodo de un horario que ya tiene sesiones.';
  END IF;
  IF NEW.estado = 'PUBLICADO' AND OLD.estado <> 'PUBLICADO'
     AND NOT EXISTS (SELECT 1 FROM sesion WHERE horario_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-12] No se puede publicar un horario sin sesiones.';
  END IF;
  IF OLD.estado = 'PUBLICADO' AND NEW.estado <> 'PUBLICADO' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-15] Un horario PUBLICADO no vuelve a BORRADOR; cree una copia en borrador para modificarlo.';
  END IF;
END$$

DELIMITER ;

-- Fin de P2_D1c_copia_nueva.sql
