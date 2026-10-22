package co.edu.uelbosque.asignacionhorarios.validation;
import java.util.*;
import org.springframework.stereotype.Component;
@Component
public class ReglaChoqueDocente implements ReglaHorario {
    @Override public List<Incidencia> evaluar(ContextoValidacion c) {
        for (var s : c.sesiones()) {
            if (Objects.equals(s.getId(),c.sesionExcluida()) && c.sesionExcluida() != null) continue;
            if (s.getDia() == c.dia() && Objects.equals(s.getGrupo().getDocente().getId(),c.grupo().getDocente().getId())
                && c.inicio().isBefore(s.getHoraFin()) && c.fin().isAfter(s.getHoraInicio())) {
                return List.of(new Incidencia(Nivel.BLOQUEO,"DOCENTE_OCUPADO",
                   "El docente " + c.grupo().getDocente().getNombre() + " ya tiene clase en esa franja"));
            }
        }
        return List.of();
    }
}
