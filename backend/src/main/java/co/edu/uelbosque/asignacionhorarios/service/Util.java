package co.edu.uelbosque.asignacionhorarios.service;
import co.edu.uelbosque.asignacionhorarios.model.*;
import org.springframework.http.HttpStatus;
import java.util.*;
public final class Util {
    private Util() {}
    public static <T> T requerido(Optional<T> opt, String nombre) {
        return opt.orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, nombre+" no encontrado"));
    }
    public static void exigir(boolean valido, String mensaje) {
        if (!valido) throw new ApiException(HttpStatus.BAD_REQUEST,mensaje);
    }
    public static void editable(Horario horario) {
        if (horario.getEstado()!=EstadoHorario.BORRADOR) throw new ApiException(HttpStatus.CONFLICT,
            "No se puede editar un horario publicado; crear un nuevo borrador para cambios");
    }
    public static int limiteOperativo(Grupo grupo) {
        return (int)Math.floor(grupo.getCupoMaximo() * (1 + grupo.getPeriodo().getToleranciaCupoPct().doubleValue()/100));
    }
}
