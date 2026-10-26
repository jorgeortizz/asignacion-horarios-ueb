-- Aplicación controlada del almuerzo de 2026-2. MySQL 8.0.45 / Workbench 8.0.
-- PREPARADO PARA REVISIÓN: no ejecutar hasta aprobar el plan completo.
-- Este archivo no aplica V3 ni modifica los DEFAULT del esquema.
-- Usuario comprobado: 'horarios_migra'@'127.0.0.1'. Los mínimos figuran en
-- permisos_control_almuerzo_2026_2.sql; no hace falta ampliar sus permisos actuales.
--
-- Preparación, SIEMPRE antes de iniciar la transacción de aplicación:
-- 1. Reservar una ventana sin escrituras de la aplicación ni mantenimiento DDL.
-- 2. En una conexión NUEVA, sin trabajo pendiente, revisar e instalar una sola vez
--    preparar_control_almuerzo_2026_2.sql. Contiene CREATE PROCEDURE, que hace
--    commit implícito: jamás ejecutarlo con una transacción pendiente.
--    Detenerse si la preparación da algún error o ya existen esas rutinas;
--    no borrar/reemplazar objetos automáticamente ni continuar con una mezcla.
-- 3. Usar la conexión original para los pasos siguientes y mantener ESTA pestaña
--    abierta. Activar en Workbench "Stop Script Execution On Errors".
--    Verificar que la cuenta sea horarios_migra y anotar CONNECTION_ID().
--    Las llamadas usan el esquema explícito para evitar otra base seleccionada.
--
-- Aplicación y revisión, en la MISMA pestaña y conexión:
-- 4. Ejecutar únicamente las dos sentencias activas de este archivo: CALL aplicar
--    y SELECT de estado. START TRANSACTION está dentro del procedimiento.
--    No cambiar Auto-Commit después de iniciarla. La transacción deja bloqueados
--    los registros hasta confirmar o revertir; revisar sin una pausa prolongada.
-- 5. Si CALL falla, DETENERSE. El handler revierte los cambios de su transacción.
--    No continuar a la confirmación. Un fallo previo al START no cancela una
--    transacción ajena que ya estuviera abierta: por eso se exige conexión limpia.
-- 6. Si funciona, exigir PENDIENTE_CONFIRMACION, conexión_actual=conexion_aplicacion,
--    filas_sesion=5 y filas_periodo=1, además de todos los informes de invariantes
--    satisfactorios. Las modificaciones aún NO están confirmadas.
-- 7. Tras revisar TODOS los resultados, elegir UNA opción del final. Copiarla
--    SIN los dos guiones a la misma pestaña, colocar el cursor en esa sentencia
--    y ejecutar solo esa sentencia (Ctrl+Enter). No ejecutar ambas opciones.
--
-- Mientras esté pendiente, NO ejecutar:
--   * COMMIT manual ni el botón de confirmación de Workbench: el procedimiento
--     confirmar vuelve a verificar los invariantes antes de autorizar COMMIT.
--   * START TRANSACTION, BEGIN WORK, preflight_V3.sql ni el script de propuestas:
--     otro START puede confirmar implícitamente la transacción actual.
--   * CREATE/ALTER/DROP, LOCK TABLES, SET autocommit=1, la preparación o V3.
--   * Scripts completos o comandos desde otra conexión para "continuar" esta.
-- Si se cierra/pierde la conexión antes de confirmar, InnoDB revierte lo pendiente.
-- Una reconexión tiene otros marcadores y no permite continuar la operación.
-- Si hubo COMMIT/ROLLBACK manual, el SAVEPOINT deja de existir y confirmar rechaza
-- la operación; eso NO puede deshacer un COMMIT manual que alguien ya ejecutó.
-- Los marcadores de sesión son diagnósticos, no sustituyen la revalidación final.
--
-- Resultado esperado:
--   * Solo sesiones 12,13,14,18,23: 13:00-15:00 -> 15:00-17:00, mismos días/IDs/grupos.
--   * Periodo 2: almuerzo 13:00-14:00; sus otras columnas permanecen iguales.
--   * Horario 2: sigue BORRADOR, con 24 sesiones; no se altera su publicación.
--   * Periodo 1, su PUBLICADO y sus ocho sesiones: todos los campos idénticos.
--   * Sin bloqueos de duración, jornada, cuadrícula, almuerzo, choques, cupos,
--     frecuencia máxima o disponibilidad firme. No se cambian docentes/cursos.
--   * Los días y frecuencias se conservan. No aparecen preferencias incumplidas
--     ni nuevos días consecutivos en las cinco sesiones movidas.
--   * Continúan las advertencias previas: aula especial de esas cinco sesiones,
--     grupo 19 viernes/sábado consecutivos, grupo 15 candidato a cierre y grupo 21
--     con 1 de 2 sesiones. El ajuste NO vuelve publicable el horario completo.
-- V3 queda pendiente de una aprobación/aplicación SEPARADA, después de cerrar
-- satisfactoriamente esta transacción y repetir la auditoría correspondiente.

CALL horarios_ueb.sp_almuerzo_2026_2_aplicar();

SELECT CASE
         WHEN @almuerzo_2026_2_estado = 'PENDIENTE_CONFIRMACION'
          AND @almuerzo_2026_2_conexion = CONNECTION_ID()
          AND @almuerzo_2026_2_filas_sesion = 5
          AND @almuerzo_2026_2_filas_periodo = 1
          AND @almuerzo_2026_2_invariantes_verificados = TRUE
          AND @almuerzo_2026_2_huellas_verificadas IS NOT NULL
         THEN 'PENDIENTE_CONFIRMACION: revisar informes; cambios aun sin COMMIT'
         ELSE 'SIN_APLICACION_PENDIENTE_VALIDADA: detenerse y revisar el error/estado'
       END AS resultado_operacion,
       CURRENT_USER() AS cuenta_autenticada,
       CONNECTION_ID() AS conexion_actual,
       @almuerzo_2026_2_conexion AS conexion_aplicacion,
       @almuerzo_2026_2_estado AS estado,
       @almuerzo_2026_2_filas_sesion AS filas_sesion,
       @almuerzo_2026_2_filas_periodo AS filas_periodo,
       @almuerzo_2026_2_invariantes_verificados AS invariantes_verificados,
       @almuerzo_2026_2_huellas_verificadas AS huellas_verificadas;

-- OPCIÓN A, SOLO tras resultados correctos y aprobación del operador:
-- CALL horarios_ueb.sp_almuerzo_2026_2_confirmar();
-- Debe terminar en CONFIRMADO. Revalidación fallida => ROLLBACK + error.
-- No añadir un COMMIT manual antes o después de esta llamada.

-- OPCIÓN B, ante duda, error de revisión o decisión de cancelar:
-- ROLLBACK AND NO CHAIN NO RELEASE;
-- Después de revertir, cerrar esta conexión y usar una nueva si se revisa otro
-- intento. ROLLBACK manual no limpia variables de sesión: no interpretar sus
-- valores antiguos como una transacción todavía pendiente o confirmable.
