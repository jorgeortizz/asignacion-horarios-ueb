package co.edu.uelbosque.asignacionhorarios.service;

import static org.junit.jupiter.api.Assertions.*;

import co.edu.uelbosque.asignacionhorarios.dto.Peticiones;
import co.edu.uelbosque.asignacionhorarios.dto.Respuestas;
import co.edu.uelbosque.asignacionhorarios.model.EstadoHorario;
import co.edu.uelbosque.asignacionhorarios.model.SentidoRestriccion;
import co.edu.uelbosque.asignacionhorarios.model.TipoRestriccion;
import co.edu.uelbosque.asignacionhorarios.model.TipoVinculacion;
import co.edu.uelbosque.asignacionhorarios.repository.SesionRepository;
import jakarta.persistence.EntityManager;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

/** Flujos de negocio con persistencia H2 real; cada prueba revierte sus datos. */
@SpringBootTest
@ActiveProfiles("demo")
@Transactional
class FlujoHorarioTests {
    @Autowired private PeriodoService periodos;
    @Autowired private RegistroService registro;
    @Autowired private GeneracionService generacion;
    @Autowired private HorarioService horarios;
    @Autowired private ConsultaService consultas;
    @Autowired private SesionRepository sesiones;
    @Autowired private EntityManager entityManager;

    @Test
    void registraGeneraMuevePublicaYConsultaConFiltrosYCsv() {
        Datos datos = registrar(2);
        var restricciones = registro.restriccionesDocente(datos.docenteId());
        assertEquals(1, restricciones.size());
        assertEquals((byte) 1, restricciones.getFirst().getDia());
        assertEquals(SentidoRestriccion.NO_DISPONIBLE, restricciones.getFirst().getSentido());
        assertEquals(44, registro.gruposPeriodo(datos.periodoId()).getFirst().limiteOperativo());

        var generado = generacion.generar(datos.periodoId());
        persistirYRecargar();
        assertEquals(2, generado.sesionesGeneradas());
        assertTrue(generado.noUbicadas().isEmpty());
        var borrador = horarios.detalle(generado.horarioId());
        assertEquals(EstadoHorario.BORRADOR, borrador.estado());
        assertNotNull(borrador.fechaCreacion());
        assertEquals(2, consultas.consultar(borrador.id(), null, null, false).size());
        assertTrue(consultas.consultar(borrador.id(), null, null, true).isEmpty());

        var sesion = borrador.sesiones().getFirst();
        var movimiento = horarios.mover(borrador.id(), sesion.id(),
            new Peticiones.Movimiento((byte) 6, LocalTime.of(9, 0)));
        assertTrue(movimiento.aplicado());
        assertEquals(LocalTime.of(11, 0), movimiento.sesion().horaFin());
        persistirYRecargar();
        var guardada = sesiones.findById(sesion.id()).orElseThrow();
        assertEquals((byte) 6, guardada.getDia());
        assertEquals(LocalTime.of(9, 0), guardada.getHoraInicio());
        assertEquals(LocalTime.of(11, 0), guardada.getHoraFin());

        var publicado = horarios.publicar(borrador.id());
        persistirYRecargar();
        assertEquals(EstadoHorario.PUBLICADO, publicado.estado());
        assertNotNull(publicado.fechaPublicacion());
        assertEquals(EstadoHorario.PUBLICADO, horarios.detalle(publicado.id()).estado());
        assertEquals(2, consultas.consultar(publicado.id(), datos.docenteId(), datos.cursoId(), true).size());
        assertTrue(consultas.consultar(publicado.id(), Long.MAX_VALUE, null, true).isEmpty());
        assertTrue(consultas.consultar(publicado.id(), null, Long.MAX_VALUE, true).isEmpty());

        String csv = consultas.exportarCsv(publicado.id(), datos.docenteId(), datos.cursoId());
        assertTrue(csv.startsWith("dia,hora_inicio,hora_fin,docente,curso,grupo,necesita_aula_especial\r\n"));
        assertEquals(3, csv.lines().count());
        assertTrue(csv.contains("\"Docente \"\"Prueba\"\", UEB\""));
        assertTrue(csv.contains("\"Programación, \"\"V2\"\"\""));
        assertTrue(csv.contains("6,09:00,11:00,"));
        assertTrue(csv.contains(",true\r\n"));
    }

    @Test
    void unMovimientoBloqueadoNoModificaLaSesionPersistida() {
        Datos datos = registrar(1);
        var generado = generacion.generar(datos.periodoId());
        persistirYRecargar();
        var anterior = horarios.detalle(generado.horarioId()).sesiones().getFirst();

        var movimiento = horarios.mover(generado.horarioId(), anterior.id(),
            new Peticiones.Movimiento((byte) 1, LocalTime.of(7, 0)));

        assertFalse(movimiento.aplicado());
        assertTrue(movimiento.validacion().incidencias().stream()
            .anyMatch(i -> i.codigo().equals("DOCENTE_NO_DISPONIBLE")));
        persistirYRecargar();
        var posterior = sesiones.findById(anterior.id()).orElseThrow();
        assertEquals(anterior.dia(), posterior.getDia());
        assertEquals(anterior.horaInicio(), posterior.getHoraInicio());
        assertEquals(anterior.horaFin(), posterior.getHoraFin());
    }

    @Test
    void unHorarioPublicadoRechazaMovimientos() {
        Datos datos = registrar(1);
        var generado = generacion.generar(datos.periodoId());
        persistirYRecargar();
        var publicado = horarios.publicar(generado.horarioId());
        persistirYRecargar();
        var sesion = publicado.sesiones().getFirst();

        ApiException error = assertThrows(ApiException.class, () -> horarios.mover(publicado.id(), sesion.id(),
            new Peticiones.Movimiento((byte) 6, LocalTime.of(9, 0))));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertTrue(error.getMessage().contains("publicado"));
        var sinCambios = sesiones.findById(sesion.id()).orElseThrow();
        assertEquals(sesion.dia(), sinCambios.getDia());
        assertEquals(sesion.horaInicio(), sinCambios.getHoraInicio());
    }

    @Test
    void laGeneracionParcialInformaFaltantesYNoPermitePublicar() {
        var disponibilidad = new Peticiones.Restriccion((byte) 6, LocalTime.of(9, 0), LocalTime.of(11, 0),
            TipoRestriccion.FIRME, SentidoRestriccion.DISPONIBLE);
        Datos datos = registrar(2, List.of(disponibilidad));

        var generado = generacion.generar(datos.periodoId());
        persistirYRecargar();

        assertEquals(1, generado.sesionesGeneradas());
        assertEquals(1, generado.noUbicadas().size());
        assertEquals(datos.grupoId(), generado.noUbicadas().getFirst().grupoId());
        assertEquals(1, generado.noUbicadas().getFirst().faltantes());
        ApiException error = assertThrows(ApiException.class, () -> horarios.publicar(generado.horarioId()));
        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertTrue(error.getMessage().contains("faltan o sobran sesiones"));
        assertEquals(EstadoHorario.BORRADOR, horarios.detalle(generado.horarioId()).estado());
    }

    @Test
    void laPublicacionRevalidaLosChoquesDocentesEntreGrupos() {
        Datos datos = registrar(1);
        registro.crearGrupo(new Peticiones.Grupo(datos.periodoId(), datos.cursoId(), datos.docenteId(),
            "B", null, null, 20));
        var generado = generacion.generar(datos.periodoId());
        persistirYRecargar();
        assertEquals(2, generado.sesionesGeneradas());
        var actuales = sesiones.findByHorarioIdOrderByDiaAscHoraInicioAsc(generado.horarioId());
        var primera = actuales.getFirst();
        var segunda = actuales.getLast();
        // Simula un borrador importado: el índice permite la misma casilla en grupos distintos.
        segunda.setDia(primera.getDia());
        segunda.setHoraInicio(primera.getHoraInicio());
        segunda.setHoraFin(primera.getHoraFin());
        persistirYRecargar();

        ApiException error = assertThrows(ApiException.class, () -> horarios.publicar(generado.horarioId()));

        assertEquals(HttpStatus.CONFLICT, error.getStatus());
        assertTrue(error.getMessage().contains("ya tiene clase"));
        assertEquals(EstadoHorario.BORRADOR, horarios.detalle(generado.horarioId()).estado());
    }

    private Datos registrar(int frecuencia) {
        return registrar(frecuencia, List.of(new Peticiones.Restriccion((byte) 1,
            LocalTime.of(7, 0), LocalTime.of(9, 0),
            TipoRestriccion.FIRME, SentidoRestriccion.NO_DISPONIBLE)));
    }

    private Datos registrar(int frecuencia, List<Peticiones.Restriccion> restricciones) {
        var periodo = periodos.crear(new Peticiones.Periodo("Prueba flujo V2",
            LocalDate.of(2030, 1, 15), LocalDate.of(2030, 6, 15)));
        var docente = registro.crearDocente(new Peticiones.Docente("Docente \"Prueba\", UEB",
            TipoVinculacion.TC, Set.of("Sistemas"), false, restricciones));
        var curso = registro.crearCurso(new Peticiones.Curso("FLUJO-V2", "Programación, \"V2\"",
            frecuencia, 120, true));
        Respuestas.GrupoDto grupo = registro.crearGrupo(new Peticiones.Grupo(
            periodo.getId(), curso.getId(), docente.getId(), "A", null, null, 20));
        Datos datos = new Datos(periodo.getId(), docente.getId(), curso.getId(), grupo.id());
        persistirYRecargar();
        return datos;
    }

    private void persistirYRecargar() {
        entityManager.flush();
        entityManager.clear();
    }

    private record Datos(Long periodoId, Long docenteId, Long cursoId, Long grupoId) {}
}