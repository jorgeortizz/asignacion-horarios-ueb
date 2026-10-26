package co.edu.uelbosque.asignacionhorarios.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

/** Prueba unitaria del nombre de la vista Thymeleaf inicial. */
class InicioControllerTests {

    @Test
    void inicioDevuelveLaPlantillaIndex() {
        assertEquals("index", new InicioController().inicio());
    }
}
