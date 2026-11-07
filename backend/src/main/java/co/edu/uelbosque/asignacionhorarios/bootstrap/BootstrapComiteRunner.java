package co.edu.uelbosque.asignacionhorarios.bootstrap;

import co.edu.uelbosque.asignacionhorarios.model.CodigoRol;
import co.edu.uelbosque.asignacionhorarios.model.Usuario;
import co.edu.uelbosque.asignacionhorarios.repository.RolRepository;
import co.edu.uelbosque.asignacionhorarios.repository.UsuarioRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** Única cuenta inicial. No expone endpoints ni permite elegir roles por HTTP. */
@Component
@ConditionalOnProperty(name = "ueb.bootstrap.enabled", havingValue = "true")
public class BootstrapComiteRunner implements ApplicationRunner {
    private final UsuarioRepository usuarios;
    private final RolRepository roles;
    private final PasswordEncoder encoder;

    @Value("${ueb.bootstrap.identificador:}") private String identificador;
    @Value("${ueb.bootstrap.password:}") private String password;

    public BootstrapComiteRunner(UsuarioRepository usuarios, RolRepository roles, PasswordEncoder encoder) {
        this.usuarios = usuarios;
        this.roles = roles;
        this.encoder = encoder;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (usuarios.count() != 0) {
            throw new IllegalStateException("Bootstrap permitido solamente cuando usuario está vacío");
        }
        if (identificador == null || identificador.isBlank() || identificador.length() > 100) {
            throw new IllegalStateException("UEB_BOOTSTRAP_IDENTIFICADOR inválido");
        }
        if (password == null || password.length() < 12 || password.length() > 256) {
            throw new IllegalStateException("UEB_BOOTSTRAP_PASSWORD debe tener entre 12 y 256 caracteres");
        }
        var rol = roles.findByCodigo(CodigoRol.COMITE_TACTICO)
            .orElseThrow(() -> new IllegalStateException("No existe COMITE_TACTICO: compruebe Flyway V4"));
        usuarios.saveAndFlush(new Usuario(identificador.strip(), encoder.encode(password), rol, null));
        // No registrar el identificador ni la contraseña en logs.
    }
}
