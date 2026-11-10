package co.edu.uelbosque.asignacionhorarios.controller;

import co.edu.uelbosque.asignacionhorarios.service.AulasService;
import co.edu.uelbosque.asignacionhorarios.service.AulasService.*;
import java.util.List;
import co.edu.uelbosque.asignacionhorarios.service.ConsultaPublicaService;
import co.edu.uelbosque.asignacionhorarios.dto.Respuestas;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
public class AulasController {
    private final AulasService aulas;
    private final ConsultaPublicaService consultas;
    public AulasController(AulasService aulas, ConsultaPublicaService consultas) {
        this.aulas=aulas; this.consultas=consultas;
    }

    @GetMapping("/aulas") public List<Aula> listar() {return aulas.listar();}
    @PostMapping("/aulas") public Aula crear(@RequestBody Aula aula) {return aulas.guardar(null,aula);}
    @PutMapping("/aulas/{id}") public Aula actualizar(@PathVariable Long id,@RequestBody Aula aula) {
        return aulas.guardar(id,aula);
    }
    @GetMapping("/aulas/requisitos") public List<TipoCurso> requisitos() {return aulas.requisitos();}
    @PutMapping("/aulas/cursos/{cursoId}/tipo") public TipoCurso curso(@PathVariable Long cursoId,
                                                           @RequestBody TipoCurso dto) {
        return aulas.guardarRequisito(cursoId,dto.tipo());
    }
    @GetMapping("/aulas/horarios/{horarioId}/asignaciones") public List<Asignacion> asignaciones(@PathVariable Long horarioId) {
        return aulas.porHorario(horarioId,false);
    }
    @PostMapping("/aulas/horarios/{horarioId}/autoasignar") public Resultado auto(@PathVariable Long horarioId) {
        return aulas.automatico(horarioId);
    }
    @PutMapping("/aulas/horarios/{horarioId}/sesiones/{sesionId}") public void asignar(
            @PathVariable Long horarioId,@PathVariable Long sesionId,@RequestBody AulaSeleccion body) {
        aulas.asignar(horarioId,sesionId,body.aulaId());
    }
    /** Completa aulas faltantes en publicados previos sin alterar clases o franjas. */
    @PostMapping("/aulas/horarios/{horarioId}/completar-publicado")
    public Resultado completarPublicado(@PathVariable Long horarioId) {
        return aulas.completarPublicado(horarioId);
    }

    /** CSV anónimo del horario publicado vigente con columna aula. */
    @GetMapping(value="/publico/aulas/periodos/{periodoId}/cursos/{cursoId}/exportar.csv",
                produces="text/csv;charset=UTF-8")
    public ResponseEntity<String> csvConAulas(@PathVariable Long periodoId,@PathVariable Long cursoId) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
            .header(HttpHeaders.CONTENT_DISPOSITION,
                "attachment; filename=horario-curso-" + cursoId + "-aulas.csv")
            .body(aulas.csvConAulas(consultas,periodoId,cursoId));
    }

    /** Anónimo y solo para el horario publicado vigente; no expone aulas de borradores. */
    @GetMapping("/publico/aulas/horarios/{horarioId}") public ResponseEntity<List<Asignacion>> publico(
            @PathVariable Long horarioId) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(aulas.porHorario(horarioId,true));
    }
}
