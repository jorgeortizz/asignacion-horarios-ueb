package co.edu.uelbosque.asignacionhorarios.controller;

import co.edu.uelbosque.asignacionhorarios.dto.Respuestas;
import co.edu.uelbosque.asignacionhorarios.service.ConsultaPublicaService;
import java.util.List;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** API anónima: consulta únicamente el horario publicado vigente. */
@RestController
@RequestMapping("/api/v1/publico/periodos/{periodoId}")
public class ConsultaPublicaController {
    private final ConsultaPublicaService consultas;

    public ConsultaPublicaController(ConsultaPublicaService consultas) {
        this.consultas = consultas;
    }

    @GetMapping("/horario-vigente")
    public ResponseEntity<Respuestas.HorarioDto> horario(@PathVariable Long periodoId) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
            .body(consultas.horarioVigente(periodoId));
    }

    @GetMapping("/cursos/{cursoId}/sesiones")
    public ResponseEntity<List<Respuestas.SesionDto>> curso(
            @PathVariable Long periodoId, @PathVariable Long cursoId) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
            .body(consultas.sesionesCurso(periodoId, cursoId));
    }

    @GetMapping(value = "/cursos/{cursoId}/exportar.csv", produces = "text/csv;charset=UTF-8")
    public ResponseEntity<String> csv(
            @PathVariable Long periodoId, @PathVariable Long cursoId) {
        return ResponseEntity.ok()
            .cacheControl(CacheControl.noStore())
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=horario-curso-" + cursoId + ".csv")
            .body(consultas.csvCurso(periodoId, cursoId));
    }
}
