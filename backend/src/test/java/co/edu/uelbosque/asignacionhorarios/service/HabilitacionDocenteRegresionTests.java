package co.edu.uelbosque.asignacionhorarios.service;

import co.edu.uelbosque.asignacionhorarios.model.Curso;
import co.edu.uelbosque.asignacionhorarios.model.Docente;
import co.edu.uelbosque.asignacionhorarios.model.TipoVinculacion;
import co.edu.uelbosque.asignacionhorarios.repository.CursoRepository;
import co.edu.uelbosque.asignacionhorarios.repository.DocenteRepository;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Regresión del rechazo de IDs nulos, sin modificar reglas académicas. */
@SpringBootTest
@ActiveProfiles("demo")
@Transactional
class HabilitacionDocenteRegresionTests {
    @Autowired private HabilitacionDocenteService habilitaciones;
    @Autowired private DocenteRepository docentes;
    @Autowired private CursoRepository cursos;

    @Test
    void aceptaSetOfConIdentificadorValido() {
        var docente = crearDocente();
        var curso = crearCurso();

        var resultado = habilitaciones.actualizarCursos(
            docente.getId(), Set.of(curso.getId()));

        assertEquals(List.of(curso.getId()), resultado);
        assertEquals(List.of(curso.getId()),
            habilitaciones.obtenerCursos(docente.getId()));
    }

    @Test
    void rechazaUnConjuntoQueContieneNullConErrorDeNegocio() {
        var docente = crearDocente();
        var curso = crearCurso();
        Set<Long> ids = new LinkedHashSet<>();
        ids.add(curso.getId());
        ids.add(null);

        var error = assertThrows(ApiException.class,
            () -> habilitaciones.actualizarCursos(docente.getId(), ids));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("La lista de cursos no es válida", error.getMessage());
        assertTrue(habilitaciones.obtenerCursos(docente.getId()).isEmpty());
    }

    @Test
    void rechazaUnaColeccionNulaSinNullPointerException() {
        var docente = crearDocente();

        var error = assertThrows(ApiException.class,
            () -> habilitaciones.actualizarCursos(docente.getId(), null));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        assertEquals("La lista de cursos no es válida", error.getMessage());
    }

    private Docente crearDocente() {
        var docente = new Docente();
        docente.setNombre("Docente regresión " + UUID.randomUUID());
        docente.setTipoVinculacion(TipoVinculacion.TC);
        return docentes.saveAndFlush(docente);
    }

    private Curso crearCurso() {
        var curso = new Curso();
        curso.setCodigo("REG-" + UUID.randomUUID().toString().substring(0, 8));
        curso.setNombre("Curso de regresión");
        curso.setSesionesSemanales((byte) 2);
        curso.setDuracionSesionMin((short) 120);
        curso.setNecesitaAulaEspecial(false);
        return cursos.saveAndFlush(curso);
    }
}
