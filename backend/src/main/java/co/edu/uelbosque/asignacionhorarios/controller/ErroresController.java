package co.edu.uelbosque.asignacionhorarios.controller;

import co.edu.uelbosque.asignacionhorarios.service.ApiException;
import jakarta.persistence.OptimisticLockException;
import jakarta.persistence.PersistenceException;
import java.sql.SQLException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import org.hibernate.JDBCException;
import org.hibernate.StaleStateException;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.TransactionSystemException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ErroresController {
    private static final Pattern CODIGO_BD = Pattern.compile("^\\[(BD-(?:0[1-9]|1[0-2]))\\](?:\\s|$)");
    private static final Map<String, String> MENSAJES_BD = Map.ofEntries(
        Map.entry("BD-01", "El grupo y el horario de la sesión deben pertenecer al mismo periodo académico."),
        Map.entry("BD-02", "La duración de la sesión debe coincidir con la duración del curso."),
        Map.entry("BD-03", "La sesión debe estar dentro de la franja horaria del periodo."),
        Map.entry("BD-04", "La sesión no puede coincidir con el horario de almuerzo."),
        Map.entry("BD-05", "No se puede cambiar el periodo de un grupo que ya tiene sesiones."),
        Map.entry("BD-06", "No se puede cambiar el periodo de un horario que ya tiene sesiones."),
        Map.entry("BD-07", "No se puede eliminar un horario publicado porque forma parte del historial."),
        Map.entry("BD-08", "No se pueden agregar, modificar ni eliminar sesiones de un horario publicado. Use el flujo de republicación."),
        Map.entry("BD-09", "No se puede cambiar la duración de un curso que ya tiene sesiones programadas."),
        Map.entry("BD-10", "No se puede cambiar el curso de un grupo que ya tiene sesiones."),
        Map.entry("BD-11", "El horario debe crearse como borrador; la publicación es una acción posterior."),
        Map.entry("BD-12", "El horario debe tener al menos una sesión antes de publicarse.")
    );
    private static final Map<Integer, String> MENSAJES_INTEGRIDAD = Map.of(
        1452, "La referencia indicada no existe. Revise los registros seleccionados.",
        1451, "No se puede eliminar el registro porque tiene información asociada.",
        1062, "Ya existe un registro con esos datos.",
        3819, "Los datos incumplen una regla de validación.",
        1048, "Falta un dato obligatorio."
    );

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<Map<String, Object>> negocio(ApiException e) {
        return respuesta(e.getStatus(), e.getMessage());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> valido(MethodArgumentNotValidException e) {
        var errores = e.getBindingResult().getFieldErrors().stream()
            .map(f -> f.getField() + ": " + f.getDefaultMessage()).toList();
        return ResponseEntity.badRequest().body(Map.of("error", "Datos inválidos", "detalle", errores));
    }

    @ExceptionHandler({DataAccessException.class, PersistenceException.class, TransactionSystemException.class})
    public ResponseEntity<Map<String, Object>> persistencia(RuntimeException e) {
        List<Throwable> causas = causasDe(e);
        if (causas.stream().anyMatch(c -> c instanceof OptimisticLockingFailureException
                || c instanceof OptimisticLockException || c instanceof StaleStateException)) {
            return respuesta(HttpStatus.CONFLICT,
                "El horario fue modificado por otra operación. Recargue los datos e intente nuevamente.");
        }

        for (Throwable causa : causas) {
            String mensaje = causa.getMessage();
            if (mensaje == null) continue;
            var codigo = CODIGO_BD.matcher(mensaje.stripLeading());
            if (codigo.find()) {
                String valor = codigo.group(1);
                return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of(
                    "error", MENSAJES_BD.get(valor), "codigo", valor, "estado", HttpStatus.CONFLICT.value()));
            }
        }

        for (Throwable causa : causas) {
            if (causa instanceof SQLException sql) {
                String mensaje = MENSAJES_INTEGRIDAD.get(sql.getErrorCode());
                if (mensaje != null) return respuesta(HttpStatus.CONFLICT, mensaje);
            }
        }
        if (causas.stream().anyMatch(DataIntegrityViolationException.class::isInstance)) {
            return respuesta(HttpStatus.CONFLICT, "La operación viola una restricción de integridad.");
        }
        return respuesta(HttpStatus.INTERNAL_SERVER_ERROR, "No se pudo completar la operación de persistencia.");
    }

    private static ResponseEntity<Map<String, Object>> respuesta(HttpStatus estado, String mensaje) {
        return ResponseEntity.status(estado).body(Map.of("error", mensaje, "estado", estado.value()));
    }

    private static List<Throwable> causasDe(Throwable excepcion) {
        List<Throwable> causas = new ArrayList<>();
        Set<Throwable> visitadas = Collections.newSetFromMap(new IdentityHashMap<>());
        var pendientes = new ArrayDeque<Throwable>();
        pendientes.add(excepcion);
        while (!pendientes.isEmpty()) {
            Throwable actual = pendientes.removeFirst();
            if (!visitadas.add(actual)) continue;
            causas.add(actual);
            if (actual.getCause() != null) pendientes.addLast(actual.getCause());
            if (actual instanceof SQLException sql && sql.getNextException() != null) {
                pendientes.addLast(sql.getNextException());
            }
            if (actual instanceof JDBCException jdbc && jdbc.getSQLException() != null) {
                pendientes.addLast(jdbc.getSQLException());
            }
            if (actual instanceof TransactionSystemException transaccion
                    && transaccion.getOriginalException() != null) {
                pendientes.addLast(transaccion.getOriginalException());
            }
        }
        return causas;
    }
}