package co.edu.uelbosque.asignacionhorarios.validation;
import java.util.List;
import org.springframework.stereotype.Component;
@Component
public class ReglaBloqueFijo implements ReglaHorario {
    private final BloquesFijos bloques;
    public ReglaBloqueFijo(BloquesFijos bloques) { this.bloques = bloques; }
    @Override public List<Incidencia> evaluar(ContextoValidacion c) {
        var p = c.horario().getPeriodo();
        boolean valido = bloques.inicios(p,c.dia()).contains(c.inicio()) &&
             c.inicio().plusMinutes(p.getDuracionBloqueMin()).equals(c.fin()) &&
             c.grupo().getCurso().getDuracionSesionMin() == p.getDuracionBloqueMin();
        return valido ? List.of() : List.of(new Incidencia(Nivel.BLOQUEO,"BLOQUE","La sesión no corresponde a un bloque fijo válido del periodo"));
    }
}
