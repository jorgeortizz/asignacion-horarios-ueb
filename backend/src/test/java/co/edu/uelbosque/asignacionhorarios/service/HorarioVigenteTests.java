package co.edu.uelbosque.asignacionhorarios.service;

import co.edu.uelbosque.asignacionhorarios.controller.ErroresController;
import co.edu.uelbosque.asignacionhorarios.controller.HorarioController;
import co.edu.uelbosque.asignacionhorarios.model.EstadoHorario;
import co.edu.uelbosque.asignacionhorarios.model.Horario;
import co.edu.uelbosque.asignacionhorarios.model.PeriodoAcademico;
import co.edu.uelbosque.asignacionhorarios.repository.HorarioRepository;
import co.edu.uelbosque.asignacionhorarios.repository.PeriodoAcademicoRepository;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Ejecuta la consulta nativa contra la vista equivalente de H2, sin Flyway. */
@SpringBootTest
@ActiveProfiles("demo")
@Transactional
class HorarioVigenteTests {
    @Autowired private HorarioRepository horarios;
    @Autowired private PeriodoAcademicoRepository periodos;
    @Autowired private HorarioService servicio;

    private PeriodoAcademico periodo(String nombre) {
        var p = new PeriodoAcademico();
        p.setNombre(nombre);
        p.setFechaInicio(LocalDate.of(2026, 7, 1));
        p.setFechaFin(LocalDate.of(2026, 12, 1));
        p.setHoraInicioSemana(LocalTime.of(7, 0));
        p.setHoraFinSemana(LocalTime.of(22, 0));
        p.setHoraInicioSabado(LocalTime.of(7, 0));
        p.setHoraFinSabado(LocalTime.of(13, 0));
        p.setAlmuerzoInicio(LocalTime.of(12, 0));
        p.setAlmuerzoFin(LocalTime.of(13, 0));
        p.setDuracionBloqueMin((short) 120);
        p.setMaxSesionesSemana((byte) 4);
        p.setCupoMaximoBase((short) 40);
        p.setCupoMinimo((short) 10);
        p.setToleranciaCupoPct(new BigDecimal("10.00"));
        return periodos.saveAndFlush(p);
    }

    // Datos de consulta: estas inserciones no ejercitan el flujo de publicar.
    private Horario horario(PeriodoAcademico periodo, EstadoHorario estado, LocalDateTime fecha) {
        var h = new Horario();
        h.setPeriodo(periodo);
        h.setEstado(estado);
        h.setFechaPublicacion(fecha);
        return horarios.saveAndFlush(h);
    }

    @Test
    void eligeUltimaFechaPublicacionAunqueExistaOtroPublicadoConMayorIdYUnBorrador() {
        var p = periodo("vigente-fecha");
        var fecha = LocalDateTime.of(2026, 8, 10, 10, 0);
        var vigente = horario(p, EstadoHorario.PUBLICADO, fecha);
        horario(p, EstadoHorario.PUBLICADO, fecha.minusDays(1));
        horario(p, EstadoHorario.BORRADOR, null);

        assertEquals(vigente.getId(), horarios.findVigenteByPeriodoId(p.getId()).orElseThrow().getId());
        var respuesta = servicio.vigente(p.getId());
        assertEquals(vigente.getId(), respuesta.id());
        assertEquals(EstadoHorario.PUBLICADO, respuesta.estado());
        assertEquals(fecha, respuesta.fechaPublicacion());
    }

    @Test
    void desempataLaMismaFechaDePublicacionConElMayorId() {
        var p = periodo("vigente-empate");
        var fecha = LocalDateTime.of(2026, 8, 10, 10, 0);
        var anterior = horario(p, EstadoHorario.PUBLICADO, fecha);
        var vigente = horario(p, EstadoHorario.PUBLICADO, fecha);

        assertTrue(vigente.getId() > anterior.getId());
        assertEquals(vigente.getId(), horarios.findVigenteByPeriodoId(p.getId()).orElseThrow().getId());
    }

    @Test
    void cadaPeriodoConservaSuPropioPublicadoVigente() {
        var primero = periodo("vigente-primero");
        var segundo = periodo("vigente-segundo");
        var fecha = LocalDateTime.of(2026, 8, 10, 10, 0);
        var h1 = horario(primero, EstadoHorario.PUBLICADO, fecha);
        var h2 = horario(segundo, EstadoHorario.PUBLICADO, fecha.plusDays(1));

        assertEquals(h1.getId(), servicio.vigente(primero.getId()).id());
        assertEquals(h2.getId(), servicio.vigente(segundo.getId()).id());
    }

    @Test
    void unPeriodoConSoloBorradoresNoTieneVigenteYRespondeNoEncontrado() {
        var p = periodo("vigente-borrador");
        horario(p, EstadoHorario.BORRADOR, null);

        assertTrue(horarios.findVigenteByPeriodoId(p.getId()).isEmpty());
        var error = assertThrows(ApiException.class, () -> servicio.vigente(p.getId()));
        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        assertEquals("Horario publicado vigente no encontrado", error.getMessage());
    }

    @Test
    void unPeriodoInexistenteNoTienePublicadoVigente() {
        assertTrue(horarios.findVigenteByPeriodoId(Long.MAX_VALUE).isEmpty());
        assertEquals(HttpStatus.NOT_FOUND,
            assertThrows(ApiException.class, () -> servicio.vigente(Long.MAX_VALUE)).getStatus());
    }

    @Test
    void endpointDePeriodoDevuelveElPublicadoVigente() throws Exception {
        var p = periodo("vigente-endpoint");
        var h = horario(p, EstadoHorario.PUBLICADO, LocalDateTime.of(2026, 8, 10, 10, 0));
        var mvc = MockMvcBuilders.standaloneSetup(new HorarioController(servicio))
            .setControllerAdvice(new ErroresController()).build();

        mvc.perform(get("/api/v1/periodos/{id}/horario-vigente", p.getId()))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.id").value(h.getId()))
            .andExpect(jsonPath("$.periodoId").value(p.getId()))
            .andExpect(jsonPath("$.estado").value("PUBLICADO"));
    }

    @Test
    void endpointDePeriodoSinPublicadoResponde404() throws Exception {
        var p = periodo("vigente-sin-publicar");
        var mvc = MockMvcBuilders.standaloneSetup(new HorarioController(servicio))
            .setControllerAdvice(new ErroresController()).build();

        mvc.perform(get("/api/v1/periodos/{id}/horario-vigente", p.getId()))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.error").value("Horario publicado vigente no encontrado"));
    }
}
