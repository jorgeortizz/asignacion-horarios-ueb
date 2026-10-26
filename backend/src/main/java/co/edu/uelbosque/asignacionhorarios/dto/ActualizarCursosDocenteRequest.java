package co.edu.uelbosque.asignacionhorarios.dto;

import java.util.Set;

import jakarta.validation.constraints.NotNull;

public record ActualizarCursosDocenteRequest(
    @NotNull Set<@NotNull Long> cursoIds
) {}