package co.edu.uelbosque.asignacionhorarios.validation;
import co.edu.uelbosque.asignacionhorarios.model.*;
import co.edu.uelbosque.asignacionhorarios.service.Util;
import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
/** Reglas de cupo, candidato a cierre y marca aula especial (Tabla 26). */
class ReglasComplementariasTests {
    private Grupo grupo(int inscritos, int minimo, String tolerancia, boolean necesitaAula) {
        var p=new PeriodoAcademico();p.setToleranciaCupoPct(new BigDecimal(tolerancia));
        var c=new Curso();c.setNecesitaAulaEspecial(necesitaAula);
        var g=new Grupo();g.setPeriodo(p);g.setCurso(c);g.setInscritos((short)inscritos);
        g.setCupoMaximo((short)40);g.setCupoMinimo((short)minimo);return g;
    }
    @Test void cambiaCupoConToleranciaSinCambiarCodigo() {
        assertEquals(44,Util.limiteOperativo(grupo(43,10,"10.00",false)));
        assertEquals(42,Util.limiteOperativo(grupo(43,10,"5.00",false)));
    }
    @Test void menosDeDiezEsCandidatoPeroNoSeCierra() {
        var g=grupo(9,10,"10.00",false);assertTrue(g.getInscritos()<g.getCupoMinimo());
        assertFalse(grupo(10,10,"10.00",false).getInscritos()<10);
    }
    @Test void aulaEspecialSeRegistraSinCrearSalones() {
        assertTrue(grupo(10,10,"10.00",true).getCurso().isNecesitaAulaEspecial());
    }
}
