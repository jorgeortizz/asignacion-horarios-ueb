package co.edu.uelbosque.asignacionhorarios.model;

import jakarta.persistence.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;

@Entity
@Table(name="horario")
public class Horario {
    @Id
    @GeneratedValue(strategy=GenerationType.IDENTITY)
    @Column(name="id")
    private Long id;

    @ManyToOne(fetch=FetchType.LAZY, optional=false)
        @JoinColumn(name="periodo_id", nullable=false)
    private PeriodoAcademico periodo;

    @Enumerated(EnumType.STRING)
        @Column(name="estado", nullable=false, length=10)
    private EstadoHorario estado;

    @Column(name="fecha_creacion", nullable=false)
    private LocalDateTime fechaCreacion;

    @Column(name="fecha_publicacion")
    private LocalDateTime fechaPublicacion;

    @Version
        @Column(name="version", nullable=false)
    private int version;

    public Horario() {}

    public Long getId() { return id; }

    public PeriodoAcademico getPeriodo() { return periodo; }
    public void setPeriodo(PeriodoAcademico value) { this.periodo = value; }

    public EstadoHorario getEstado() { return estado; }
    public void setEstado(EstadoHorario value) { this.estado = value; }

    public LocalDateTime getFechaCreacion() { return fechaCreacion; }
    public void setFechaCreacion(LocalDateTime value) { this.fechaCreacion = value; }

    public LocalDateTime getFechaPublicacion() { return fechaPublicacion; }
    public void setFechaPublicacion(LocalDateTime value) { this.fechaPublicacion = value; }

    public int getVersion() { return version; }
    public void setVersion(int value) { this.version = value; }

    @PrePersist
    void beforeInsert() {
        if (estado == null) estado = EstadoHorario.BORRADOR;
        if (fechaCreacion == null) fechaCreacion = LocalDateTime.now();
    }
}
