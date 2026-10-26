package co.edu.uelbosque.asignacionhorarios.model;

import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;

@Entity
@Table(name = "docente")
public class Docente {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "nombre", nullable = false, length = 150)
    private String nombre;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    @Column(name = "tipo_vinculacion", nullable = false, length = 15)
    private TipoVinculacion tipoVinculacion;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "docente_especialidad", joinColumns = @JoinColumn(name = "docente_id", nullable = false, foreignKey = @ForeignKey(name = "fk_docente_especialidad_docente")))
    @Column(name = "especialidad", nullable = false, length = 100)
    private Set<String> especialidades = new LinkedHashSet<>();

    @ManyToMany(fetch = FetchType.LAZY)
    @JoinTable(name = "docente_curso", joinColumns = @JoinColumn(name = "docente_id"), inverseJoinColumns = @JoinColumn(name = "curso_id"))
    private Set<Curso> cursosHabilitados = new LinkedHashSet<>();

    public Set<Curso> getCursosHabilitados() {
        return cursosHabilitados;
    }

    public void setCursosHabilitados(Set<Curso> cursosHabilitados) {
        this.cursosHabilitados = cursosHabilitados;
    }

    public Docente() {
    }

    public Long getId() {
        return id;
    }

    public String getNombre() {
        return nombre;
    }

    public void setNombre(String value) {
        this.nombre = value;
    }

    public TipoVinculacion getTipoVinculacion() {
        return tipoVinculacion;
    }

    public void setTipoVinculacion(TipoVinculacion value) {
        this.tipoVinculacion = value;
    }

    public Set<String> getEspecialidades() {
        return especialidades;
    }

    public void setEspecialidades(Set<String> value) {
        this.especialidades = value;
    }

}
