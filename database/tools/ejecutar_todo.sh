#!/usr/bin/env bash
# =============================================================================
# ejecutar_todo.sh — Batería reproducible de la base de datos (solo DESARROLLO)
#
# Uso:
#   TEST_DB_RESET='BORRAR horarios_ueb SOLO PRUEBAS' \
#   MYSQL="mysql -uroot -p<clave> -h127.0.0.1" \
#   JDBC_URL="jdbc:mysql://127.0.0.1:3306/horarios_ueb" DB_USER=root DB_PASSWORD=<clave> \
#   FLYWAY=/ruta/flyway  tools/ejecutar_todo.sh  [carpeta_evidencia]
#
# BORRA Y RECREA horarios_ueb varias veces. No lo ejecute contra un servidor
# compartido. FLYWAY es opcional: sin él se omiten las pruebas con Flyway.
# Termina con código 0 solo si todas las comprobaciones pasan.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
# La presencia de V3 no autoriza los reinicios de esta batería. La conexión
# debe apuntar a una base desechable, nunca a la base que se desea conservar.
if [ "${TEST_DB_RESET:-}" != 'BORRAR horarios_ueb SOLO PRUEBAS' ]; then
  echo "Batería detenida: requiere TEST_DB_RESET='BORRAR horarios_ueb SOLO PRUEBAS' para una base desechable. No se ejecutó ningún cambio." >&2
  exit 2
fi
# El esquema de nuevas instalaciones ya incorpora el almuerzo 13:00-14:00.
# La migración solo cambia DEFAULT, sin modificar los periodos existentes.
MIGRACION_ALMUERZO=migraciones/V3__ajuste_horario_almuerzo.sql
if [ ! -f "$MIGRACION_ALMUERZO" ]; then
  echo "Falta $MIGRACION_ALMUERZO. No se ejecutó ningún cambio." >&2
  exit 2
fi
MYSQL=${MYSQL:-"mysql -uroot"}
M="$MYSQL --default-character-set=utf8mb4"
EV=${1:-evidencia}
mkdir -p "$EV"
FALLOS=0
VERSION=$($M -N -e "SELECT VERSION()")
echo "MySQL $VERSION · $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$EV/00_resumen.txt"

log()   { echo "$*" | tee -a "$EV/00_resumen.txt"; }
fallo() { log "FALLO: $*"; FALLOS=$((FALLOS + 1)); }
reset() { $M --init-command="SET @confirmar_reinicio_dev='BORRAR horarios_ueb'" < 00_reset_dev.sql > /dev/null || fallo "00_reset_dev.sql"; }
correr(){ # correr <archivo> <salida>
  $M --table < "$1" > "$2" 2>&1 || fallo "$1 terminó con error (ver $2)"; }
resumen_pruebas(){ # resumen_pruebas <salida> <etiqueta>
  local f; f=$(grep -A3 "total_pruebas" "$1" | grep -E "^\| [0-9]" | awk -F'|' '{gsub(/ /,"",$3); gsub(/ /,"",$4); print $3" pruebas, "$4" fallidas"}')
  log "  $2: $f"
  echo "$f" | grep -q ", 0 fallidas" || fallo "$2 tiene pruebas fallidas"; }

log "1. Flujo de desarrollo: 00 -> 01 -> 02 -> 03 -> 04 (x2)"
reset
correr 01_schema.sql  "$EV/01_schema.txt"
correr 02_seed.sql    "$EV/02_seed.txt"
correr 03_queries.sql "$EV/03_queries.txt"
correr 04_tests.sql   "$EV/04_tests.txt";   resumen_pruebas "$EV/04_tests.txt"   "04_tests (1.ª)"
correr 04_tests.sql   "$EV/04_tests_2.txt"; resumen_pruebas "$EV/04_tests_2.txt" "04_tests (2.ª, repetible)"
tools/huella_esquema.sh "$M" horarios_ueb > "$EV/huella_01_schema.txt"

log "2. 01_schema.sql no destruye datos: segunda ejecución sobre la base cargada"
if $M < 01_schema.sql > "$EV/01_schema_segunda_vez.txt" 2>&1; then
  fallo "01_schema.sql debía detenerse (tablas existentes)"
else
  grep -q "ERROR 1050" "$EV/01_schema_segunda_vez.txt" && log "  OK: se detuvo con ERROR 1050" || fallo "error inesperado"
fi
[ "$($M -N -e 'SELECT COUNT(*) FROM horarios_ueb.sesion')" = "32" ] && log "  OK: las 32 sesiones siguen intactas" || fallo "se perdieron datos"

log "3. Guardia de 00_reset_dev.sql sin confirmación"
if $M < 00_reset_dev.sql > "$EV/00_reset_sin_confirmar.txt" 2>&1; then fallo "el reinicio no se detuvo"; else log "  OK: se detuvo (ERROR 1242)"; fi
[ "$($M -N -e 'SELECT COUNT(*) FROM horarios_ueb.sesion')" = "32" ] && log "  OK: la base no se borró" || fallo "la base se borró sin confirmación"

log "4. Migraciones pendientes (en bases de desarrollo separadas)"
reset; correr 01_schema.sql /dev/null
$M horarios_ueb < migraciones/pendientes/P1_D1b_republicar_mismo_horario.sql || fallo "P1"
$M horarios_ueb < migraciones/pendientes/P3_D2_parametros_con_publicado.sql  || fallo "P3"
correr 02_seed.sql /dev/null
correr 05_tests_pendientes.sql "$EV/05_tests_pendientes.txt"; resumen_pruebas "$EV/05_tests_pendientes.txt" "05_tests_pendientes (P1+P3)"
reset; correr 01_schema.sql /dev/null
$M horarios_ueb < migraciones/pendientes/P2_D1c_copia_nueva.sql || fallo "P2"
correr 02_seed.sql /dev/null
correr 06_tests_pendiente_P2.sql "$EV/06_tests_pendiente_P2.txt"; resumen_pruebas "$EV/06_tests_pendiente_P2.txt" "06_tests_pendiente_P2 (P2)"

log "5. Las pruebas nuevas detectan los problemas del esquema anterior (V1 sin V2)"
reset; $M horarios_ueb < migraciones/V1__esquema_inicial.sql; correr 02_seed.sql /dev/null
$M --table < 04_tests.sql > "$EV/04_tests_sobre_V1.txt" 2>&1
grep -E "\| FALLA " "$EV/04_tests_sobre_V1.txt" | awk -F'|' '{gsub(/ /,"",$3); printf "%s ", $3}' > "$EV/04_tests_sobre_V1_fallidas.txt"
log "  Pruebas que fallan sobre V1 (esperado: > 0): $(wc -w < "$EV/04_tests_sobre_V1_fallidas.txt") -> $(cat "$EV/04_tests_sobre_V1_fallidas.txt")"
[ "$(wc -w < "$EV/04_tests_sobre_V1_fallidas.txt")" -gt 0 ] || fallo "las pruebas no distinguen V1 de V2"

log "6. Equivalencia: 01_schema.sql == V1 + V2 + V3 (cliente mysql)"
reset; $M horarios_ueb < migraciones/V1__esquema_inicial.sql && $M horarios_ueb < migraciones/V2__revision_tecnica.sql && $M horarios_ueb < "$MIGRACION_ALMUERZO"
tools/huella_esquema.sh "$M" horarios_ueb > "$EV/huella_V1_V2_V3_mysql.txt"
diff -q "$EV/huella_01_schema.txt" "$EV/huella_V1_V2_V3_mysql.txt" > /dev/null && log "  OK: definiciones idénticas" || fallo "01_schema.sql difiere de V1+V2+V3"

if [ -n "${FLYWAY:-}" ]; then
  FW="$FLYWAY -url=${JDBC_URL} -user=${DB_USER} -password=${DB_PASSWORD:-} -locations=filesystem:migraciones"
  log "7. Flyway: instalación limpia V1 -> V2 -> V3"
  reset; $FW migrate > "$EV/flyway_limpia.txt" 2>&1 || fallo "flyway migrate (limpia)"
  tools/huella_esquema.sh "$M" horarios_ueb > "$EV/huella_V1_V2_V3_flyway.txt"
  diff -q "$EV/huella_01_schema.txt" "$EV/huella_V1_V2_V3_flyway.txt" > /dev/null && log "  OK: idéntica a 01_schema.sql" || fallo "Flyway difiere de 01_schema.sql"
  correr 02_seed.sql /dev/null
  correr 04_tests.sql "$EV/04_tests_flyway.txt"; resumen_pruebas "$EV/04_tests_flyway.txt" "04_tests sobre esquema Flyway"

  log "8. Migración de una base anterior CON DATOS (V1 + seed + datos extra) a V3"
  reset; $M horarios_ueb < migraciones/V1__esquema_inicial.sql; correr 02_seed.sql /dev/null
  $M < tools/datos_extra_migracion.sql || fallo "datos extra"
  correr migraciones/preflight_V2.sql "$EV/preflight_antes.txt"
  grep -E "^\| P0[0-9]" "$EV/preflight_antes.txt" | awk -F'|' '$5+0 != 0 {exit 1}' && log "  OK: preflight sin bloqueos" || fallo "preflight con bloqueos"
  $M -N -e "CHECKSUM TABLE horarios_ueb.periodo_academico, horarios_ueb.docente, horarios_ueb.docente_especialidad, horarios_ueb.restriccion_horaria, horarios_ueb.curso, horarios_ueb.grupo, horarios_ueb.horario, horarios_ueb.sesion" > "$EV/checksum_antes.txt"
  $FW -baselineVersion=1 -baselineDescription="esquema inicial (aplicado sin Flyway)" baseline > "$EV/flyway_baseline.txt" 2>&1 || fallo "flyway baseline"
  $FW migrate > "$EV/flyway_migrate_datos.txt" 2>&1 || fallo "flyway migrate (con datos)"
  $M -N -e "CHECKSUM TABLE horarios_ueb.periodo_academico, horarios_ueb.docente, horarios_ueb.docente_especialidad, horarios_ueb.restriccion_horaria, horarios_ueb.curso, horarios_ueb.grupo, horarios_ueb.horario, horarios_ueb.sesion" > "$EV/checksum_despues.txt"
  diff -q "$EV/checksum_antes.txt" "$EV/checksum_despues.txt" > /dev/null && log "  OK: CHECKSUM de las 8 tablas idéntico antes y después" || fallo "los datos cambiaron en la migración"
  $FW info > "$EV/flyway_info_datos.txt" 2>&1
  tools/huella_esquema.sh "$M" horarios_ueb > "$EV/huella_migrada_con_datos.txt"
  diff -q "$EV/huella_01_schema.txt" "$EV/huella_migrada_con_datos.txt" > /dev/null && log "  OK: esquema migrado idéntico a 01_schema.sql" || fallo "esquema migrado difiere"
  $M -N -e "SELECT COUNT(*) FROM horarios_ueb.v_sesion_conflicto_parametros" | grep -qx 0 && log "  OK: sin sesiones en conflicto tras migrar" || fallo "conflictos tras migrar"

  log "8b. Camino de fallo: datos que bloquean V2 (enum no canónico, booleano 7)"
  reset; $M horarios_ueb < migraciones/V1__esquema_inicial.sql; correr 02_seed.sql /dev/null
  $M horarios_ueb -e "INSERT INTO docente (id, nombre, tipo_vinculacion) VALUES (8, 'Docente con dato mal cargado', 'tc'); UPDATE curso SET necesita_aula_especial = 7 WHERE id = 9;"
  correr migraciones/preflight_V2.sql "$EV/preflight_bloqueado.txt"
  grep -E "^\| P04 .*\| +1 \|$" "$EV/preflight_bloqueado.txt" > /dev/null && grep -E "^\| P05 .*\| +1 \|$" "$EV/preflight_bloqueado.txt" > /dev/null \
    && log "  OK: el preflight bloquea (P04 y P05)" || fallo "el preflight no detectó los datos"
  tools/huella_esquema.sh "$M" horarios_ueb > "$EV/huella_V1_antes_de_fallo.txt"
  $FW -baselineVersion=1 baseline > /dev/null 2>&1
  if $FW migrate > "$EV/flyway_migrate_bloqueado.txt" 2>&1; then fallo "V2 debía fallar con datos inválidos"; else log "  OK: V2 se detiene: $(grep -o '\[V2-PRE\][^.]*' "$EV/flyway_migrate_bloqueado.txt" | head -1)"; fi
  tools/huella_esquema.sh "$M" horarios_ueb > "$EV/huella_V1_despues_de_fallo.txt"
  grep -A1 "^### ROUTINE tmp_v2_precondiciones" "$EV/huella_V1_despues_de_fallo.txt" > /dev/null && log "  Nota: queda el procedimiento auxiliar tmp_v2_precondiciones (V2 lo elimina al reintentar)"
  awk '/^### ROUTINE tmp_v2_precondiciones/{salta=2} salta>0{salta--; next} {print}' "$EV/huella_V1_despues_de_fallo.txt" > "$EV/huella_V1_despues_de_fallo_sin_aux.txt"
  diff -q "$EV/huella_V1_antes_de_fallo.txt" "$EV/huella_V1_despues_de_fallo_sin_aux.txt" > /dev/null && log "  OK: fallo atómico: tablas, vistas, triggers y CHECK siguen siendo los de V1" || fallo "V2 dejó cambios parciales"
  [ "$($M -N -e "SELECT tipo_vinculacion FROM horarios_ueb.docente WHERE id = 8")" = "tc" ] && log "  OK: los datos no se modificaron" || fallo "datos alterados por la migración fallida"
  $FW repair > "$EV/flyway_repair.txt" 2>&1 || fallo "flyway repair"
  $M horarios_ueb -e "UPDATE docente SET tipo_vinculacion = UPPER(tipo_vinculacion); UPDATE curso SET necesita_aula_especial = (necesita_aula_especial <> 0);"
  $FW migrate > "$EV/flyway_migrate_tras_correccion.txt" 2>&1 && log "  OK: tras corregir y reparar, V2 se aplica" || fallo "V2 no se aplicó tras corregir"
  tools/huella_esquema.sh "$M" horarios_ueb > "$EV/huella_tras_correccion.txt"
  diff -q "$EV/huella_01_schema.txt" "$EV/huella_tras_correccion.txt" > /dev/null && log "  OK: esquema final idéntico a 01_schema.sql" || fallo "esquema tras corrección difiere"

  log "9. Migración de V1 + seed a V3 y batería completa"
  reset; $M horarios_ueb < migraciones/V1__esquema_inicial.sql; correr 02_seed.sql /dev/null
  $FW -baselineVersion=1 baseline > /dev/null 2>&1 && $FW migrate > /dev/null 2>&1 || fallo "flyway (seed)"
  correr 04_tests.sql "$EV/04_tests_migrada.txt"; resumen_pruebas "$EV/04_tests_migrada.txt" "04_tests sobre base migrada"

  log "10. Activación de una decisión aprobada: P1 y P3 como V4 y V5 con Flyway"
  TMPM=$(mktemp -d); cp migraciones/V1__esquema_inicial.sql migraciones/V2__revision_tecnica.sql "$TMPM/"
  cp "$MIGRACION_ALMUERZO" "$TMPM/"
  cp migraciones/pendientes/P1_D1b_republicar_mismo_horario.sql "$TMPM/V4__republicar_mismo_horario.sql"
  cp migraciones/pendientes/P3_D2_parametros_con_publicado.sql  "$TMPM/V5__parametros_con_publicado.sql"
  reset; $M horarios_ueb < migraciones/V1__esquema_inicial.sql; correr 02_seed.sql /dev/null
  $FLYWAY -url=${JDBC_URL} -user=${DB_USER} -password=${DB_PASSWORD:-} -locations=filesystem:$TMPM -baselineVersion=1 baseline > /dev/null 2>&1
  $FLYWAY -url=${JDBC_URL} -user=${DB_USER} -password=${DB_PASSWORD:-} -locations=filesystem:$TMPM migrate > "$EV/flyway_V4_V5.txt" 2>&1 || fallo "flyway V4/V5"
  correr 05_tests_pendientes.sql "$EV/05_tests_flyway_V4_V5.txt"; resumen_pruebas "$EV/05_tests_flyway_V4_V5.txt" "05_tests tras V4+V5"
  rm -rf "$TMPM"
fi

log "11. Estado final: base de desarrollo limpia con seed"
reset; correr 01_schema.sql /dev/null; correr 02_seed.sql /dev/null
log "RESULTADO: $([ $FALLOS -eq 0 ] && echo 'TODO CORRECTO' || echo "$FALLOS FALLOS")"
exit $FALLOS
