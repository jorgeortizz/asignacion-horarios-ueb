package co.edu.uelbosque.asignacionhorarios.controller;
import co.edu.uelbosque.asignacionhorarios.dto.Peticiones;
import co.edu.uelbosque.asignacionhorarios.model.PeriodoAcademico;
import co.edu.uelbosque.asignacionhorarios.service.PeriodoService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/v1/periodos")
public class ParametrizacionController {
    private final PeriodoService servicio;
    public ParametrizacionController(PeriodoService servicio) {this.servicio=servicio;}
    @PostMapping public ResponseEntity<PeriodoAcademico> crear(@Valid @RequestBody Peticiones.Periodo p) {
        return ResponseEntity.status(HttpStatus.CREATED).body(servicio.crear(p));
    }
    @GetMapping public List<PeriodoAcademico> listar() {return servicio.listar();}
    @GetMapping("/{id}") public PeriodoAcademico obtener(@PathVariable Long id) {return servicio.obtener(id);}
    @PutMapping("/{id}/parametros") public PeriodoAcademico actualizar(@PathVariable Long id,@Valid @RequestBody Peticiones.Parametros p) {
        return servicio.actualizar(id,p);
    }
}
