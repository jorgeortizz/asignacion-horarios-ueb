package co.edu.uelbosque.asignacionhorarios.controller;

import co.edu.uelbosque.asignacionhorarios.model.CodigoRol;
import co.edu.uelbosque.asignacionhorarios.service.AdministracionUsuariosService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Registro de cuentas SOLO para Comité Táctico, protegido por SeguridadConfig. */
@RestController
@RequestMapping("/api/v1/usuarios")
public class AdministracionUsuariosController {
    private final AdministracionUsuariosService servicio;

    public AdministracionUsuariosController(AdministracionUsuariosService servicio) {
        this.servicio = servicio;
    }

    public record CrearCuenta(
        @NotBlank @Size(min = 3, max = 100) String identificador,
        @NotBlank @Size(min = 12, max = 256) String password,
        @NotNull CodigoRol rol,
        Long docenteId
    ) {}

    @PostMapping
    public ResponseEntity<AdministracionUsuariosService.CuentaCreada> crear(
            @Valid @RequestBody CrearCuenta peticion) {
        var creada = servicio.crear(peticion.identificador(), peticion.password(),
            peticion.rol(), peticion.docenteId());
        return ResponseEntity.status(HttpStatus.CREATED).cacheControl(CacheControl.noStore())
            .body(creada);
    }
}
