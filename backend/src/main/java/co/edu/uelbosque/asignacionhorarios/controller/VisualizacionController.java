package co.edu.uelbosque.asignacionhorarios.controller;
import co.edu.uelbosque.asignacionhorarios.dto.Respuestas;
import co.edu.uelbosque.asignacionhorarios.service.ConsultaService;
import java.util.List;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/v1/horarios/{id}")
public class VisualizacionController {
    private final ConsultaService servicio;
    public VisualizacionController(ConsultaService servicio) {this.servicio=servicio;}
    @GetMapping("/sesiones") public List<Respuestas.SesionDto> sesiones(@PathVariable Long id,
      @RequestParam(required=false) Long docenteId,@RequestParam(required=false) Long cursoId,
      @RequestParam(required=false,defaultValue="true") Boolean soloPublicados) {
        return servicio.consultar(id,docenteId,cursoId,soloPublicados);
    }
    @GetMapping(value="/exportar.csv",produces="text/csv;charset=UTF-8")
    public ResponseEntity<String> exportar(@PathVariable Long id,
      @RequestParam(required=false) Long docenteId,@RequestParam(required=false) Long cursoId) {
        return ResponseEntity.ok().header(HttpHeaders.CONTENT_DISPOSITION,"attachment; filename=horario-"+id+".csv")
          .body(servicio.exportarCsv(id,docenteId,cursoId));
    }
}
