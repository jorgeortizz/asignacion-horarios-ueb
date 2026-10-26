package co.edu.uelbosque.asignacionhorarios.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

/** Controlador tecnico provisional para comprobar MVC + Thymeleaf. */
@Controller
public class InicioController {

    @GetMapping("/")
    public String inicio() {
        return "index";
    }
}
