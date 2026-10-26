package co.edu.uelbosque.asignacionhorarios.controller;
import co.edu.uelbosque.asignacionhorarios.dto.Respuestas;
import co.edu.uelbosque.asignacionhorarios.service.GeneracionService;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/v1/periodos")
public class GeneracionHorarioController {
    private final GeneracionService generador;
    public GeneracionHorarioController(GeneracionService generador) {this.generador=generador;}
    @PostMapping("/{periodoId}/generar") public ResponseEntity<Respuestas.Generacion> generar(@PathVariable Long periodoId) {
        return ResponseEntity.status(HttpStatus.CREATED).body(generador.generar(periodoId));
    }
}
