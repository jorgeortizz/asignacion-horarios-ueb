#!/usr/bin/env bash
# Imprime la definición normalizada de todos los objetos de un esquema MySQL
# (tablas, vistas, rutinas y triggers) para comparar dos instalaciones.
# Uso: huella_esquema.sh "<comando mysql con credenciales>" <esquema>
set -euo pipefail
M="$1"; DB="$2"
q() { $M -N -B -e "$1"; }
for t in $(q "SELECT table_name FROM information_schema.tables WHERE table_schema='$DB' AND table_type='BASE TABLE' AND table_name<>'flyway_schema_history' ORDER BY table_name"); do
  echo "### TABLE $t"; q "SHOW CREATE TABLE \`$DB\`.\`$t\`" | cut -f2- | sed -E 's/ AUTO_INCREMENT=[0-9]+//' | sed 's/\\n/\n/g' | sort
done
for v in $(q "SELECT table_name FROM information_schema.views WHERE table_schema='$DB' ORDER BY table_name"); do
  echo "### VIEW $v"; q "SELECT view_definition FROM information_schema.views WHERE table_schema='$DB' AND table_name='$v'"
done
for r in $(q "SELECT routine_name FROM information_schema.routines WHERE routine_schema='$DB' ORDER BY routine_name"); do
  echo "### ROUTINE $r"; q "SELECT routine_definition FROM information_schema.routines WHERE routine_schema='$DB' AND routine_name='$r'"
done
for g in $(q "SELECT trigger_name FROM information_schema.triggers WHERE trigger_schema='$DB' ORDER BY trigger_name"); do
  echo "### TRIGGER $g"; q "SELECT CONCAT(action_timing,' ',event_manipulation,' ON ',event_object_table) FROM information_schema.triggers WHERE trigger_schema='$DB' AND trigger_name='$g'"
  q "SELECT action_statement FROM information_schema.triggers WHERE trigger_schema='$DB' AND trigger_name='$g'"
done
