package co.edu.uelbosque.asignacionhorarios.security;

import co.edu.uelbosque.asignacionhorarios.repository.UsuarioRepository;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UsuarioDetailsService implements UserDetailsService {
    private final UsuarioRepository usuarios;

    public UsuarioDetailsService(UsuarioRepository usuarios) {
        this.usuarios = usuarios;
    }

    @Override
    @Transactional(readOnly = true)
    public UserDetails loadUserByUsername(String identificador) throws UsernameNotFoundException {
        if (identificador == null || identificador.isBlank()) {
            throw new UsernameNotFoundException("Credenciales inválidas");
        }
        var usuario = usuarios.findByIdentificadorIgnoreCase(identificador.strip())
            .orElseThrow(() -> new UsernameNotFoundException("Credenciales inválidas"));
        if (usuario.getRol() == null || usuario.getRol().getCodigo() == null) {
            throw new UsernameNotFoundException("Credenciales inválidas");
        }
        return new UsuarioPrincipal(
            usuario.getId(), usuario.getIdentificador(), usuario.getPasswordHash(),
            usuario.isActivo(), usuario.getRol().getCodigo(),
            usuario.getDocente() == null ? null : usuario.getDocente().getId()
        );
    }
}
