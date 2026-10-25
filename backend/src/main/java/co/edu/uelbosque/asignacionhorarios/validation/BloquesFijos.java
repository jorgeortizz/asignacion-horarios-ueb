package co.edu.uelbosque.asignacionhorarios.validation;
import co.edu.uelbosque.asignacionhorarios.model.PeriodoAcademico;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Component;
/** Bloques anclados al inicio de la jornada; el almuerzo filtra sin reanclar la cuadrícula. */
@Component
public class BloquesFijos {
    public List<LocalTime> inicios(PeriodoAcademico p, byte dia) {
        if (dia < 1 || dia > 6) return List.of();
        LocalTime inicio = dia == 6 ? p.getHoraInicioSabado() : p.getHoraInicioSemana();
        LocalTime fin = dia == 6 ? p.getHoraFinSabado() : p.getHoraFinSemana();
        int duracion = p.getDuracionBloqueMin();
        if (duracion <= 0 || !inicio.isBefore(fin)) return List.of();
        List<LocalTime> bloques = new ArrayList<>();
        for (LocalTime t = inicio; !t.plusMinutes(duracion).isAfter(fin); t = t.plusMinutes(duracion)) {
            LocalTime salida = t.plusMinutes(duracion);
            if (!(t.isBefore(p.getAlmuerzoFin()) && salida.isAfter(p.getAlmuerzoInicio()))) {
                bloques.add(t);
            }
        }
        return List.copyOf(bloques);
    }
}
