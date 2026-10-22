package co.edu.uelbosque.asignacionhorarios.model;

import jakarta.persistence.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;

@Entity
@Table(name="sesion")
public class Sesion {
    @Id
    @GeneratedValue(strategy=GenerationType.IDENTITY)
    @Column(name="id")
    private Long id;

    @ManyToOne(fetch=FetchType.LAZY, optional=false)
        @JoinColumn(name="horario_id", nullable=false)
    private Horario horario;

    @ManyToOne(fetch=FetchType.LAZY, optional=false)
        @JoinColumn(name="grupo_id", nullable=false)
    private Grupo grupo;

    @Column(name="dia", nullable=false)
    private byte dia;

    @Column(name="hora_inicio", nullable=false)
    private LocalTime horaInicio;

    @Column(name="hora_fin", nullable=false)
    private LocalTime horaFin;

    public Sesion() {}

    public Long getId() { return id; }

    public Horario getHorario() { return horario; }
    public void setHorario(Horario value) { this.horario = value; }

    public Grupo getGrupo() { return grupo; }
    public void setGrupo(Grupo value) { this.grupo = value; }

    public byte getDia() { return dia; }
    public void setDia(byte value) { this.dia = value; }

    public LocalTime getHoraInicio() { return horaInicio; }
    public void setHoraInicio(LocalTime value) { this.horaInicio = value; }

    public LocalTime getHoraFin() { return horaFin; }
    public void setHoraFin(LocalTime value) { this.horaFin = value; }

}
