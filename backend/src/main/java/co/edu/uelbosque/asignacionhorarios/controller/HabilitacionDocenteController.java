package co.edu.uelbosque.asignacionhorarios.controller;

import java.util.List;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import co.edu.uelbosque.asignacionhorarios.dto.ActualizarCursosDocenteRequest;
import co.edu.uelbosque.asignacionhorarios.service.HabilitacionDocenteService;
import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/docentes")
public class HabilitacionDocenteController {

    private final HabilitacionDocenteService servicio;

    public HabilitacionDocenteController(
            HabilitacionDocenteService servicio) {
        this.servicio = servicio;
    }

    @GetMapping("/{id}/cursos-habilitados")
    public List<Long> obtener(@PathVariable Long id) {
        return servicio.obtenerCursos(id);
    }

    @PutMapping("/{id}/cursos-habilitados")
    public List<Long> actualizar(
            @PathVariable Long id,
            @Valid @RequestBody
            ActualizarCursosDocenteRequest request) {

        return servicio.actualizarCursos(
            id,
            request.cursoIds()
        );
    }
}