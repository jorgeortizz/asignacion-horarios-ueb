package co.edu.uelbosque.asignacionhorarios.model;

import jakarta.persistence.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;

@Entity
@Table(name="periodo_academico")
public class PeriodoAcademico {
    @Id
    @GeneratedValue(strategy=GenerationType.IDENTITY)
    @Column(name="id")
    private Long id;

    @Column(name="nombre", nullable=false, length=20)
    private String nombre;

    @Column(name="fecha_inicio", nullable=false)
    private LocalDate fechaInicio;

    @Column(name="fecha_fin", nullable=false)
    private LocalDate fechaFin;

    @Column(name="hora_inicio_semana", nullable=false)
    private LocalTime horaInicioSemana;

    @Column(name="hora_fin_semana", nullable=false)
    private LocalTime horaFinSemana;

    @Column(name="hora_inicio_sabado", nullable=false)
    private LocalTime horaInicioSabado;

    @Column(name="hora_fin_sabado", nullable=false)
    private LocalTime horaFinSabado;

    @Column(name="almuerzo_inicio", nullable=false)
    private LocalTime almuerzoInicio;

    @Column(name="almuerzo_fin", nullable=false)
    private LocalTime almuerzoFin;

    @Column(name="duracion_bloque_min", nullable=false)
    private short duracionBloqueMin;

    @Column(name="max_sesiones_semana", nullable=false)
    private byte maxSesionesSemana;

    @Column(name="cupo_maximo_base", nullable=false)
    private short cupoMaximoBase;

    @Column(name="tolerancia_cupo_pct", nullable=false, precision=5, scale=2)
    private BigDecimal toleranciaCupoPct;

    @Column(name="cupo_minimo", nullable=false)
    private short cupoMinimo;

    public PeriodoAcademico() {}

    public Long getId() { return id; }

    public String getNombre() { return nombre; }
    public void setNombre(String value) { this.nombre = value; }

    public LocalDate getFechaInicio() { return fechaInicio; }
    public void setFechaInicio(LocalDate value) { this.fechaInicio = value; }

    public LocalDate getFechaFin() { return fechaFin; }
    public void setFechaFin(LocalDate value) { this.fechaFin = value; }

    public LocalTime getHoraInicioSemana() { return horaInicioSemana; }
    public void setHoraInicioSemana(LocalTime value) { this.horaInicioSemana = value; }

    public LocalTime getHoraFinSemana() { return horaFinSemana; }
    public void setHoraFinSemana(LocalTime value) { this.horaFinSemana = value; }

    public LocalTime getHoraInicioSabado() { return horaInicioSabado; }
    public void setHoraInicioSabado(LocalTime value) { this.horaInicioSabado = value; }

    public LocalTime getHoraFinSabado() { return horaFinSabado; }
    public void setHoraFinSabado(LocalTime value) { this.horaFinSabado = value; }

    public LocalTime getAlmuerzoInicio() { return almuerzoInicio; }
    public void setAlmuerzoInicio(LocalTime value) { this.almuerzoInicio = value; }

    public LocalTime getAlmuerzoFin() { return almuerzoFin; }
    public void setAlmuerzoFin(LocalTime value) { this.almuerzoFin = value; }

    public short getDuracionBloqueMin() { return duracionBloqueMin; }
    public void setDuracionBloqueMin(short value) { this.duracionBloqueMin = value; }

    public byte getMaxSesionesSemana() { return maxSesionesSemana; }
    public void setMaxSesionesSemana(byte value) { this.maxSesionesSemana = value; }

    public short getCupoMaximoBase() { return cupoMaximoBase; }
    public void setCupoMaximoBase(short value) { this.cupoMaximoBase = value; }

    public BigDecimal getToleranciaCupoPct() { return toleranciaCupoPct; }
    public void setToleranciaCupoPct(BigDecimal value) { this.toleranciaCupoPct = value; }

    public short getCupoMinimo() { return cupoMinimo; }
    public void setCupoMinimo(short value) { this.cupoMinimo = value; }

}
