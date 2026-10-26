package co.edu.uelbosque.asignacionhorarios.validation;
import java.util.List;
public record ResultadoValidacion(boolean permitido, List<Incidencia> incidencias) {
    public static ResultadoValidacion of(List<Incidencia> incidencias) {
        return new ResultadoValidacion(incidencias.stream().noneMatch(i -> i.nivel() == Nivel.BLOQUEO), List.copyOf(incidencias));
    }
}
