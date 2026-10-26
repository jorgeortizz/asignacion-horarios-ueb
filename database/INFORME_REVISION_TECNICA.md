# Segunda revisión técnica de la base de datos

**Módulo de Asignación de Horarios Docente-Curso** · Universidad El Bosque · Programa de Ingeniería de Sistemas · Fase 2

Revisión del esquema entregado el 21-oct-2026 (versión V1), antes de integrarlo con el backend Spring Boot. Se conservan las siete entidades principales, la tabla auxiliar `docente_especialidad` y todas las relaciones. No se agregan tablas ni columnas.

**Resultado:** de 15 problemas, 12 quedan corregidos (V2, `01_schema.sql`, pruebas y documentación) y 1 queda corregido en parte (P04). Otro depende de una decisión del Comité (P08) y el último se documenta como mejora futura (P15). Las 3 reglas que dependen de las decisiones D1, D2 y D3 están escritas y probadas en `migraciones/pendientes/`, sin aplicar.

---

## 1. Problemas identificados

Severidad: **Alta** = puede perder o corromper datos, o romper la integración · **Media** = deja datos incoherentes o engañosos sin aviso · **Baja** = calidad o robustez.

| # | Sev. | Problema | Archivo / objeto (V1) | Demostración | Estado |
|---|---|---|---|---|---|
| P01 | Alta | Las sesiones de un horario **PUBLICADO** se podían insertar, mover y borrar. Solo se protegía el `DELETE` del horario: borrando antes sus sesiones se vaciaba el historial. | `01_schema.sql`: `trg_sesion_bi`, `trg_sesion_bu`; faltaba un trigger `BEFORE DELETE` en `sesion` | `04_tests` H01–H05 fallan sobre V1 | **Corregido en V2** (BD-08) |
| P02 | Alta | `01_schema.sql` empezaba con `DROP DATABASE`: ejecutarlo para "actualizar" borraba todos los datos. No había mecanismo de migración. | `01_schema.sql`, línea 25 | — | **Corregido**: `01_schema.sql` no destructivo, `00_reset_dev.sql` con guardia, migraciones Flyway V1/V2 |
| P03 | Alta | Columnas enum con collation `utf8mb4_0900_ai_ci`: el CHECK aceptaba `'tc'`, `'Tc'` o `'tres_cuartos'`. Hibernate (`@Enumerated(STRING)`) **no puede leer** esas filas (`No enum constant`). | `docente.tipo_vinculacion`, `restriccion_horaria.tipo`/`sentido`, `horario.estado` | Se insertaron `'tc'`, `'Tc'` y `'tres_cuartos'` sin error; K06–K08 fallan sobre V1 | **Corregido en V2** (collation `utf8mb4_0900_bin`) |
| P04 | Alta | Cambiar almuerzo, franjas, bloque o máximo de sesiones de un periodo **con horarios existentes** no se validaba ni se reportaba. Un horario PUBLICADO podía quedar en contradicción con las reglas de su propio periodo sin ningún indicio (I24–I25). | `periodo_academico` | I01–I25 | **Parcial en V2**: vista `v_sesion_conflicto_parametros` y CHECK franja ≥ bloque. **El bloqueo queda pendiente de D2** (P3) |
| P05 | Media | Un horario podía **crearse directamente como PUBLICADO** (sin validación ni acción del Comité) o publicarse sin sesiones (contradice 1..* de la Fig. 4). | `horario` | H07, H09 fallan sobre V1 | **Corregido en V2** (BD-11, BD-12) |
| P06 | Media | Cambiar la **duración de un curso** con sesiones dejaba sesiones con `hora_fin` incoherente; luego cualquier ajuste de esas sesiones fallaba con BD-02. | `curso.duracion_sesion_min` | J01 falla sobre V1 | **Corregido en V2** (BD-09) |
| P07 | Media | Cambiar el **curso de un grupo** con sesiones reescribía qué se dictó en el historial y podía romper la duración. | `grupo.curso_id` | J04 falla sobre V1 | **Corregido en V2** (BD-10) |
| P08 | Media | Cambiar el **docente** de un grupo con sesiones publicadas reescribe el historial (J07–J08) y puede crear un choque dentro de un horario publicado. | `grupo.docente_id` | J07, J08 (LIMITE) | **Pendiente de D3** (incluido en P1) |
| P09 | Media | El esquema permite varios PUBLICADOS por periodo, pero nada indicaba cuál es el **vigente** que ven estudiantes y docentes. | `horario` | H21–H22 | **Corregido en V2** (`v_horario_vigente`); unicidad pendiente de D1 (P1) |
| P10 | Media | Contrato JPA transcrito a mano y sin verificación. Sugería `Integer` para TINYINT/SMALLINT (`ddl-auto=validate` puede rechazarlos) y no detectaba cambios de esquema. | `ANALISIS_MODELO_BD.md`, sección 11 | — | **Corregido**: `CONTRATO_JPA.md` generado desde `information_schema` y pruebas K01–K12 |
| P11 | Media | Algunas pruebas se presentaban como "T26-x" (prueba de aceptación) cuando solo consultaban datos; A02 fallaría en cuanto Flyway cree `flyway_schema_history`. | `04_tests.sql` (G15–G18, A02) | — | **Corregido**: categorías SQL/RED/DATOS/INSUMO/LIMITE y A02 ajustada |
| P12 | Baja | `necesita_aula_especial` aceptaba cualquier TINYINT (se insertó 7). | `curso` | K10 falla sobre V1 | **Corregido en V2** (CHECK 0/1) |
| P13 | Baja | Una franja L-V más corta que un bloque dejaba el periodo sin bloques válidos sin ningún error. | `periodo_academico` | I18 falla sobre V1 | **Corregido en V2** (CHECK) |
| P14 | Baja | Las referencias de versión decían 9.7.2; la vigente de la línea LTS es **9.7.4** (20-oct-2026). | README, análisis | — | **Actualizado** |
| P15 | Baja | Cambiar el nombre o la frecuencia de un curso, o agregar restricciones horarias, altera cómo se ve o se evalúa el historial (J10–J15). | `curso`, `restriccion_horaria` | J10–J15 (LIMITE / INSUMO) | **Documentado** como mejora futura; reglas para Java en BK13 |

**Hallazgos de la propia revisión, detectados por las pruebas antes de entregar:**

- **MySQL no vuelve a evaluar los CHECK al cambiar la collation de una columna.** En la prueba de migración con datos inválidos, el `ALTER … COLLATE utf8mb4_0900_bin` se aplicó aunque existía `'tc'`, y V2 falló más adelante, a medias. Sobre una base que solo tuviera ese problema, V2 habría terminado "con éxito" dejando filas que Hibernate no puede leer. **Corrección:** V2 empieza con una verificación de precondiciones (`[V2-PRE]`) que detiene la migración **antes de cualquier cambio**. Comprobado: tras el fallo, tablas, vistas, triggers y CHECK siguen siendo los de V1 (paso 8b de `tools/ejecutar_todo.sh`).
- El primer borrador del mensaje BD-08 superaba los 128 caracteres de `MESSAGE_TEXT`, y MySQL devolvía `ERROR 1648` en lugar del error de negocio. Las pruebas H01–H05 lo detectaron antes de la entrega. Se acortaron los mensajes y ahora todos los `[BD-xx]` miden ≤ 109 caracteres (comprobado con un script sobre todos los archivos).

**Demostración global:** `04_tests.sql` ejecutado sobre el esquema anterior (V1 sin V2) falla en **34 pruebas** (lista en `evidencia/<versión>/04_tests_sobre_V1_fallidas.txt`); sobre V2 pasan las 165.

---

## 2. Decisiones que requieren confirmación del Comité Táctico

Ninguna de estas reglas se activó. Cada una está redactada y probada como migración pendiente, lista para convertirse en `V3__…` si se aprueba.

### D1. ¿Cómo se modifica un horario ya publicado? (vacío 5: "modifica y republica")

| Opción | Cómo funciona | Conserva | Pierde | Migración |
|---|---|---|---|---|
| **D1-b (recomendada)** | Se despublica **el mismo horario** (PUBLICADO → BORRADOR), se ajusta, se revalida y se republica. Un solo PUBLICADO por periodo. | El horario vigente y su fecha de publicación; un único horario oficial, sin ambigüedad. | La versión publicada anterior (no hay bitácora, que ya es mejora futura). Mientras está en BORRADOR, no hay horario publicado visible. | `P1_D1b_republicar_mismo_horario.sql` |
| D1-c | El publicado nunca vuelve a BORRADOR: se copia a un borrador nuevo, se ajusta y se publica. El vigente es el más reciente (`v_horario_vigente`). | Los días y horas de cada versión publicada. | Nada de las sesiones, pero los datos del **grupo** (docente, inscritos) se comparten entre versiones: la versión anterior muestra el docente nuevo (P2-10). El historial es parcial y puede inducir a error. | `P2_D1c_copia_nueva.sql` |

**Recomendación: D1-b.** Es el flujo más simple para el Comité, mantiene un solo horario oficial por periodo y no da una falsa impresión de historial completo. Conservar versiones fieles exige versionar grupos o una bitácora, que el proyecto ya declara mejora futura.
**Lo que V2 ya garantiza con cualquiera de las dos opciones:** las sesiones de un PUBLICADO no se tocan (BD-08), no se publica un horario vacío (BD-12), no se crea uno como PUBLICADO (BD-11) y no se borra uno publicado (BD-07). Hoy V2 todavía permite despublicar y tener varios publicados; eso es lo que decide D1.

### D2. ¿Se pueden cambiar los parámetros de un periodo que ya tiene horario PUBLICADO? (vacío 4)

- **D2-a (recomendada):** no. Franjas, almuerzo, bloque y máximo de sesiones quedan fijos mientras exista un PUBLICADO; para cambiarlos se despublica (D1-b) o se trabaja en el siguiente periodo. Los parámetros de **cupo no se bloquean**, porque la inscripción ocurre después de publicar. → `P3_D2_parametros_con_publicado.sql` (BD-16).
- D2-b (vigente hoy): se permite; las sesiones afectadas aparecen en `v_sesion_conflicto_parametros` y el Comité las corrige.

Con horarios solo en BORRADOR, las dos opciones se comportan igual: el cambio se permite y se marca. Así se cumple el vacío 4 sin dejar un horario publicado en contradicción con su periodo.

### D3. ¿Se puede cambiar el docente de un grupo que tiene sesiones publicadas?

Depende de D1. Con D1-b, la recomendación es bloquearlo hasta despublicar (BD-14, incluido en P1). Así el cambio pasa por la revalidación y la republicación. Con D1-c, bloquearlo impediría cualquier cambio de docente, porque la versión anterior sigue PUBLICADA. Por eso no se incluye en P2 y la limitación queda documentada.

### D4. Periodos terminados (recomendación, sin SQL)

Se recomienda que Spring Boot **no permita editar** horarios, grupos ni parámetros de periodos con `fecha_fin` anterior a hoy, salvo que una persona del Comité lo autorice de forma explícita. No se implementa como trigger por tres razones: dependería de la fecha del servidor, las pruebas no serían reproducibles y bloquearía correcciones legítimas.

### Decisiones pendientes de la revisión anterior (sin cambios)

Siguen abiertas A1 (`restriccion_horaria.sentido`), **A2 (`grupo.periodo_id`, propuesta estructural que aún necesita confirmación del equipo)**, A3 (cupo propio del grupo), A4 (periodo vigente para el máximo de sesiones), A5 (consecutivos por grupo), A6 (docente pendiente), A7 (restricciones por periodo) y la sede (vacío 10). V2 no cambia ninguna de ellas.

---

## 3. Estrategia por tema: qué garantiza SQL y qué valida Spring Boot

| Tema | MySQL garantiza (V2) | Spring Boot debe validar | Pendiente |
|---|---|---|---|
| **1. Horarios publicados** | BD-08 (sesiones inmutables), BD-11, BD-12, BD-07; `v_horario_vigente` | Que publicar y despublicar sean acciones explícitas del Comité; **validación completa** del horario antes de publicar (la BD acepta publicar con choques: P3-08); revalidar antes de republicar (BK07, BK11) | D1, D3 |
| **2. Migraciones** | Flyway V1 (frozen) + V2; `01_schema.sql` no destructivo y equivalente a V1+V2 (verificado); `00_reset_dev.sql` con guardia | `ddl-auto=none`, `spring.flyway.clean-disabled=true` y `baseline-on-migrate` solo para la base anterior | — |
| **3. Parámetros con horarios** | CHECK franja ≥ bloque; cada sesión nueva o movida se valida con los parámetros vigentes (BD-02 a BD-04); `v_sesion_conflicto_parametros` lista lo que quedó en conflicto | Mostrar el impacto **antes** de guardar (Q15) y pedir confirmación; nunca mover sesiones automáticamente; rechazar cursos que superen el nuevo máximo (I21); no propagar el cupo base a los grupos existentes salvo que el Comité lo pida (I23) | D2 |
| **4. Historial (docente, curso, restricciones)** | BD-09 (duración de curso con sesiones), BD-10 (curso de un grupo con sesiones) | Revalidar los BORRADORES del periodo tras cambiar docente o restricciones; no marcar como error los publicados de periodos cerrados (BK13) | D3; mejora futura: versionar curso y grupo por periodo, restricciones por periodo (A7), bitácora |
| **5. Pruebas negativas** | Secciones H, I, J y K de `04_tests.sql`; `05` y `06` para las migraciones pendientes | Pruebas BK01–BK13 en JUnit | — |
| **6. Alcance de las pruebas SQL** | Categorías SQL / RED / DATOS / INSUMO / LIMITE en cada resultado | Las reglas de Tabla 19 y Tabla 26 se aceptan solo con pruebas Java | — |
| **7. Versión** | Probado en MySQL **9.7.2** y **9.7.4** LTS | — | — |
| **8. Contrato JPA** | Huella SHA-256 de columnas (K01), nombres de FK (K02), objetos (K03), valores de enum exactos (K04–K12) | Entidades según `CONTRATO_JPA.md` | — |

### Cambios indispensables para el MVP frente a mejoras futuras (tema 4)

| Cambio sobre datos ya programados | MVP (ahora) | Mejora futura |
|---|---|---|
| Duración de un curso | Bloqueada si tiene sesiones (BD-09) | Versionar el curso por periodo |
| Curso de un grupo | Bloqueado si tiene sesiones (BD-10) | — |
| Docente de un grupo | Permitido; Java revalida. Bloqueo con publicado si se aprueba D3 | Docente por versión de horario o bitácora |
| Nombre o frecuencia de un curso | Permitidos (corrección); Java no reevalúa como error los publicados de periodos cerrados | Versionar el curso por periodo |
| Restricciones horarias | Permitidas; Java revalida los borradores e informa sobre los publicados (J15) | `restriccion_horaria.periodo_id` (A7) |
| Inscritos | Permitidos siempre (la matrícula es posterior a publicar) | — |

---

## 4. Procedimiento de migración del esquema anterior (V1) al corregido (V2)

Probado con Flyway 13.10.3 sobre una base V1 con los datos de prueba más datos adicionales (`tools/datos_extra_migracion.sql`). El CHECKSUM de las 8 tablas fue idéntico antes y después, y el esquema resultante coincide exactamente con `01_schema.sql`.

1. **Ventana de mantenimiento.** Detenga la aplicación. MySQL no ejecuta DDL dentro de transacciones, y V2 reemplaza triggers (durante un instante no existen).
2. **Respaldo.**
   `mysqldump -u <admin> -p --routines --triggers --single-transaction horarios_ueb > respaldo_pre_V2.sql`
3. **Verificación previa (solo lectura).** Ejecute `migraciones/preflight_V2.sql`. Todas las filas `P0x` deben tener `bloquea = 0`. Guarde la salida del `CHECKSUM TABLE`.
   - Si `P04 > 0` (valores enum no canónicos): corríjalos y documente el cambio, por ejemplo `UPDATE docente SET tipo_vinculacion = UPPER(tipo_vinculacion);`. Es el único caso en que hay que modificar datos.
   - Si `P05 > 0`: `UPDATE curso SET necesita_aula_especial = (necesita_aula_especial <> 0);`
   - Si `P01 > 0`: ajuste la franja o el bloque del periodo indicado.
4. **Registrar V1 como línea base.** La base se creó con el `01_schema.sql` antiguo, sin Flyway. Marque V1 como aplicada sin ejecutarla:
   - CLI: `flyway -url=jdbc:mysql://<host>:3306/horarios_ueb -user=<admin> -password=<clave> -locations=filesystem:migraciones -baselineVersion=1 baseline`
   - Spring Boot: `spring.flyway.baseline-on-migrate=true` y `spring.flyway.baseline-version=1`, solo en este primer arranque.
5. **Aplicar V2:** `flyway … migrate` o arrancar la aplicación con Flyway habilitado.
6. **Verificar.**
   - `flyway info`: V1 = Baseline, V2 = Success.
   - El `CHECKSUM TABLE` debe ser idéntico al del paso 3 (salvo las correcciones de P04 y P05, si las hubo).
   - `SELECT * FROM v_sesion_conflicto_parametros;`: revise las sesiones listadas, si hay.
   - Opcional: `tools/huella_esquema.sh` debe coincidir con una instalación limpia de `01_schema.sql`.
7. **Arrancar la aplicación** con `spring.jpa.hibernate.ddl-auto=none` y `spring.flyway.clean-disabled=true`.

**Si V2 se detiene con `[V2-PRE]`:** no cambió nada salvo el procedimiento auxiliar `tmp_v2_precondiciones`, que V2 elimina al reintentar. Corrija los datos que indica el mensaje (pasos 3 y 3a), ejecute `flyway repair` para limpiar el registro fallido y vuelva a ejecutar `migrate`. Este camino está probado en el paso 8b.
**Si V2 falla por otra causa** (después de las precondiciones): restaure `respaldo_pre_V2.sql`, ejecute `flyway repair`, corrija la causa y repita desde el paso 3. Recuerde que MySQL no revierte el DDL.

**Instalación nueva** (sin base anterior): solo `flyway migrate`, que aplica V1 y V2. Equivale a `01_schema.sql`.

**Activar una decisión aprobada:** copie la migración pendiente a `src/main/resources/db/migration/` con el siguiente número (por ejemplo, `P1_…` como `V3__republicar_mismo_horario.sql` y `P3_…` como `V4__parametros_con_publicado.sql`). Antes, confirme que ningún periodo tiene dos horarios PUBLICADOS (P1 crearía un índice único). Este flujo también está probado (paso 10 de `tools/ejecutar_todo.sh`).

En el proyecto Spring copie a `db/migration/` **solo** los archivos `V*.sql`, nunca `preflight_V2.sql` ni `pendientes/`.

---

## 5. Evidencia y reproducibilidad

- **Versiones de MySQL:** Community Server **9.7.2** y **9.7.4** LTS, compilados desde el código fuente oficial (`github.com/mysql/mysql-server`, etiquetas `mysql-9.7.2` y `mysql-9.7.4`). El entorno de trabajo no tenía acceso a los paquetes binarios.
- **Flyway:** 13.10.3 (CLI). En el contenedor no estaba MySQL Connector/J, así que Flyway usó el controlador MariaDB que incluye su distribución; la aplicación Spring usará `mysql-connector-j`. Flyway advierte que 9.7 es más nuevo que la última versión de MySQL que ha verificado (9.4); todas las migraciones se aplicaron sin errores.
- **Script reproducible:** `tools/ejecutar_todo.sh` (BORRA y recrea `horarios_ueb`; solo para desarrollo). Ejecuta:
  - el flujo de desarrollo y la no destructividad de `01_schema.sql`;
  - la guardia de `00_reset_dev.sql`;
  - las pruebas de las migraciones pendientes;
  - `04_tests.sql` sobre V1, que debe fallar;
  - la equivalencia 01 = V1+V2, con el cliente mysql y con Flyway;
  - la migración con datos y su CHECKSUM;
  - el camino de fallo: V2 bloqueada, fallo atómico, corrección y repair;
  - la activación de P1+P3 como V3/V4.
- **Resultados:** `evidencia/9.7.2/` y `evidencia/9.7.4/` (salidas completas y `00_resumen.txt`).

**No verificado aquí:** la integración real con Spring Boot (entidades JPA, `ddl-auto=validate` y las pruebas BK01–BK13), que corresponde a la fase del backend. El controlador `mysql-connector-j` tampoco se probó, por la razón indicada.
