package co.edu.uelbosque.asignacionhorarios.service;

import co.edu.uelbosque.asignacionhorarios.model.CodigoRol;
import co.edu.uelbosque.asignacionhorarios.model.Docente;
import co.edu.uelbosque.asignacionhorarios.model.Usuario;
import co.edu.uelbosque.asignacionhorarios.repository.DocenteRepository;
import co.edu.uelbosque.asignacionhorarios.repository.RolRepository;
import co.edu.uelbosque.asignacionhorarios.repository.UsuarioRepository;
import java.util.Locale;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Alta controlada de cuentas. Nunca expone hashes ni admite roles libres como String. */
@Service
public class AdministracionUsuariosService {
    private final UsuarioRepository usuarios;
    private final RolRepository roles;
    private final DocenteRepository docentes;
    private final PasswordEncoder encoder;

    public AdministracionUsuariosService(UsuarioRepository usuarios, RolRepository roles,
            DocenteRepository docentes, PasswordEncoder encoder) {
        this.usuarios = usuarios;
        this.roles = roles;
        this.docentes = docentes;
        this.encoder = encoder;
    }

    public record CuentaCreada(Long id, String identificador, CodigoRol rol,
                               Long docenteId, boolean activo) {}

    @Transactional
    public CuentaCreada crear(String identificador, String password,
                             CodigoRol codigoRol, Long docenteId) {
        String normalizado = identificador.strip().toLowerCase(Locale.ROOT);
        if (usuarios.findByIdentificadorIgnoreCase(normalizado).isPresent()) {
            throw new ApiException(HttpStatus.CONFLICT, "Ya existe una cuenta con ese identificador");
        }

        if (codigoRol == CodigoRol.DOCENTE && docenteId == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Las cuentas DOCENTE requieren docenteId");
        }
        if (codigoRol != CodigoRol.DOCENTE && docenteId != null) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                "Solo una cuenta DOCENTE puede tener asociación académica");
        }
        if (docenteId != null && usuarios.existsByDocenteId(docenteId)) {
            throw new ApiException(HttpStatus.CONFLICT, "Este docente ya tiene una cuenta");
        }

        var rol = roles.findByCodigo(codigoRol)
            .orElseThrow(() -> new ApiException(HttpStatus.BAD_REQUEST, "Rol no configurado"));
        Docente docente = docenteId == null ? null : Util.requerido(docentes.findById(docenteId), "Docente");
        var cuenta = usuarios.saveAndFlush(new Usuario(normalizado, encoder.encode(password), rol, docente));
        return new CuentaCreada(cuenta.getId(), cuenta.getIdentificador(), codigoRol,
            docenteId, cuenta.isActivo());
    }
}
