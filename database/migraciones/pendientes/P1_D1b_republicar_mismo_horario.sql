-- =============================================================================
-- P1_D1b_republicar_mismo_horario.sql   *** PENDIENTE DE DECISIÓN D1 y D3 ***
--
-- NO se aplica hasta que el Comité Táctico apruebe la opción D1-b
-- (RECOMENDADA): para modificar un horario publicado se despublica el mismo
-- horario (PUBLICADO -> BORRADOR), se ajusta, se valida y se vuelve a
-- publicar.
-- Incompatible con P2_D1c_copia_nueva.sql: aplique solo una de las dos.
--
-- Al aprobarse: copiar a db/migration con el siguiente número libre, por
-- ejemplo V3__republicar_mismo_horario.sql, y ejecutar 05_tests_pendientes.sql.
--
-- Reglas:
--   * Un solo horario PUBLICADO por periodo (índice único funcional, sin
--     columna nueva: no cambia el contrato JPA). Error 1062.
--   * [BD-14] (decisión D3) No se cambia el docente de un grupo que tiene
--     sesiones en un horario PUBLICADO: primero se despublica, se cambia,
--     se revalida y se republica.
-- =============================================================================

SET NAMES utf8mb4;
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,ONLY_FULL_GROUP_BY';

CREATE UNIQUE INDEX uk_horario_un_publicado_por_periodo
  ON horario ((IF(estado = 'PUBLICADO', periodo_id, NULL)));

DELIMITER $$

DROP TRIGGER IF EXISTS trg_grupo_bu$$
CREATE TRIGGER trg_grupo_bu
BEFORE UPDATE ON grupo
FOR EACH ROW
BEGIN
  IF NEW.periodo_id <> OLD.periodo_id
     AND EXISTS (SELECT 1 FROM sesion WHERE grupo_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-05] No se puede cambiar el periodo de un grupo que ya tiene sesiones.';
  END IF;
  IF NEW.curso_id <> OLD.curso_id
     AND EXISTS (SELECT 1 FROM sesion WHERE grupo_id = OLD.id) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-10] No se puede cambiar el curso de un grupo que ya tiene sesiones.';
  END IF;
  IF NEW.docente_id <> OLD.docente_id
     AND EXISTS (SELECT 1
                   FROM sesion s JOIN horario h ON h.id = s.horario_id
                  WHERE s.grupo_id = OLD.id AND h.estado = 'PUBLICADO') THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-14] No se cambia el docente de un grupo con sesiones en un horario PUBLICADO; despublique primero.';
  END IF;
END$$

DELIMITER ;

-- Fin de P1_D1b_republicar_mismo_horario.sql
