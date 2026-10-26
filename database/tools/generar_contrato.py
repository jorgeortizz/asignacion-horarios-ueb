#!/usr/bin/env python3
"""Genera CONTRATO_JPA.md a partir del esquema instalado (information_schema).

Uso:  python3 tools/generar_contrato.py "<comando mysql con credenciales>" > CONTRATO_JPA.md
Los nombres, tipos, nulabilidad, defaults, FK, CHECK e índices se leen de la
base; solo el mapeo a Java (tipo y anotación) está definido aquí, y el script
falla si una columna del esquema no tiene mapeo (o al revés).
"""
import subprocess, sys, hashlib

MYSQL = sys.argv[1]
DB = "horarios_ueb"

def q(sql):
    out = subprocess.run(MYSQL.split() + ["-N", "-B", "--default-character-set=utf8mb4", "-e", sql],
                         capture_output=True, text=True, check=True).stdout
    return [line.split("\t") for line in out.splitlines() if line]

ENTIDAD = {
    "periodo_academico": "PeriodoAcademico", "docente": "Docente",
    "docente_especialidad": "(colección en Docente)", "restriccion_horaria": "RestriccionHoraria",
    "curso": "Curso", "grupo": "Grupo", "horario": "Horario", "sesion": "Sesion",
}
ORDEN = list(ENTIDAD)

# (tabla, columna) -> (campo Java, tipo Java, anotación JPA)
J = {}
def m(t, c, campo, tipo, anot=""): J[(t, c)] = (campo, tipo, anot)
ID = '@Id @GeneratedValue(strategy = GenerationType.IDENTITY)'
for t in ["periodo_academico", "docente", "restriccion_horaria", "curso", "grupo", "horario", "sesion"]:
    m(t, "id", "id", "Long", ID)
m("periodo_academico", "nombre", "nombre", "String", '@Column(nullable = false, unique = true, length = 20)')
m("periodo_academico", "fecha_inicio", "fechaInicio", "LocalDate")
m("periodo_academico", "fecha_fin", "fechaFin", "LocalDate")
for c, f in [("hora_inicio_semana", "horaInicioSemana"), ("hora_fin_semana", "horaFinSemana"),
             ("hora_inicio_sabado", "horaInicioSabado"), ("hora_fin_sabado", "horaFinSabado"),
             ("almuerzo_inicio", "almuerzoInicio"), ("almuerzo_fin", "almuerzoFin")]:
    m("periodo_academico", c, f, "LocalTime")
m("periodo_academico", "duracion_bloque_min", "duracionBloqueMin", "Short")
m("periodo_academico", "max_sesiones_semana", "maxSesionesSemana", "Byte")
m("periodo_academico", "cupo_maximo_base", "cupoMaximoBase", "Short")
m("periodo_academico", "tolerancia_cupo_pct", "toleranciaCupoPct", "BigDecimal", '@Column(precision = 5, scale = 2)')
m("periodo_academico", "cupo_minimo", "cupoMinimo", "Short")
m("docente", "nombre", "nombre", "String", '@Column(nullable = false, length = 150)')
m("docente", "tipo_vinculacion", "tipoVinculacion", "TipoVinculacion", '@Enumerated(EnumType.STRING) @Column(length = 15)')
m("docente_especialidad", "docente_id", "(clave de la colección)", "—",
  '@ElementCollection @CollectionTable(name = "docente_especialidad", joinColumns = @JoinColumn(name = "docente_id"))')
m("docente_especialidad", "especialidad", "especialidades", "Set<String>", '@Column(name = "especialidad", length = 100)')
m("restriccion_horaria", "docente_id", "docente", "Docente", '@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "docente_id")')
m("restriccion_horaria", "dia", "dia", "DayOfWeek", '@Convert(converter = DiaSemanaConverter.class)')
m("restriccion_horaria", "hora_inicio", "horaInicio", "LocalTime")
m("restriccion_horaria", "hora_fin", "horaFin", "LocalTime")
m("restriccion_horaria", "tipo", "tipo", "TipoRestriccion", '@Enumerated(EnumType.STRING) @Column(length = 12)')
m("restriccion_horaria", "sentido", "sentido", "SentidoRestriccion", '@Enumerated(EnumType.STRING) @Column(length = 15)')
m("curso", "codigo", "codigo", "String", '@Column(unique = true, length = 20)')
m("curso", "nombre", "nombre", "String", '@Column(nullable = false, length = 150)')
m("curso", "sesiones_semanales", "sesionesSemanales", "Byte")
m("curso", "duracion_sesion_min", "duracionSesionMin", "Short")
m("curso", "necesita_aula_especial", "necesitaAulaEspecial", "boolean")
m("grupo", "periodo_id", "periodo", "PeriodoAcademico", '@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "periodo_id")')
m("grupo", "curso_id", "curso", "Curso", '@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "curso_id")')
m("grupo", "docente_id", "docente", "Docente", '@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "docente_id")')
m("grupo", "codigo", "codigo", "String", '@Column(nullable = false, length = 10)')
m("grupo", "cupo_maximo", "cupoMaximo", "Short")
m("grupo", "cupo_minimo", "cupoMinimo", "Short")
m("grupo", "inscritos", "inscritos", "Short")
m("horario", "periodo_id", "periodo", "PeriodoAcademico", '@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "periodo_id")')
m("horario", "estado", "estado", "EstadoHorario", '@Enumerated(EnumType.STRING) @Column(length = 10)')
m("horario", "fecha_creacion", "fechaCreacion", "LocalDateTime", '@Column(insertable = false, updatable = false)')
m("horario", "fecha_publicacion", "fechaPublicacion", "LocalDateTime")
m("horario", "version", "version", "Integer", '@Version')
m("sesion", "horario_id", "horario", "Horario", '@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "horario_id")')
m("sesion", "grupo_id", "grupo", "Grupo", '@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "grupo_id")')
m("sesion", "dia", "dia", "DayOfWeek", '@Convert(converter = DiaSemanaConverter.class)')
m("sesion", "hora_inicio", "horaInicio", "LocalTime")
m("sesion", "hora_fin", "horaFin", "LocalTime")

tablas = "','".join(ORDEN)
cols = q(f"""SELECT table_name, column_name, column_type, is_nullable, IFNULL(column_default,'∅'),
             IFNULL(collation_name,''), column_key, extra
             FROM information_schema.columns WHERE table_schema='{DB}' AND table_name IN ('{tablas}')
             ORDER BY FIELD(table_name,'{tablas}'), ordinal_position""")
en_bd = {(r[0], r[1]) for r in cols}
faltan = en_bd ^ set(J)
if faltan:
    sys.exit(f"Columnas sin mapeo o mapeos sin columna: {sorted(faltan)}")

fks = q(f"""SELECT k.constraint_name, k.table_name, k.column_name, k.referenced_table_name, k.referenced_column_name,
            r.delete_rule, r.update_rule
            FROM information_schema.key_column_usage k
            JOIN information_schema.referential_constraints r
              ON r.constraint_schema = k.table_schema AND r.constraint_name = k.constraint_name
            WHERE k.table_schema='{DB}' AND k.referenced_table_name IS NOT NULL ORDER BY k.constraint_name""")
checks = q(f"""SELECT tc.table_name, cc.constraint_name, cc.check_clause
               FROM information_schema.check_constraints cc
               JOIN information_schema.table_constraints tc
                 ON tc.constraint_schema = cc.constraint_schema AND tc.constraint_name = cc.constraint_name
               WHERE cc.constraint_schema='{DB}' ORDER BY FIELD(tc.table_name,'{tablas}'), cc.constraint_name""")
idx = q(f"""SELECT table_name, index_name, IF(non_unique=0,'UNIQUE',''),
            GROUP_CONCAT(IFNULL(column_name, CONCAT('(', expression, ')')) ORDER BY seq_in_index SEPARATOR ', ')
            FROM information_schema.statistics WHERE table_schema='{DB}' AND table_name IN ('{tablas}')
            GROUP BY table_name, index_name, non_unique ORDER BY FIELD(table_name,'{tablas}'), index_name""")
trig = q(f"""SELECT trigger_name, action_timing, event_manipulation, event_object_table
             FROM information_schema.triggers WHERE trigger_schema='{DB}' ORDER BY event_object_table, trigger_name""")
vistas = q(f"SELECT table_name FROM information_schema.views WHERE table_schema='{DB}' ORDER BY table_name")
version = q("SELECT VERSION()")[0][0]
huella = q(f"""SET SESSION group_concat_max_len=1000000;
  SELECT SHA2(GROUP_CONCAT(CONCAT_WS('|', table_name, ordinal_position, column_name, column_type, is_nullable,
  IFNULL(column_default, '-'), IFNULL(collation_name, '-')) ORDER BY table_name, ordinal_position SEPARATOR ';'), 256)
  FROM information_schema.columns WHERE table_schema='{DB}' AND table_name IN ('{tablas}')""")[0][0]

o = []
w = o.append
w("# Contrato de integración Spring Boot / JPA — esquema V2\n")
w(f"Generado automáticamente con `tools/generar_contrato.py` desde `information_schema` de MySQL {version}. "
  "No lo edite a mano: si cambia el esquema, cree una migración nueva, vuelva a generar este archivo y "
  "actualice la huella de la prueba K01 de `04_tests.sql`.\n")
w(f"**Huella SHA-256 de columnas:** `{huella}` (prueba K01).\n")
w("""## Reglas generales

- Declare `@Table(name = "...")` y `@Column(name = "...")` explícitos y use `PhysicalNamingStrategyStandardImpl` (README, sección 6).
- `spring.jpa.hibernate.ddl-auto=none` en todos los perfiles; `validate` solo en una prueba de integración. **Nunca `update` ni `create`.**
- Ids: `Long` con `GenerationType.IDENTITY` (`BIGINT AUTO_INCREMENT`).
- `TINYINT` → `Byte` y `SMALLINT` → `Short`, para que `validate` coincida exactamente. Si el equipo prefiere `Integer`, agregue `@JdbcTypeCode(SqlTypes.TINYINT)` o `@JdbcTypeCode(SqlTypes.SMALLINT)`.
- Enums: `@Enumerated(EnumType.STRING)` con constantes **idénticas** a los valores del CHECK. Las columnas enum usan `utf8mb4_0900_bin`, así que solo se acepta el valor exacto (pruebas K04 a K09). Si `validate` espera el tipo nativo `enum` de MySQL, agregue `@JdbcTypeCode(SqlTypes.VARCHAR)` al campo.
- `dia` (1 = lunes … 6 = sábado) ↔ `java.time.DayOfWeek` con un `AttributeConverter<DayOfWeek, Byte>`: `DayOfWeek.of(valor)` y `dia.getValue()`. Rechace `SUNDAY` en Java antes de persistir; la BD lo rechaza con un CHECK.
- `sesion.hora_fin` = `hora_inicio` + `curso.duracion_sesion_min`: lo calcula el servicio; nunca se pide al usuario (trigger BD-02).
- Sin `cascade = REMOVE` ni `orphanRemoval` desde `PeriodoAcademico`, `Horario`, `Curso` ni `Grupo`: la BD lo impide (RESTRICT) y el historial debe conservarse. Solo `Docente.restricciones` (`cascade = ALL, orphanRemoval = true`) y `Docente.especialidades` (`@ElementCollection`).
- Las vistas `v_*` son de solo lectura: `@Query(nativeQuery = true)` o entidades `@Immutable @Subselect`.

## Enums Java

| Enum | Constantes (exactas) | Columna |
|---|---|---|
| `TipoVinculacion` | `TC`, `TRES_CUARTOS`, `MEDIO_TIEMPO`, `CUARTO_TIEMPO` | `docente.tipo_vinculacion` |
| `TipoRestriccion` | `FIRME`, `PREFERENCIA` | `restriccion_horaria.tipo` |
| `SentidoRestriccion` | `DISPONIBLE`, `NO_DISPONIBLE` (propuesta D10, pendiente) | `restriccion_horaria.sentido` |
| `EstadoHorario` | `BORRADOR`, `PUBLICADO` | `horario.estado` |
""")
w("## Columnas\n")
for t in ORDEN:
    w(f"### `{t}` → `{ENTIDAD[t]}`\n")
    w("| Columna | Tipo SQL | Nulo | Default | Clave | Campo Java | Tipo Java | Anotación JPA |")
    w("|---|---|---|---|---|---|---|---|")
    for r in cols:
        if r[0] != t: continue
        campo, tipo, anot = J[(t, r[1])]
        tipo_sql = r[2] + (f" {r[5]}" if r[5] == "utf8mb4_0900_bin" else "")
        extra = " auto_increment" if "auto_increment" in r[7] else ""
        default = r[4].replace("|", "\\|")
        anot_md = f"`{anot}`" if anot else "—"
        default_md = "—" if default == "∅" else f"`{default}`"
        w(f"| `{r[1]}` | `{tipo_sql}`{extra} | {'sí' if r[3]=='YES' else 'no'} | {default_md} | {r[6] or '—'} | `{campo}` | `{tipo}` | {anot_md} |")
    w("")
w("""### Relaciones inversas (no tienen columna)

| Entidad | Campo | Anotación |
|---|---|---|
| `Docente` | `List<RestriccionHoraria> restricciones` | `@OneToMany(mappedBy = "docente", cascade = CascadeType.ALL, orphanRemoval = true)` |
| `Docente` | `List<Grupo> grupos` | `@OneToMany(mappedBy = "docente")` (opcional, sin cascade) |
| `Curso` | `List<Grupo> grupos` | `@OneToMany(mappedBy = "curso")` (opcional, sin cascade) |
| `PeriodoAcademico` | `List<Horario> horarios` / `List<Grupo> grupos` | `@OneToMany(mappedBy = "periodo")` sin cascade |
| `Horario` | `List<Sesion> sesiones` | `@OneToMany(mappedBy = "horario")` **sin** cascade REMOVE |
| `Grupo` | `List<Sesion> sesiones` | `@OneToMany(mappedBy = "grupo")` sin cascade |
""")
w("## Claves foráneas (nombres exactos)\n")
w("| FK | Columna | Referencia | ON DELETE | ON UPDATE |")
w("|---|---|---|---|---|")
for r in fks:
    w(f"| `{r[0]}` | `{r[1]}.{r[2]}` | `{r[3]}.{r[4]}` | {r[5]} | {r[6]} |")
w("\n## Restricciones CHECK\n")
w("| Tabla | CHECK | Condición |")
w("|---|---|---|")
for r in checks:
    clausula = r[2].replace(chr(92), "").replace("_utf8mb4", "").replace("`", "").replace("|", "\\|")
    w(f"| `{r[0]}` | `{r[1]}` | {clausula} |")
w("\n## Índices y claves únicas\n")
w("| Tabla | Índice | Único | Columnas |")
w("|---|---|---|---|")
for r in idx:
    w(f"| `{r[0]}` | `{r[1]}` | {r[2] or '—'} | `{r[3]}` |")
w("\n## Triggers y errores que el backend debe traducir\n")
w("| Trigger | Momento | Tabla |")
w("|---|---|---|")
for r in trig:
    w(f"| `{r[0]}` | {r[1]} {r[2]} | `{r[3]}` |")
w("""
| Error | SQLSTATE / errno | Excepción típica en Spring | Significado |
|---|---|---|---|
| `[BD-01]` … `[BD-12]` | 45000 / 1644 | `JpaSystemException` / `GenericJDBCException` (causa `SQLException`) | Regla de la BD (ver README, sección 5). Lea el prefijo `[BD-xx]` del mensaje. |
| FK hija inexistente | 23000 / 1452 | `DataIntegrityViolationException` | Referencia a un id que no existe. |
| FK con hijos | 23000 / 1451 | `DataIntegrityViolationException` | Borrado bloqueado por RESTRICT. |
| UNIQUE | 23000 / 1062 | `DataIntegrityViolationException` | Duplicado (nombre de periodo, grupo, casilla, código…). |
| CHECK | HY000 / 3819 | `DataIntegrityViolationException` | Dominio o rango inválido. |
| NOT NULL | 23000 / 1048 | `DataIntegrityViolationException` | Falta un dato obligatorio. |
| `@Version` | — | `ObjectOptimisticLockingFailureException` | Otro usuario modificó el horario; recargar. |
""")
w("## Vistas de solo lectura\n")
w(", ".join(f"`{r[0]}`" for r in vistas) + "\n")
w("""## Repositorio: bloqueo para editar un horario

```java
public interface HorarioRepository extends JpaRepository<Horario, Long> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select h from Horario h where h.id = :id")
    Optional<Horario> findByIdParaEditar(@Param("id") Long id);
}
```

Cada operación de mover, insertar, eliminar sesiones, publicar o despublicar ocurre en un `@Transactional` que primero llama a `findByIdParaEditar`, valida con las reglas Java (Tabla 19) y luego escribe. La BD repite como red de seguridad solo BD-02 a BD-04 y BD-08.
""")
print("\n".join(o))
