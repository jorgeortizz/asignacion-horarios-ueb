package co.edu.uelbosque.asignacionhorarios;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

/** Verifica que el contexto Spring se inicia sin necesitar MySQL en el Sprint 0A. */
@SpringBootTest
class AsignacionHorariosApplicationTests {

    @Test
    void contextLoads() {
        // Si falla el arranque del contexto, falla esta prueba.
    }
}
