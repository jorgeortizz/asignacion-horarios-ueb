-- PREPARACION para revisar; NO ejecutar junto con la transaccion de escritura.
-- MySQL 8.0.45 / horarios_ueb. No es una migracion Flyway.
-- Este archivo SOLO crea cuatro procedimientos auxiliares SQL SECURITY INVOKER.
-- Ejecutarlo, tras aprobacion, en una conexion nueva sin trabajo pendiente.
-- CREATE PROCEDURE hace commit implicito: instalar TODOS los auxiliares ANTES
-- de llamar a aplicar(); no repetir este archivo mientras haya una transaccion.
-- No se reemplaza ningun objeto existente. Si alguno de estos nombres existe,
-- detenerse y revisar su definicion; no ignorar el error ni continuar a aplicar().
--
-- La aplicacion y confirmacion estan en aplicar_almuerzo_2026_2.sql.
-- No hay CALL externos, COMMIT externo, DROP, ALTER, seed ni V3 en este archivo.
-- Huellas de la auditoria aprobada del 2026-10-24: ocho conjuntos completos,
-- columnas explicitas en orden del esquema, JSON_ARRAY por fila y SHA-256.
-- El separador canonico es un salto de linea, escrito como escape SQL '\n'.
-- Se fija sql_mode al CREAR las rutinas para interpretar ese separador igual.
-- No cambiar hashes para aceptar una BD diferente: se requiere otra revision.

USE horarios_ueb;
SET NAMES utf8mb4;
SET SESSION sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

DELIMITER $$

CREATE PROCEDURE sp_almuerzo_2026_2_huellas (OUT p_huellas JSON)
SQL SECURITY INVOKER
READS SQL DATA
BEGIN
  DECLARE v_texto LONGTEXT CHARACTER SET utf8mb4;
  -- Truncar una huella nunca puede convertir un estado no esperado en aceptado.
  DECLARE EXIT HANDLER FOR SQLWARNING
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-01] Advertencia al serializar datos; no aceptar huellas truncadas.';

  IF @@session.group_concat_max_len < 1048576 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-01] group_concat_max_len debe ser al menos 1048576.';
  END IF;
  SET p_huellas = JSON_OBJECT();

  SELECT COALESCE(GROUP_CONCAT(CAST(JSON_ARRAY(t.id,t.nombre,t.fecha_inicio,t.fecha_fin,t.hora_inicio_semana,t.hora_fin_semana,t.hora_inicio_sabado,t.hora_fin_sabado,t.almuerzo_inicio,t.almuerzo_fin,t.duracion_bloque_min,t.max_sesiones_semana,t.cupo_maximo_base,t.tolerancia_cupo_pct,t.cupo_minimo) AS CHAR CHARACTER SET utf8mb4)
           ORDER BY t.id SEPARATOR '\n'),'') INTO v_texto
    FROM periodo_academico t WHERE t.id IN (1,2);
  IF OCTET_LENGTH(v_texto) >= @@session.group_concat_max_len THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-01] Huella periodo demasiado grande; revisar sin cambiar datos.';
  END IF;
  SET p_huellas = JSON_SET(p_huellas, '$.periodo', SHA2(v_texto,256));

  SELECT COALESCE(GROUP_CONCAT(CAST(JSON_ARRAY(t.id,t.periodo_id,t.estado,t.fecha_creacion,t.fecha_publicacion,t.version) AS CHAR CHARACTER SET utf8mb4)
           ORDER BY t.id SEPARATOR '\n'),'') INTO v_texto
    FROM horario t WHERE t.periodo_id IN (1,2);
  IF OCTET_LENGTH(v_texto) >= @@session.group_concat_max_len THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-01] Huella horario demasiado grande; revisar sin cambiar datos.';
  END IF;
  SET p_huellas = JSON_SET(p_huellas, '$.horario', SHA2(v_texto,256));

  SELECT COALESCE(GROUP_CONCAT(CAST(JSON_ARRAY(t.id,t.horario_id,t.grupo_id,t.dia,t.hora_inicio,t.hora_fin) AS CHAR CHARACTER SET utf8mb4)
           ORDER BY t.id SEPARATOR '\n'),'') INTO v_texto
    FROM sesion t WHERE t.horario_id IN (1,2);
  IF OCTET_LENGTH(v_texto) >= @@session.group_concat_max_len THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-01] Huella sesion demasiado grande; revisar sin cambiar datos.';
  END IF;
  SET p_huellas = JSON_SET(p_huellas, '$.sesion', SHA2(v_texto,256));

  SELECT COALESCE(GROUP_CONCAT(CAST(JSON_ARRAY(t.id,t.periodo_id,t.curso_id,t.docente_id,t.codigo,t.cupo_maximo,t.cupo_minimo,t.inscritos) AS CHAR CHARACTER SET utf8mb4)
           ORDER BY t.id SEPARATOR '\n'),'') INTO v_texto
    FROM grupo t WHERE t.periodo_id IN (1,2);
  IF OCTET_LENGTH(v_texto) >= @@session.group_concat_max_len THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-01] Huella grupo demasiado grande; revisar sin cambiar datos.';
  END IF;
  SET p_huellas = JSON_SET(p_huellas, '$.grupo', SHA2(v_texto,256));

  SELECT COALESCE(GROUP_CONCAT(CAST(JSON_ARRAY(t.id,t.codigo,t.nombre,t.sesiones_semanales,t.duracion_sesion_min,t.necesita_aula_especial) AS CHAR CHARACTER SET utf8mb4)
           ORDER BY t.id SEPARATOR '\n'),'') INTO v_texto
    FROM curso t WHERE EXISTS (SELECT 1 FROM grupo g WHERE g.curso_id=t.id AND g.periodo_id IN(1,2));
  IF OCTET_LENGTH(v_texto) >= @@session.group_concat_max_len THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-01] Huella curso demasiado grande; revisar sin cambiar datos.';
  END IF;
  SET p_huellas = JSON_SET(p_huellas, '$.curso', SHA2(v_texto,256));

  SELECT COALESCE(GROUP_CONCAT(CAST(JSON_ARRAY(t.id,t.nombre,t.tipo_vinculacion) AS CHAR CHARACTER SET utf8mb4)
           ORDER BY t.id SEPARATOR '\n'),'') INTO v_texto
    FROM docente t WHERE EXISTS (SELECT 1 FROM grupo g WHERE g.docente_id=t.id AND g.periodo_id IN(1,2));
  IF OCTET_LENGTH(v_texto) >= @@session.group_concat_max_len THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-01] Huella docente demasiado grande; revisar sin cambiar datos.';
  END IF;
  SET p_huellas = JSON_SET(p_huellas, '$.docente', SHA2(v_texto,256));

  SELECT COALESCE(GROUP_CONCAT(CAST(JSON_ARRAY(t.id,t.docente_id,t.dia,t.hora_inicio,t.hora_fin,t.tipo,t.sentido) AS CHAR CHARACTER SET utf8mb4)
           ORDER BY t.id SEPARATOR '\n'),'') INTO v_texto
    FROM restriccion_horaria t WHERE EXISTS (SELECT 1 FROM grupo g WHERE g.docente_id=t.docente_id AND g.periodo_id IN(1,2));
  IF OCTET_LENGTH(v_texto) >= @@session.group_concat_max_len THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-01] Huella restriccion demasiado grande; revisar sin cambiar datos.';
  END IF;
  SET p_huellas = JSON_SET(p_huellas, '$.restriccion', SHA2(v_texto,256));

  SELECT COALESCE(GROUP_CONCAT(CAST(JSON_ARRAY(t.docente_id,t.especialidad) AS CHAR CHARACTER SET utf8mb4)
           ORDER BY t.docente_id,t.especialidad SEPARATOR '\n'),'') INTO v_texto
    FROM docente_especialidad t WHERE EXISTS (SELECT 1 FROM grupo g WHERE g.docente_id=t.docente_id AND g.periodo_id IN(1,2));
  IF OCTET_LENGTH(v_texto) >= @@session.group_concat_max_len THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-01] Huella docente_especialidad demasiado grande; revisar sin cambiar datos.';
  END IF;
  SET p_huellas = JSON_SET(p_huellas, '$.docente_especialidad', SHA2(v_texto,256));
END$$

CREATE PROCEDURE sp_almuerzo_2026_2_verificar ()
SQL SECURITY INVOKER
READS SQL DATA
BEGIN
  DECLARE v_actual JSON;
  DECLARE v_esperada JSON;
  DECLARE v_post BOOLEAN;

  SET @almuerzo_2026_2_invariantes_verificados=FALSE,
      @almuerzo_2026_2_huellas_verificadas=NULL;
  IF NOT (@almuerzo_2026_2_conexion <=> CONNECTION_ID())
     OR COALESCE(@almuerzo_2026_2_estado,'') NOT IN ('APLICANDO','PENDIENTE_CONFIRMACION') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-02] Contexto o conexion incorrectos; no confirmar.';
  END IF;
  SET v_post = @almuerzo_2026_2_estado = 'PENDIENTE_CONFIRMACION';
  IF v_post THEN
    SET v_esperada = JSON_OBJECT(
      'periodo','970d482c8f8202157d16ae67d7041d1df298033ecabdf899c2e28c598151000b',
      'horario','bd23a8f24e6eeb081193d78bba7ee5151afff174dc2020a54cbf621e2e8710df',
      'sesion','b948d7679937d24f7e8e4571086cd9c07bea9abee92825817adb6238a8f11e6b',
      'grupo','feba4bf9a71acd7eaea462112490d636535d8d7825b813a193ddf26b638d9941',
      'curso','c7755d75c8fb3eae4c5b650976d5ff29bbb17a5c7e8d1d4e6cb0ac676e9f28df',
      'docente','d93d2342679bb895d303b2530e6b7fadbab59324c8159ed044e28a615bfd6989',
      'restriccion','59f45a937b2c24e2e8e04aea7f4149b1b778a543540876faa22311fe851878b8',
      'docente_especialidad','bf317113ec0e2d6b2da1dbd2217f5ba425aadac3f3fe93ba18d41ac8138eb1ec');
  ELSE
    SET v_esperada = JSON_OBJECT(
      'periodo','99e0d3182f3e7af2fe75df97b901cb12b47961747b5442b53dba64925af7725c',
      'horario','bd23a8f24e6eeb081193d78bba7ee5151afff174dc2020a54cbf621e2e8710df',
      'sesion','7842327390a1e6e43f4167e5bb17a7260dd145e24aa1b48693171cc87ad41c79',
      'grupo','feba4bf9a71acd7eaea462112490d636535d8d7825b813a193ddf26b638d9941',
      'curso','c7755d75c8fb3eae4c5b650976d5ff29bbb17a5c7e8d1d4e6cb0ac676e9f28df',
      'docente','d93d2342679bb895d303b2530e6b7fadbab59324c8159ed044e28a615bfd6989',
      'restriccion','59f45a937b2c24e2e8e04aea7f4149b1b778a543540876faa22311fe851878b8',
      'docente_especialidad','bf317113ec0e2d6b2da1dbd2217f5ba425aadac3f3fe93ba18d41ac8138eb1ec');
  END IF;

  CALL sp_almuerzo_2026_2_huellas(v_actual);
  -- Incluye TODOS los campos de p1/p2, h1/h2 y las 32 sesiones, ademas de
  -- grupos, cursos, docentes, restricciones y especialidades. POST permite
  -- exclusivamente las horas de cinco sesiones y los dos parametros de p2.
  IF NOT (CAST(v_actual AS BINARY) <=> CAST(v_esperada AS BINARY)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-03] Los datos completos no coinciden con la referencia aprobada; revertir.';
  END IF;

  IF (SELECT COUNT(*) FROM periodo_academico WHERE id IN (1,2)) <> 2
     OR (SELECT COUNT(*) FROM horario WHERE periodo_id IN (1,2)) <> 2
     OR (SELECT COUNT(*) FROM sesion WHERE horario_id = 1) <> 8
     OR (SELECT COUNT(*) FROM sesion WHERE horario_id = 2) <> 24
     OR NOT EXISTS(SELECT 1 FROM periodo_academico WHERE id=1 AND nombre='2026-1'
                     AND almuerzo_inicio='12:00:00' AND almuerzo_fin='13:00:00')
     OR NOT EXISTS(SELECT 1 FROM horario WHERE id=1 AND periodo_id=1 AND estado='PUBLICADO')
     OR NOT EXISTS(SELECT 1 FROM horario WHERE id=2 AND periodo_id=2 AND estado='BORRADOR')
     OR EXISTS(SELECT 1 FROM horario WHERE periodo_id=2 AND estado='PUBLICADO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-04] Cambiaron periodos, estados o cantidades de sesiones.';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM periodo_academico WHERE id=2 AND nombre='2026-2'
                 AND duracion_bloque_min=120 AND max_sesiones_semana=4
                 AND hora_inicio_semana='07:00:00' AND hora_fin_semana='22:00:00'
                 AND hora_inicio_sabado='07:00:00' AND hora_fin_sabado='13:00:00'
                 AND almuerzo_inicio=IF(v_post,CAST('13:00:00' AS TIME),CAST('12:00:00' AS TIME))
                 AND almuerzo_fin=IF(v_post,CAST('14:00:00' AS TIME),CAST('13:00:00' AS TIME))) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-05] Los parametros del periodo 2026-2 no son los previstos.';
  END IF;

  IF (SELECT COUNT(*) FROM sesion WHERE horario_id=2 AND id IN (12,13,14,18,23)
       AND ((id=12 AND grupo_id=12 AND dia=1) OR (id=13 AND grupo_id=12 AND dia=3)
         OR (id=14 AND grupo_id=12 AND dia=5) OR (id=18 AND grupo_id=14 AND dia=4)
         OR (id=23 AND grupo_id=17 AND dia=2))
       AND hora_inicio=IF(v_post,CAST('15:00:00' AS TIME),CAST('13:00:00' AS TIME))
       AND hora_fin=IF(v_post,CAST('17:00:00' AS TIME),CAST('15:00:00' AS TIME))) <> 5 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-06] No coinciden exactamente los cinco IDs, grupos, dias y horas.';
  END IF;

  IF v_post AND (NOT (@almuerzo_2026_2_filas_sesion <=> 5)
                OR NOT (@almuerzo_2026_2_filas_periodo <=> 1)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-07] ROW_COUNT no fue cinco sesiones y un periodo.';
  END IF;

  -- Franja, intervalo semiabierto, duracion y ancla de la cuadricula.
  IF EXISTS(SELECT 1 FROM sesion s JOIN horario h ON h.id=s.horario_id
       JOIN periodo_academico p ON p.id=h.periodo_id JOIN grupo g ON g.id=s.grupo_id
       JOIN curso c ON c.id=g.curso_id WHERE h.periodo_id IN (1,2)
       AND (g.periodo_id<>h.periodo_id OR s.dia NOT BETWEEN 1 AND 6
         OR s.hora_inicio<IF(s.dia=6,p.hora_inicio_sabado,p.hora_inicio_semana)
         OR s.hora_fin>IF(s.dia=6,p.hora_fin_sabado,p.hora_fin_semana)
         OR TIME_TO_SEC(TIMEDIFF(s.hora_fin,s.hora_inicio))<>c.duracion_sesion_min*60
         OR c.duracion_sesion_min<>p.duracion_bloque_min
         OR MOD(TIME_TO_SEC(TIMEDIFF(s.hora_inicio,
                IF(s.dia=6,p.hora_inicio_sabado,p.hora_inicio_semana))),p.duracion_bloque_min*60)<>0
         OR (s.hora_inicio<p.almuerzo_fin AND s.hora_fin>p.almuerzo_inicio))) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-08] Hay conflicto de periodo, jornada, duracion, cuadricula o almuerzo.';
  END IF;

  IF EXISTS(SELECT 1 FROM sesion a JOIN sesion b ON b.horario_id=a.horario_id
       AND b.dia=a.dia AND b.id>a.id JOIN grupo ga ON ga.id=a.grupo_id
       JOIN grupo gb ON gb.id=b.grupo_id WHERE a.horario_id IN (1,2)
       AND (a.grupo_id=b.grupo_id OR ga.docente_id=gb.docente_id)
       AND a.hora_inicio<b.hora_fin AND a.hora_fin>b.hora_inicio) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-09] Hay choque de docente o grupo en un horario.';
  END IF;

  -- Una inclusion FIRME en cualquier dia exige cobertura completa en el dia
  -- de la sesion; las exclusiones FIRME se comparan como intervalos semiabiertos.
  IF EXISTS(SELECT 1 FROM sesion s JOIN grupo g ON g.id=s.grupo_id
       WHERE s.horario_id IN (1,2)
       AND ((EXISTS(SELECT 1 FROM restriccion_horaria r WHERE r.docente_id=g.docente_id
                      AND r.tipo='FIRME' AND r.sentido='DISPONIBLE')
             AND NOT EXISTS(SELECT 1 FROM restriccion_horaria r WHERE r.docente_id=g.docente_id
                      AND r.tipo='FIRME' AND r.sentido='DISPONIBLE' AND r.dia=s.dia
                      AND r.hora_inicio<=s.hora_inicio AND r.hora_fin>=s.hora_fin))
         OR EXISTS(SELECT 1 FROM restriccion_horaria r WHERE r.docente_id=g.docente_id
                      AND r.tipo='FIRME' AND r.sentido='NO_DISPONIBLE' AND r.dia=s.dia
                      AND s.hora_inicio<r.hora_fin AND s.hora_fin>r.hora_inicio))) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-10] Hay incumplimiento de disponibilidad firme del docente.';
  END IF;

  IF EXISTS(SELECT 1 FROM grupo g JOIN periodo_academico p ON p.id=g.periodo_id
       JOIN curso c ON c.id=g.curso_id WHERE g.periodo_id IN (1,2)
       AND (c.sesiones_semanales>p.max_sesiones_semana
         OR g.inscritos>FLOOR(g.cupo_maximo*(1+p.tolerancia_cupo_pct/100)))) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-11] Hay exceso de cupo o frecuencia maxima.';
  END IF;

  -- La unica frecuencia incompleta aprobada es la preexistente del grupo 21.
  IF EXISTS(SELECT 1 FROM grupo g JOIN curso c ON c.id=g.curso_id
       JOIN horario h ON h.periodo_id=g.periodo_id
       LEFT JOIN sesion s ON s.horario_id=h.id AND s.grupo_id=g.id
       WHERE g.periodo_id IN (1,2) AND g.id<>21
       GROUP BY h.id,g.id,c.sesiones_semanales HAVING COUNT(s.id)<>c.sesiones_semanales)
     OR NOT EXISTS(SELECT 1 FROM grupo g JOIN curso c ON c.id=g.curso_id
       LEFT JOIN sesion s ON s.grupo_id=g.id AND s.horario_id=2
       WHERE g.id=21 AND g.periodo_id=2 AND c.sesiones_semanales=2
       GROUP BY g.id HAVING COUNT(s.id)=1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-12] Cambio la frecuencia aprobada de algun grupo.';
  END IF;
  -- Estos diagnosticos solo se publican tras completar todas las comprobaciones.
  SET @almuerzo_2026_2_invariantes_verificados=TRUE,
      @almuerzo_2026_2_huellas_verificadas=CAST(v_actual AS CHAR CHARACTER SET utf8mb4);
END$$

CREATE PROCEDURE sp_almuerzo_2026_2_aplicar ()
SQL SECURITY INVOKER
MODIFIES SQL DATA
BEGIN
  DECLARE v_iniciada BOOLEAN DEFAULT FALSE;
  DECLARE v_fin BOOLEAN DEFAULT FALSE;
  DECLARE v_id BIGINT;
  DECLARE v_docente_id BIGINT;
  DECLARE v_especialidad VARCHAR(100);

  DECLARE c_horarios CURSOR FOR SELECT id FROM horario FORCE INDEX (idx_horario_periodo_estado)
    WHERE periodo_id IN (1,2) ORDER BY id FOR SHARE;
  DECLARE c_sesiones_hist CURSOR FOR SELECT id FROM sesion FORCE INDEX (idx_sesion_horario_casilla)
    WHERE horario_id=1 ORDER BY id FOR SHARE;
  DECLARE c_sesiones_borr CURSOR FOR SELECT id FROM sesion FORCE INDEX (idx_sesion_horario_casilla)
    WHERE horario_id=2 ORDER BY id FOR UPDATE;
  DECLARE c_grupos CURSOR FOR SELECT id FROM grupo FORCE INDEX (uk_grupo_periodo_curso_codigo)
    WHERE periodo_id IN (1,2) ORDER BY id FOR SHARE;
  DECLARE c_cursos CURSOR FOR SELECT c.id FROM curso c JOIN grupo g ON g.curso_id=c.id
    WHERE g.periodo_id IN (1,2) ORDER BY c.id FOR SHARE;
  DECLARE c_docentes CURSOR FOR SELECT d.id FROM docente d JOIN grupo g ON g.docente_id=d.id
    WHERE g.periodo_id IN (1,2) ORDER BY d.id FOR SHARE;
  DECLARE c_restricciones CURSOR FOR SELECT id FROM restriccion_horaria FORCE INDEX (idx_restriccion_horaria_docente_dia)
    WHERE docente_id=v_docente_id ORDER BY id FOR SHARE;
  DECLARE c_especialidades CURSOR FOR SELECT especialidad FROM docente_especialidad
    WHERE docente_id=v_docente_id ORDER BY especialidad FOR SHARE;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin=TRUE;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    -- SET TRANSACTION falla si ya habia una transaccion: no revertirla ni
    -- borrar sus marcadores. Solo se revierte lo iniciado por esta llamada.
    IF v_iniciada THEN
      ROLLBACK AND NO CHAIN NO RELEASE;
      SET @almuerzo_2026_2_estado='ERROR_REVERTIDO', @almuerzo_2026_2_conexion=NULL,
          @almuerzo_2026_2_filas_sesion=NULL, @almuerzo_2026_2_filas_periodo=NULL,
          @almuerzo_2026_2_invariantes_verificados=FALSE,
          @almuerzo_2026_2_huellas_verificadas=NULL;
    END IF;
    RESIGNAL;
  END;

  IF COALESCE(@almuerzo_2026_2_estado,'')='PENDIENTE_CONFIRMACION' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '[ALM-13] Ya hay un ajuste pendiente en esta sesion; confirmar o revertir.';
  END IF;
  SET SESSION group_concat_max_len=1048576;
  SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ WRITE;
  START TRANSACTION READ WRITE;
  SET v_iniciada=TRUE;
  SET @almuerzo_2026_2_conexion=CONNECTION_ID(), @almuerzo_2026_2_estado='APLICANDO',
      @almuerzo_2026_2_filas_sesion=NULL, @almuerzo_2026_2_filas_periodo=NULL,
      @almuerzo_2026_2_invariantes_verificados=FALSE,
      @almuerzo_2026_2_huellas_verificadas=NULL;

  -- Lecturas ACTUALES con locks primero. No crear una snapshot anterior a
  -- esperar estos bloqueos; el primer SELECT consistente va en verificar().
  SET v_id=NULL, v_fin=FALSE;
  SELECT id INTO v_id FROM periodo_academico WHERE id=1 FOR SHARE;
  IF v_id IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='[ALM-14] Falta periodo 1.'; END IF;
  SET v_id=NULL, v_fin=FALSE;
  SELECT id INTO v_id FROM periodo_academico WHERE id=2 FOR UPDATE;
  IF v_id IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='[ALM-14] Falta periodo 2.'; END IF;

  SET v_fin=FALSE;
  OPEN c_horarios;
  bloquear_horarios: LOOP
    FETCH c_horarios INTO v_id;
    IF v_fin THEN LEAVE bloquear_horarios; END IF;
  END LOOP;
  CLOSE c_horarios;

  SET v_fin=FALSE;
  OPEN c_sesiones_hist;
  bloquear_sesiones_hist: LOOP
    FETCH c_sesiones_hist INTO v_id;
    IF v_fin THEN LEAVE bloquear_sesiones_hist; END IF;
  END LOOP;
  CLOSE c_sesiones_hist;

  SET v_fin=FALSE;
  OPEN c_sesiones_borr;
  bloquear_sesiones_borr: LOOP
    FETCH c_sesiones_borr INTO v_id;
    IF v_fin THEN LEAVE bloquear_sesiones_borr; END IF;
  END LOOP;
  CLOSE c_sesiones_borr;

  SET v_fin=FALSE;
  OPEN c_grupos;
  bloquear_grupos: LOOP
    FETCH c_grupos INTO v_id;
    IF v_fin THEN LEAVE bloquear_grupos; END IF;
  END LOOP;
  CLOSE c_grupos;

  SET v_fin=FALSE;
  OPEN c_cursos;
  bloquear_cursos: LOOP
    FETCH c_cursos INTO v_id;
    IF v_fin THEN LEAVE bloquear_cursos; END IF;
  END LOOP;
  CLOSE c_cursos;

  SET v_fin=FALSE;
  OPEN c_docentes;
  bloquear_docentes: LOOP
    FETCH c_docentes INTO v_docente_id;
    IF v_fin THEN LEAVE bloquear_docentes; END IF;

    SET v_fin=FALSE;
    OPEN c_restricciones;
    bloquear_restricciones: LOOP
      FETCH c_restricciones INTO v_id;
      IF v_fin THEN LEAVE bloquear_restricciones; END IF;
    END LOOP;
    CLOSE c_restricciones;

    SET v_fin=FALSE;
    OPEN c_especialidades;
    bloquear_especialidades: LOOP
      FETCH c_especialidades INTO v_especialidad;
      IF v_fin THEN LEAVE bloquear_especialidades; END IF;
    END LOOP;
    CLOSE c_especialidades;
    SET v_fin=FALSE;
  END LOOP;
  CLOSE c_docentes;

  CALL sp_almuerzo_2026_2_verificar();

  -- Las cinco cambian de horas, conservando ID, horario, grupo y dia. El
  -- trigger real sigue validando cada fila con el almuerzo anterior 12-13.
  UPDATE sesion SET hora_inicio='15:00:00', hora_fin='17:00:00'
   WHERE horario_id=2 AND hora_inicio='13:00:00' AND hora_fin='15:00:00'
     AND ((id=12 AND grupo_id=12 AND dia=1) OR (id=13 AND grupo_id=12 AND dia=3)
       OR (id=14 AND grupo_id=12 AND dia=5) OR (id=18 AND grupo_id=14 AND dia=4)
       OR (id=23 AND grupo_id=17 AND dia=2));
  SET @almuerzo_2026_2_filas_sesion=ROW_COUNT();
  IF @almuerzo_2026_2_filas_sesion<>5 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='[ALM-15] El UPDATE no modifico exactamente las cinco sesiones.';
  END IF;

  -- Ninguna sesion del periodo puede quedar en conflicto al cambiar almuerzo.
  -- Los rangos de horarios y sesiones ya estan bloqueados; no se publica nada.
  UPDATE periodo_academico p SET almuerzo_inicio='13:00:00', almuerzo_fin='14:00:00'
   WHERE p.id=2 AND p.nombre='2026-2' AND p.almuerzo_inicio='12:00:00' AND p.almuerzo_fin='13:00:00'
     AND NOT EXISTS(SELECT 1 FROM horario h WHERE h.periodo_id=p.id AND h.estado='PUBLICADO')
     AND NOT EXISTS(SELECT 1 FROM sesion s JOIN horario h ON h.id=s.horario_id
                     WHERE h.periodo_id=p.id AND s.hora_inicio<'14:00:00' AND s.hora_fin>'13:00:00');
  SET @almuerzo_2026_2_filas_periodo=ROW_COUNT();
  IF @almuerzo_2026_2_filas_periodo<>1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='[ALM-16] No se modifico exclusivamente el periodo 2.';
  END IF;

  SET @almuerzo_2026_2_estado='PENDIENTE_CONFIRMACION';
  CALL sp_almuerzo_2026_2_verificar();
  SAVEPOINT almuerzo_validado;

  -- Resultados visibles en esta misma conexion; la transaccion sigue abierta.
  SELECT CONNECTION_ID() AS conexion, @almuerzo_2026_2_estado AS estado,
         @almuerzo_2026_2_filas_sesion AS sesiones_modificadas,
         @almuerzo_2026_2_filas_periodo AS periodos_modificados,
         (SELECT COUNT(*) FROM sesion WHERE horario_id=2) AS sesiones_borrador,
         (SELECT COUNT(*) FROM sesion WHERE horario_id=1) AS sesiones_historicas,
         (SELECT COUNT(*) FROM sesion s JOIN horario h ON h.id=s.horario_id
            JOIN periodo_academico p ON p.id=h.periodo_id WHERE p.id=2
             AND s.hora_inicio<p.almuerzo_fin AND s.hora_fin>p.almuerzo_inicio)
           AS conflictos_almuerzo,
         @almuerzo_2026_2_invariantes_verificados AS invariantes_verificados,
         @almuerzo_2026_2_huellas_verificadas AS huellas_verificadas,
         (SELECT COUNT(*) FROM sesion WHERE horario_id=2 AND grupo_id=21)
           AS sesiones_programadas_grupo_21,
         (SELECT c.sesiones_semanales FROM grupo g JOIN curso c ON c.id=g.curso_id
           WHERE g.id=21) AS sesiones_requeridas_grupo_21,
         'Historico y restricciones verificados. Este procedimiento no aplica V3.' AS detalle;
  SELECT s.id,s.horario_id,s.grupo_id,s.dia,s.hora_inicio,s.hora_fin,
         c.nombre AS curso,d.nombre AS docente,c.necesita_aula_especial
    FROM sesion s JOIN grupo g ON g.id=s.grupo_id JOIN curso c ON c.id=g.curso_id
    JOIN docente d ON d.id=g.docente_id WHERE s.id IN (12,13,14,18,23) ORDER BY s.id;
END$$

CREATE PROCEDURE sp_almuerzo_2026_2_confirmar ()
SQL SECURITY INVOKER
MODIFIES SQL DATA
BEGIN
  DECLARE v_contexto BOOLEAN DEFAULT FALSE;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    IF v_contexto THEN
      ROLLBACK AND NO CHAIN NO RELEASE;
      SET @almuerzo_2026_2_estado='ERROR_REVERTIDO', @almuerzo_2026_2_conexion=NULL,
          @almuerzo_2026_2_filas_sesion=NULL, @almuerzo_2026_2_filas_periodo=NULL,
          @almuerzo_2026_2_invariantes_verificados=FALSE,
          @almuerzo_2026_2_huellas_verificadas=NULL;
    END IF;
    RESIGNAL;
  END;

  IF NOT (@almuerzo_2026_2_conexion <=> CONNECTION_ID())
     OR NOT (@almuerzo_2026_2_estado <=> 'PENDIENTE_CONFIRMACION') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='[ALM-17] No hay ajuste pendiente en esta conexion; no confirmar.';
  END IF;
  SET v_contexto=TRUE;
  -- Guard real de la transaccion. COMMIT, ROLLBACK, DDL o reconexion eliminan
  -- el SAVEPOINT; no basta con que sobrevivan variables de sesion.
  RELEASE SAVEPOINT almuerzo_validado;
  SAVEPOINT almuerzo_validado;
  CALL sp_almuerzo_2026_2_verificar();
  COMMIT AND NO CHAIN NO RELEASE;
  SET @almuerzo_2026_2_estado='CONFIRMADO', @almuerzo_2026_2_conexion=NULL;
  SELECT CONNECTION_ID() AS conexion, @almuerzo_2026_2_estado AS estado,
         @almuerzo_2026_2_filas_sesion AS sesiones_modificadas,
         @almuerzo_2026_2_filas_periodo AS periodos_modificados,
         @almuerzo_2026_2_invariantes_verificados AS invariantes_verificados,
         @almuerzo_2026_2_huellas_verificadas AS huellas_verificadas;
END$$

DELIMITER ;
