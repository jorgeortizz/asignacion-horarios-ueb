package co.edu.uelbosque.asignacionhorarios.model;

import jakarta.persistence.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;

@Entity
@Table(name="grupo")
public class Grupo {
    @Id
    @GeneratedValue(strategy=GenerationType.IDENTITY)
    @Column(name="id")
    private Long id;

    @ManyToOne(fetch=FetchType.LAZY, optional=false)
        @JoinColumn(name="periodo_id", nullable=false)
    private PeriodoAcademico periodo;

    @ManyToOne(fetch=FetchType.LAZY, optional=false)
        @JoinColumn(name="curso_id", nullable=false)
    private Curso curso;

    @ManyToOne(fetch=FetchType.LAZY, optional=false)
        @JoinColumn(name="docente_id", nullable=false)
    private Docente docente;

    @Column(name="codigo", nullable=false, length=10)
    private String codigo;

    @Column(name="cupo_maximo", nullable=false)
    private short cupoMaximo;

    @Column(name="cupo_minimo", nullable=false)
    private short cupoMinimo;

    @Column(name="inscritos", nullable=false)
    private short inscritos;

    public Grupo() {}

    public Long getId() { return id; }

    public PeriodoAcademico getPeriodo() { return periodo; }
    public void setPeriodo(PeriodoAcademico value) { this.periodo = value; }

    public Curso getCurso() { return curso; }
    public void setCurso(Curso value) { this.curso = value; }

    public Docente getDocente() { return docente; }
    public void setDocente(Docente value) { this.docente = value; }

    public String getCodigo() { return codigo; }
    public void setCodigo(String value) { this.codigo = value; }

    public short getCupoMaximo() { return cupoMaximo; }
    public void setCupoMaximo(short value) { this.cupoMaximo = value; }

    public short getCupoMinimo() { return cupoMinimo; }
    public void setCupoMinimo(short value) { this.cupoMinimo = value; }

    public short getInscritos() { return inscritos; }
    public void setInscritos(short value) { this.inscritos = value; }

}
