package co.edu.uelbosque.asignacionhorarios.security;

import co.edu.uelbosque.asignacionhorarios.model.CodigoRol;
import java.io.Serial;
import java.util.Collection;
import java.util.List;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;

/** Datos mínimos y serializables que se guardan en la sesión; no es una entidad JPA. */
public record UsuarioPrincipal(
        Long id,
        String identificador,
        String passwordHash,
        boolean activo,
        CodigoRol rol,
        Long docenteId
) implements UserDetails {
    @Serial private static final long serialVersionUID = 1L;

    @Override public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(new SimpleGrantedAuthority("ROLE_" + rol.name()));
    }

    @Override public String getPassword() { return passwordHash; }
    @Override public String getUsername() { return identificador; }
    @Override public boolean isEnabled() { return activo; }

    /** Nunca incluir el hash en el toString() del principal de sesión. */
    @Override public String toString() {
        return "UsuarioPrincipal[id=" + id + ", identificador=" + identificador
            + ", rol=" + rol + "]";
    }
}
