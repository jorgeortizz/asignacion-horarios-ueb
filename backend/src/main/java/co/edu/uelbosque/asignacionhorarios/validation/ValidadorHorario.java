package co.edu.uelbosque.asignacionhorarios.validation;
import java.util.*;
import org.springframework.stereotype.Component;
@Component
public class ValidadorHorario {
    private final List<ReglaHorario> reglas;
    public ValidadorHorario(List<ReglaHorario> reglas) { this.reglas = List.copyOf(reglas); }
    public ResultadoValidacion validar(ContextoValidacion contexto) {
        List<Incidencia> incidencias = new ArrayList<>();
        for (ReglaHorario regla : reglas) incidencias.addAll(regla.evaluar(contexto));
        return ResultadoValidacion.of(incidencias);
    }
}
