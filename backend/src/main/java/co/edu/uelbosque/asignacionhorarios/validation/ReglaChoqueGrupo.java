package co.edu.uelbosque.asignacionhorarios.validation;
import java.util.*;
import org.springframework.stereotype.Component;
@Component
public class ReglaChoqueGrupo implements ReglaHorario {
    @Override public List<Incidencia> evaluar(ContextoValidacion c) {
        for (var s:c.sesiones()) {
            if (c.sesionExcluida()!=null && Objects.equals(s.getId(),c.sesionExcluida())) continue;
            if (s.getDia()==c.dia() && Objects.equals(s.getGrupo().getId(),c.grupo().getId()) &&
               c.inicio().isBefore(s.getHoraFin()) && c.fin().isAfter(s.getHoraInicio())) {
                return List.of(new Incidencia(Nivel.BLOQUEO,"GRUPO_OCUPADO","El grupo ya tiene una clase en esa franja"));
            }
        }
        return List.of();
    }
}
