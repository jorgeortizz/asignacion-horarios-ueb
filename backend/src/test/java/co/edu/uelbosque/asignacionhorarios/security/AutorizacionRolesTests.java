package co.edu.uelbosque.asignacionhorarios.security;

import co.edu.uelbosque.asignacionhorarios.model.*;
import co.edu.uelbosque.asignacionhorarios.repository.RolRepository;
import co.edu.uelbosque.asignacionhorarios.repository.UsuarioRepository;
import jakarta.persistence.EntityManager;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Autorización HTTP y aislamiento de datos con H2 real. No utiliza las credenciales
 * iniciales de MySQL ni desactiva CSRF para probar los POST.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("demo")
@Transactional
class AutorizacionRolesTests {
    @Autowired MockMvc mvc;
    @Autowired EntityManager em;
    @Autowired RolRepository roles;
    @Autowired UsuarioRepository usuarios;
    @Autowired PasswordEncoder encoder;

    private Long periodoPublicadoId;
    private Long periodoBorradorId;
    private Long horarioPublicadoId;
    private Long horarioBorradorId;
    private Long cursoId;
    private Long docenteUnoId;
    private Long docenteDosId;

    @BeforeEach
    void prepararDatos() {
        String sufijo = UUID.randomUUID().toString().substring(0, 8);
        var p1 = periodo("PUB-" + sufijo);
        var p2 = periodo("BOR-" + sufijo);
        periodoPublicadoId = p1.getId();
        periodoBorradorId = p2.getId();

        var curso = new Curso();
        curso.setCodigo("SEG-" + sufijo);
        curso.setNombre("Curso para autorización");
        curso.setSesionesSemanales((byte) 1);
        curso.setDuracionSesionMin((short) 120);
        curso.setNecesitaAulaEspecial(false);
        em.persist(curso);
        em.flush();
        cursoId = curso.getId();

        var docente1 = docente("Docente propietario");
        var docente2 = docente("Docente ajeno");
        docenteUnoId = docente1.getId();
        docenteDosId = docente2.getId();

        var g1 = grupo(p1, curso, docente1, "A");
        var g2 = grupo(p1, curso, docente2, "B");
        var gb = grupo(p2, curso, docente2, "C");

        var publicado = horario(p1, EstadoHorario.PUBLICADO);
        var borrador = horario(p2, EstadoHorario.BORRADOR);
        horarioPublicadoId = publicado.getId();
        horarioBorradorId = borrador.getId();

        sesion(publicado, g1, (byte) 1);
        sesion(publicado, g2, (byte) 2);
        sesion(borrador, gb, (byte) 3);
        em.flush();
    }

    private PeriodoAcademico periodo(String nombre) {
        var p = new PeriodoAcademico();
        p.setNombre(nombre);
        p.setFechaInicio(LocalDate.of(2026, 7, 1));
        p.setFechaFin(LocalDate.of(2026, 12, 1));
        p.setHoraInicioSemana(LocalTime.of(7, 0));
        p.setHoraFinSemana(LocalTime.of(22, 0));
        p.setHoraInicioSabado(LocalTime.of(7, 0));
        p.setHoraFinSabado(LocalTime.of(13, 0));
        p.setAlmuerzoInicio(LocalTime.of(13, 0));
        p.setAlmuerzoFin(LocalTime.of(14, 0));
        p.setDuracionBloqueMin((short) 120);
        p.setMaxSesionesSemana((byte) 4);
        p.setCupoMaximoBase((short) 40);
        p.setCupoMinimo((short) 10);
        p.setToleranciaCupoPct(new BigDecimal("10.00"));
        em.persist(p);
        em.flush();
        return p;
    }

    private Docente docente(String nombre) {
        var d = new Docente();
        d.setNombre(nombre);
        d.setTipoVinculacion(TipoVinculacion.TC);
        em.persist(d);
        em.flush();
        return d;
    }

    private Grupo grupo(PeriodoAcademico p, Curso c, Docente d, String codigo) {
        var g = new Grupo();
        g.setPeriodo(p);
        g.setCurso(c);
        g.setDocente(d);
        g.setCodigo(codigo);
        g.setCupoMaximo((short) 40);
        g.setCupoMinimo((short) 10);
        g.setInscritos((short) 20);
        em.persist(g);
        em.flush();
        return g;
    }

    private Horario horario(PeriodoAcademico p, EstadoHorario estado) {
        var h = new Horario();
        h.setPeriodo(p);
        h.setEstado(estado);
        if (estado == EstadoHorario.PUBLICADO) {
            h.setFechaPublicacion(LocalDateTime.of(2026, 8, 10, 9, 0));
        }
        em.persist(h);
        em.flush();
        return h;
    }

    private void sesion(Horario horario, Grupo grupo, byte dia) {
        var s = new Sesion();
        s.setHorario(horario);
        s.setGrupo(grupo);
        s.setDia(dia);
        s.setHoraInicio(LocalTime.of(9, 0));
        s.setHoraFin(LocalTime.of(11, 0));
        em.persist(s);
    }

    private RequestPostProcessor como(CodigoRol rol, Long docenteId) {
        var principal = new UsuarioPrincipal(88L, "cuenta.prueba", "{bcrypt}solo-prueba",
            true, rol, docenteId);
        var auth = UsernamePasswordAuthenticationToken.authenticated(
            principal, null, principal.getAuthorities());
        return authentication(auth);
    }

    private MockHttpServletRequestBuilder conCsrf(MockHttpServletRequestBuilder req) throws Exception {
        var respuesta = mvc.perform(get("/api/v1/auth/csrf"))
            .andExpect(status().isOk()).andReturn();
        var cookie = respuesta.getResponse().getCookie("XSRF-TOKEN");
        assertNotNull(cookie, "La cookie CSRF debe existir");
        return req.cookie(cookie).header("X-XSRF-TOKEN", cookie.getValue());
    }

    @Test
    void publicoVeUnicamenteElHorarioPublicadoVigente() throws Exception {
        mvc.perform(get("/api/v1/publico/periodos/{id}/horario-vigente", periodoPublicadoId)
                .param("soloPublicados", "false"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.estado").value("PUBLICADO"))
            .andExpect(jsonPath("$.sesiones.length()").value(2));

        mvc.perform(get("/api/v1/publico/periodos/{id}/cursos/{cursoId}/sesiones",
                periodoPublicadoId, cursoId))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(2));

        mvc.perform(get("/api/v1/publico/periodos/{id}/cursos/{cursoId}/sesiones",
                periodoPublicadoId, Long.MAX_VALUE))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void publicoNoPuedeForzarBorradores() throws Exception {
        mvc.perform(get("/api/v1/publico/periodos/{id}/horario-vigente", periodoBorradorId)
                .param("soloPublicados", "false"))
            .andExpect(status().isNotFound());
        mvc.perform(get("/api/v1/publico/periodos/{id}/cursos/{cursoId}/sesiones",
                periodoBorradorId, cursoId))
            .andExpect(status().isNotFound());
    }

    @Test
    void anonimoNoVeLasRutasAdministrativasNiPropias() throws Exception {
        mvc.perform(get("/api/v1/horarios/{id}/sesiones", horarioBorradorId)
                .param("soloPublicados", "false"))
            .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/v1/horarios/{id}/exportar.csv", horarioPublicadoId))
            .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/v1/docentes/me/horario-publicado")
                .param("periodoId", periodoPublicadoId.toString()))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void docenteVeSoloSusSesionesAunqueIntenteElegirOtroId() throws Exception {
        mvc.perform(get("/api/v1/docentes/me/horario-publicado")
                .param("periodoId", periodoPublicadoId.toString())
                .param("docenteId", docenteDosId.toString())
                .with(como(CodigoRol.DOCENTE, docenteUnoId)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.docenteId").value(docenteUnoId))
            .andExpect(jsonPath("$.sesiones.length()").value(1))
            .andExpect(jsonPath("$.sesiones[0].docenteId").value(docenteUnoId));

        mvc.perform(get("/api/v1/docentes/me/horario-publicado")
                .param("periodoId", periodoBorradorId.toString())
                .with(como(CodigoRol.DOCENTE, docenteUnoId)))
            .andExpect(status().isNotFound());

        mvc.perform(get("/api/v1/docentes").with(como(CodigoRol.DOCENTE, docenteUnoId)))
            .andExpect(status().isForbidden());
    }

    @Test
    void estudianteSoloPuedeConsultarPublicado() throws Exception {
        mvc.perform(get("/api/v1/publico/periodos/{id}/horario-vigente", periodoPublicadoId)
                .with(como(CodigoRol.ESTUDIANTE, null)))
            .andExpect(status().isOk());
        mvc.perform(get("/api/v1/horarios/{id}", horarioBorradorId)
                .with(como(CodigoRol.ESTUDIANTE, null)))
            .andExpect(status().isForbidden());
        mvc.perform(get("/api/v1/docentes/me/horario-publicado")
                .param("periodoId", periodoPublicadoId.toString())
                .with(como(CodigoRol.ESTUDIANTE, null)))
            .andExpect(status().isForbidden());
    }

    @Test
    void coordinacionVeBorradoresPeroNoPublicaNiCreaCuentas() throws Exception {
        mvc.perform(get("/api/v1/horarios/{id}/sesiones", horarioBorradorId)
                .param("soloPublicados", "false")
                .with(como(CodigoRol.COORDINACION_ACADEMICA, null)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.length()").value(1));

        mvc.perform(conCsrf(post("/api/v1/horarios/{id}/publicar", horarioBorradorId)
                .with(como(CodigoRol.COORDINACION_ACADEMICA, null))))
            .andExpect(status().isForbidden());

        mvc.perform(conCsrf(post("/api/v1/usuarios")
                .with(como(CodigoRol.COORDINACION_ACADEMICA, null))
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"identificador\":\"nuevo\",\"password\":\"ClaveSegura123!\",\"rol\":\"ESTUDIANTE\"}")))
            .andExpect(status().isForbidden());
    }

    @Test
    void comiteCreaCuentaConBcryptSinDevolverHash() throws Exception {
        roles.saveAndFlush(new Rol(CodigoRol.ESTUDIANTE, "Estudiante"));
        String identificador = "est-" + UUID.randomUUID() + "@ejemplo.test";
        String json = "{\"identificador\":\"" + identificador + "\","
            + "\"password\":\"ClaveSegura123!\",\"rol\":\"ESTUDIANTE\"}";
        mvc.perform(conCsrf(post("/api/v1/usuarios")
                .with(como(CodigoRol.COMITE_TACTICO, null))
                .contentType(MediaType.APPLICATION_JSON).content(json)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.rol").value("ESTUDIANTE"))
            .andExpect(jsonPath("$.passwordHash").doesNotExist());

        var creada = usuarios.findByIdentificadorIgnoreCase(identificador).orElseThrow();
        assertTrue(encoder.matches("ClaveSegura123!", creada.getPasswordHash()));
        assertNotEquals("ClaveSegura123!", creada.getPasswordHash());
    }

    @Test
    void cuentaDocenteExigeAsociacionYNoPermiteDuplicarla() throws Exception {
        roles.saveAndFlush(new Rol(CodigoRol.DOCENTE, "Docente"));
        String base = "doc-" + UUID.randomUUID() + "@ejemplo.test";
        String sinAsociacion = "{\"identificador\":\"" + base + "\","
            + "\"password\":\"ClaveSegura123!\",\"rol\":\"DOCENTE\"}";
        mvc.perform(conCsrf(post("/api/v1/usuarios")
                .with(como(CodigoRol.COMITE_TACTICO, null))
                .contentType(MediaType.APPLICATION_JSON).content(sinAsociacion)))
            .andExpect(status().isBadRequest());

        String valido = "{\"identificador\":\"" + base + "\","
            + "\"password\":\"ClaveSegura123!\",\"rol\":\"DOCENTE\","
            + "\"docenteId\":" + docenteUnoId + "}";
        mvc.perform(conCsrf(post("/api/v1/usuarios")
                .with(como(CodigoRol.COMITE_TACTICO, null))
                .contentType(MediaType.APPLICATION_JSON).content(valido)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.docenteId").value(docenteUnoId));

        mvc.perform(conCsrf(post("/api/v1/usuarios")
                .with(como(CodigoRol.COMITE_TACTICO, null))
                .contentType(MediaType.APPLICATION_JSON)
                .content(valido.replace(base, "otro-" + base))))
            .andExpect(status().isConflict());
    }

    @Test
    void cursoCsvPublicoNoExponeBorradoresNiElCsvAdministrativo() throws Exception {
        mvc.perform(get("/api/v1/publico/periodos/{id}/cursos/{cursoId}/exportar.csv",
                periodoPublicadoId, cursoId))
            .andExpect(status().isOk())
            .andExpect(content().contentTypeCompatibleWith("text/csv"))
            .andExpect(content().string(org.hamcrest.Matchers.containsString("Docente propietario")));

        mvc.perform(get("/api/v1/publico/periodos/{id}/cursos/{cursoId}/exportar.csv",
                periodoBorradorId, cursoId))
            .andExpect(status().isNotFound());
    }
}
