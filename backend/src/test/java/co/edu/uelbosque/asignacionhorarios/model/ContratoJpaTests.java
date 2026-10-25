package co.edu.uelbosque.asignacionhorarios.model;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;
import jakarta.persistence.OptimisticLockException;
import jakarta.persistence.PersistenceException;
import jakarta.validation.ConstraintViolationException;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.*;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.EnumSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import static org.junit.jupiter.api.Assertions.*;

/** Contrasta los mapeos con las columnas oficiales y ejercita persistencia real en H2. */
@SpringBootTest
@ActiveProfiles("demo")
@Transactional
class ContratoJpaTests {
    @Autowired EntityManager em;
    @Autowired EntityManagerFactory emf;
    @Autowired JdbcTemplate jdbc;
    @Autowired ApplicationContext context;
    @Autowired PlatformTransactionManager transactionManager;

    @ParameterizedTest
    @CsvSource(delimiter='|', value={
        "periodo_academico|id,nombre,fecha_inicio,fecha_fin,hora_inicio_semana,hora_fin_semana,hora_inicio_sabado,hora_fin_sabado,almuerzo_inicio,almuerzo_fin,duracion_bloque_min,max_sesiones_semana,cupo_maximo_base,tolerancia_cupo_pct,cupo_minimo",
        "docente|id,nombre,tipo_vinculacion",
        "docente_especialidad|docente_id,especialidad",
        "restriccion_horaria|id,docente_id,dia,hora_inicio,hora_fin,tipo,sentido",
        "curso|id,codigo,nombre,sesiones_semanales,duracion_sesion_min,necesita_aula_especial",
        "grupo|id,periodo_id,curso_id,docente_id,codigo,cupo_maximo,cupo_minimo,inscritos",
        "horario|id,periodo_id,estado,fecha_creacion,fecha_publicacion,version",
        "sesion|id,horario_id,grupo_id,dia,hora_inicio,hora_fin"
    })
    void tablasYColumnasCoincidenConElContrato(String tabla, String columnas) {
        var actuales = jdbc.execute((ConnectionCallback<Set<String>>) conexion -> {
            Set<String> resultado = new HashSet<>();
            try (var rs = conexion.getMetaData().getColumns(null, "PUBLIC", tabla.toUpperCase(Locale.ROOT), null)) {
                while (rs.next()) resultado.add(rs.getString("COLUMN_NAME").toLowerCase(Locale.ROOT));
            }
            return resultado;
        });
        assertEquals(Set.of(columnas.split(",")), actuales, tabla);
    }

    @ParameterizedTest
    @CsvSource({
        "periodo_academico,duracion_bloque_min,5", "periodo_academico,max_sesiones_semana,-6",
        "periodo_academico,cupo_maximo_base,5", "periodo_academico,cupo_minimo,5",
        "curso,sesiones_semanales,-6", "curso,duracion_sesion_min,5",
        "grupo,cupo_maximo,5", "grupo,cupo_minimo,5", "grupo,inscritos,5",
        "sesion,dia,-6", "restriccion_horaria,dia,-6", "horario,version,4",
        "docente,tipo_vinculacion,12", "restriccion_horaria,tipo,12",
        "restriccion_horaria,sentido,12", "horario,estado,12"
    })
    void tiposJdbcRespetanTinyintSmallintIntYVarchar(String tabla, String columna, int tipo) {
        jdbc.execute((ConnectionCallback<Void>) conexion -> {
            try (var rs = conexion.getMetaData().getColumns(null, "PUBLIC",
                    tabla.toUpperCase(Locale.ROOT), columna.toUpperCase(Locale.ROOT))) {
                assertTrue(rs.next());
                assertEquals(tipo, rs.getInt("DATA_TYPE"), tabla + "." + columna);
            }
            return null;
        });
    }

    @Test void demoNoEjecutaFlyway() {
        assertTrue(context.getBeansOfType(Flyway.class).isEmpty());
        assertEquals(0, jdbc.queryForObject("""
            select count(*) from information_schema.tables
            where lower(table_name) = 'flyway_schema_history'
            """, Integer.class));
    }

    @Test void persisteLasSieteEntidadesConDiasNumericosYRecuperaLaFechaGenerada() {
        var datos = datos();
        var h = datos.horario();
        assertNotNull(h.getFechaCreacion());
        assertNotEquals(LocalDateTime.of(1900, 1, 1, 0, 0), h.getFechaCreacion());
        assertEquals(0, h.getVersion());
        var fecha = h.getFechaCreacion();
        for (byte dia = 2; dia <= 6; dia++) {
            em.persist(sesion(h, datos.grupo(), dia));
            em.persist(restriccion(datos.docente(), dia,
                dia % 2 == 0 ? TipoRestriccion.PREFERENCIA : TipoRestriccion.FIRME,
                dia % 2 == 0 ? SentidoRestriccion.DISPONIBLE : SentidoRestriccion.NO_DISPONIBLE));
        }
        em.flush();
        em.clear();
        var sesion = em.find(Sesion.class, datos.sesion().getId());
        assertEquals(datos.grupo().getId(), sesion.getGrupo().getId());
        assertEquals(datos.horario().getId(), sesion.getHorario().getId());
        assertEquals(Set.of("Matematicas", "Programacion"), sesion.getGrupo().getDocente().getEspecialidades());
        assertTrue(sesion.getGrupo().getCurso().isNecesitaAulaEspecial());
        assertEquals(new BigDecimal("10.00"), sesion.getGrupo().getPeriodo().getToleranciaCupoPct());
        assertEquals(List.of((byte)1,(byte)2,(byte)3,(byte)4,(byte)5,(byte)6),
            em.createQuery("select s.dia from Sesion s where s.horario.id=:id order by s.dia", Byte.class)
                .setParameter("id", h.getId()).getResultList());
        assertEquals(6L, em.createQuery("select count(r) from RestriccionHoraria r where r.docente.id=:id", Long.class)
            .setParameter("id", datos.docente().getId()).getSingleResult());
        var preferencias = em.createQuery("select r from RestriccionHoraria r where r.docente.id=:id and r.dia=2", RestriccionHoraria.class)
            .setParameter("id", datos.docente().getId()).getSingleResult();
        assertEquals(TipoRestriccion.PREFERENCIA, preferencias.getTipo());
        assertEquals(SentidoRestriccion.DISPONIBLE, preferencias.getSentido());
        assertEquals(SentidoRestriccion.NO_DISPONIBLE, em.find(RestriccionHoraria.class, datos.restriccion().getId()).getSentido());
        var guardado = em.find(Horario.class, h.getId());
        guardado.setFechaCreacion(LocalDateTime.of(1901,1,1,0,0));
        guardado.setFechaPublicacion(LocalDateTime.of(2026,10,1,10,0));
        em.flush();
        assertEquals(1, guardado.getVersion());
        em.clear();
        assertEquals(fecha, em.find(Horario.class, h.getId()).getFechaCreacion());
    }

    @ParameterizedTest
    @EnumSource(TipoVinculacion.class)
    void conservaLosValoresExactosDeVinculacion(TipoVinculacion tipo) {
        var d = new Docente();
        d.setNombre("Prueba enum"); d.setTipoVinculacion(tipo);
        em.persist(d); em.flush(); em.clear();
        assertEquals(tipo, em.find(Docente.class, d.getId()).getTipoVinculacion());
        assertEquals(tipo.name(), jdbc.queryForObject("select tipo_vinculacion from docente where id=?", String.class, d.getId()));
    }

    @ParameterizedTest
    @CsvSource({"sesion,0", "sesion,7", "restriccion,0", "restriccion,7"})
    void rechazaDiasFueraDeLunesASabadoAntesDePersistir(String entidad, byte dia) {
        var d = datos();
        Object invalido = entidad.equals("sesion") ? sesion(d.horario(), d.grupo(), dia)
            : restriccion(d.docente(), dia, TipoRestriccion.FIRME, SentidoRestriccion.NO_DISPONIBLE);
        assertThrows(ConstraintViolationException.class, () -> { em.persist(invalido); em.flush(); });
    }

    @ParameterizedTest
    @ValueSource(strings={"horario", "periodo", "curso", "grupo"})
    void noBorraEnCascadaLasSesionesHistoricas(String entidad) {
        var d = datos();
        Object padre = switch (entidad) {
            case "horario" -> d.horario(); case "periodo" -> d.horario().getPeriodo();
            case "curso" -> d.grupo().getCurso(); default -> d.grupo();
        };
        var tipo = padre.getClass();
        Object id = emf.getPersistenceUnitUtil().getIdentifier(padre);
        // Cargar solo el padre obliga a verificar la FK, sin referencias hijas en memoria.
        em.clear();
        Object recargado = em.find(tipo, id);
        assertThrows(PersistenceException.class, () -> { em.remove(recargado); em.flush(); });
    }

    @Test
    @Transactional(propagation=Propagation.NOT_SUPPORTED)
    void versionRechazaUnaEscrituraConcurrenteObsoleta() {
        var tx = new TransactionTemplate(transactionManager);
        Long[] ids = tx.execute(status -> {
            var p = periodo(); em.persist(p);
            var h = new Horario(); h.setPeriodo(p); em.persist(h); em.flush();
            return new Long[]{h.getId(), p.getId()};
        });
        try (var primera = emf.createEntityManager(); var segunda = emf.createEntityManager()) {
            primera.getTransaction().begin(); segunda.getTransaction().begin();
            try {
                var h1 = primera.find(Horario.class, ids[0]);
                var h2 = segunda.find(Horario.class, ids[0]);
                h1.setFechaPublicacion(LocalDateTime.of(2026,10,1,10,0));
                primera.getTransaction().commit();
                assertEquals(1, h1.getVersion());
                h2.setFechaPublicacion(LocalDateTime.of(2026,10,2,10,0));
                assertThrows(OptimisticLockException.class, segunda::flush);
            } finally {
                if (primera.getTransaction().isActive()) primera.getTransaction().rollback();
                if (segunda.getTransaction().isActive()) segunda.getTransaction().rollback();
            }
        } finally {
            tx.executeWithoutResult(status -> {
                em.remove(em.find(Horario.class, ids[0]));
                em.remove(em.find(PeriodoAcademico.class, ids[1]));
            });
        }
    }

    private record Datos(Docente docente, Grupo grupo, Horario horario, Sesion sesion, RestriccionHoraria restriccion) {}
    private Datos datos() {
        var p = periodo(); em.persist(p);
        var docente = new Docente(); docente.setNombre("Docente contrato"); docente.setTipoVinculacion(TipoVinculacion.TC);
        docente.setEspecialidades(new LinkedHashSet<>(List.of("Matematicas", "Programacion"))); em.persist(docente);
        var curso = new Curso(); curso.setNombre("Curso contrato"); curso.setSesionesSemanales((byte)2);
        curso.setDuracionSesionMin((short)120); curso.setNecesitaAulaEspecial(true); em.persist(curso);
        var grupo = new Grupo(); grupo.setPeriodo(p); grupo.setDocente(docente); grupo.setCurso(curso);
        grupo.setCodigo("G1"); grupo.setCupoMaximo((short)40); grupo.setCupoMinimo((short)10); grupo.setInscritos((short)20); em.persist(grupo);
        var horario = new Horario(); horario.setPeriodo(p);
        horario.setFechaCreacion(LocalDateTime.of(1900,1,1,0,0)); em.persist(horario);
        var sesion = sesion(horario, grupo, (byte)1); em.persist(sesion);
        var restriccion = restriccion(docente, (byte)1, TipoRestriccion.FIRME, SentidoRestriccion.NO_DISPONIBLE); em.persist(restriccion);
        em.flush();
        return new Datos(docente, grupo, horario, sesion, restriccion);
    }
    private PeriodoAcademico periodo() {
        var p = new PeriodoAcademico(); p.setNombre("jpa-" + UUID.randomUUID().toString().substring(0,12));
        p.setFechaInicio(LocalDate.of(2026,7,1)); p.setFechaFin(LocalDate.of(2026,12,1));
        p.setHoraInicioSemana(LocalTime.of(7,0)); p.setHoraFinSemana(LocalTime.of(22,0));
        p.setHoraInicioSabado(LocalTime.of(7,0)); p.setHoraFinSabado(LocalTime.of(13,0));
        p.setAlmuerzoInicio(LocalTime.of(13,0)); p.setAlmuerzoFin(LocalTime.of(14,0));
        p.setDuracionBloqueMin((short)120); p.setMaxSesionesSemana((byte)4);
        p.setCupoMaximoBase((short)40); p.setCupoMinimo((short)10); p.setToleranciaCupoPct(new BigDecimal("10.00"));
        return p;
    }
    private Sesion sesion(Horario h, Grupo g, byte dia) {
        var s = new Sesion(); s.setHorario(h); s.setGrupo(g); s.setDia(dia);
        s.setHoraInicio(LocalTime.of(7,0)); s.setHoraFin(LocalTime.of(9,0)); return s;
    }
    private RestriccionHoraria restriccion(Docente docente, byte dia, TipoRestriccion tipo, SentidoRestriccion sentido) {
        var r = new RestriccionHoraria(); r.setDocente(docente); r.setDia(dia);
        r.setHoraInicio(LocalTime.of(9,0)); r.setHoraFin(LocalTime.of(11,0)); r.setTipo(tipo); r.setSentido(sentido); return r;
    }
}
