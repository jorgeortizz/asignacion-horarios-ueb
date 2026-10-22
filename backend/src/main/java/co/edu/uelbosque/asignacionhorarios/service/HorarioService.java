package co.edu.uelbosque.asignacionhorarios.service;
import co.edu.uelbosque.asignacionhorarios.repository.*;
import co.edu.uelbosque.asignacionhorarios.model.*;
import co.edu.uelbosque.asignacionhorarios.dto.*;
import co.edu.uelbosque.asignacionhorarios.validation.*;
import java.time.*;
import java.util.*;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
@Service
public class HorarioService {
    private final HorarioRepository horarios;
    private final SesionRepository sesiones;
    private final GrupoRepository grupos;
    private final RestriccionHorariaRepository restricciones;
    private final ValidacionService validacion;
    public HorarioService(HorarioRepository horarios,SesionRepository sesiones,GrupoRepository grupos,
                          RestriccionHorariaRepository restricciones,ValidacionService validacion) {
        this.horarios=horarios;this.sesiones=sesiones;this.grupos=grupos;
        this.restricciones=restricciones;this.validacion=validacion;
    }
    @Transactional public Respuestas.MovimientoResultado mover(Long horarioId,Long sesionId,Peticiones.Movimiento p) {
        // Bloqueo de la fila horario: serializa movimientos concurrentes dentro del mismo borrador.
        var h=Util.requerido(horarios.bloquear(horarioId),"Horario");Util.editable(h);
        var s=Util.requerido(sesiones.findById(sesionId),"Sesión");
        Util.exigir(s.getHorario().getId().equals(horarioId),"La sesión no pertenece al horario");
        var actual=sesiones.findByHorarioIdOrderByDiaAscHoraInicioAsc(horarioId);
        var r=validacion.validar(h,s.getGrupo(),p.dia(),p.horaInicio(),s.getId(),actual,
                  restricciones.findByDocenteIdOrderByDiaAscHoraInicioAsc(s.getGrupo().getDocente().getId()));
        if(!r.permitido()) return new Respuestas.MovimientoResultado(false,r,Respuestas.SesionDto.de(s));
        s.setDia(p.dia());s.setHoraInicio(p.horaInicio());
        s.setHoraFin(p.horaInicio().plusMinutes(s.getGrupo().getCurso().getDuracionSesionMin()));
        // Guardado en la misma transacción que el bloqueo del horario.
        sesiones.saveAndFlush(s);
        return new Respuestas.MovimientoResultado(true,r,Respuestas.SesionDto.de(s));
    }
    @Transactional public Respuestas.HorarioDto publicar(Long id) {
        var h=Util.requerido(horarios.bloquear(id),"Horario");Util.editable(h);
        var actuales=sesiones.findByHorarioIdOrderByDiaAscHoraInicioAsc(id);
        var gruposPeriodo=grupos.findByPeriodoIdOrderById(h.getPeriodo().getId());
        Util.exigir(!gruposPeriodo.isEmpty(),"El periodo no tiene grupos para publicar");
        var errores=new ArrayList<String>();
        for(var g:gruposPeriodo) {
            long count=actuales.stream().filter(s->s.getGrupo().getId().equals(g.getId())).count();
            if(count!=g.getCurso().getSesionesSemanales()) errores.add("Grupo "+g.getCodigo()+": faltan o sobran sesiones");
            if(g.getInscritos()>Util.limiteOperativo(g)) errores.add("Grupo "+g.getCodigo()+": inscritos superan cupo permitido");
        }
        Map<Long,List<RestriccionHoraria>> cache=new HashMap<>();
        for(var s:actuales) {
            var d=s.getGrupo().getDocente();
            var r=validacion.validar(h,s.getGrupo(),s.getDia(),s.getHoraInicio(),s.getId(),actuales,
                   cache.computeIfAbsent(d.getId(),restricciones::findByDocenteIdOrderByDiaAscHoraInicioAsc));
            r.incidencias().stream().filter(i->i.nivel()==Nivel.BLOQUEO)
             .forEach(i->errores.add("Sesión "+s.getId()+": "+i.motivo()));
        }
        if(!errores.isEmpty()) throw new ApiException(HttpStatus.CONFLICT, "No se puede publicar: "+String.join("; ",errores));
        h.setEstado(EstadoHorario.PUBLICADO);h.setFechaPublicacion(LocalDateTime.now());horarios.saveAndFlush(h);
        return new Respuestas.HorarioDto(h.getId(),h.getPeriodo().getId(),h.getEstado(),h.getFechaCreacion(),
                 h.getFechaPublicacion(),actuales.stream().map(Respuestas.SesionDto::de).toList());
    }
    @Transactional(readOnly=true) public Respuestas.HorarioDto detalle(Long id) {
        var h=Util.requerido(horarios.findById(id),"Horario");
        var datos=sesiones.findByHorarioIdOrderByDiaAscHoraInicioAsc(id).stream().map(Respuestas.SesionDto::de).toList();
        return new Respuestas.HorarioDto(h.getId(),h.getPeriodo().getId(),h.getEstado(),h.getFechaCreacion(),h.getFechaPublicacion(),datos);
    }
    @Transactional(readOnly=true) public List<Respuestas.HorarioDto> historico(Long periodoId) {
        return horarios.findByPeriodoIdOrderByFechaCreacionDesc(periodoId).stream().map(h->detalle(h.getId())).toList();
    }
}
