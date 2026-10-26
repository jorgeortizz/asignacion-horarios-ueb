package co.edu.uelbosque.asignacionhorarios.dto;
import co.edu.uelbosque.asignacionhorarios.model.*;
import co.edu.uelbosque.asignacionhorarios.validation.*;
import java.time.*;
import java.util.*;
public final class Respuestas {
    private Respuestas() {}
    public record SesionDto(Long id, Long horarioId, Long grupoId, String grupo, Long cursoId, String curso,
                            Long docenteId, String docente, byte dia, LocalTime horaInicio, LocalTime horaFin,
                            boolean necesitaAulaEspecial) {
        public static SesionDto de(Sesion s) {
            var g=s.getGrupo();return new SesionDto(s.getId(),s.getHorario().getId(),g.getId(),g.getCodigo(),
                g.getCurso().getId(),g.getCurso().getNombre(),g.getDocente().getId(),g.getDocente().getNombre(),
                s.getDia(),s.getHoraInicio(),s.getHoraFin(),g.getCurso().isNecesitaAulaEspecial());
        }
    }
    public record HorarioDto(Long id, Long periodoId, EstadoHorario estado, LocalDateTime fechaCreacion,
                              LocalDateTime fechaPublicacion, List<SesionDto> sesiones) {}
    public record GrupoDto(Long id, Long periodoId, Long cursoId, Long docenteId, String codigo,
                            int inscritos, int limiteOperativo, boolean candidatoCierre,
                            boolean necesitaAulaEspecial) {}
    public record NoUbicada(Long grupoId, String curso, int faltantes, String motivo) {}
    public record Generacion(Long horarioId, int sesionesGeneradas, List<NoUbicada> noUbicadas,
                             List<Incidencia> advertencias) {}
    public record MovimientoResultado(boolean aplicado, ResultadoValidacion validacion, SesionDto sesion) {}
}
