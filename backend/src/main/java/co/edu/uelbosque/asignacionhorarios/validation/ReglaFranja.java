package co.edu.uelbosque.asignacionhorarios.validation;
import co.edu.uelbosque.asignacionhorarios.model.PeriodoAcademico;
import java.time.LocalTime;
import java.util.List;
import org.springframework.stereotype.Component;
@Component
public class ReglaFranja implements ReglaHorario {
    @Override public List<Incidencia> evaluar(ContextoValidacion c) {
        PeriodoAcademico p = c.horario().getPeriodo();
        LocalTime desde = c.dia() == 6 ? p.getHoraInicioSabado() : p.getHoraInicioSemana();
        LocalTime hasta = c.dia() == 6 ? p.getHoraFinSabado() : p.getHoraFinSemana();
        if (c.dia() < 1 || c.dia() > 6 || !c.inicio().isBefore(c.fin())
                || c.inicio().isBefore(desde) || c.fin().isAfter(hasta)) {
            return List.of(new Incidencia(Nivel.BLOQUEO,"FRANJA","Sesión fuera de la franja institucional"));
        }
        return List.of();
    }
}
