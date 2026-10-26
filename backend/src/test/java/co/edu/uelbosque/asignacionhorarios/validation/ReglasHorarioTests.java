package co.edu.uelbosque.asignacionhorarios.validation;

import co.edu.uelbosque.asignacionhorarios.model.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import static org.junit.jupiter.api.Assertions.*;

/** Casos derivados de la Tabla 19 y la Tabla 26 del informe académico. */
class ReglasHorarioTests {
    private PeriodoAcademico periodo() {
        var p=new PeriodoAcademico();p.setHoraInicioSemana(LocalTime.of(7,0));p.setHoraFinSemana(LocalTime.of(22,0));
        p.setHoraInicioSabado(LocalTime.of(7,0));p.setHoraFinSabado(LocalTime.of(13,0));
        p.setAlmuerzoInicio(LocalTime.of(13,0));p.setAlmuerzoFin(LocalTime.of(14,0));
        p.setDuracionBloqueMin((short)120);p.setMaxSesionesSemana((byte)4);
        p.setToleranciaCupoPct(new BigDecimal("10.00"));return p;
    }
    private Grupo grupo() {
        var d=new Docente();d.setNombre("Docente de prueba");
        var c=new Curso();c.setNombre("Curso de prueba");c.setDuracionSesionMin((short)120);c.setSesionesSemanales((byte)2);
        var g=new Grupo();g.setDocente(d);g.setCurso(c);g.setPeriodo(periodo());return g;
    }
    private Horario horario(Grupo g) {
        var h=new Horario();h.setPeriodo(g.getPeriodo());return h;
    }
    private ContextoValidacion ctx(Grupo g,int dia,int inicio,List<Sesion> sesiones,List<RestriccionHoraria> restricciones) {
        return new ContextoValidacion(horario(g),g,(byte)dia,LocalTime.of(inicio,0),LocalTime.of(inicio+2,0),null,sesiones,restricciones);
    }
    private List<ReglaHorario> reglas() { return List.of(new ReglaFranja(),new ReglaAlmuerzo(),
        new ReglaBloqueFijo(new BloquesFijos()),new ReglaChoqueDocente(),new ReglaChoqueGrupo(),
        new ReglaDisponibilidad(),new ReglaDiasConsecutivos()); }
    private ResultadoValidacion validar(ContextoValidacion c) {return new ValidadorHorario(reglas()).validar(c);}
    private Sesion sesion(Grupo g,int dia,int ini) {
        var s=new Sesion();s.setGrupo(g);s.setHorario(horario(g));s.setDia((byte)dia);
        s.setHoraInicio(LocalTime.of(ini,0));s.setHoraFin(LocalTime.of(ini+2,0));return s;
    }
    private RestriccionHoraria restriccion(int dia,int desde,int hasta,TipoRestriccion tipo, SentidoRestriccion sentido) {
        var r=new RestriccionHoraria();r.setDia((byte)dia);r.setHoraInicio(LocalTime.of(desde,0));
        r.setHoraFin(LocalTime.of(hasta,0));r.setTipo(tipo);r.setSentido(sentido);return r;
    }
    @Test void bloquesConservanAnclajeYAdmitenOnceATreceElSabado() {
        var p=periodo();var b=new BloquesFijos();int total=0;
        var semana=List.of(LocalTime.of(7,0),LocalTime.of(9,0),LocalTime.of(11,0),
            LocalTime.of(15,0),LocalTime.of(17,0),LocalTime.of(19,0));
        for(byte dia=1;dia<=5;dia++) assertEquals(semana,b.inicios(p,dia));
        for(byte dia=1;dia<=6;dia++) total+=b.inicios(p,dia).size();
        assertEquals(33,total);
        assertEquals(List.of(LocalTime.of(7,0),LocalTime.of(9,0),LocalTime.of(11,0)),b.inicios(p,(byte)6));
    }
    @ParameterizedTest
    @CsvSource({"11, false", "12, true", "13, true", "14, false"})
    void almuerzoEvaluaSoloElSolapamientoSemiabierto(int inicio,boolean conflicto) {
        var incidencias=new ReglaAlmuerzo().evaluar(ctx(grupo(),1,inicio,List.of(),List.of()));
        assertEquals(conflicto,!incidencias.isEmpty());
        if(conflicto) assertEquals("ALMUERZO",incidencias.getFirst().codigo());
    }
    @Test void almuerzoUsaLosParametrosDeCadaPeriodo() {
        var g=grupo();var c=ctx(g,1,11,List.of(),List.of());var regla=new ReglaAlmuerzo();
        assertTrue(regla.evaluar(c).isEmpty());
        g.getPeriodo().setAlmuerzoInicio(LocalTime.of(12,0));
        g.getPeriodo().setAlmuerzoFin(LocalTime.of(13,0));
        assertEquals("ALMUERZO",regla.evaluar(c).getFirst().codigo());
        assertFalse(new BloquesFijos().inicios(g.getPeriodo(),(byte)1).contains(LocalTime.of(11,0)));
        assertTrue(new BloquesFijos().inicios(g.getPeriodo(),(byte)1).contains(LocalTime.of(13,0)));
    }
    @Test void catorceADieciseisNoCruzaAlmuerzoPeroEstaFueraDeLaCuadricula() {
        var c=ctx(grupo(),1,14,List.of(),List.of());
        assertTrue(new ReglaAlmuerzo().evaluar(c).isEmpty());
        assertTrue(new ReglaFranja().evaluar(c).isEmpty());
        var incidencias=validar(c).incidencias();
        assertEquals(1,incidencias.size());assertEquals("BLOQUE",incidencias.getFirst().codigo());
        assertTrue(validar(ctx(grupo(),1,11,List.of(),List.of())).permitido());
    }
    @ParameterizedTest
    @CsvSource({"1, 5, false", "1, 7, true", "1, 20, true", "1, 21, false",
        "5, 20, true", "6, 7, true", "6, 11, true", "6, 12, false", "7, 7, false"})
    void franjaSeEvaluaIndependientementeDelAlmuerzoYLaCuadricula(int dia,int inicio,boolean permitido) {
        assertEquals(permitido,new ReglaFranja().evaluar(ctx(grupo(),dia,inicio,List.of(),List.of())).isEmpty());
    }
    @Test void duracionDistintaDeDosHorasSeRechazaSinConflictoDeAlmuerzo() {
        var g=grupo();g.getCurso().setDuracionSesionMin((short)60);
        var c=new ContextoValidacion(horario(g),g,(byte)1,LocalTime.of(7,0),LocalTime.of(8,0),null,List.of(),List.of());
        assertTrue(new ReglaAlmuerzo().evaluar(c).isEmpty());
        assertTrue(new ReglaFranja().evaluar(c).isEmpty());
        assertEquals("BLOQUE",new ReglaBloqueFijo(new BloquesFijos()).evaluar(c).getFirst().codigo());
    }
    @Test void choqueDocenteBloqueaSesionMismoDiaYHora() {
        var g=grupo(); var r=validar(ctx(g,1,19,List.of(sesion(g,1,19)),List.of()));
        assertFalse(r.permitido());assertTrue(r.incidencias().stream().anyMatch(i->i.codigo().equals("DOCENTE_OCUPADO")));
    }
    @Test void disponibilidadDeNocheRechazaTarde() {
        var g=grupo();var franja=restriccion(1,18,22,TipoRestriccion.FIRME,SentidoRestriccion.DISPONIBLE);
        assertFalse(validar(ctx(g,1,15,List.of(),List.of(franja))).permitido());
        assertTrue(validar(ctx(g,1,19,List.of(),List.of(franja))).permitido());
    }
    @Test void consecutivosSonAdvertenciaNoBloqueo() {
        var g=grupo();var r=validar(ctx(g,2,15,List.of(sesion(g,1,15)),List.of()));
        assertTrue(r.permitido());assertTrue(r.incidencias().stream().anyMatch(i->i.codigo().equals("DIAS_CONSECUTIVOS")));
        assertTrue(validar(ctx(g,4,15,List.of(sesion(g,1,15)),List.of())).incidencias().isEmpty());
    }
    @Test void bloqueDesalineadoBloquea() {
        var g=grupo();assertFalse(validar(ctx(g,1,8,List.of(),List.of())).permitido());
    }
}
