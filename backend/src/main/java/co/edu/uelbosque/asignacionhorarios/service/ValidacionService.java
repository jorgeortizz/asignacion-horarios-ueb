package co.edu.uelbosque.asignacionhorarios.service;
import co.edu.uelbosque.asignacionhorarios.repository.*;
import co.edu.uelbosque.asignacionhorarios.model.*;
import co.edu.uelbosque.asignacionhorarios.validation.*;
import co.edu.uelbosque.asignacionhorarios.dto.Peticiones;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
@Service
public class ValidacionService {
    private final GrupoRepository grupos;
    private final HorarioRepository horarios;
    private final SesionRepository sesiones;
    private final RestriccionHorariaRepository restricciones;
    private final ValidadorHorario validador;
    public ValidacionService(GrupoRepository grupos, HorarioRepository horarios, SesionRepository sesiones,
                             RestriccionHorariaRepository restricciones, ValidadorHorario validador) {
        this.grupos=grupos;this.horarios=horarios;this.sesiones=sesiones;
        this.restricciones=restricciones;this.validador=validador;
    }
    public ResultadoValidacion validar(Horario horario, Grupo grupo, byte dia, LocalTime inicio, Long excluir,
                                     List<Sesion> actuales, List<RestriccionHoraria> restriccionesDocente) {
        Util.exigir(horario.getPeriodo().getId().equals(grupo.getPeriodo().getId()),"El grupo no pertenece al periodo del horario");
        Util.exigir(!inicio.isAfter(LocalTime.MAX.minusMinutes(grupo.getCurso().getDuracionSesionMin())),"Hora de inicio inválida");
        var fin=inicio.plusMinutes(grupo.getCurso().getDuracionSesionMin());
        return validador.validar(new ContextoValidacion(horario,grupo,dia,inicio,fin,excluir,actuales,restriccionesDocente));
    }
    @Transactional(readOnly=true) public ResultadoValidacion previsualizar(Long horarioId, Peticiones.Previsualizar p) {
        var horario=Util.requerido(horarios.findById(horarioId),"Horario");
        Util.editable(horario);
        var grupo=Util.requerido(grupos.findById(p.grupoId()),"Grupo");
        if(p.sesionExcluida()!=null) {
            var excluida=Util.requerido(sesiones.findById(p.sesionExcluida()),"Sesión");
            Util.exigir(excluida.getHorario().getId().equals(horarioId) && excluida.getGrupo().getId().equals(p.grupoId()),"La sesión excluida no corresponde");
        }
        return validar(horario,grupo,p.dia(),p.horaInicio(),p.sesionExcluida(),
            sesiones.findByHorarioIdOrderByDiaAscHoraInicioAsc(horarioId),
            restricciones.findByDocenteIdOrderByDiaAscHoraInicioAsc(grupo.getDocente().getId()));
    }
}
