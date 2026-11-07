package co.edu.uelbosque.asignacionhorarios.model;

import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "rol", uniqueConstraints =
    @UniqueConstraint(name = "uk_rol_codigo", columnNames = "codigo"))
public class Rol {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.VARCHAR)
    @Column(name = "codigo", nullable = false, length = 32)
    private CodigoRol codigo;

    @Column(name = "nombre", nullable = false, length = 100)
    private String nombre;

    protected Rol() {}

    public Rol(CodigoRol codigo, String nombre) {
        this.codigo = codigo;
        this.nombre = nombre;
    }

    public Long getId() { return id; }
    public CodigoRol getCodigo() { return codigo; }
    public String getNombre() { return nombre; }
}
