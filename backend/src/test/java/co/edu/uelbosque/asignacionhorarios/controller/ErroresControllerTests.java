package co.edu.uelbosque.asignacionhorarios.controller;

import static org.junit.jupiter.api.Assertions.*;

import co.edu.uelbosque.asignacionhorarios.model.Horario;
import co.edu.uelbosque.asignacionhorarios.service.ApiException;
import jakarta.persistence.OptimisticLockException;
import jakarta.persistence.PersistenceException;
import jakarta.persistence.RollbackException;
import java.sql.BatchUpdateException;
import java.sql.SQLException;
import java.time.Duration;
import java.util.Map;
import java.util.stream.Stream;
import org.hibernate.StaleObjectStateException;
import org.hibernate.exception.GenericJDBCException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.orm.jpa.JpaSystemException;
import org.springframework.transaction.TransactionSystemException;

class ErroresControllerTests {
    private final ErroresController controller = new ErroresController();
    private static final String SQL_PRIVADO = "UPDATE horario SET estado = 'PUBLICADO'; datos internos";

    @ParameterizedTest
    @CsvSource(delimiter = '|', value = {
        "BD-01|El grupo y el horario de la sesión deben pertenecer al mismo periodo académico.",
        "BD-02|La duración de la sesión debe coincidir con la duración del curso.",
        "BD-03|La sesión debe estar dentro de la franja horaria del periodo.",
        "BD-04|La sesión no puede coincidir con el horario de almuerzo.",
        "BD-05|No se puede cambiar el periodo de un grupo que ya tiene sesiones.",
        "BD-06|No se puede cambiar el periodo de un horario que ya tiene sesiones.",
        "BD-07|No se puede eliminar un horario publicado porque forma parte del historial.",
        "BD-08|No se pueden agregar, modificar ni eliminar sesiones de un horario publicado. Use el flujo de republicación.",
        "BD-09|No se puede cambiar la duración de un curso que ya tiene sesiones programadas.",
        "BD-10|No se puede cambiar el curso de un grupo que ya tiene sesiones.",
        "BD-11|El horario debe crearse como borrador; la publicación es una acción posterior.",
        "BD-12|El horario debe tener al menos una sesión antes de publicarse."
    })
    void traduceLasDoceReglasSinExponerElMensajeSql(String codigo, String mensaje) {
        var respuesta = controller.persistencia(jpa(sql("[" + codigo + "] " + SQL_PRIVADO, 1644)));

        assertEquals(HttpStatus.CONFLICT, respuesta.getStatusCode());
        assertEquals(Map.of("error", mensaje, "codigo", codigo, "estado", 409), respuesta.getBody());
        assertFalse(respuesta.getBody().toString().contains(SQL_PRIVADO));
    }

    static Stream<Arguments> envolturasDePersistencia() {
        SQLException sql = sql("[BD-12] " + SQL_PRIVADO, 1644);
        return Stream.of(
            Arguments.of(jpa(sql)),
            Arguments.of(new DataIntegrityViolationException(SQL_PRIVADO, sql)),
            Arguments.of(new TransactionSystemException(SQL_PRIVADO, new RollbackException(SQL_PRIVADO, sql))),
            Arguments.of(new GenericJDBCException(SQL_PRIVADO, sql)),
            Arguments.of(new PersistenceException(SQL_PRIVADO, sql))
        );
    }

    @ParameterizedTest
    @MethodSource("envolturasDePersistencia")
    void reconoceLaReglaDentroDeExcepcionesDeJpaYDelCommit(RuntimeException excepcion) {
        var respuesta = controller.persistencia(excepcion);

        assertEquals(HttpStatus.CONFLICT, respuesta.getStatusCode());
        assertEquals("BD-12", respuesta.getBody().get("codigo"));
        assertEquals(409, respuesta.getBody().get("estado"));
    }

    @Test
    void recorreLasExcepcionesDeUnLoteJdbc() {
        var lote = new BatchUpdateException(SQL_PRIVADO, "HY000", 0, new int[0]);
        lote.setNextException(sql("[BD-04] " + SQL_PRIVADO, 1644));

        var respuesta = controller.persistencia(jpa(lote));

        assertEquals(HttpStatus.CONFLICT, respuesta.getStatusCode());
        assertEquals("BD-04", respuesta.getBody().get("codigo"));
    }

    @Test
    void terminaCuandoLaCadenaJdbcTieneUnCiclo() {
        SQLException ciclica = new SQLException(SQL_PRIVADO, "HY000", 0) {
            @Override public SQLException getNextException() { return this; }
        };

        var respuesta = assertTimeoutPreemptively(Duration.ofSeconds(1),
            () -> controller.persistencia(jpa(ciclica)));

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, respuesta.getStatusCode());
    }

    @Test
    void examinaLaExcepcionOriginalDeLaTransaccionAunqueNoSeaSuCausa() {
        var transaccion = new TransactionSystemException(SQL_PRIVADO, new PersistenceException(SQL_PRIVADO));
        transaccion.initApplicationException(jpa(sql("[BD-09] " + SQL_PRIVADO, 1644)));

        var respuesta = controller.persistencia(transaccion);

        assertEquals("BD-09", respuesta.getBody().get("codigo"));
        assertEquals(HttpStatus.CONFLICT, respuesta.getStatusCode());
    }

    static Stream<RuntimeException> conflictosDeVersion() {
        return Stream.of(
            new ObjectOptimisticLockingFailureException(Horario.class, 1L),
            new OptimisticLockException(SQL_PRIVADO),
            new StaleObjectStateException(Horario.class.getName(), 1L),
            new TransactionSystemException(SQL_PRIVADO,
                new RollbackException(SQL_PRIVADO, new OptimisticLockException(SQL_PRIVADO)))
        );
    }

    @ParameterizedTest
    @MethodSource("conflictosDeVersion")
    void losConflictosOptimistasPidenRecargarInclusoDuranteElCommit(RuntimeException excepcion) {
        var respuesta = controller.persistencia(excepcion);

        assertEquals(HttpStatus.CONFLICT, respuesta.getStatusCode());
        assertEquals(409, respuesta.getBody().get("estado"));
        assertTrue(respuesta.getBody().get("error").toString().contains("Recargue"));
        assertFalse(respuesta.getBody().toString().contains(SQL_PRIVADO));
    }

    @ParameterizedTest
    @CsvSource(delimiter = '|', value = {
        "1452|La referencia indicada no existe. Revise los registros seleccionados.",
        "1451|No se puede eliminar el registro porque tiene información asociada.",
        "1062|Ya existe un registro con esos datos.",
        "3819|Los datos incumplen una regla de validación.",
        "1048|Falta un dato obligatorio."
    })
    void traduceLosErroresDeIntegridadDeMysql(int numero, String mensaje) {
        var respuesta = controller.persistencia(jpa(sql(SQL_PRIVADO, numero)));

        assertEquals(HttpStatus.CONFLICT, respuesta.getStatusCode());
        assertEquals(Map.of("error", mensaje, "estado", 409), respuesta.getBody());
    }

    @Test
    void mantieneUnaRespuestaGenericaParaIntegridadNoIdentificada() {
        var respuesta = controller.persistencia(new DataIntegrityViolationException(SQL_PRIVADO));

        assertEquals(HttpStatus.CONFLICT, respuesta.getStatusCode());
        assertEquals(Map.of("error", "La operación viola una restricción de integridad.", "estado", 409),
            respuesta.getBody());
    }

    @Test
    void unErrorDePersistenciaDesconocidoEsInternoYSinDetallesSql() {
        var respuesta = controller.persistencia(jpa(sql(SQL_PRIVADO, 9999)));

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, respuesta.getStatusCode());
        assertEquals(Map.of("error", "No se pudo completar la operación de persistencia.", "estado", 500),
            respuesta.getBody());
    }

    @ParameterizedTest
    @ValueSource(strings = {"[BD-00]", "[BD-010]", "[BD-13]", "[BD-14]", "[BD-15]", "[BD-16]", "texto [BD-01]"})
    void noConfundeCodigosParecidosNiReglasPendientes(String prefijo) {
        var respuesta = controller.persistencia(jpa(sql(prefijo + " " + SQL_PRIVADO, 1644)));

        assertEquals(HttpStatus.INTERNAL_SERVER_ERROR, respuesta.getStatusCode());
        assertFalse(respuesta.getBody().containsKey("codigo"));
        assertFalse(respuesta.getBody().toString().contains(SQL_PRIVADO));
    }

    @Test
    void conservaElEstadoYMensajeDeErroresDeNegocio() {
        var respuesta = controller.negocio(new ApiException(HttpStatus.NOT_FOUND, "Horario no encontrado"));

        assertEquals(HttpStatus.NOT_FOUND, respuesta.getStatusCode());
        assertEquals(Map.of("error", "Horario no encontrado", "estado", 404), respuesta.getBody());
    }

    private static SQLException sql(String mensaje, int numero) {
        return new SQLException(mensaje, numero == 1644 ? "45000" : "23000", numero);
    }

    private static JpaSystemException jpa(SQLException sql) {
        return new JpaSystemException(new GenericJDBCException(SQL_PRIVADO, sql));
    }
}