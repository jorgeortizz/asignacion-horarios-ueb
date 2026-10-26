package co.edu.uelbosque.asignacionhorarios.validation;

import co.edu.uelbosque.asignacionhorarios.model.*;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

/** Casos derivados de la Tabla 19 y la Tabla 26 del informe académico. */
class ReglasHorarioTests {
    private PeriodoAcademico periodo() {
        var p=new PeriodoAcademico();p.setHoraInicioSemana(LocalTime.of(7,0));p.setHoraFinSemana(LocalTime.of(22,0));
        p.setHoraInicioSabado(LocalTime.of(7,0));p.setHoraFinSabado(LocalTime.of(13,0));
        p.setAlmuerzoInicio(LocalTime.of(12,0));p.setAlmuerzoFin(LocalTime.of(13,0));
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
    @Test void bloquesInicialesTienenTreintaYDosOpciones() {
        var p=periodo();var b=new BloquesFijos();int total=0;
        for(byte dia=1;dia<=6;dia++) total+=b.inicios(p,dia).size();
        assertEquals(32,total);assertEquals(List.of(LocalTime.of(7,0),LocalTime.of(9,0)),b.inicios(p,(byte)6));
    }
    @Test void almuerzoRechazaOnceATrecePeroAceptaNueveYtrece() {
        var g=grupo();assertFalse(validar(ctx(g,1,11,List.of(),List.of())).permitido());
        assertTrue(validar(ctx(g,1,9,List.of(),List.of())).permitido());
        assertTrue(validar(ctx(g,1,13,List.of(),List.of())).permitido());
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
        var g=grupo();var r=validar(ctx(g,2,13,List.of(sesion(g,1,13)),List.of()));
        assertTrue(r.permitido());assertTrue(r.incidencias().stream().anyMatch(i->i.codigo().equals("DIAS_CONSECUTIVOS")));
        assertTrue(validar(ctx(g,4,13,List.of(sesion(g,1,13)),List.of())).incidencias().isEmpty());
    }
    @Test void bloqueDesalineadoBloquea() {
        var g=grupo();assertFalse(validar(ctx(g,1,8,List.of(),List.of())).permitido());
    }
}
