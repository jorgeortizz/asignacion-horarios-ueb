package co.edu.uelbosque.asignacionhorarios.controller;

import java.util.List;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Catálogo anónimo de períodos que tienen un horario publicado vigente. */
@RestController
@RequestMapping("/api/v1/publico")
public class PeriodosPublicadosPublicosController {
    private final JdbcTemplate jdbc;

    public PeriodosPublicadosPublicosController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public record PeriodoPublicado(Long id, String nombre) {}

    @GetMapping("/periodos-publicados")
    @Transactional(readOnly = true)
    public ResponseEntity<List<PeriodoPublicado>> listar() {
        // Reutiliza la misma vista que resuelve el horario vigente en HorarioRepository.
        // Nunca se exponen períodos que solo tienen borradores.
        var periodos = jdbc.query("""
            SELECT p.id, p.nombre
            FROM periodo_academico p
            WHERE EXISTS (
                SELECT 1
                FROM v_horario_vigente v
                JOIN horario h ON h.id = v.horario_id
                WHERE v.periodo_id = p.id AND h.estado = 'PUBLICADO'
            )
            ORDER BY p.nombre DESC, p.id DESC
            """, (rs, fila) -> new PeriodoPublicado(rs.getLong("id"), rs.getString("nombre")));
        return ResponseEntity.ok()
            .cacheControl(CacheControl.noStore())
            .body(periodos);
    }
}
