package co.edu.uelbosque.asignacionhorarios.validation;
import java.util.List;
import org.springframework.stereotype.Component;
@Component
public class ReglaAlmuerzo implements ReglaHorario {
    @Override public List<Incidencia> evaluar(ContextoValidacion c) {
        var p = c.horario().getPeriodo();
        return c.inicio().isBefore(p.getAlmuerzoFin()) && c.fin().isAfter(p.getAlmuerzoInicio())
           ? List.of(new Incidencia(Nivel.BLOQUEO,"ALMUERZO","La sesión se cruza con el almuerzo")) : List.of();
    }
}
