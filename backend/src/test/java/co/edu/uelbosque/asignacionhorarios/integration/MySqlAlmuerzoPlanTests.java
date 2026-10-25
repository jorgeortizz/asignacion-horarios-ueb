package co.edu.uelbosque.asignacionhorarios.integration;

import co.edu.uelbosque.asignacionhorarios.model.*;
import co.edu.uelbosque.asignacionhorarios.service.Util;
import co.edu.uelbosque.asignacionhorarios.validation.*;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.*;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.annotation.Rollback;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.*;

/** Comprueba una propuesta en copias Java; solo ejecuta SELECT sobre MySQL. */
@EnabledIfEnvironmentVariable(named="MYSQL_ALMUERZO_PLAN", matches="true")
@ActiveProfiles("mysql")
@SpringBootTest(properties={
    "spring.datasource.url=${MYSQL_TEST_URL}",
    "spring.datasource.username=${MYSQL_TEST_USER}",
    "spring.datasource.password=${MYSQL_TEST_PASSWORD}",
    "spring.jpa.hibernate.ddl-auto=validate",
    "spring.flyway.enabled=false",
    "spring.sql.init.mode=never",
    "spring.jpa.defer-datasource-initialization=false"
})
@Transactional(readOnly=true, isolation=Isolation.REPEATABLE_READ)
@Rollback
class MySqlAlmuerzoPlanTests {
    @Autowired ApplicationContext context;
    @Autowired JdbcTemplate jdbc;
    @Autowired ValidadorHorario validador;

    @Test void verificaLasCincoReubicacionesSinModificarLaBase() {
        assertTrue(context.getBeansOfType(Flyway.class).isEmpty());
        var antes = instantanea();
        var periodo = jdbc.queryForObject("SELECT * FROM periodo_academico WHERE nombre = '2026-2'",
            (rs, n) -> periodo(rs));
        assertNotNull(periodo);
        assertEquals(LocalTime.of(12,0), periodo.getAlmuerzoInicio(), "Se comprueba el escenario previo al ajuste");
        assertEquals(LocalTime.of(13,0), periodo.getAlmuerzoFin());
        assertEquals(120, periodo.getDuracionBloqueMin());
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM horario WHERE periodo_id = ? AND estado = 'PUBLICADO'",
            Integer.class, periodo.getId()), "El periodo objetivo debe seguir sin publicados");
        var horario = jdbc.queryForObject("SELECT * FROM horario WHERE id = 2 AND periodo_id = ?",
            (rs, n) -> horario(rs, periodo), periodo.getId());
        assertNotNull(horario);
        assertEquals(EstadoHorario.BORRADOR, horario.getEstado());

        var cursos = porId(jdbc.query("""
            SELECT c.* FROM curso c WHERE EXISTS
              (SELECT 1 FROM grupo g WHERE g.curso_id = c.id AND g.periodo_id = ?)
            """, (rs, n) -> curso(rs), periodo.getId()), Curso::getId);
        var docentes = porId(jdbc.query("""
            SELECT d.* FROM docente d WHERE EXISTS
              (SELECT 1 FROM grupo g WHERE g.docente_id = d.id AND g.periodo_id = ?)
            """, (rs, n) -> docente(rs), periodo.getId()), Docente::getId);
        var grupos = porId(jdbc.query("SELECT * FROM grupo WHERE periodo_id = ? ORDER BY id",
            (rs, n) -> grupo(rs, periodo, cursos, docentes), periodo.getId()), Grupo::getId);
        var restricciones = jdbc.query("""
            SELECT r.* FROM restriccion_horaria r WHERE EXISTS
              (SELECT 1 FROM grupo g WHERE g.docente_id = r.docente_id AND g.periodo_id = ?)
            ORDER BY r.id
            """, (rs, n) -> restriccion(rs, docentes), periodo.getId());
        var originales = jdbc.query("SELECT * FROM sesion WHERE horario_id = ? ORDER BY id",
            (rs, n) -> sesion(rs, horario, grupos), horario.getId());
        assertEquals(24, originales.size(), "La auditoría recibida describe 24 sesiones del borrador");
        var afectadas = originales.stream().filter(s ->
            s.getHoraInicio().isBefore(LocalTime.of(14,0)) && s.getHoraFin().isAfter(LocalTime.of(13,0)))
            .map(Sesion::getId).collect(Collectors.toSet());
        assertEquals(5, afectadas.size(), "La propuesta requiere revisar exactamente las cinco sesiones notificadas");

        // Son objetos nuevos, creados con JDBC, sin EntityManager ni repositorios JPA.
        var propuestas = originales.stream().map(s -> copia(s, afectadas.contains(s.getId()))).toList();
        assertEquals(originales.stream().map(Sesion::getId).toList(), propuestas.stream().map(Sesion::getId).toList());
        assertEquals(frecuencias(originales), frecuencias(propuestas));
        for (int i=0; i<originales.size(); i++) {
            var anterior = originales.get(i);
            var propuesta = propuestas.get(i);
            assertEquals(anterior.getDia(), propuesta.getDia());
            assertEquals(anterior.getGrupo().getId(), propuesta.getGrupo().getId());
            if (afectadas.contains(anterior.getId())) {
                System.out.printf("PROPUESTA sesion=%d curso=%s grupo=%d/%s docente=%d/%s dia=%d %s-%s -> %s-%s%n",
                    anterior.getId(), anterior.getGrupo().getCurso().getNombre(), anterior.getGrupo().getId(),
                    anterior.getGrupo().getCodigo(), anterior.getGrupo().getDocente().getId(),
                    anterior.getGrupo().getDocente().getNombre(), anterior.getDia(),
                    anterior.getHoraInicio(), anterior.getHoraFin(), propuesta.getHoraInicio(), propuesta.getHoraFin());
            } else {
                assertEquals(anterior.getHoraInicio(), propuesta.getHoraInicio());
                assertEquals(anterior.getHoraFin(), propuesta.getHoraFin());
            }
        }
        for (var g : grupos.values()) {
            assertEquals(periodo.getId(), g.getPeriodo().getId());
            assertTrue(g.getCurso().getSesionesSemanales() <= periodo.getMaxSesionesSemana(), "Frecuencia máxima grupo " + g.getId());
            assertEquals(periodo.getDuracionBloqueMin(), g.getCurso().getDuracionSesionMin());
            assertTrue(g.getInscritos() <= Util.limiteOperativo(g), "Cupo grupo " + g.getId());
            long cantidad = frecuencias(propuestas).getOrDefault(g.getId(), 0L);
            assertTrue(cantidad <= g.getCurso().getSesionesSemanales(), "Sobran sesiones en grupo " + g.getId());
            if (cantidad < g.getCurso().getSesionesSemanales()) {
                System.out.printf("PENDIENTE_PREEXISTENTE grupo=%d frecuencia=%d/%d; resolver el almuerzo no completa el horario.%n",
                    g.getId(), cantidad, g.getCurso().getSesionesSemanales());
            }
        }

        verificarConjunto("almuerzo actual 12-13", horario, propuestas, restricciones);
        periodo.setAlmuerzoInicio(LocalTime.of(13,0));
        periodo.setAlmuerzoFin(LocalTime.of(14,0));
        verificarConjunto("almuerzo propuesto 13-14", horario, propuestas, restricciones);
        assertEquals(antes, instantanea(), "La comprobación no modifica periodos, horarios ni sesiones de la base");
        System.out.println("PLAN VERIFICADO SOLO EN MEMORIA: no se aplicaron reubicaciones ni V3.");
    }

    private void verificarConjunto(String escenario, Horario h, List<Sesion> plan, List<RestriccionHoraria> restricciones) {
        var bloqueos = new ArrayList<String>();
        for (var s : plan) {
            assertEquals(120, Duration.between(s.getHoraInicio(),s.getHoraFin()).toMinutes());
            assertEquals(h.getPeriodo().getId(),s.getGrupo().getPeriodo().getId());
            var resultado = validador.validar(new ContextoValidacion(h,s.getGrupo(),s.getDia(),
                s.getHoraInicio(),s.getHoraFin(),s.getId(),plan,restricciones.stream()
                    .filter(r -> r.getDocente().getId().equals(s.getGrupo().getDocente().getId())).toList()));
            for (var incidencia : resultado.incidencias()) {
                var detalle = escenario + " sesion=" + s.getId() + " " + incidencia.codigo() + ": " + incidencia.motivo();
                if (incidencia.nivel()==Nivel.BLOQUEO) bloqueos.add(detalle);
                else System.out.println("ADVERTENCIA " + detalle);
            }
        }
        assertTrue(bloqueos.isEmpty(), String.join("\n",bloqueos));
    }

    private List<List<Map<String,Object>>> instantanea() {
        // Incluye íntegros el histórico y el borrador, sin asumir IDs de sesiones.
        return List.of(jdbc.queryForList("SELECT * FROM periodo_academico ORDER BY id"),
            jdbc.queryForList("SELECT * FROM horario ORDER BY id"),
            jdbc.queryForList("SELECT * FROM sesion ORDER BY id"));
    }

    private static Map<Long,Long> frecuencias(List<Sesion> sesiones) {
        return sesiones.stream().collect(Collectors.groupingBy(s -> s.getGrupo().getId(),Collectors.counting()));
    }
    private static <T> Map<Long,T> porId(List<T> filas, Function<T,Long> id) {
        return filas.stream().collect(Collectors.toMap(id,Function.identity()));
    }
    private static <T> T conId(T entidad, long id) {
        ReflectionTestUtils.setField(entidad,"id",id);
        return entidad;
    }
    private static PeriodoAcademico periodo(ResultSet rs) throws SQLException {
        var p=conId(new PeriodoAcademico(),rs.getLong("id"));
        p.setNombre(rs.getString("nombre"));
        p.setHoraInicioSemana(rs.getObject("hora_inicio_semana",LocalTime.class));
        p.setHoraFinSemana(rs.getObject("hora_fin_semana",LocalTime.class));
        p.setHoraInicioSabado(rs.getObject("hora_inicio_sabado",LocalTime.class));
        p.setHoraFinSabado(rs.getObject("hora_fin_sabado",LocalTime.class));
        p.setAlmuerzoInicio(rs.getObject("almuerzo_inicio",LocalTime.class));
        p.setAlmuerzoFin(rs.getObject("almuerzo_fin",LocalTime.class));
        p.setDuracionBloqueMin(rs.getShort("duracion_bloque_min"));
        p.setMaxSesionesSemana(rs.getByte("max_sesiones_semana"));
        p.setToleranciaCupoPct(rs.getBigDecimal("tolerancia_cupo_pct"));
        return p;
    }
    private static Horario horario(ResultSet rs, PeriodoAcademico p) throws SQLException {
        var h=conId(new Horario(),rs.getLong("id"));
        h.setPeriodo(p);h.setEstado(EstadoHorario.valueOf(rs.getString("estado")));
        h.setFechaCreacion(rs.getObject("fecha_creacion",LocalDateTime.class));
        h.setFechaPublicacion(rs.getObject("fecha_publicacion",LocalDateTime.class));
        h.setVersion(rs.getInt("version"));return h;
    }
    private static Curso curso(ResultSet rs) throws SQLException {
        var c=conId(new Curso(),rs.getLong("id"));
        c.setNombre(rs.getString("nombre"));c.setCodigo(rs.getString("codigo"));
        c.setSesionesSemanales(rs.getByte("sesiones_semanales"));
        c.setDuracionSesionMin(rs.getShort("duracion_sesion_min"));
        c.setNecesitaAulaEspecial(rs.getBoolean("necesita_aula_especial"));return c;
    }
    private static Docente docente(ResultSet rs) throws SQLException {
        var d=conId(new Docente(),rs.getLong("id"));d.setNombre(rs.getString("nombre"));
        d.setTipoVinculacion(TipoVinculacion.valueOf(rs.getString("tipo_vinculacion")));return d;
    }
    private static Grupo grupo(ResultSet rs,PeriodoAcademico p,Map<Long,Curso> cursos,Map<Long,Docente> docentes) throws SQLException {
        var g=conId(new Grupo(),rs.getLong("id"));g.setPeriodo(p);
        g.setCurso(cursos.get(rs.getLong("curso_id")));g.setDocente(docentes.get(rs.getLong("docente_id")));
        g.setCodigo(rs.getString("codigo"));g.setCupoMaximo(rs.getShort("cupo_maximo"));
        g.setCupoMinimo(rs.getShort("cupo_minimo"));g.setInscritos(rs.getShort("inscritos"));return g;
    }
    private static RestriccionHoraria restriccion(ResultSet rs,Map<Long,Docente> docentes) throws SQLException {
        var r=conId(new RestriccionHoraria(),rs.getLong("id"));r.setDocente(docentes.get(rs.getLong("docente_id")));
        r.setDia(rs.getByte("dia"));r.setHoraInicio(rs.getObject("hora_inicio",LocalTime.class));
        r.setHoraFin(rs.getObject("hora_fin",LocalTime.class));
        r.setTipo(TipoRestriccion.valueOf(rs.getString("tipo")));
        r.setSentido(SentidoRestriccion.valueOf(rs.getString("sentido")));return r;
    }
    private static Sesion sesion(ResultSet rs,Horario h,Map<Long,Grupo> grupos) throws SQLException {
        var s=conId(new Sesion(),rs.getLong("id"));s.setHorario(h);s.setGrupo(grupos.get(rs.getLong("grupo_id")));
        s.setDia(rs.getByte("dia"));s.setHoraInicio(rs.getObject("hora_inicio",LocalTime.class));
        s.setHoraFin(rs.getObject("hora_fin",LocalTime.class));return s;
    }
    private static Sesion copia(Sesion original,boolean reubicar) {
        var s=conId(new Sesion(),original.getId());s.setHorario(original.getHorario());s.setGrupo(original.getGrupo());
        s.setDia(original.getDia());s.setHoraInicio(reubicar?LocalTime.of(15,0):original.getHoraInicio());
        s.setHoraFin(reubicar?LocalTime.of(17,0):original.getHoraFin());return s;
    }
}
