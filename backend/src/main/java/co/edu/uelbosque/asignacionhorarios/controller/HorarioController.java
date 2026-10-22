package co.edu.uelbosque.asignacionhorarios.controller;
import co.edu.uelbosque.asignacionhorarios.dto.*;
import co.edu.uelbosque.asignacionhorarios.service.HorarioService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/v1")
public class HorarioController {
    private final HorarioService servicio;
    public HorarioController(HorarioService servicio) {this.servicio=servicio;}
    @GetMapping("/horarios/{id}") public Respuestas.HorarioDto ver(@PathVariable Long id) {return servicio.detalle(id);}
    @GetMapping("/periodos/{id}/horarios") public List<Respuestas.HorarioDto> historico(@PathVariable Long id) {return servicio.historico(id);}
    @PostMapping("/horarios/{id}/publicar") public Respuestas.HorarioDto publicar(@PathVariable Long id) {return servicio.publicar(id);}
    @PutMapping("/horarios/{id}/sesiones/{sesionId}") public Respuestas.MovimientoResultado mover(
         @PathVariable Long id,@PathVariable Long sesionId,@Valid @RequestBody Peticiones.Movimiento movimiento) {
        return servicio.mover(id,sesionId,movimiento);
    }
}
