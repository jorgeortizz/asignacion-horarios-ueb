-- =============================================================================
-- P3_D2_parametros_con_publicado.sql   *** PENDIENTE DE DECISIÓN D2 ***
--
-- NO se aplica hasta que el Comité Táctico apruebe la opción D2-a
-- (RECOMENDADA): los parámetros que definen la forma del horario (franjas,
-- almuerzo, duración del bloque y máximo de sesiones) no se cambian mientras
-- el periodo tenga un horario PUBLICADO. Así el horario publicado nunca queda
-- en contradicción con las reglas de su propio periodo.
-- Con horarios solo en BORRADOR el cambio sigue permitido y las sesiones
-- afectadas se listan en v_sesion_conflicto_parametros (vacío 4).
-- Los parámetros de cupo (cupo_maximo_base, tolerancia_cupo_pct,
-- cupo_minimo) NO se bloquean: la inscripción ocurre después de publicar.
--
-- Compatible con P1 o con P2. Al aprobarse: copiar a db/migration con el
-- siguiente número libre y ejecutar 05_tests_pendientes.sql.
-- =============================================================================

SET NAMES utf8mb4;
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,ONLY_FULL_GROUP_BY';

DELIMITER $$

CREATE TRIGGER trg_periodo_academico_bu
BEFORE UPDATE ON periodo_academico
FOR EACH ROW
BEGIN
  IF (NEW.hora_inicio_semana  <> OLD.hora_inicio_semana
      OR NEW.hora_fin_semana     <> OLD.hora_fin_semana
      OR NEW.hora_inicio_sabado  <> OLD.hora_inicio_sabado
      OR NEW.hora_fin_sabado     <> OLD.hora_fin_sabado
      OR NEW.almuerzo_inicio     <> OLD.almuerzo_inicio
      OR NEW.almuerzo_fin        <> OLD.almuerzo_fin
      OR NEW.duracion_bloque_min <> OLD.duracion_bloque_min
      OR NEW.max_sesiones_semana <> OLD.max_sesiones_semana)
     AND EXISTS (SELECT 1 FROM horario WHERE periodo_id = OLD.id AND estado = 'PUBLICADO') THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = '[BD-16] Periodo con horario PUBLICADO: no se cambian franjas, almuerzo, bloque ni máximo de sesiones.';
  END IF;
END$$

DELIMITER ;

-- Fin de P3_D2_parametros_con_publicado.sql
