package co.edu.uelbosque.asignacionhorarios.dto;
import co.edu.uelbosque.asignacionhorarios.model.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;
/** Contrato REST preliminar, independiente de la representación de tablas. */
public final class Peticiones {
    private Peticiones() {}
    public record Restriccion(@NotNull Byte dia, @NotNull LocalTime horaInicio, @NotNull LocalTime horaFin,
                              @NotNull TipoRestriccion tipo, @NotNull SentidoRestriccion sentido) {}
    public record Docente(@NotBlank String nombre, @NotNull TipoVinculacion tipoVinculacion,
                          Set<String> especialidades, boolean sinRestricciones, List<@Valid Restriccion> restricciones) {}
    public record Curso(String codigo, @NotBlank String nombre,
                        @NotNull @Min(1) @Max(10) Integer sesionesSemanales,
                        @NotNull @Min(30) @Max(240) Integer duracionSesionMin,
                        boolean necesitaAulaEspecial) {}
    public record Grupo(@NotNull Long periodoId, @NotNull Long cursoId, @NotNull Long docenteId,
                        @NotBlank String codigo, Integer cupoMaximo, Integer cupoMinimo,
                        @NotNull @Min(0) Integer inscritos) {}
    public record Periodo(@NotBlank String nombre, @NotNull LocalDate fechaInicio,
                          @NotNull LocalDate fechaFin) {}
    public record Parametros(@NotNull LocalTime horaInicioSemana, @NotNull LocalTime horaFinSemana,
                             @NotNull LocalTime horaInicioSabado, @NotNull LocalTime horaFinSabado,
                             @NotNull LocalTime almuerzoInicio, @NotNull LocalTime almuerzoFin,
                             @NotNull @Min(30) @Max(240) Integer duracionBloqueMin,
                             @NotNull @Min(1) @Max(10) Integer maxSesionesSemana,
                             @NotNull @Min(1) Integer cupoMaximoBase,
                             @NotNull @DecimalMin("0") @DecimalMax("100") BigDecimal toleranciaCupoPct,
                             @NotNull @Min(0) Integer cupoMinimo) {}
    public record Movimiento(@NotNull @Min(1) @Max(6) Byte dia, @NotNull LocalTime horaInicio) {}
    public record Previsualizar(@NotNull Long grupoId, @NotNull @Min(1) @Max(6) Byte dia,
                                @NotNull LocalTime horaInicio, Long sesionExcluida) {}
}
