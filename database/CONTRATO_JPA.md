# Contrato de integración Spring Boot / JPA — esquema V2

Generado automáticamente con `tools/generar_contrato.py` desde `information_schema` de MySQL 9.7.4. No lo edite a mano: si cambia el esquema, cree una migración nueva, vuelva a generar este archivo y actualice la huella de la prueba K01 de `04_tests.sql`.

**Huella SHA-256 de columnas:** `3cad7286b09207d269d78c2a7604e8049d4b8ac133f5b2b583a18a7850ae4299` (prueba K01).

## Reglas generales

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

## Columnas

### `periodo_academico` → `PeriodoAcademico`

| Columna | Tipo SQL | Nulo | Default | Clave | Campo Java | Tipo Java | Anotación JPA |
|---|---|---|---|---|---|---|---|
| `id` | `bigint` auto_increment | no | — | PRI | `id` | `Long` | `@Id @GeneratedValue(strategy = GenerationType.IDENTITY)` |
| `nombre` | `varchar(20)` | no | — | UNI | `nombre` | `String` | `@Column(nullable = false, unique = true, length = 20)` |
| `fecha_inicio` | `date` | no | — | — | `fechaInicio` | `LocalDate` | — |
| `fecha_fin` | `date` | no | — | — | `fechaFin` | `LocalDate` | — |
| `hora_inicio_semana` | `time` | no | `07:00:00` | — | `horaInicioSemana` | `LocalTime` | — |
| `hora_fin_semana` | `time` | no | `22:00:00` | — | `horaFinSemana` | `LocalTime` | — |
| `hora_inicio_sabado` | `time` | no | `07:00:00` | — | `horaInicioSabado` | `LocalTime` | — |
| `hora_fin_sabado` | `time` | no | `13:00:00` | — | `horaFinSabado` | `LocalTime` | — |
| `almuerzo_inicio` | `time` | no | `12:00:00` | — | `almuerzoInicio` | `LocalTime` | — |
| `almuerzo_fin` | `time` | no | `13:00:00` | — | `almuerzoFin` | `LocalTime` | — |
| `duracion_bloque_min` | `smallint` | no | `120` | — | `duracionBloqueMin` | `Short` | — |
| `max_sesiones_semana` | `tinyint` | no | `4` | — | `maxSesionesSemana` | `Byte` | — |
| `cupo_maximo_base` | `smallint` | no | `40` | — | `cupoMaximoBase` | `Short` | — |
| `tolerancia_cupo_pct` | `decimal(5,2)` | no | `10.00` | — | `toleranciaCupoPct` | `BigDecimal` | `@Column(precision = 5, scale = 2)` |
| `cupo_minimo` | `smallint` | no | `10` | — | `cupoMinimo` | `Short` | — |

### `docente` → `Docente`

| Columna | Tipo SQL | Nulo | Default | Clave | Campo Java | Tipo Java | Anotación JPA |
|---|---|---|---|---|---|---|---|
| `id` | `bigint` auto_increment | no | — | PRI | `id` | `Long` | `@Id @GeneratedValue(strategy = GenerationType.IDENTITY)` |
| `nombre` | `varchar(150)` | no | — | MUL | `nombre` | `String` | `@Column(nullable = false, length = 150)` |
| `tipo_vinculacion` | `varchar(15) utf8mb4_0900_bin` | no | — | — | `tipoVinculacion` | `TipoVinculacion` | `@Enumerated(EnumType.STRING) @Column(length = 15)` |

### `docente_especialidad` → `(colección en Docente)`

| Columna | Tipo SQL | Nulo | Default | Clave | Campo Java | Tipo Java | Anotación JPA |
|---|---|---|---|---|---|---|---|
| `docente_id` | `bigint` | no | — | PRI | `(clave de la colección)` | `—` | `@ElementCollection @CollectionTable(name = "docente_especialidad", joinColumns = @JoinColumn(name = "docente_id"))` |
| `especialidad` | `varchar(100)` | no | — | PRI | `especialidades` | `Set<String>` | `@Column(name = "especialidad", length = 100)` |

### `restriccion_horaria` → `RestriccionHoraria`

| Columna | Tipo SQL | Nulo | Default | Clave | Campo Java | Tipo Java | Anotación JPA |
|---|---|---|---|---|---|---|---|
| `id` | `bigint` auto_increment | no | — | PRI | `id` | `Long` | `@Id @GeneratedValue(strategy = GenerationType.IDENTITY)` |
| `docente_id` | `bigint` | no | — | MUL | `docente` | `Docente` | `@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "docente_id")` |
| `dia` | `tinyint` | no | — | — | `dia` | `DayOfWeek` | `@Convert(converter = DiaSemanaConverter.class)` |
| `hora_inicio` | `time` | no | — | — | `horaInicio` | `LocalTime` | — |
| `hora_fin` | `time` | no | — | — | `horaFin` | `LocalTime` | — |
| `tipo` | `varchar(12) utf8mb4_0900_bin` | no | — | — | `tipo` | `TipoRestriccion` | `@Enumerated(EnumType.STRING) @Column(length = 12)` |
| `sentido` | `varchar(15) utf8mb4_0900_bin` | no | — | — | `sentido` | `SentidoRestriccion` | `@Enumerated(EnumType.STRING) @Column(length = 15)` |

### `curso` → `Curso`

| Columna | Tipo SQL | Nulo | Default | Clave | Campo Java | Tipo Java | Anotación JPA |
|---|---|---|---|---|---|---|---|
| `id` | `bigint` auto_increment | no | — | PRI | `id` | `Long` | `@Id @GeneratedValue(strategy = GenerationType.IDENTITY)` |
| `codigo` | `varchar(20)` | sí | — | UNI | `codigo` | `String` | `@Column(unique = true, length = 20)` |
| `nombre` | `varchar(150)` | no | — | MUL | `nombre` | `String` | `@Column(nullable = false, length = 150)` |
| `sesiones_semanales` | `tinyint` | no | — | — | `sesionesSemanales` | `Byte` | — |
| `duracion_sesion_min` | `smallint` | no | `120` | — | `duracionSesionMin` | `Short` | — |
| `necesita_aula_especial` | `tinyint(1)` | no | `0` | MUL | `necesitaAulaEspecial` | `boolean` | — |

### `grupo` → `Grupo`

| Columna | Tipo SQL | Nulo | Default | Clave | Campo Java | Tipo Java | Anotación JPA |
|---|---|---|---|---|---|---|---|
| `id` | `bigint` auto_increment | no | — | PRI | `id` | `Long` | `@Id @GeneratedValue(strategy = GenerationType.IDENTITY)` |
| `periodo_id` | `bigint` | no | — | MUL | `periodo` | `PeriodoAcademico` | `@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "periodo_id")` |
| `curso_id` | `bigint` | no | — | MUL | `curso` | `Curso` | `@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "curso_id")` |
| `docente_id` | `bigint` | no | — | MUL | `docente` | `Docente` | `@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "docente_id")` |
| `codigo` | `varchar(10)` | no | — | — | `codigo` | `String` | `@Column(nullable = false, length = 10)` |
| `cupo_maximo` | `smallint` | no | — | — | `cupoMaximo` | `Short` | — |
| `cupo_minimo` | `smallint` | no | — | — | `cupoMinimo` | `Short` | — |
| `inscritos` | `smallint` | no | `0` | — | `inscritos` | `Short` | — |

### `horario` → `Horario`

| Columna | Tipo SQL | Nulo | Default | Clave | Campo Java | Tipo Java | Anotación JPA |
|---|---|---|---|---|---|---|---|
| `id` | `bigint` auto_increment | no | — | PRI | `id` | `Long` | `@Id @GeneratedValue(strategy = GenerationType.IDENTITY)` |
| `periodo_id` | `bigint` | no | — | MUL | `periodo` | `PeriodoAcademico` | `@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "periodo_id")` |
| `estado` | `varchar(10) utf8mb4_0900_bin` | no | `BORRADOR` | — | `estado` | `EstadoHorario` | `@Enumerated(EnumType.STRING) @Column(length = 10)` |
| `fecha_creacion` | `datetime` | no | `CURRENT_TIMESTAMP` | — | `fechaCreacion` | `LocalDateTime` | `@Column(insertable = false, updatable = false)` |
| `fecha_publicacion` | `datetime` | sí | — | — | `fechaPublicacion` | `LocalDateTime` | — |
| `version` | `int` | no | `0` | — | `version` | `Integer` | `@Version` |

### `sesion` → `Sesion`

| Columna | Tipo SQL | Nulo | Default | Clave | Campo Java | Tipo Java | Anotación JPA |
|---|---|---|---|---|---|---|---|
| `id` | `bigint` auto_increment | no | — | PRI | `id` | `Long` | `@Id @GeneratedValue(strategy = GenerationType.IDENTITY)` |
| `horario_id` | `bigint` | no | — | MUL | `horario` | `Horario` | `@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "horario_id")` |
| `grupo_id` | `bigint` | no | — | MUL | `grupo` | `Grupo` | `@ManyToOne(optional = false, fetch = FetchType.LAZY) @JoinColumn(name = "grupo_id")` |
| `dia` | `tinyint` | no | — | — | `dia` | `DayOfWeek` | `@Convert(converter = DiaSemanaConverter.class)` |
| `hora_inicio` | `time` | no | — | — | `horaInicio` | `LocalTime` | — |
| `hora_fin` | `time` | no | — | — | `horaFin` | `LocalTime` | — |

### Relaciones inversas (no tienen columna)

| Entidad | Campo | Anotación |
|---|---|---|
| `Docente` | `List<RestriccionHoraria> restricciones` | `@OneToMany(mappedBy = "docente", cascade = CascadeType.ALL, orphanRemoval = true)` |
| `Docente` | `List<Grupo> grupos` | `@OneToMany(mappedBy = "docente")` (opcional, sin cascade) |
| `Curso` | `List<Grupo> grupos` | `@OneToMany(mappedBy = "curso")` (opcional, sin cascade) |
| `PeriodoAcademico` | `List<Horario> horarios` / `List<Grupo> grupos` | `@OneToMany(mappedBy = "periodo")` sin cascade |
| `Horario` | `List<Sesion> sesiones` | `@OneToMany(mappedBy = "horario")` **sin** cascade REMOVE |
| `Grupo` | `List<Sesion> sesiones` | `@OneToMany(mappedBy = "grupo")` sin cascade |

## Claves foráneas (nombres exactos)

| FK | Columna | Referencia | ON DELETE | ON UPDATE |
|---|---|---|---|---|
| `fk_docente_especialidad_docente` | `docente_especialidad.docente_id` | `docente.id` | CASCADE | RESTRICT |
| `fk_grupo_curso` | `grupo.curso_id` | `curso.id` | RESTRICT | RESTRICT |
| `fk_grupo_docente` | `grupo.docente_id` | `docente.id` | RESTRICT | RESTRICT |
| `fk_grupo_periodo_academico` | `grupo.periodo_id` | `periodo_academico.id` | RESTRICT | RESTRICT |
| `fk_horario_periodo_academico` | `horario.periodo_id` | `periodo_academico.id` | RESTRICT | RESTRICT |
| `fk_restriccion_horaria_docente` | `restriccion_horaria.docente_id` | `docente.id` | CASCADE | RESTRICT |
| `fk_sesion_grupo` | `sesion.grupo_id` | `grupo.id` | RESTRICT | RESTRICT |
| `fk_sesion_horario` | `sesion.horario_id` | `horario.id` | RESTRICT | RESTRICT |

## Restricciones CHECK

| Tabla | CHECK | Condición |
|---|---|---|
| `periodo_academico` | `ck_periodo_academico_almuerzo` | (almuerzo_fin > almuerzo_inicio) |
| `periodo_academico` | `ck_periodo_academico_cupo_max` | (cupo_maximo_base > 0) |
| `periodo_academico` | `ck_periodo_academico_cupo_min` | ((cupo_minimo >= 0) and (cupo_minimo <= cupo_maximo_base)) |
| `periodo_academico` | `ck_periodo_academico_duracion` | (duracion_bloque_min between 30 and 240) |
| `periodo_academico` | `ck_periodo_academico_fechas` | (fecha_fin > fecha_inicio) |
| `periodo_academico` | `ck_periodo_academico_franja_bloque` | (time_to_sec(timediff(hora_fin_semana,hora_inicio_semana)) >= (duracion_bloque_min * 60)) |
| `periodo_academico` | `ck_periodo_academico_franja_sab` | (hora_fin_sabado > hora_inicio_sabado) |
| `periodo_academico` | `ck_periodo_academico_franja_sem` | (hora_fin_semana > hora_inicio_semana) |
| `periodo_academico` | `ck_periodo_academico_max_ses` | (max_sesiones_semana between 1 and 10) |
| `periodo_academico` | `ck_periodo_academico_nombre` | (char_length(trim(nombre)) > 0) |
| `periodo_academico` | `ck_periodo_academico_tolerancia` | (tolerancia_cupo_pct between 0 and 100) |
| `docente` | `ck_docente_nombre` | (char_length(trim(nombre)) > 0) |
| `docente` | `ck_docente_tipo_vinculacion` | (tipo_vinculacion in ('TC','TRES_CUARTOS','MEDIO_TIEMPO','CUARTO_TIEMPO')) |
| `docente_especialidad` | `ck_docente_especialidad_valor` | (char_length(trim(especialidad)) > 0) |
| `restriccion_horaria` | `ck_restriccion_horaria_dia` | (dia between 1 and 6) |
| `restriccion_horaria` | `ck_restriccion_horaria_horas` | (hora_fin > hora_inicio) |
| `restriccion_horaria` | `ck_restriccion_horaria_sentido` | (sentido in ('DISPONIBLE','NO_DISPONIBLE')) |
| `restriccion_horaria` | `ck_restriccion_horaria_tipo` | (tipo in ('FIRME','PREFERENCIA')) |
| `curso` | `ck_curso_aula_especial` | (necesita_aula_especial in (0,1)) |
| `curso` | `ck_curso_duracion` | (duracion_sesion_min between 30 and 240) |
| `curso` | `ck_curso_nombre` | (char_length(trim(nombre)) > 0) |
| `curso` | `ck_curso_sesiones` | (sesiones_semanales between 1 and 10) |
| `grupo` | `ck_grupo_codigo` | (char_length(trim(codigo)) > 0) |
| `grupo` | `ck_grupo_cupo_maximo` | (cupo_maximo > 0) |
| `grupo` | `ck_grupo_cupo_minimo` | (cupo_minimo >= 0) |
| `grupo` | `ck_grupo_cupos` | (cupo_minimo <= cupo_maximo) |
| `grupo` | `ck_grupo_inscritos` | (inscritos >= 0) |
| `horario` | `ck_horario_estado` | (estado in ('BORRADOR','PUBLICADO')) |
| `horario` | `ck_horario_publicacion` | ((estado = 'BORRADOR') or (fecha_publicacion is not null)) |
| `horario` | `ck_horario_version` | (version >= 0) |
| `sesion` | `ck_sesion_dia` | (dia between 1 and 6) |
| `sesion` | `ck_sesion_horas` | (hora_fin > hora_inicio) |

## Índices y claves únicas

| Tabla | Índice | Único | Columnas |
|---|---|---|---|
| `periodo_academico` | `PRIMARY` | UNIQUE | `id` |
| `periodo_academico` | `uk_periodo_academico_nombre` | UNIQUE | `nombre` |
| `docente` | `idx_docente_nombre` | — | `nombre` |
| `docente` | `PRIMARY` | UNIQUE | `id` |
| `docente_especialidad` | `PRIMARY` | UNIQUE | `docente_id, especialidad` |
| `restriccion_horaria` | `idx_restriccion_horaria_docente_dia` | — | `docente_id, dia, hora_inicio` |
| `restriccion_horaria` | `PRIMARY` | UNIQUE | `id` |
| `restriccion_horaria` | `uk_restriccion_horaria_franja` | UNIQUE | `docente_id, dia, hora_inicio, hora_fin, tipo, sentido` |
| `curso` | `idx_curso_aula_especial` | — | `necesita_aula_especial` |
| `curso` | `idx_curso_nombre` | — | `nombre` |
| `curso` | `PRIMARY` | UNIQUE | `id` |
| `curso` | `uk_curso_codigo` | UNIQUE | `codigo` |
| `grupo` | `idx_grupo_curso_periodo` | — | `curso_id, periodo_id` |
| `grupo` | `idx_grupo_docente_periodo` | — | `docente_id, periodo_id` |
| `grupo` | `PRIMARY` | UNIQUE | `id` |
| `grupo` | `uk_grupo_periodo_curso_codigo` | UNIQUE | `periodo_id, curso_id, codigo` |
| `horario` | `idx_horario_periodo_estado` | — | `periodo_id, estado` |
| `horario` | `PRIMARY` | UNIQUE | `id` |
| `sesion` | `idx_sesion_grupo_horario` | — | `grupo_id, horario_id` |
| `sesion` | `idx_sesion_horario_casilla` | — | `horario_id, dia, hora_inicio` |
| `sesion` | `PRIMARY` | UNIQUE | `id` |
| `sesion` | `uk_sesion_horario_grupo_casilla` | UNIQUE | `horario_id, grupo_id, dia, hora_inicio` |

## Triggers y errores que el backend debe traducir

| Trigger | Momento | Tabla |
|---|---|---|
| `trg_curso_bu` | BEFORE UPDATE | `curso` |
| `trg_grupo_bu` | BEFORE UPDATE | `grupo` |
| `trg_horario_bd` | BEFORE DELETE | `horario` |
| `trg_horario_bi` | BEFORE INSERT | `horario` |
| `trg_horario_bu` | BEFORE UPDATE | `horario` |
| `trg_sesion_bd` | BEFORE DELETE | `sesion` |
| `trg_sesion_bi` | BEFORE INSERT | `sesion` |
| `trg_sesion_bu` | BEFORE UPDATE | `sesion` |

| Error | SQLSTATE / errno | Excepción típica en Spring | Significado |
|---|---|---|---|
| `[BD-01]` … `[BD-12]` | 45000 / 1644 | `JpaSystemException` / `GenericJDBCException` (causa `SQLException`) | Regla de la BD (ver README, sección 5). Lea el prefijo `[BD-xx]` del mensaje. |
| FK hija inexistente | 23000 / 1452 | `DataIntegrityViolationException` | Referencia a un id que no existe. |
| FK con hijos | 23000 / 1451 | `DataIntegrityViolationException` | Borrado bloqueado por RESTRICT. |
| UNIQUE | 23000 / 1062 | `DataIntegrityViolationException` | Duplicado (nombre de periodo, grupo, casilla, código…). |
| CHECK | HY000 / 3819 | `DataIntegrityViolationException` | Dominio o rango inválido. |
| NOT NULL | 23000 / 1048 | `DataIntegrityViolationException` | Falta un dato obligatorio. |
| `@Version` | — | `ObjectOptimisticLockingFailureException` | Otro usuario modificó el horario; recargar. |

## Vistas de solo lectura

`v_bloque_valido`, `v_grupo_cupo`, `v_horario_vigente`, `v_sesion_conflicto_parametros`, `v_sesion_detalle`

## Repositorio: bloqueo para editar un horario

```java
public interface HorarioRepository extends JpaRepository<Horario, Long> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select h from Horario h where h.id = :id")
    Optional<Horario> findByIdParaEditar(@Param("id") Long id);
}
```

Cada operación de mover, insertar, eliminar sesiones, publicar o despublicar ocurre en un `@Transactional` que primero llama a `findByIdParaEditar`, valida con las reglas Java (Tabla 19) y luego escribe. La BD repite como red de seguridad solo BD-02 a BD-04 y BD-08.

