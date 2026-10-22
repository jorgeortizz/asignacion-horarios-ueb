package co.edu.uelbosque.asignacionhorarios.model;

import jakarta.persistence.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;

@Entity
@Table(name="curso")
public class Curso {
    @Id
    @GeneratedValue(strategy=GenerationType.IDENTITY)
    @Column(name="id")
    private Long id;

    @Column(name="codigo", length=20, unique=true)
    private String codigo;

    @Column(name="nombre", nullable=false, length=150)
    private String nombre;

    @Column(name="sesiones_semanales", nullable=false)
    private byte sesionesSemanales;

    @Column(name="duracion_sesion_min", nullable=false)
    private short duracionSesionMin;

    @Column(name="necesita_aula_especial", nullable=false)
    private boolean necesitaAulaEspecial;

    public Curso() {}

    public Long getId() { return id; }

    public String getCodigo() { return codigo; }
    public void setCodigo(String value) { this.codigo = value; }

    public String getNombre() { return nombre; }
    public void setNombre(String value) { this.nombre = value; }

    public byte getSesionesSemanales() { return sesionesSemanales; }
    public void setSesionesSemanales(byte value) { this.sesionesSemanales = value; }

    public short getDuracionSesionMin() { return duracionSesionMin; }
    public void setDuracionSesionMin(short value) { this.duracionSesionMin = value; }

    public boolean isNecesitaAulaEspecial() { return necesitaAulaEspecial; }
    public void setNecesitaAulaEspecial(boolean value) { this.necesitaAulaEspecial = value; }

}
