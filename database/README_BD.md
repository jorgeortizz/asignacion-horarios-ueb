# README_BD — Base de datos del Módulo de Asignación de Horarios Docente-Curso

Universidad El Bosque · Programa de Ingeniería de Sistemas · Proyecto Núcleo 1 · Fase 2 (base de datos) · **esquema V2**

## 1. Propósito

Persistir el modelo de datos del módulo (Figura 4 del informe técnico): docentes y sus restricciones, cursos, grupos, periodos académicos con sus parámetros, horarios (BORRADOR o PUBLICADO) y sus sesiones. La base de datos garantiza la integridad referencial, los dominios, los rangos simples, la protección de los horarios publicados y la conservación del historial por periodo.

Las reglas de asignación **no** son responsabilidad de la base de datos y las implementa el backend Spring Boot: choques de docente, disponibilidad, días consecutivos, cuadrícula de bloques, cupos, generación, validación antes de publicar y la decisión de publicar. Las pruebas SQL no sustituyen las pruebas Java (BK01–BK13).

| Documento | Contenido |
|---|---|
| `INFORME_REVISION_TECNICA.md` | Problemas, severidad, decisiones pendientes D1–D4 y procedimiento de migración V1 → V2 |
| `CONTRATO_JPA.md` | Contrato exacto para el backend, generado desde el esquema |
| `ANALISIS_MODELO_BD.md` | Análisis del modelo, ER y trazabilidad (primera entrega, actualizado) |

## 2. Motor y versión

| Elemento | Valor |
|---|---|
| Motor | **MySQL Community Server 9.7 LTS**. Use el último parche de la línea; al 21-oct-2026 es **9.7.4** (publicado el 20-oct-2026). Historial: 9.7.0 (21-abr), 9.7.1 (16-jun), 9.7.2 (28-jul), 9.7.3 (18-ago), 9.7.4 (20-oct). |
| Versiones con las que se ejecutó todo | **9.7.2** y **9.7.4**, compilados desde el código fuente oficial (`mysql/mysql-server`). Resultados en `evidencia/`. |
| No recomendado | La línea *Innovation* 26.x (26.7, 26.10): no es LTS. |
| Tablas / codificación | InnoDB · `utf8mb4` / `utf8mb4_0900_ai_ci`; las columnas enum usan `utf8mb4_0900_bin` |
| Mínimo técnico | MySQL 8.0.16 o superior (CHECK, CTE recursivas, índices funcionales). No se garantiza en MariaDB. |
| Migraciones | Flyway (probado con 13.10.3 CLI). Flyway 13.10.3 aún no declara verificado MySQL 9.7 (sí hasta 9.4) y muestra una advertencia; las migraciones se aplicaron sin errores. |

## 3. Archivos

```
00_reset_dev.sql              SOLO desarrollo: borra y recrea horarios_ueb (exige confirmación)
01_schema.sql                 Esquema V2 completo, NO destructivo (= V1 + V2)
02_seed.sql                   Datos ficticios de prueba
03_queries.sql                16 consultas de referencia con resultado esperado
04_tests.sql                  165 pruebas del esquema V2
05_tests_pendientes.sql       22 pruebas de las migraciones pendientes P1 + P3
06_tests_pendiente_P2.sql     10 pruebas de la migración pendiente P2
migraciones/
  V1__esquema_inicial.sql     Esquema de la primera entrega (no se edita)
  V2__revision_tecnica.sql    Correcciones de la segunda revisión
  preflight_V2.sql            Verificación previa a V2 (solo lectura)
  pendientes/                 Reglas que esperan decisión del Comité (NO aplicar)
    P1_D1b_republicar_mismo_horario.sql
    P2_D1c_copia_nueva.sql
    P3_D2_parametros_con_publicado.sql
tools/
  ejecutar_todo.sh            Batería reproducible completa (solo desarrollo)
  huella_esquema.sh           Huella de definiciones para comparar esquemas
  generar_contrato.py         Genera CONTRATO_JPA.md desde information_schema
  datos_extra_migracion.sql   Datos extra para la prueba de migración
evidencia/9.7.2/, evidencia/9.7.4/   Salidas de la última ejecución
modelo_er.*                   Diagrama entidad-relación (sin cambios estructurales en V2)
```

## 4. Entorno de desarrollo

### Primera instalación o reinicio completo

```bash
# 1) Reinicio (borra horarios_ueb). La confirmación es obligatoria:
mysql -u root -p --init-command="SET @confirmar_reinicio_dev = 'BORRAR horarios_ueb'" < 00_reset_dev.sql
# 2) Esquema, datos, consultas y pruebas
mysql -u root -p < 01_schema.sql
mysql -u root -p < 02_seed.sql
mysql -u root -p --table < 03_queries.sql
mysql -u root -p --table < 04_tests.sql      # resumen final: fallidas = 0
```

En una base vacía (instalación nueva) no hace falta el paso 1: `01_schema.sql` usa `CREATE DATABASE IF NOT EXISTS`.

**MySQL Workbench:** en la misma pestaña, ejecute a mano `SET @confirmar_reinicio_dev = 'BORRAR horarios_ueb';` y luego abra y ejecute `00_reset_dev.sql` completo. Después ejecute `01`, `02`, `03` y `04` con *Execute all*, dejando activada la opción *Stop script execution on errors*.

**Garantías comprobadas:**
- Sin la confirmación exacta, `00_reset_dev.sql` se detiene con `ERROR 1242` antes del `DROP`.
- `01_schema.sql` sobre una base con tablas se detiene con `ERROR 1050` sin tocar datos.
- `04_tests.sql` revierte todos sus cambios y se puede repetir.

### Batería completa (reproducible)

```bash
MYSQL="mysql -uroot -p<clave> -h127.0.0.1" \
JDBC_URL="jdbc:mysql://127.0.0.1:3306/horarios_ueb" DB_USER=root DB_PASSWORD=<clave> \
FLYWAY=/ruta/a/flyway  tools/ejecutar_todo.sh evidencia/mi_ejecucion
```

Borra y recrea `horarios_ueb` varias veces; úselo solo en desarrollo. Termina con `RESULTADO: TODO CORRECTO` y código de salida 0 si todo pasa.

### Probar una decisión pendiente

```bash
# P1 + P3 (recomendadas)
mysql … --init-command="SET @confirmar_reinicio_dev='BORRAR horarios_ueb'" < 00_reset_dev.sql
mysql … < 01_schema.sql
mysql … horarios_ueb < migraciones/pendientes/P1_D1b_republicar_mismo_horario.sql
mysql … horarios_ueb < migraciones/pendientes/P3_D2_parametros_con_publicado.sql
mysql … < 02_seed.sql
mysql … --table < 05_tests_pendientes.sql
```

## 5. Tablas, vistas y errores

| Tabla | Entidad | Contenido |
|---|---|---|
| `periodo_academico` | PeriodoAcademico | Semestre y parámetros: franjas, almuerzo, bloque, máximo de sesiones, cupo base, tolerancia y mínimo |
| `docente` | Docente | Nombre y `tipo_vinculacion` |
| `docente_especialidad` | *(auxiliar)* | Especialidades (colección de valores) |
| `restriccion_horaria` | RestriccionHoraria | Día, horas, `tipo` y `sentido` |
| `curso` | Curso | Código, nombre, sesiones semanales, duración y aula especial |
| `grupo` | Grupo | Periodo, curso, docente, código, cupos e inscritos |
| `horario` | Horario | Periodo, estado, fechas y versión |
| `sesion` | Sesion | Horario, grupo y bloque (`dia`, `hora_inicio`, `hora_fin`) |

Vistas de solo lectura:
- `v_bloque_valido`: cuadrícula derivada de los parámetros.
- `v_grupo_cupo`: límite operativo y candidatos a cierre.
- `v_sesion_detalle`: sesión con curso, grupo, docente y periodo.
- `v_horario_vigente` *(V2)*: último PUBLICADO de cada periodo; es lo que deben consultar estudiantes y docentes.
- `v_sesion_conflicto_parametros` *(V2)*: sesiones que no cumplen los parámetros actuales de su periodo.

Errores propios (SQLSTATE `45000`, errno 1644). El backend los traduce leyendo el prefijo:

| Código | Causa | Tipo |
|---|---|---|
| `[BD-01]` | Sesión con grupo y horario de periodos distintos | Integridad |
| `[BD-02]` | Duración de la sesión distinta a la del curso | Red de seguridad |
| `[BD-03]` | Sesión fuera de la franja del periodo | Red de seguridad |
| `[BD-04]` | Sesión que se solapa con el almuerzo | Red de seguridad |
| `[BD-05]` / `[BD-06]` | Cambiar el periodo de un grupo u horario con sesiones | Integridad |
| `[BD-07]` | Eliminar un horario publicado | Historial |
| `[BD-08]` *(V2)* | Insertar, mover o eliminar sesiones de un horario PUBLICADO | Historial |
| `[BD-09]` *(V2)* | Cambiar la duración de un curso con sesiones | Historial |
| `[BD-10]` *(V2)* | Cambiar el curso de un grupo con sesiones | Historial |
| `[BD-11]` *(V2)* | Crear un horario directamente como PUBLICADO | Publicación |
| `[BD-12]` *(V2)* | Publicar un horario sin sesiones | Publicación |
| `[BD-14]` | *(pendiente P1)* Cambiar el docente de un grupo con sesiones publicadas | Decisión D3 |
| `[BD-15]` | *(pendiente P2)* Despublicar un horario | Decisión D1-c |
| `[BD-16]` | *(pendiente P3)* Cambiar parámetros de forma con un horario publicado | Decisión D2 |

## 6. Conexión desde Spring Boot y migraciones

Dependencias Maven:

```xml
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-data-jpa</artifactId>
</dependency>
<dependency>
  <groupId>com.mysql</groupId>
  <artifactId>mysql-connector-j</artifactId>
  <scope>runtime</scope>
</dependency>
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-flyway</artifactId> <!-- Spring Boot 4.x; en 3.x use org.flywaydb:flyway-core -->
</dependency>
<dependency>
  <groupId>org.flywaydb</groupId>
  <artifactId>flyway-mysql</artifactId>
</dependency>
```

`src/main/resources/application.properties`. Los secretos se toman de variables de entorno:

```properties
spring.datasource.url=jdbc:mysql://${DB_HOST:localhost}:${DB_PORT:3306}/${DB_NAME:horarios_ueb}?serverTimezone=America/Bogota&characterEncoding=UTF-8&sslMode=${DB_SSL_MODE:REQUIRED}
spring.datasource.username=${DB_USER}
spring.datasource.password=${DB_PASSWORD}

# El esquema lo gestiona Flyway; Hibernate NUNCA lo crea ni lo altera.
spring.jpa.hibernate.ddl-auto=none
spring.jpa.open-in-view=false
spring.jpa.properties.hibernate.jdbc.time_zone=America/Bogota
spring.jpa.hibernate.naming.physical-strategy=org.hibernate.boot.model.naming.PhysicalNamingStrategyStandardImpl

spring.flyway.enabled=true
spring.flyway.locations=classpath:db/migration
spring.flyway.clean-disabled=true
spring.flyway.validate-on-migrate=true
# Solo para una base creada antes con el 01_schema.sql antiguo (ver INFORME, sección 4):
spring.flyway.baseline-on-migrate=${FLYWAY_BASELINE:false}
spring.flyway.baseline-version=1
```

En desarrollo local sin TLS puede usar `DB_SSL_MODE=DISABLED` y agregar `&allowPublicKeyRetrieval=true` a la URL. Nunca lo haga en un servidor compartido.

**Reglas de migración:**
1. En `src/main/resources/db/migration/` van **solo** los `V*.sql`: hoy `V1__esquema_inicial.sql` y `V2__revision_tecnica.sql`.
2. Una migración aplicada **no se edita**; cada cambio es un `V{n+1}__descripcion.sql` nuevo, revisado en Git.
3. Al aprobarse una decisión, la migración pendiente se copia como el siguiente `V` (por ejemplo, `V3__republicar_mismo_horario.sql`).
4. `01_schema.sql` se mantiene igual a la suma de las migraciones: regénérelo al crear una `V` nueva y verifique la igualdad con `tools/huella_esquema.sh`. También regenere `CONTRATO_JPA.md` y la huella K01.
5. `00_reset_dev.sql`, `02_seed.sql` y los archivos de prueba nunca van a `db/migration`.

**Paso de V1 a V2 en una base existente:** siga el procedimiento del `INFORME_REVISION_TECNICA.md`, sección 4 (respaldo → preflight → baseline → migrate → verificación).

## 7. Recomendaciones de seguridad

1. **Dos usuarios.** Un usuario de **migración** (DDL) solo para Flyway y un usuario de **aplicación** sin DDL:
   ```sql
   CREATE USER 'horarios_app'@'<host-app>' IDENTIFIED BY '<contraseña-fuerte>';
   GRANT SELECT, INSERT, UPDATE, DELETE ON horarios_ueb.* TO 'horarios_app'@'<host-app>';
   CREATE USER 'horarios_migra'@'<host-app>' IDENTIFIED BY '<otra-contraseña>';
   GRANT ALL PRIVILEGES ON horarios_ueb.* TO 'horarios_migra'@'<host-app>';
   ```
   Si Flyway corre dentro de la aplicación, configure `spring.flyway.user` y `spring.flyway.password` con el usuario de migración.
2. Los secretos van solo en variables de entorno o en un gestor de secretos, nunca en Git.
3. El puerto 3306 no se expone a Internet; use TLS (`sslMode=REQUIRED`) fuera del entorno local.
4. Use siempre consultas parametrizadas.
5. `spring.flyway.clean-disabled=true` en todos los perfiles; `00_reset_dev.sql` y `tools/ejecutar_todo.sh` nunca se ejecutan en servidores compartidos.
6. Haga respaldos periódicos con `--routines --triggers`.
7. El usuario de aplicación no puede crear procedimientos, así que los archivos `04`–`06` (que los crean) no se pueden ejecutar con él: corren solo en desarrollo.

## 8. Respaldo y restauración

```bash
mysqldump -u root -p --routines --triggers --single-transaction horarios_ueb > respaldo_horarios.sql
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS horarios_ueb CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci"
mysql -u root -p horarios_ueb < respaldo_horarios.sql
```

`--routines --triggers` es obligatorio: sin ellos se pierden las reglas BD-01 a BD-12. El respaldo incluye `flyway_schema_history`, de modo que la base restaurada conserva su versión de migración.

## 9. Decisiones pendientes de validación

Detalle en `INFORME_REVISION_TECNICA.md`, sección 2.

- **D1** · Flujo de modificación de un horario publicado: despublicar y republicar (recomendada, P1) o copia nueva (P2).
- **D2** · Parámetros congelados con un horario publicado (recomendada, P3).
- **D3** · Cambio de docente en un grupo con sesiones publicadas (incluido en P1).
- **D4** · Bloqueo de periodos terminados en Spring Boot (recomendación sin SQL).
- De la revisión anterior: A1 `sentido`, **A2 `grupo.periodo_id` (requiere confirmación)**, A3–A8 y la sede (vacío 10).
