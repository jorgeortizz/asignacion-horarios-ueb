package co.edu.uelbosque.asignacionhorarios.service;

import co.edu.uelbosque.asignacionhorarios.model.PeriodoAcademico;
import co.edu.uelbosque.asignacionhorarios.repository.HorarioRepository;
import co.edu.uelbosque.asignacionhorarios.repository.PeriodoAcademicoRepository;
import co.edu.uelbosque.asignacionhorarios.repository.SesionRepository;
import java.util.Comparator;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** No expone borradores ni períodos de otros docentes. */
@Service
public class PeriodosPublicadosDocenteService {
    private final PeriodoAcademicoRepository periodos;
    private final HorarioRepository horarios;
    private final SesionRepository sesiones;

    public PeriodosPublicadosDocenteService(
            PeriodoAcademicoRepository periodos, HorarioRepository horarios, SesionRepository sesiones) {
        this.periodos = periodos;
        this.horarios = horarios;
        this.sesiones = sesiones;
    }

    public record PeriodoDisponible(Long id, String nombre) {}

    @Transactional(readOnly = true)
    public List<PeriodoDisponible> listarParaDocente(Long docenteId) {
        if (docenteId == null) return List.of();

        return periodos.findAll().stream()
            .sorted(Comparator.comparing(PeriodoAcademico::getFechaInicio).reversed())
            .filter(periodo -> horarios.findVigenteByPeriodoId(periodo.getId())
                .map(horario -> sesiones.findByHorarioIdOrderByDiaAscHoraInicioAsc(horario.getId())
                    .stream().anyMatch(s -> docenteId.equals(s.getGrupo().getDocente().getId())))
                .orElse(false))
            .map(periodo -> new PeriodoDisponible(periodo.getId(), periodo.getNombre()))
            .toList();
    }
}
