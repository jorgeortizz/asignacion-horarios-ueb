package co.edu.uelbosque.asignacionhorarios.model;

import co.edu.uelbosque.asignacionhorarios.repository.RolRepository;
import co.edu.uelbosque.asignacionhorarios.repository.UsuarioRepository;
import jakarta.persistence.EntityManager;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.*;
import org.springframework.dao.InvalidDataAccessApiUsageException;

@SpringBootTest
@ActiveProfiles("demo")
@Transactional
class UsuariosRolesJpaTests {
    @Autowired
    EntityManager em;
    @Autowired
    RolRepository roles;
    @Autowired
    UsuarioRepository usuarios;

    @Test
    void persisteCuentaDocenteYRecuperaSuAsociacion() {
        var rol = roles.saveAndFlush(new Rol(CodigoRol.DOCENTE, "Docente"));
        var docente = new Docente();
        docente.setNombre("Docente autenticado de prueba");
        docente.setTipoVinculacion(TipoVinculacion.TC);
        em.persist(docente);

        var nombre = "doc-" + UUID.randomUUID() + "@ejemplo.test";
        // Cadena de prueba sintética; no representa una contraseña real.
        var cuenta = usuarios.saveAndFlush(new Usuario(nombre, "{bcrypt}hash-de-prueba", rol, docente));
        em.clear();
        var encontrado = usuarios.findByIdentificadorIgnoreCase(nombre.toUpperCase()).orElseThrow();
        assertEquals(cuenta.getId(), encontrado.getId());
        assertEquals(CodigoRol.DOCENTE, encontrado.getRol().getCodigo());
        assertEquals(docente.getId(), encontrado.getDocente().getId());
        assertTrue(encontrado.isActivo());
        assertTrue(usuarios.existsByDocenteId(docente.getId()));
    }

    @Test
    void cuentaDocenteNoPuedePersistirSinVinculoAcademico() {
        var rol = roles.saveAndFlush(new Rol(CodigoRol.DOCENTE, "Docente"));

        var cuenta = new Usuario(
                "sin-vinculo-" + UUID.randomUUID(),
                "{bcrypt}prueba",
                rol,
                null);

        var error = assertThrows(
                InvalidDataAccessApiUsageException.class,
                () -> usuarios.saveAndFlush(cuenta));

        Throwable causa = error;

        while (causa.getCause() != null) {
            causa = causa.getCause();
        }

        assertInstanceOf(IllegalStateException.class, causa);
        assertEquals(
                "Una cuenta DOCENTE requiere asociación con Docente",
                causa.getMessage());
    }
}
