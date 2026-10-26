package co.edu.uelbosque.asignacionhorarios.controller;
import co.edu.uelbosque.asignacionhorarios.dto.*;
import co.edu.uelbosque.asignacionhorarios.service.*;
import jakarta.validation.Valid;
import java.util.*;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/v1")
public class RegistroController {
    private final RegistroService registros;
    public RegistroController(RegistroService registros) {this.registros=registros;}
    @PostMapping("/docentes") public ResponseEntity<Map<String,Object>> docente(@Valid @RequestBody Peticiones.Docente p) {
        var d=registros.crearDocente(p);return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("id",d.getId(),"nombre",d.getNombre()));
    }
    @GetMapping("/docentes") public List<Map<String,Object>> docentes() {
        return registros.docentes().stream().map(d->Map.<String,Object>of("id",d.getId(),"nombre",d.getNombre(),
            "tipoVinculacion",d.getTipoVinculacion(),"especialidades",d.getEspecialidades())).toList();
    }
    @GetMapping("/docentes/{id}/restricciones") public List<Map<String,Object>> restricciones(@PathVariable Long id) {
        return registros.restriccionesDocente(id).stream().map(r->Map.<String,Object>of("id",r.getId(),"dia",r.getDia(),
        "horaInicio",r.getHoraInicio(),"horaFin",r.getHoraFin(),"tipo",r.getTipo(),"sentido",r.getSentido())).toList();
    }
    @PostMapping("/cursos") public ResponseEntity<Map<String,Object>> curso(@Valid @RequestBody Peticiones.Curso p) {
        var c=registros.crearCurso(p);return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("id",c.getId(),"nombre",c.getNombre()));
    }
   @GetMapping("/cursos")
public List<Map<String, Object>> cursos() {
    return registros.cursos().stream().map(c -> {
        Map<String, Object> datos = new LinkedHashMap<>();

        datos.put("id", c.getId());
        datos.put("codigo", c.getCodigo());
        datos.put("nombre", c.getNombre());
        datos.put("sesionesSemanales", c.getSesionesSemanales());
        datos.put("duracionSesionMin", c.getDuracionSesionMin());
        datos.put("necesitaAulaEspecial", c.isNecesitaAulaEspecial());

        return datos;
    }).toList();
}
    @PostMapping("/grupos") public ResponseEntity<Respuestas.GrupoDto> grupo(@Valid @RequestBody Peticiones.Grupo p) {
        return ResponseEntity.status(HttpStatus.CREATED).body(registros.crearGrupo(p));
    }
    @GetMapping("/periodos/{id}/grupos") public List<Respuestas.GrupoDto> grupos(@PathVariable Long id) {
        return registros.gruposPeriodo(id);
    }
}
