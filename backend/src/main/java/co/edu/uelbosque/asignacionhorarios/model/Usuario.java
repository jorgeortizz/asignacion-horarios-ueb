package co.edu.uelbosque.asignacionhorarios.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;

/** Cuenta de acceso. No se usa como DTO de respuesta. */
@Entity
@Table(name = "usuario", uniqueConstraints = {
    @UniqueConstraint(name = "uk_usuario_identificador", columnNames = "identificador"),
    @UniqueConstraint(name = "uk_usuario_docente", columnNames = "docente_id")
})
public class Usuario {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "identificador", nullable = false, length = 100)
    private String identificador;

    @JsonIgnore
    @Column(name = "password_hash", nullable = false, length = 255)
    private String passwordHash;

    @Column(name = "activo", nullable = false)
    private boolean activo = true;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "rol_id", nullable = false,
        foreignKey = @ForeignKey(name = "fk_usuario_rol"))
    private Rol rol;

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "docente_id", unique = true,
        foreignKey = @ForeignKey(name = "fk_usuario_docente"))
    private Docente docente;

    protected Usuario() {}

    /** El hash se generará con PasswordEncoder en la Etapa 3. Nunca texto plano. */
    public Usuario(String identificador, String passwordHash, Rol rol, Docente docente) {
        this.identificador = identificador;
        this.passwordHash = passwordHash;
        this.rol = rol;
        this.docente = docente;
    }

    @PrePersist
    @PreUpdate
    void validarAsociacionDocente() {
        if (rol != null && rol.getCodigo() == CodigoRol.DOCENTE && docente == null) {
            throw new IllegalStateException("Una cuenta DOCENTE requiere asociación con Docente");
        }
    }

    public Long getId() { return id; }
    public String getIdentificador() { return identificador; }
    public String getPasswordHash() { return passwordHash; }
    public boolean isActivo() { return activo; }
    public void setActivo(boolean activo) { this.activo = activo; }
    public Rol getRol() { return rol; }
    public Docente getDocente() { return docente; }
}
