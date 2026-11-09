package co.edu.uelbosque.asignacionhorarios.service;

import static org.junit.jupiter.api.Assertions.*;

import co.edu.uelbosque.asignacionhorarios.dto.Peticiones;
import co.edu.uelbosque.asignacionhorarios.model.EstadoHorario;
import co.edu.uelbosque.asignacionhorarios.model.Horario;
import co.edu.uelbosque.asignacionhorarios.repository.HorarioRepository;
import co.edu.uelbosque.asignacionhorarios.repository.PeriodoAcademicoRepository;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Regresion de bloqueo de filas y control de versiones con H2 real.
 * No usa MySQL y no se marca @Transactional: las tareas necesitan transacciones
 * independientes para que el bloqueo de la base tenga efecto.
 */
@SpringBootTest
@ActiveProfiles("demo")
class HorarioConcurrenciaTests {

    @Autowired private HorarioRepository horarios;
    @Autowired private PeriodoAcademicoRepository periodos;
    @Autowired private PeriodoService periodoService;
    @Autowired private HorarioService horarioService;
    @Autowired private PlatformTransactionManager transactionManager;

    private Long horarioCreado;
    private Long periodoCreado;

    private Long crearBorrador() {
        var periodo = periodoService.crear(new Peticiones.Periodo(
                "concur-" + UUID.randomUUID().toString().substring(0, 12),
                LocalDate.of(2032, 1, 15), LocalDate.of(2032, 6, 15)));
        periodoCreado = periodo.getId();
        var horario = new Horario();
        horario.setPeriodo(periodo);
        horario.setEstado(EstadoHorario.BORRADOR);
        horarioCreado = horarios.saveAndFlush(horario).getId();
        return horarioCreado;
    }

    @AfterEach
    void borrarDatosAislados() {
        // Se crearon solo un periodo y un horario, sin grupos ni sesiones.
        if (horarioCreado != null) horarios.deleteById(horarioCreado);
        if (periodoCreado != null) periodos.deleteById(periodoCreado);
    }

    @ParameterizedTest(name = "La operacion {0} espera el bloqueo y rechaza el publicado")
    @ValueSource(strings = {"mover", "publicar"})
    void publicacionConcurrenteImpideEditarORepetirLaPublicacion(String operacion) throws Exception {
        Long id = crearBorrador();
        var bloqueoAdquirido = new CountDownLatch(1);
        var liberarBloqueo = new CountDownLatch(1);
        var segundaIniciada = new CountDownLatch(1);
        var ejecutor = Executors.newFixedThreadPool(2);

        try {
            var primera = ejecutor.submit(() -> {
                new TransactionTemplate(transactionManager).executeWithoutResult(tx -> {
                    var horario = horarios.bloquear(id).orElseThrow();
                    bloqueoAdquirido.countDown();
                    try {
                        if (!liberarBloqueo.await(10, TimeUnit.SECONDS)) {
                            throw new AssertionError("No se libero a tiempo el bloqueo de prueba");
                        }
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        throw new AssertionError("Se interrumpio la prueba", e);
                    }
                    // Simula que otra operacion termina la publicacion mientras
                    // la peticion competidora espera la misma fila.
                    horario.setEstado(EstadoHorario.PUBLICADO);
                    horario.setFechaPublicacion(LocalDateTime.now());
                    horarios.saveAndFlush(horario);
                });
            });
            assertTrue(bloqueoAdquirido.await(10, TimeUnit.SECONDS),
                    "La primera transaccion no obtuvo el bloqueo");

            var segunda = ejecutor.submit(() -> {
                segundaIniciada.countDown();
                return assertThrows(ApiException.class, () -> {
                    if ("mover".equals(operacion)) {
                        // El estado se verifica ANTES de buscar esta sesion inexistente.
                        horarioService.mover(id, -1L,
                                new Peticiones.Movimiento((byte) 1, LocalTime.of(9, 0)));
                    } else {
                        horarioService.publicar(id);
                    }
                });
            });

            assertTrue(segundaIniciada.await(10, TimeUnit.SECONDS));
            assertThrows(TimeoutException.class,
                    () -> segunda.get(300, TimeUnit.MILLISECONDS),
                    "La peticion concurrente no debio terminar mientras la fila estaba bloqueada");

            liberarBloqueo.countDown();
            primera.get(10, TimeUnit.SECONDS);
            var rechazo = segunda.get(10, TimeUnit.SECONDS);
            assertEquals(HttpStatus.CONFLICT, rechazo.getStatus());
            var guardado = horarios.findById(id).orElseThrow();
            assertEquals(EstadoHorario.PUBLICADO, guardado.getEstado());
            assertNotNull(guardado.getFechaPublicacion());
        } finally {
            liberarBloqueo.countDown();
            ejecutor.shutdownNow();
            assertTrue(ejecutor.awaitTermination(10, TimeUnit.SECONDS),
                    "Las tareas concurrentes no terminaron");
        }
    }

    @Test
    void versionOptimistaImpideSobrescribirUnHorarioDesactualizado() {
        Long id = crearBorrador();
        var transaccion = new TransactionTemplate(transactionManager);

        // Leemos una instancia y cerramos su transaccion: queda desasociada.
        var desactualizado = transaccion.execute(tx -> horarios.findById(id).orElseThrow());
        assertNotNull(desactualizado);
        int versionAnterior = desactualizado.getVersion();

        transaccion.executeWithoutResult(tx -> {
            var actual = horarios.findById(id).orElseThrow();
            actual.setEstado(EstadoHorario.PUBLICADO);
            actual.setFechaPublicacion(LocalDateTime.now());
            horarios.saveAndFlush(actual);
        });

        // Un segundo intento conserva la version antigua y no debe prevalecer.
        desactualizado.setEstado(EstadoHorario.BORRADOR);
        desactualizado.setFechaPublicacion(LocalDateTime.now().plusDays(1));
        assertThrows(OptimisticLockingFailureException.class,
                () -> transaccion.executeWithoutResult(tx -> horarios.saveAndFlush(desactualizado)));

        var guardado = horarios.findById(id).orElseThrow();
        assertEquals(EstadoHorario.PUBLICADO, guardado.getEstado());
        assertEquals(versionAnterior + 1, guardado.getVersion());
    }
}
