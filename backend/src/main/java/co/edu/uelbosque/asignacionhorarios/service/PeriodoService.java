package co.edu.uelbosque.asignacionhorarios.service;
import co.edu.uelbosque.asignacionhorarios.dto.Peticiones;
import co.edu.uelbosque.asignacionhorarios.model.*;
import co.edu.uelbosque.asignacionhorarios.repository.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
@Service
public class PeriodoService {
    private final PeriodoAcademicoRepository periodos;
    private final HorarioRepository horarios;
    private final SesionRepository sesiones;
    public PeriodoService(PeriodoAcademicoRepository periodos, HorarioRepository horarios, SesionRepository sesiones) {
        this.periodos=periodos;this.horarios=horarios;this.sesiones=sesiones;
    }
    @Transactional public PeriodoAcademico crear(Peticiones.Periodo r) {
        Util.exigir(r.fechaInicio().isBefore(r.fechaFin()),"La fecha inicial debe anteceder a la final");
        Util.exigir(periodos.findByNombre(r.nombre()).isEmpty(),"El periodo ya existe");
        var p=new PeriodoAcademico();p.setNombre(r.nombre());p.setFechaInicio(r.fechaInicio());p.setFechaFin(r.fechaFin());
        p.setHoraInicioSemana(LocalTime.of(7,0));p.setHoraFinSemana(LocalTime.of(22,0));
        p.setHoraInicioSabado(LocalTime.of(7,0));p.setHoraFinSabado(LocalTime.of(13,0));
        p.setAlmuerzoInicio(LocalTime.of(12,0));p.setAlmuerzoFin(LocalTime.of(13,0));
        p.setDuracionBloqueMin((short)120);p.setMaxSesionesSemana((byte)4);
        p.setCupoMaximoBase((short)40);p.setCupoMinimo((short)10);p.setToleranciaCupoPct(new BigDecimal("10.00"));
        return periodos.save(p);
    }
    @Transactional(readOnly=true) public List<PeriodoAcademico> listar() { return periodos.findAll(); }
    @Transactional(readOnly=true) public PeriodoAcademico obtener(Long id) { return Util.requerido(periodos.findById(id),"Periodo"); }
    @Transactional public PeriodoAcademico actualizar(Long id, Peticiones.Parametros r) {
        var p=Util.requerido(periodos.findById(id),"Periodo");
        Util.exigir(r.horaInicioSemana().isBefore(r.horaFinSemana()) && r.horaInicioSabado().isBefore(r.horaFinSabado())
          && r.almuerzoInicio().isBefore(r.almuerzoFin()),"Franjas horarias inválidas");
        Util.exigir(r.cupoMinimo()<=r.cupoMaximoBase(),"Cupo mínimo supera el máximo");
        Util.exigir(r.cupoMaximoBase()<=Short.MAX_VALUE && r.cupoMinimo()<=Short.MAX_VALUE,"Cupo fuera del rango técnico");
        var hs=horarios.findByPeriodoIdOrderByFechaCreacionDesc(id);
        boolean tieneSesiones=hs.stream().anyMatch(h->sesiones.countByHorarioId(h.getId())>0);
        boolean cambioTemporal = !Objects.equals(p.getHoraInicioSemana(),r.horaInicioSemana()) ||
          !Objects.equals(p.getHoraFinSemana(),r.horaFinSemana()) ||
          !Objects.equals(p.getHoraInicioSabado(),r.horaInicioSabado()) ||
          !Objects.equals(p.getHoraFinSabado(),r.horaFinSabado()) ||
          !Objects.equals(p.getAlmuerzoInicio(),r.almuerzoInicio()) ||
          !Objects.equals(p.getAlmuerzoFin(),r.almuerzoFin()) ||
          p.getDuracionBloqueMin()!=r.duracionBloqueMin();
        Util.exigir(!tieneSesiones || !cambioTemporal,
          "Hay horarios con sesiones: no cambie bloques, franjas o almuerzo sin plan de migración y revalidación");
        p.setHoraInicioSemana(r.horaInicioSemana());p.setHoraFinSemana(r.horaFinSemana());
        p.setHoraInicioSabado(r.horaInicioSabado());p.setHoraFinSabado(r.horaFinSabado());
        p.setAlmuerzoInicio(r.almuerzoInicio());p.setAlmuerzoFin(r.almuerzoFin());
        p.setDuracionBloqueMin(r.duracionBloqueMin().shortValue());p.setMaxSesionesSemana(r.maxSesionesSemana().byteValue());
        p.setCupoMaximoBase(r.cupoMaximoBase().shortValue());p.setCupoMinimo(r.cupoMinimo().shortValue());
        p.setToleranciaCupoPct(r.toleranciaCupoPct());
        return periodos.save(p);
    }
}
