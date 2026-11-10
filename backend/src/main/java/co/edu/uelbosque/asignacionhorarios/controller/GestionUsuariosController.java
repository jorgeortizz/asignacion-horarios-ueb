package co.edu.uelbosque.asignacionhorarios.controller;

import co.edu.uelbosque.asignacionhorarios.service.GestionUsuariosService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

/** Administración de cuentas. La ruta completa se protege en SeguridadConfig. */
@RestController
@RequestMapping("/api/v1/admin/usuarios")
public class GestionUsuariosController {
    private final GestionUsuariosService servicio;

    public GestionUsuariosController(GestionUsuariosService servicio) {
        this.servicio = servicio;
    }

    public record CrearUsuario(
        @NotBlank @Size(min = 3, max = 100) String identificador,
        @NotBlank @Size(min = 12, max = 72) String password,
        @NotBlank String rol,
        Long docenteId
    ) {}

    public record CambiarEstado(@NotNull Boolean activo) {}

    @GetMapping
    public ResponseEntity<List<GestionUsuariosService.UsuarioDto>> listar() {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
            .body(servicio.listar());
    }

    @PostMapping
    public ResponseEntity<GestionUsuariosService.UsuarioDto> crear(
            @Valid @RequestBody CrearUsuario peticion) {
        var usuario = servicio.crear(peticion.identificador(), peticion.password(),
            peticion.rol(), peticion.docenteId());
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore())
            .body(usuario);
    }

    @PatchMapping("/{id}/estado")
    public ResponseEntity<GestionUsuariosService.UsuarioDto> estado(
            @PathVariable Long id, @Valid @RequestBody CambiarEstado peticion,
            Authentication autenticacion) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
            .body(servicio.cambiarEstado(id, peticion.activo(), autenticacion));
    }
}
