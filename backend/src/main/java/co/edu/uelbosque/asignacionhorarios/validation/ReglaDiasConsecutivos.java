package co.edu.uelbosque.asignacionhorarios.validation;
import java.util.*;
import org.springframework.stereotype.Component;
@Component
public class ReglaDiasConsecutivos implements ReglaHorario {
    @Override public List<Incidencia> evaluar(ContextoValidacion c) {
        // Según la suposición del informe: por grupo, dentro de la semana (no sábado-lunes).
        boolean seguido = c.sesiones().stream().anyMatch(s ->
            !(c.sesionExcluida()!=null && Objects.equals(s.getId(),c.sesionExcluida())) &&
            Objects.equals(s.getGrupo().getId(),c.grupo().getId()) && Math.abs(s.getDia()-c.dia())==1);
        return seguido ? List.of(new Incidencia(Nivel.ADVERTENCIA,"DIAS_CONSECUTIVOS",
          "El mismo grupo tiene otra sesión en un día consecutivo")) : List.of();
    }
}
