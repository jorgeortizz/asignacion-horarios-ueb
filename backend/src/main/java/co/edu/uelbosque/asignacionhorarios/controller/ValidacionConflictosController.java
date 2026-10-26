package co.edu.uelbosque.asignacionhorarios.controller;
import co.edu.uelbosque.asignacionhorarios.dto.Peticiones;
import co.edu.uelbosque.asignacionhorarios.validation.ResultadoValidacion;
import co.edu.uelbosque.asignacionhorarios.service.ValidacionService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/v1/horarios")
public class ValidacionConflictosController {
    private final ValidacionService servicio;
    public ValidacionConflictosController(ValidacionService servicio) {this.servicio=servicio;}
    @PostMapping("/{id}/validar") public ResultadoValidacion validar(@PathVariable Long id,
      @Valid @RequestBody Peticiones.Previsualizar p) {return servicio.previsualizar(id,p);}
}
