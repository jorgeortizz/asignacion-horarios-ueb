package co.edu.uelbosque.asignacionhorarios.service;
import co.edu.uelbosque.asignacionhorarios.model.*;
import co.edu.uelbosque.asignacionhorarios.repository.*;
import co.edu.uelbosque.asignacionhorarios.dto.*;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.http.HttpStatus;
@Service
public class RegistroService {
    private final DocenteRepository docentes;
    private final CursoRepository cursos;
    private final GrupoRepository grupos;
    private final RestriccionHorariaRepository restricciones;
    private final PeriodoAcademicoRepository periodos;
    public RegistroService(DocenteRepository docentes, CursoRepository cursos, GrupoRepository grupos,
                           RestriccionHorariaRepository restricciones, PeriodoAcademicoRepository periodos) {
        this.docentes=docentes;this.cursos=cursos;this.grupos=grupos;this.restricciones=restricciones;this.periodos=periodos;
    }
    @Transactional public co.edu.uelbosque.asignacionhorarios.model.Docente crearDocente(Peticiones.Docente p) {
        var lista=p.restricciones()==null?List.<Peticiones.Restriccion>of():p.restricciones();
        Util.exigir(p.sinRestricciones() == lista.isEmpty(), "Indique 'sin restricciones' o registre al menos una franja");
        var d=new co.edu.uelbosque.asignacionhorarios.model.Docente();
        d.setNombre(p.nombre().trim());d.setTipoVinculacion(p.tipoVinculacion());
        d.setEspecialidades(p.especialidades()==null?new LinkedHashSet<>():new LinkedHashSet<>(p.especialidades()));
        docentes.save(d);
        for (var r:lista) {
            Util.exigir(r.dia()!=null && r.dia()>=1 && r.dia()<=6, "Día entre lunes y sábado");
            Util.exigir(r.horaInicio()!=null && r.horaFin()!=null && r.horaInicio().isBefore(r.horaFin()),"Intervalo de restricción inválido");
            var entidad=new RestriccionHoraria(); entidad.setDocente(d);entidad.setDia(r.dia());
            entidad.setHoraInicio(r.horaInicio()); entidad.setHoraFin(r.horaFin());
            entidad.setTipo(r.tipo());entidad.setSentido(r.sentido());restricciones.save(entidad);
        }
        return d;
    }
    @Transactional public co.edu.uelbosque.asignacionhorarios.model.Curso crearCurso(Peticiones.Curso p) {
        var c=new co.edu.uelbosque.asignacionhorarios.model.Curso();
        c.setCodigo(p.codigo()==null||p.codigo().isBlank()?null:p.codigo().trim());
        c.setNombre(p.nombre().trim());c.setSesionesSemanales(p.sesionesSemanales().byteValue());
        c.setDuracionSesionMin(p.duracionSesionMin().shortValue());c.setNecesitaAulaEspecial(p.necesitaAulaEspecial());
        return cursos.save(c);
    }
    @Transactional public Respuestas.GrupoDto crearGrupo(Peticiones.Grupo p) {
        var periodo=Util.requerido(periodos.findById(p.periodoId()), "Periodo");
        var curso=Util.requerido(cursos.findById(p.cursoId()), "Curso");
        var docente=Util.requerido(docentes.findById(p.docenteId()), "Docente");
        Util.exigir(curso.getSesionesSemanales()<=periodo.getMaxSesionesSemana(),"El curso supera el máximo de sesiones del periodo");
        Util.exigir(curso.getDuracionSesionMin()==periodo.getDuracionBloqueMin(),"Duración de curso incompatible con los bloques del periodo");
        Util.exigir(!grupos.existsByPeriodoIdAndCursoIdAndCodigo(p.periodoId(),p.cursoId(),p.codigo().trim()),"Ya existe este grupo en el periodo");
        int max=p.cupoMaximo()==null?periodo.getCupoMaximoBase():p.cupoMaximo();
        int min=p.cupoMinimo()==null?periodo.getCupoMinimo():p.cupoMinimo();
        Util.exigir(max>0 && max<=Short.MAX_VALUE && min>=0 && min<=max,"Cupos inválidos");
        int limite=(int)Math.floor(max*(1+periodo.getToleranciaCupoPct().doubleValue()/100));
        Util.exigir(p.inscritos()<=Short.MAX_VALUE && p.inscritos()<=limite,"Inscritos superan cupo máximo más tolerancia");
        var g=new co.edu.uelbosque.asignacionhorarios.model.Grupo();
        g.setPeriodo(periodo);g.setCurso(curso);g.setDocente(docente);g.setCodigo(p.codigo().trim());
        g.setCupoMaximo((short)max);g.setCupoMinimo((short)min);g.setInscritos(p.inscritos().shortValue());
        return dto(grupos.save(g));
    }
    public static Respuestas.GrupoDto dto(co.edu.uelbosque.asignacionhorarios.model.Grupo g) {
        return new Respuestas.GrupoDto(g.getId(),g.getPeriodo().getId(),g.getCurso().getId(),g.getDocente().getId(),
            g.getCodigo(),g.getInscritos(),Util.limiteOperativo(g),g.getInscritos()<g.getCupoMinimo(),g.getCurso().isNecesitaAulaEspecial());
    }
    @Transactional(readOnly=true) public List<Respuestas.GrupoDto> gruposPeriodo(Long id) {
        return grupos.findByPeriodoIdOrderById(id).stream().map(RegistroService::dto).toList();
    }
    @Transactional(readOnly=true) public List<co.edu.uelbosque.asignacionhorarios.model.Docente> docentes() {return docentes.findAll();}
    @Transactional(readOnly=true) public List<co.edu.uelbosque.asignacionhorarios.model.Curso> cursos() {return cursos.findAll();}
    @Transactional(readOnly=true) public List<RestriccionHoraria> restriccionesDocente(Long id) {return restricciones.findByDocenteIdOrderByDiaAscHoraInicioAsc(id);}
}
