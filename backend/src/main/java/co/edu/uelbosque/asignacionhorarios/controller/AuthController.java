package co.edu.uelbosque.asignacionhorarios.controller;

import co.edu.uelbosque.asignacionhorarios.security.UsuarioPrincipal;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.Map;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.logout.SecurityContextLogoutHandler;
import org.springframework.security.web.context.SecurityContextRepository;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
    private final AuthenticationManager authenticationManager;
    private final SecurityContextRepository contexts;
    private final CookieCsrfTokenRepository csrfRepository;

    public AuthController(AuthenticationManager authenticationManager,
                          SecurityContextRepository contexts,
                          CookieCsrfTokenRepository csrfRepository) {
        this.authenticationManager = authenticationManager;
        this.contexts = contexts;
        this.csrfRepository = csrfRepository;
    }

    public record Credenciales(@NotBlank @Size(max = 100) String identificador,
                              @NotBlank String password) {}

    public record SesionActual(Long id, String identificador, String rol, Long docenteId) {
        static SesionActual de(Authentication auth) {
            var principal = (UsuarioPrincipal) auth.getPrincipal();
            return new SesionActual(principal.id(), principal.identificador(),
                principal.rol().name(), principal.docenteId());
        }
    }

    @GetMapping("/csrf")
    public ResponseEntity<Map<String, String>> csrf(CsrfToken token) {
        // Obtener el token fuerza su carga y la emisión de XSRF-TOKEN al navegador.
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
            .body(Map.of("headerName", token.getHeaderName(), "token", token.getToken()));
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@Valid @RequestBody Credenciales credenciales,
                                   HttpServletRequest request, HttpServletResponse response) {
        final Authentication autenticado;
        try {
            autenticado = authenticationManager.authenticate(
                UsernamePasswordAuthenticationToken.unauthenticated(
                    credenciales.identificador().strip(), credenciales.password()));
        } catch (AuthenticationException ex) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).cacheControl(CacheControl.noStore())
                .body(Map.of("error", "Credenciales inválidas", "estado", 401));
        }

        // Sesión nueva o identificador rotado para prevenir fijación de sesión.
        if (request.getSession(false) == null) {
            request.getSession(true);
        } else {
            request.changeSessionId();
        }
        var context = SecurityContextHolder.createEmptyContext();
        context.setAuthentication(autenticado);
        SecurityContextHolder.setContext(context);
        // Un controlador que autentica manualmente debe guardar explícitamente el contexto.
        contexts.saveContext(context, request, response);
        renovarCsrf(request, response);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(SesionActual.de(autenticado));
    }

    @GetMapping("/me")
    public ResponseEntity<SesionActual> me(Authentication autenticado) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(SesionActual.de(autenticado));
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(HttpServletRequest request, HttpServletResponse response,
                                       Authentication autenticado) {
        new SecurityContextLogoutHandler().logout(request, response, autenticado);
        renovarCsrf(request, response);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    private void renovarCsrf(HttpServletRequest request, HttpServletResponse response) {
        csrfRepository.saveToken(null, request, response);
        var tokenNuevo = csrfRepository.generateToken(request);
        csrfRepository.saveToken(tokenNuevo, request, response);
    }
}
