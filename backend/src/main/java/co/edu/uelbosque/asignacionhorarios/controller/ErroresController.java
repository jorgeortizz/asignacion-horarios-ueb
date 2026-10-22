package co.edu.uelbosque.asignacionhorarios.controller;
import co.edu.uelbosque.asignacionhorarios.service.ApiException;
import java.util.*;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.*;
import org.springframework.web.bind.*;
import org.springframework.web.bind.annotation.*;
@RestControllerAdvice
public class ErroresController {
    @ExceptionHandler(ApiException.class) public ResponseEntity<Map<String,Object>> negocio(ApiException e) {
        return ResponseEntity.status(e.getStatus()).body(Map.of("error",e.getMessage(),"estado",e.getStatus().value()));
    }
    @ExceptionHandler(MethodArgumentNotValidException.class) public ResponseEntity<Map<String,Object>> valido(MethodArgumentNotValidException e) {
        var errores=e.getBindingResult().getFieldErrors().stream().map(f->f.getField()+": "+f.getDefaultMessage()).toList();
        return ResponseEntity.badRequest().body(Map.of("error","Datos inválidos","detalle",errores));
    }
    @ExceptionHandler(DataIntegrityViolationException.class) public ResponseEntity<Map<String,Object>> integridad(DataIntegrityViolationException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error","La operación viola una restricción de integridad"));
    }
}
