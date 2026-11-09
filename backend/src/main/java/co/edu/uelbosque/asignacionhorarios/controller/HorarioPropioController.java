package co.edu.uelbosque.asignacionhorarios.controller;

import co.edu.uelbosque.asignacionhorarios.dto.Respuestas;
import co.edu.uelbosque.asignacionhorarios.security.UsuarioPrincipal;
import co.edu.uelbosque.asignacionhorarios.service.ConsultaPublicaService;
import co.edu.uelbosque.asignacionhorarios.service.PeriodosPublicadosDocenteService;
import java.util.List;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** No recibe docenteId: siempre lo obtiene de la sesión autenticada. */
@RestController
@RequestMapping("/api/v1/docentes/me")
public class HorarioPropioController {
    private final ConsultaPublicaService consultas;
    private final PeriodosPublicadosDocenteService periodos;

    public HorarioPropioController(ConsultaPublicaService consultas, PeriodosPublicadosDocenteService periodos) {
        this.consultas = consultas;
        this.periodos = periodos;
    }

    public record HorarioPropio(Long periodoId, Long docenteId, List<Respuestas.SesionDto> sesiones) {}

    /** Lista solo los períodos con sesiones publicadas del docente de la sesión. */
    @GetMapping("/periodos-publicados")
    public ResponseEntity<List<PeriodosPublicadosDocenteService.PeriodoDisponible>> periodosPublicados(
            @AuthenticationPrincipal UsuarioPrincipal principal) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
            .body(periodos.listarParaDocente(principal.docenteId()));
    }

    @GetMapping("/horario-publicado")
    public ResponseEntity<HorarioPropio> horarioPublicado(
            @RequestParam Long periodoId, @AuthenticationPrincipal UsuarioPrincipal principal) {
        Long docenteId = principal.docenteId();
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
            .body(new HorarioPropio(periodoId, docenteId,
                consultas.sesionesDocente(periodoId, docenteId)));
    }
}
