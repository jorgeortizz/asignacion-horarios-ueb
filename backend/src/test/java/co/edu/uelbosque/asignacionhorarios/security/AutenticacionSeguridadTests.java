package co.edu.uelbosque.asignacionhorarios.security;

import co.edu.uelbosque.asignacionhorarios.model.CodigoRol;
import co.edu.uelbosque.asignacionhorarios.model.Docente;
import co.edu.uelbosque.asignacionhorarios.model.TipoVinculacion;
import jakarta.persistence.EntityManager;
import co.edu.uelbosque.asignacionhorarios.model.Rol;
import co.edu.uelbosque.asignacionhorarios.model.Usuario;
import co.edu.uelbosque.asignacionhorarios.repository.RolRepository;
import co.edu.uelbosque.asignacionhorarios.repository.UsuarioRepository;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("demo")
@Transactional
class AutenticacionSeguridadTests {
    @Autowired MockMvc mvc;
    @Autowired RolRepository roles;
    @Autowired UsuarioRepository usuarios;
    @Autowired PasswordEncoder encoder;
    @Autowired EntityManager em;

    private final String clave = "PruebaSegura123!!";
    private String identificador;

    @BeforeEach
    void prepararCuentaComite() {
        identificador = "comite-" + UUID.randomUUID() + "@ejemplo.test";
        var rol = roles.saveAndFlush(new Rol(CodigoRol.COMITE_TACTICO, "Comité Táctico"));
        usuarios.saveAndFlush(new Usuario(identificador, encoder.encode(clave), rol, null));
    }

    private String json(String nombre, String password) {
        return "{\"identificador\":\"" + nombre + "\",\"password\":\"" + password + "\"}";
    }

    /**
     * Reproduce el flujo de Angular: GET /csrf recibe XSRF-TOKEN y
     * el siguiente POST devuelve ese valor mediante X-XSRF-TOKEN.
     * No utiliza el token artificial de SecurityMockMvcRequestPostProcessors.csrf().
     */
    private MockHttpServletRequestBuilder conCsrf(
            MockHttpServletRequestBuilder peticion, MockHttpSession sesion) throws Exception {
        var obtenerToken = get("/api/v1/auth/csrf");
        if (sesion != null) {
            obtenerToken.session(sesion);
            peticion.session(sesion);
        }
        var resultado = mvc.perform(obtenerToken)
            .andExpect(status().isOk())
            .andReturn();
        var cookie = resultado.getResponse().getCookie("XSRF-TOKEN");
        assertNotNull(cookie, "GET /auth/csrf debe emitir la cookie XSRF-TOKEN");
        return peticion.cookie(cookie)
            .header("X-XSRF-TOKEN", cookie.getValue());
    }

    private MvcResult login(String nombre, String password) throws Exception {
        return mvc.perform(conCsrf(post("/api/v1/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(json(nombre, password)), null))
            .andExpect(status().isOk()).andReturn();
    }

    @Test
    void csrfSePuedeSolicitarSinAutenticarse() throws Exception {
        mvc.perform(get("/api/v1/auth/csrf"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.headerName").value("X-XSRF-TOKEN"))
            .andExpect(jsonPath("$.token").isNotEmpty());
    }

    @Test
    void loginRechazaPostSinCsrf() throws Exception {
        mvc.perform(post("/api/v1/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(json(identificador, clave)))
            .andExpect(status().isForbidden());
    }

    @Test
    void loginConClaveIncorrectaNoDaSesion() throws Exception {
        mvc.perform(conCsrf(post("/api/v1/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(json(identificador, "incorrecta")), null))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void loginConsultaMeYLogoutFuncionanConSesion() throws Exception {
        var acceso = login(identificador.toUpperCase(), clave);
        assertNotNull(acceso.getRequest().getSession(false));
        var sesion = (MockHttpSession) acceso.getRequest().getSession(false);
        mvc.perform(get("/api/v1/auth/me").session(sesion))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.identificador").value(identificador))
            .andExpect(jsonPath("$.rol").value("COMITE_TACTICO"))
            .andExpect(jsonPath("$.passwordHash").doesNotExist());
        mvc.perform(conCsrf(post("/api/v1/auth/logout"), sesion))
            .andExpect(status().isNoContent());
        assertTrue(sesion.isInvalid());
    }

    @Test
    void cuentaDesactivadaNoAutentica() throws Exception {
        var cuenta = usuarios.findByIdentificadorIgnoreCase(identificador).orElseThrow();
        cuenta.setActivo(false);
        usuarios.saveAndFlush(cuenta);
        mvc.perform(conCsrf(post("/api/v1/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(json(identificador, clave)), null))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void anonimoNoPuedeUsarEndpointsAdministrativos() throws Exception {
        mvc.perform(get("/api/v1/docentes"))
            .andExpect(status().isUnauthorized());
        mvc.perform(get("/api/v1/horarios/1/sesiones?soloPublicados=false"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void coordinacionNoPuedePublicarNiConSesionAutenticada() throws Exception {
        var rol = roles.saveAndFlush(new Rol(CodigoRol.COORDINACION_ACADEMICA, "Coordinación"));
        var nombre = "coord-" + UUID.randomUUID() + "@ejemplo.test";
        usuarios.saveAndFlush(new Usuario(nombre, encoder.encode(clave), rol, null));
        var acceso = login(nombre, clave);
        var sesion = (MockHttpSession) acceso.getRequest().getSession(false);
        mvc.perform(conCsrf(post("/api/v1/horarios/999999/publicar"), sesion))
            .andExpect(status().isForbidden());
    }

    @Test
    void cuentaDocenteRecuperaSuIdAcademicoPeroNoAccedeALaAdministracion() throws Exception {
        var rol = roles.saveAndFlush(new Rol(CodigoRol.DOCENTE, "Docente"));
        var docente = new Docente();
        docente.setNombre("Docente de prueba autenticado");
        docente.setTipoVinculacion(TipoVinculacion.TC);
        em.persist(docente);
        em.flush();
        var nombre = "docente-" + UUID.randomUUID() + "@ejemplo.test";
        usuarios.saveAndFlush(new Usuario(nombre, encoder.encode(clave), rol, docente));
        var acceso = login(nombre, clave);
        var sesion = (MockHttpSession) acceso.getRequest().getSession(false);
        mvc.perform(get("/api/v1/auth/me").session(sesion))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.rol").value("DOCENTE"))
            .andExpect(jsonPath("$.docenteId").value(docente.getId()));
        mvc.perform(get("/api/v1/docentes").session(sesion))
            .andExpect(status().isForbidden());
    }

    @Test
    void comiteSiPasaLaAutorizacionDePublicacion() throws Exception {
        var acceso = login(identificador, clave);
        var sesion = (MockHttpSession) acceso.getRequest().getSession(false);
        // 404 de negocio: la autorización pasó, pero el horario no existe.
        mvc.perform(conCsrf(post("/api/v1/horarios/999999/publicar"), sesion))
            .andExpect(status().isNotFound());
    }
}
