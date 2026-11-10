package co.edu.uelbosque.asignacionhorarios.service;

import co.edu.uelbosque.asignacionhorarios.model.CodigoRol;
import co.edu.uelbosque.asignacionhorarios.model.Docente;
import co.edu.uelbosque.asignacionhorarios.model.Usuario;
import co.edu.uelbosque.asignacionhorarios.repository.DocenteRepository;
import co.edu.uelbosque.asignacionhorarios.repository.RolRepository;
import co.edu.uelbosque.asignacionhorarios.repository.UsuarioRepository;
import co.edu.uelbosque.asignacionhorarios.security.UsuarioPrincipal;
import java.nio.charset.StandardCharsets;
import java.util.Comparator;
import java.util.List;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/** Gestiona cuentas; nunca entrega el hash ni las contraseñas al frontend. */
@Service
public class GestionUsuariosService {
    public record UsuarioDto(Long id, String identificador, String rol,
                             Long docenteId, String docenteNombre, boolean activo) {}

    private final UsuarioRepository usuarios;
    private final RolRepository roles;
    private final DocenteRepository docentes;
    private final PasswordEncoder encoder;

    public GestionUsuariosService(UsuarioRepository usuarios, RolRepository roles,
                                  DocenteRepository docentes, PasswordEncoder encoder) {
        this.usuarios = usuarios;
        this.roles = roles;
        this.docentes = docentes;
        this.encoder = encoder;
    }

    @Transactional(readOnly = true)
    public List<UsuarioDto> listar() {
        return usuarios.findAll().stream()
            .map(this::dto)
            .sorted(Comparator.comparing(UsuarioDto::identificador, String.CASE_INSENSITIVE_ORDER))
            .toList();
    }

    @Transactional
    public UsuarioDto crear(String identificador, String password, String codigo, Long docenteId) {
        String nombre = identificador == null ? "" : identificador.strip();
        if (nombre.length() < 3 || nombre.length() > 100) {
            throw error(HttpStatus.BAD_REQUEST, "El identificador debe tener entre 3 y 100 caracteres");
        }
        if (password == null || password.length() < 12 || password.length() > 72 ||
                password.getBytes(StandardCharsets.UTF_8).length > 72) {
            throw error(HttpStatus.BAD_REQUEST, "La contraseña debe tener entre 12 y 72 bytes UTF-8");
        }
        final CodigoRol codigoRol;
        try {
            codigoRol = CodigoRol.valueOf(codigo);
        } catch (RuntimeException ex) {
            throw error(HttpStatus.BAD_REQUEST, "Rol no reconocido");
        }
        if (codigoRol == CodigoRol.ESTUDIANTE) {
            throw error(HttpStatus.BAD_REQUEST, "No se habilitarán cuentas del módulo de estudiantes");
        }
        if (usuarios.findByIdentificadorIgnoreCase(nombre).isPresent()) {
            throw error(HttpStatus.CONFLICT, "Ya existe una cuenta con ese identificador");
        }
        Docente docente = null;
        if (codigoRol == CodigoRol.DOCENTE) {
            if (docenteId == null || docenteId <= 0) {
                throw error(HttpStatus.BAD_REQUEST, "Selecciona el docente asociado a la cuenta");
            }
            docente = docentes.findById(docenteId)
                .orElseThrow(() -> error(HttpStatus.BAD_REQUEST, "El docente no existe"));
            if (usuarios.existsByDocenteId(docenteId)) {
                throw error(HttpStatus.CONFLICT, "El docente ya tiene una cuenta de usuario");
            }
        } else if (docenteId != null) {
            throw error(HttpStatus.BAD_REQUEST, "Solo el rol DOCENTE admite asociación docente");
        }
        var rol = roles.findByCodigo(codigoRol)
            .orElseThrow(() -> error(HttpStatus.BAD_REQUEST, "El rol no está instalado en la base de datos"));
        try {
            var creado = usuarios.saveAndFlush(new Usuario(nombre, encoder.encode(password), rol, docente));
            return dto(creado);
        } catch (DataIntegrityViolationException ex) {
            throw error(HttpStatus.CONFLICT, "El identificador o docente ya está registrado");
        }
    }

    @Transactional
    public UsuarioDto cambiarEstado(Long id, boolean activo, Authentication autenticacion) {
        var usuario = usuarios.findById(id)
            .orElseThrow(() -> error(HttpStatus.NOT_FOUND, "No existe el usuario"));
        if (!activo && usuario.isActivo()) {
            if (autenticacion != null && autenticacion.getPrincipal() instanceof UsuarioPrincipal principal
                    && principal.id().equals(id)) {
                throw error(HttpStatus.CONFLICT, "No puedes desactivar tu propia cuenta");
            }
            if (usuario.getRol().getCodigo() == CodigoRol.COMITE_TACTICO) {
                long comitesActivos = usuarios.findAll().stream()
                    .filter(u -> u.isActivo() && u.getRol().getCodigo() == CodigoRol.COMITE_TACTICO)
                    .count();
                if (comitesActivos <= 1) {
                    throw error(HttpStatus.CONFLICT, "Debe permanecer al menos una cuenta de Comité Táctico activa");
                }
            }
        }
        usuario.setActivo(activo);
        return dto(usuarios.saveAndFlush(usuario));
    }

    private UsuarioDto dto(Usuario u) {
        var docente = u.getDocente();
        return new UsuarioDto(u.getId(), u.getIdentificador(), u.getRol().getCodigo().name(),
            docente == null ? null : docente.getId(),
            docente == null ? null : docente.getNombre(), u.isActivo());
    }

    private static ResponseStatusException error(HttpStatus estado, String mensaje) {
        return new ResponseStatusException(estado, mensaje);
    }
}
