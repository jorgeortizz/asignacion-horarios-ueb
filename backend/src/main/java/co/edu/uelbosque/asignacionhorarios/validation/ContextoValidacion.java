package co.edu.uelbosque.asignacionhorarios.validation;
import co.edu.uelbosque.asignacionhorarios.model.*;
import java.time.LocalTime;
import java.util.List;
public record ContextoValidacion(Horario horario, Grupo grupo, byte dia,
    LocalTime inicio, LocalTime fin, Long sesionExcluida,
    List<Sesion> sesiones, List<RestriccionHoraria> restricciones) {
    public ContextoValidacion {
        if (horario == null || grupo == null || inicio == null || fin == null) throw new IllegalArgumentException("Faltan datos para validar");
        sesiones = List.copyOf(sesiones);
        restricciones = List.copyOf(restricciones);
    }
}
