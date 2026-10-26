package co.edu.uelbosque.asignacionhorarios.service;
import co.edu.uelbosque.asignacionhorarios.repository.*;
import co.edu.uelbosque.asignacionhorarios.model.*;
import co.edu.uelbosque.asignacionhorarios.validation.*;
import co.edu.uelbosque.asignacionhorarios.dto.Respuestas;
import java.time.*;
import java.util.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
@Service
public class GeneracionService {
    private final PeriodoAcademicoRepository periodos;
    private final GrupoRepository grupos;
    private final HorarioRepository horarios;
    private final SesionRepository sesiones;
    private final RestriccionHorariaRepository restricciones;
    private final ValidacionService validacion;
    private final BloquesFijos bloques;
    public GeneracionService(PeriodoAcademicoRepository periodos,GrupoRepository grupos,HorarioRepository horarios,
      SesionRepository sesiones,RestriccionHorariaRepository restricciones,ValidacionService validacion,BloquesFijos bloques) {
        this.periodos=periodos;this.grupos=grupos;this.horarios=horarios;this.sesiones=sesiones;
        this.restricciones=restricciones;this.validacion=validacion;this.bloques=bloques;
    }
    private record Candidato(byte dia,LocalTime inicio,ResultadoValidacion resultado,int repeticionesDia) {}
    @Transactional public Respuestas.Generacion generar(Long periodoId) {
        var periodo=Util.requerido(periodos.findById(periodoId),"Periodo");
        var asignables=new ArrayList<>(grupos.findByPeriodoIdOrderById(periodoId));
        Util.exigir(!asignables.isEmpty(),"No hay grupos registrados para este periodo");
        // Orden por demanda; si no se encuentra solución, se informa en vez de afirmar optimalidad.
        asignables.sort(Comparator.comparingInt((Grupo g)->g.getCurso().getSesionesSemanales()).reversed());
        var horario=new Horario();horario.setPeriodo(periodo);horario.setEstado(EstadoHorario.BORRADOR);
        horarios.saveAndFlush(horario);
        var colocadas=new ArrayList<Sesion>();
        var faltantes=new ArrayList<Respuestas.NoUbicada>();
        var avisos=new ArrayList<Incidencia>();
        Map<Long,List<RestriccionHoraria>> cache=new HashMap<>();
        for (var grupo:asignables) {
            int objetivo=grupo.getCurso().getSesionesSemanales();
            if (objetivo>periodo.getMaxSesionesSemana() || grupo.getCurso().getDuracionSesionMin()!=periodo.getDuracionBloqueMin()) {
                faltantes.add(new Respuestas.NoUbicada(grupo.getId(),grupo.getCurso().getNombre(),objetivo,"Frecuencia o duración incompatible con el periodo"));
                continue;
            }
            if (grupo.getInscritos()>Util.limiteOperativo(grupo)) {
                faltantes.add(new Respuestas.NoUbicada(grupo.getId(),grupo.getCurso().getNombre(),objetivo,"Grupo supera capacidad permitida"));
                continue;
            }
            var franjas=cache.computeIfAbsent(grupo.getDocente().getId(),restricciones::findByDocenteIdOrderByDiaAscHoraInicioAsc);
            int generadas=0;
            Map<String,Integer> motivos=new HashMap<>();
            for(int sesionN=0;sesionN<objetivo;sesionN++) {
                List<Candidato> candidatos=new ArrayList<>();
                for(byte dia=1;dia<=6;dia++) for(var ini:bloques.inicios(periodo,dia)) {
                    var resultado=validacion.validar(horario,grupo,dia,ini,null,colocadas,franjas);
                    if(!resultado.permitido()) {
                        resultado.incidencias().stream().filter(i -> i.nivel()==Nivel.BLOQUEO)
                            .forEach(i -> motivos.merge(i.codigo()+": "+i.motivo(),1,Integer::sum));
                    }
                    if(resultado.permitido()) {
                        final byte diaActual=dia;
                        int repetidas=(int)colocadas.stream().filter(s->s.getGrupo().getId().equals(grupo.getId()) && s.getDia()==diaActual).count();
                        candidatos.add(new Candidato(dia,ini,resultado,repetidas));
                    }
                }
                candidatos.sort(Comparator.comparingInt((Candidato c)->c.repeticionesDia())
                    .thenComparingInt(c -> c.resultado().incidencias().size()).thenComparingInt(Candidato::dia).thenComparing(Candidato::inicio));
                if(candidatos.isEmpty()) break;
                var mejor=candidatos.getFirst();
                var sesion=new Sesion();sesion.setHorario(horario);sesion.setGrupo(grupo);sesion.setDia(mejor.dia());
                sesion.setHoraInicio(mejor.inicio());sesion.setHoraFin(mejor.inicio().plusMinutes(grupo.getCurso().getDuracionSesionMin()));
                colocadas.add(sesion);avisos.addAll(mejor.resultado().incidencias());generadas++;
            }
            if(generadas<objetivo) {
                var motivo=motivos.entrySet().stream().max(Map.Entry.comparingByValue())
                  .map(Map.Entry::getKey).orElse("No hay bloques compatibles con el periodo");
                faltantes.add(new Respuestas.NoUbicada(grupo.getId(),grupo.getCurso().getNombre(),objetivo-generadas,motivo));
            }
        }
        sesiones.saveAll(colocadas);
        return new Respuestas.Generacion(horario.getId(),colocadas.size(),List.copyOf(faltantes),List.copyOf(avisos));
    }
}
