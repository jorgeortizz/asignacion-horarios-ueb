package co.edu.uelbosque.asignacionhorarios.service;
import co.edu.uelbosque.asignacionhorarios.dto.Respuestas;
import co.edu.uelbosque.asignacionhorarios.model.EstadoHorario;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.springframework.stereotype.Service;
@Service
public class ConsultaService {
    private final HorarioService horarios;
    public ConsultaService(HorarioService horarios) {this.horarios=horarios;}
    public List<Respuestas.SesionDto> consultar(Long horarioId,Long docenteId,Long cursoId,Boolean soloPublicados) {
        var horario=horarios.detalle(horarioId);
        if(Boolean.TRUE.equals(soloPublicados) && horario.estado()!=EstadoHorario.PUBLICADO) return List.of();
        return horario.sesiones().stream().filter(s->docenteId==null || docenteId.equals(s.docenteId()))
            .filter(s->cursoId==null || cursoId.equals(s.cursoId()))
            .toList();
    }
    /** Solo lectura, RFC 4180 básico con escapado de celdas CSV. */
    public String exportarCsv(Long horarioId,Long docenteId,Long cursoId) {
        var datos=consultar(horarioId,docenteId,cursoId,true);
        var sb=new StringBuilder("dia,hora_inicio,hora_fin,docente,curso,grupo,necesita_aula_especial\r\n");
        for(var s:datos) {
            sb.append(s.dia()).append(',').append(s.horaInicio()).append(',').append(s.horaFin()).append(',')
              .append(csv(s.docente())).append(',').append(csv(s.curso())).append(',').append(csv(s.grupo())).append(',')
              .append(s.necesitaAulaEspecial()).append("\r\n");
        }
        return sb.toString();
    }
    private String csv(String t) {return "\""+t.replace("\"","\"\"")+"\"";}
}
