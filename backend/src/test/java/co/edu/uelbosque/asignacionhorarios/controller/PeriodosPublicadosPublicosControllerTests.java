package co.edu.uelbosque.asignacionhorarios.controller;

import co.edu.uelbosque.asignacionhorarios.model.EstadoHorario;
import co.edu.uelbosque.asignacionhorarios.model.Horario;
import co.edu.uelbosque.asignacionhorarios.model.PeriodoAcademico;
import co.edu.uelbosque.asignacionhorarios.repository.HorarioRepository;
import co.edu.uelbosque.asignacionhorarios.repository.PeriodoAcademicoRepository;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@ActiveProfiles("demo")
@Transactional
class PeriodosPublicadosPublicosControllerTests {
    @Autowired private PeriodosPublicadosPublicosController controller;
    @Autowired private PeriodoAcademicoRepository periodos;
    @Autowired private HorarioRepository horarios;
    @Autowired private JdbcTemplate jdbc;

    private PeriodoAcademico periodo() {
        var p = new PeriodoAcademico();
        p.setNombre("UAT-" + UUID.randomUUID().toString().substring(0, 12));
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
        return periodos.saveAndFlush(p);
    }

    private void horario(PeriodoAcademico p, EstadoHorario estado) {
        var h = new Horario();
        h.setPeriodo(p);
        h.setEstado(estado);
        if (estado == EstadoHorario.PUBLICADO) h.setFechaPublicacion(LocalDateTime.of(2026, 11, 9, 10, 0));
        horarios.saveAndFlush(h);
    }

    @Test
    void listaPeriodosPublicadosSinExponerBorradores() {
        var publicado = periodo();
        var borrador = periodo();
        horario(publicado, EstadoHorario.PUBLICADO);
        horario(borrador, EstadoHorario.BORRADOR);

        var respuesta = controller.listar();
        assertEquals(200, respuesta.getStatusCode().value());
        assertNotNull(respuesta.getBody());
        assertTrue(respuesta.getBody().stream().anyMatch(p -> p.id().equals(publicado.getId())));
        assertTrue(respuesta.getBody().stream().noneMatch(p -> p.id().equals(borrador.getId())));
        assertTrue(respuesta.getHeaders().getCacheControl().contains("no-store"));
    }

    @Test
    void getDevuelveListaDeObjetosConIdYNombre() throws Exception {
        var publicado = periodo();
        horario(publicado, EstadoHorario.PUBLICADO);
        var mvc = MockMvcBuilders.standaloneSetup(new PeriodosPublicadosPublicosController(jdbc)).build();
        mvc.perform(get("/api/v1/publico/periodos-publicados"))
            .andExpect(status().isOk())
            .andExpect(content().contentTypeCompatibleWith("application/json"))
            .andExpect(header().exists(HttpHeaders.CACHE_CONTROL));
    }
}
