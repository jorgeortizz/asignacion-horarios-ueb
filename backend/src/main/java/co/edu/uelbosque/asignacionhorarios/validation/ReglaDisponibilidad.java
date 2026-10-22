package co.edu.uelbosque.asignacionhorarios.validation;
import co.edu.uelbosque.asignacionhorarios.model.*;
import java.util.*;
import org.springframework.stereotype.Component;
@Component
public class ReglaDisponibilidad implements ReglaHorario {
    @Override public List<Incidencia> evaluar(ContextoValidacion c) {
        List<Incidencia> incidencias = new ArrayList<>();
        // Las franjas DISPONIBLE son inclusiones; las NO_DISPONIBLE son exclusiones.
        // Esta interpretación es una suposición explícita pendiente del Comité Táctico.
        boolean requiereDisponible = c.restricciones().stream().anyMatch(r ->
             r.getTipo()==TipoRestriccion.FIRME && r.getSentido()==SentidoRestriccion.DISPONIBLE);
        boolean cubierto = c.restricciones().stream().anyMatch(r -> r.getDia()==c.dia() &&
             r.getTipo()==TipoRestriccion.FIRME && r.getSentido()==SentidoRestriccion.DISPONIBLE &&
             !c.inicio().isBefore(r.getHoraInicio()) && !c.fin().isAfter(r.getHoraFin()));
        if (requiereDisponible && !cubierto) incidencias.add(new Incidencia(Nivel.BLOQUEO,
             "FUERA_DISPONIBILIDAD","Fuera de la disponibilidad firme del docente"));
        for (var r : c.restricciones()) {
            if (r.getDia()!=c.dia()) continue;
            boolean seCruza = c.inicio().isBefore(r.getHoraFin()) && c.fin().isAfter(r.getHoraInicio());
            boolean contenido = !c.inicio().isBefore(r.getHoraInicio()) && !c.fin().isAfter(r.getHoraFin());
            boolean incumple = r.getSentido()==SentidoRestriccion.NO_DISPONIBLE ? seCruza : !contenido;
            if (r.getTipo()==TipoRestriccion.FIRME && r.getSentido()==SentidoRestriccion.NO_DISPONIBLE && incumple) {
                incidencias.add(new Incidencia(Nivel.BLOQUEO,"DOCENTE_NO_DISPONIBLE","La franja está bloqueada por el docente"));
            }
        }
        var preferencias = c.restricciones().stream().filter(r -> r.getTipo()==TipoRestriccion.PREFERENCIA).toList();
        boolean tienePreferenciaDisponible = preferencias.stream().anyMatch(r -> r.getSentido()==SentidoRestriccion.DISPONIBLE);
        boolean coincidePreferenciaDisponible = preferencias.stream().anyMatch(r -> r.getSentido()==SentidoRestriccion.DISPONIBLE
          && r.getDia()==c.dia() && !c.inicio().isBefore(r.getHoraInicio()) && !c.fin().isAfter(r.getHoraFin()));
        if (tienePreferenciaDisponible && !coincidePreferenciaDisponible) incidencias.add(
            new Incidencia(Nivel.ADVERTENCIA,"PREFERENCIA_DISPONIBILIDAD","Fuera de la franja preferida por el docente"));
        if (preferencias.stream().anyMatch(r -> r.getSentido()==SentidoRestriccion.NO_DISPONIBLE
            && r.getDia()==c.dia() && c.inicio().isBefore(r.getHoraFin()) && c.fin().isAfter(r.getHoraInicio()))) {
            incidencias.add(new Incidencia(Nivel.ADVERTENCIA,"PREFERENCIA_NO_DISPONIBLE","La sesión coincide con una franja no preferida"));
        }
        return incidencias;
    }
}
