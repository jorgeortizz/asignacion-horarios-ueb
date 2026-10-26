package co.edu.uelbosque.asignacionhorarios.model;

import jakarta.persistence.*;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Max;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;

@Entity
@Table(name="restriccion_horaria", uniqueConstraints=@UniqueConstraint(
    name="uk_restriccion_horaria_franja", columnNames={"docente_id", "dia", "hora_inicio", "hora_fin", "tipo", "sentido"}))
public class RestriccionHoraria {
    @Id
    @GeneratedValue(strategy=GenerationType.IDENTITY)
    @Column(name="id")
    private Long id;

    @ManyToOne(fetch=FetchType.LAZY, optional=false)
        @JoinColumn(name="docente_id", nullable=false, foreignKey=@ForeignKey(name="fk_restriccion_horaria_docente"))
    private Docente docente;

    // API y SQL conservan 1=lunes ... 6=sabado.
    @Min(1)
    @Max(6)
    @JdbcTypeCode(SqlTypes.TINYINT)
    @Column(name="dia", nullable=false)
    private byte dia;

    @Column(name="hora_inicio", nullable=false)
    private LocalTime horaInicio;

    @Column(name="hora_fin", nullable=false)
    private LocalTime horaFin;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
        @Column(name="tipo", nullable=false, length=12)
    private TipoRestriccion tipo;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
        @Column(name="sentido", nullable=false, length=15)
    private SentidoRestriccion sentido;

    public RestriccionHoraria() {}

    public Long getId() { return id; }

    public Docente getDocente() { return docente; }
    public void setDocente(Docente value) { this.docente = value; }

    public byte getDia() { return dia; }
    public void setDia(byte value) { this.dia = value; }

    public LocalTime getHoraInicio() { return horaInicio; }
    public void setHoraInicio(LocalTime value) { this.horaInicio = value; }

    public LocalTime getHoraFin() { return horaFin; }
    public void setHoraFin(LocalTime value) { this.horaFin = value; }

    public TipoRestriccion getTipo() { return tipo; }
    public void setTipo(TipoRestriccion value) { this.tipo = value; }

    public SentidoRestriccion getSentido() { return sentido; }
    public void setSentido(SentidoRestriccion value) { this.sentido = value; }

}
