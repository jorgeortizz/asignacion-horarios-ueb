package co.edu.uelbosque.asignacionhorarios.security;

import jakarta.servlet.DispatcherType;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.ProviderManager;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.DelegatingPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.context.HttpSessionSecurityContextRepository;
import org.springframework.security.web.context.SecurityContextRepository;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;

@Configuration
@EnableWebSecurity
public class SeguridadConfig {
    /** Prefijo {bcrypt} para hashes versionables; no se permite texto plano ni SHA-1. */
    @Bean
    PasswordEncoder passwordEncoder() {
        return new DelegatingPasswordEncoder("bcrypt",
            java.util.Map.of("bcrypt", new BCryptPasswordEncoder(12)));
    }

    @Bean
    AuthenticationManager authenticationManager(UserDetailsService userDetailsService, PasswordEncoder encoder) {
        var provider = new DaoAuthenticationProvider(userDetailsService);
        provider.setPasswordEncoder(encoder);
        return new ProviderManager(provider);
    }

    @Bean
    SecurityContextRepository securityContextRepository() {
        return new HttpSessionSecurityContextRepository();
    }

    @Bean
    CookieCsrfTokenRepository csrfTokenRepository() {
        var repository = CookieCsrfTokenRepository.withHttpOnlyFalse();
        repository.setCookiePath("/"); // El navegador lee XSRF-TOKEN también desde /api/...
        return repository;
    }

    @Bean
    SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            SecurityContextRepository securityContextRepository,
            CookieCsrfTokenRepository csrfTokenRepository) throws Exception {
        http
            .securityContext(context -> context.securityContextRepository(securityContextRepository))
            // Spring Security 7: compatibilidad SPA con X-XSRF-TOKEN de Angular.
            .csrf(csrf -> csrf.spa().csrfTokenRepository(csrfTokenRepository))
            .httpBasic(AbstractHttpConfigurer::disable)
            .formLogin(AbstractHttpConfigurer::disable)
            .logout(AbstractHttpConfigurer::disable) // Se controla desde AuthController.
            .requestCache(AbstractHttpConfigurer::disable)
            .exceptionHandling(errors -> errors
                .authenticationEntryPoint((req, res, ex) -> error(res, 401, "Autenticación requerida"))
                .accessDeniedHandler((req, res, ex) -> error(res, 403, "Acceso denegado")))
            .authorizeHttpRequests(authorize -> authorize
                .dispatcherTypeMatchers(DispatcherType.ERROR, DispatcherType.FORWARD).permitAll()
                .requestMatchers(HttpMethod.GET, "/", "/favicon.ico").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/v1/auth/csrf").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/v1/auth/login").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/v1/auth/me").authenticated()
                .requestMatchers(HttpMethod.POST, "/api/v1/auth/logout").authenticated()
                // Consultas separadas: solo horarios publicados vigentes, incluso anónimamente.
                .requestMatchers(HttpMethod.GET, "/api/v1/publico/**").permitAll()
                // DOCENTE solo consulta su propia identidad académica desde la sesión.
                .requestMatchers(HttpMethod.GET, "/api/v1/docentes/me/horario-publicado").hasRole("DOCENTE")
                .requestMatchers(HttpMethod.GET, "/api/v1/docentes/me/periodos-publicados").hasRole("DOCENTE")
                // Únicamente el Comité puede crear cuentas y publicar horarios.
                .requestMatchers(HttpMethod.POST, "/api/v1/usuarios").hasRole("COMITE_TACTICO")
                .requestMatchers(HttpMethod.POST, "/api/v1/horarios/*/publicar").hasRole("COMITE_TACTICO")
                // API administrativa existente: todo borrador, historial y CSV interno queda restringido.
                .requestMatchers("/api/v1/admin/usuarios", "/api/v1/admin/usuarios/**").hasRole("COMITE_TACTICO")
                .requestMatchers("/api/v1/**").hasAnyRole("COMITE_TACTICO", "COORDINACION_ACADEMICA")
                .anyRequest().denyAll());
        return http.build();
    }

    private static void error(HttpServletResponse response, int status, String mensaje) throws IOException {
        response.setStatus(status);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        response.setHeader("Cache-Control", "no-store");
        response.getWriter().write("{\"error\":\"" + mensaje + "\",\"estado\":" + status + "}");
    }
}
