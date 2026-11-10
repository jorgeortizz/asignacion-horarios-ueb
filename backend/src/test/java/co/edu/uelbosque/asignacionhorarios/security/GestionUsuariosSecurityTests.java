package co.edu.uelbosque.asignacionhorarios.security;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.context.WebApplicationContext;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@ActiveProfiles("demo")
class GestionUsuariosSecurityTests {
    @Autowired WebApplicationContext contexto;
    private MockMvc mvc;

    @BeforeEach
    void configurar() {
        mvc = MockMvcBuilders.webAppContextSetup(contexto).apply(springSecurity()).build();
    }

    @Test
    void sinSesionNoAccede() throws Exception {
        mvc.perform(get("/api/v1/admin/usuarios"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void coordinacionNoAccede() throws Exception {
        mvc.perform(get("/api/v1/admin/usuarios")
                .with(user("coordinador").roles("COORDINACION_ACADEMICA")))
            .andExpect(status().isForbidden());
    }

    @Test
    void docenteNoAccede() throws Exception {
        mvc.perform(get("/api/v1/admin/usuarios")
                .with(user("docente").roles("DOCENTE")))
            .andExpect(status().isForbidden());
    }

    @Test
    void comitePuedeListar() throws Exception {
        mvc.perform(get("/api/v1/admin/usuarios")
                .with(user("comite").roles("COMITE_TACTICO")))
            .andExpect(status().isOk());
    }
}
