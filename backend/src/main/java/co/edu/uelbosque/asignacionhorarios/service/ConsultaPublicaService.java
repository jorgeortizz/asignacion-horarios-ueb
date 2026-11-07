package co.edu.uelbosque.asignacionhorarios.service;

import co.edu.uelbosque.asignacionhorarios.dto.Respuestas;
import co.edu.uelbosque.asignacionhorarios.model.EstadoHorario;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Puerta de entrada de SOLO LECTURA para consultas públicas o de un docente.
 * No acepta el flag soloPublicados ni expone el método administrativo detalle().
 */
@Service
public class ConsultaPublicaService {
    private final HorarioService horarios;
    private final ConsultaService consultas;

    public ConsultaPublicaService(HorarioService horarios, ConsultaService consultas) {
        this.horarios = horarios;
        this.consultas = consultas;
    }

    @Transactional(readOnly = true)
    public Respuestas.HorarioDto horarioVigente(Long periodoId) {
        var vigente = horarios.vigente(periodoId);
        // Defensa adicional aunque la vista v_horario_vigente ya exige PUBLICADO.
        if (vigente.estado() != EstadoHorario.PUBLICADO) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Horario publicado vigente no encontrado");
        }
        return vigente;
    }

    @Transactional(readOnly = true)
    public List<Respuestas.SesionDto> sesionesCurso(Long periodoId, Long cursoId) {
        return horarioVigente(periodoId).sesiones().stream()
            .filter(s -> cursoId.equals(s.cursoId()))
            .toList();
    }

    @Transactional(readOnly = true)
    public List<Respuestas.SesionDto> sesionesDocente(Long periodoId, Long docenteId) {
        if (docenteId == null) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Cuenta docente sin asociación académica");
        }
        return horarioVigente(periodoId).sesiones().stream()
            .filter(s -> docenteId.equals(s.docenteId()))
            .toList();
    }

    @Transactional(readOnly = true)
    public String csvCurso(Long periodoId, Long cursoId) {
        var vigente = horarioVigente(periodoId);
        // exportarCsv vuelve a exigir PUBLICADO e incluye solo este curso.
        return consultas.exportarCsv(vigente.id(), null, cursoId);
    }
}
