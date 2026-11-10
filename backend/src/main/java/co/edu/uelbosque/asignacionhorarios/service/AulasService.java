package co.edu.uelbosque.asignacionhorarios.service;

import co.edu.uelbosque.asignacionhorarios.model.Horario;
import co.edu.uelbosque.asignacionhorarios.dto.Respuestas;
import co.edu.uelbosque.asignacionhorarios.model.EstadoHorario;
import co.edu.uelbosque.asignacionhorarios.repository.HorarioRepository;
import java.sql.*;
import java.time.LocalTime;
import java.util.*;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Salones por sesión, separados del modelo histórico previo de horarios. */
@Service
public class AulasService {
    public record Aula(Long id, String codigo, String nombre, String tipo, String edificio,
                       String piso, Integer capacidad, Boolean activa, String observaciones) {}
    public record Asignacion(Long sesionId, Long aulaId, String codigo, String nombre,
                             String tipo, String edificio, Integer capacidad) {}
    public record Resultado(int asignadas, int sinAula) {}
    public record TipoCurso(Long cursoId, String tipo) {}
    public record AulaSeleccion(Long aulaId) {}

    private static final Set<String> TIPOS = Set.of("PEDAGOGICA", "COMPUTACION", "LABORATORIO", "MULTIMEDIA");
    private final JdbcTemplate jdbc;
    private final HorarioRepository horarios;

    public AulasService(JdbcTemplate jdbc, HorarioRepository horarios) {
        this.jdbc = jdbc;
        this.horarios = horarios;
    }

    private void requerir(boolean condicion, String mensaje) {
        if (!condicion) throw new ApiException(HttpStatus.CONFLICT, mensaje);
    }
    private String tipo(String t) {
        var valor = t == null ? "" : t.trim().toUpperCase(Locale.ROOT);
        requerir(TIPOS.contains(valor), "Tipo válido: PEDAGOGICA, COMPUTACION, LABORATORIO o MULTIMEDIA");
        return valor;
    }
    private String txt(String t, String nombre, int max) {
        var valor = t == null ? "" : t.trim();
        requerir(!valor.isBlank() && valor.length() <= max, nombre + " debe tener entre 1 y " + max + " caracteres");
        return valor;
    }
    private boolean hayTablas() {
        try {
            return Boolean.TRUE.equals(jdbc.execute((org.springframework.jdbc.core.ConnectionCallback<Boolean>) c -> {
                try (ResultSet r = c.getMetaData().getTables(c.getCatalog(), null, "%", new String[]{"TABLE"})) {
                    while (r.next()) if ("aula".equalsIgnoreCase(r.getString("TABLE_NAME"))) return true;
                }
                return false;
            }));
        } catch (DataAccessException e) { return false; }
    }
    private void listo() {
        requerir(hayTablas(), "No se ha aplicado la migración de aulas (V50). Inicia Spring Boot con Flyway y MySQL.");
    }

    private static Aula aula(ResultSet r, int n) throws SQLException {
        return new Aula(r.getLong("id"), r.getString("codigo"), r.getString("nombre"),
                r.getString("tipo"), r.getString("edificio"), r.getString("piso"),
                r.getInt("capacidad"), r.getBoolean("activa"), r.getString("observaciones"));
    }
    private static Asignacion asignacion(ResultSet r, int n) throws SQLException {
        return new Asignacion(r.getLong("sesion_id"), r.getLong("aula_id"), r.getString("codigo"),
                r.getString("nombre"), r.getString("tipo"), r.getString("edificio"), r.getInt("capacidad"));
    }
    @Transactional(readOnly=true)
    public List<Aula> listar() {
        listo();
        return jdbc.query("SELECT * FROM aula ORDER BY codigo", AulasService::aula);
    }
    @Transactional
    public Aula guardar(Long id, Aula a) {
        listo();
        String codigo = txt(a.codigo(), "Código", 32).toUpperCase(Locale.ROOT);
        String nombre = txt(a.nombre(), "Nombre", 100);
        String edificio = txt(a.edificio(), "Edificio", 80);
        String piso = txt(a.piso(), "Piso", 20);
        String tipo = tipo(a.tipo());
        int capacidad = a.capacidad() == null ? 0 : a.capacidad();
        requerir(capacidad > 0 && capacidad <= 1000, "Capacidad entre 1 y 1000");
        String nota = a.observaciones() == null ? "" : a.observaciones().trim();
        requerir(nota.length() <= 255, "Observaciones excede 255 caracteres");
        boolean activa = a.activa() == null || a.activa();
        long otros = jdbc.queryForObject("SELECT COUNT(*) FROM aula WHERE codigo=? AND id<>?", Long.class,
                codigo, id == null ? -1 : id);
        requerir(otros == 0, "Ya existe un aula con ese código");
        if (id != null) {
            var anteriores = jdbc.query("SELECT * FROM aula WHERE id=?",AulasService::aula,id);
            requerir(!anteriores.isEmpty(),"Aula inexistente");
            Aula anterior = anteriores.getFirst();
            if (!Objects.equals(anterior.tipo(),tipo) || anterior.capacidad()!=capacidad || !activa) {
                int usos = jdbc.queryForObject(
                    "SELECT COUNT(*) FROM sesion_aula WHERE aula_id=?",Integer.class,id);
                requerir(usos==0,
                    "El aula tiene sesiones asignadas. Reasigna esas sesiones antes de cambiar tipo, capacidad o desactivarla.");
            }
        }
        if (id == null) {
            jdbc.update("INSERT INTO aula (codigo,nombre,tipo,edificio,piso,capacidad,activa,observaciones) VALUES (?,?,?,?,?,?,?,?)",
                codigo,nombre,tipo,edificio,piso,capacidad,activa,nota);
            return jdbc.queryForObject("SELECT * FROM aula WHERE codigo=?", AulasService::aula, codigo);
        }
        int n = jdbc.update("UPDATE aula SET codigo=?,nombre=?,tipo=?,edificio=?,piso=?,capacidad=?,activa=?,observaciones=? WHERE id=?",
                codigo,nombre,tipo,edificio,piso,capacidad,activa,nota,id);
        requerir(n == 1, "Aula inexistente");
        return jdbc.queryForObject("SELECT * FROM aula WHERE id=?", AulasService::aula, id);
    }

    @Transactional(readOnly=true)
    public List<TipoCurso> requisitos() {
        listo();
        return jdbc.query("SELECT curso_id, tipo FROM curso_tipo_aula ORDER BY curso_id",
            (rs,n) -> new TipoCurso(rs.getLong("curso_id"),rs.getString("tipo")));
    }
    @Transactional
    public TipoCurso guardarRequisito(Long cursoId, String requerida) {
        listo();
        String tipo = tipo(requerida);
        int existe = jdbc.queryForObject("SELECT COUNT(*) FROM curso WHERE id=?", Integer.class, cursoId);
        requerir(existe == 1, "Asignatura inexistente");
        jdbc.update("DELETE FROM curso_tipo_aula WHERE curso_id=?",cursoId);
        jdbc.update("INSERT INTO curso_tipo_aula(curso_id,tipo) VALUES (?,?)",cursoId,tipo);
        return new TipoCurso(cursoId,tipo);
    }

    private record DatosSesion(Long sesionId, Long horarioId, int dia, LocalTime desde, LocalTime hasta,
                               int inscritos, String requerido) {}
    private List<DatosSesion> sesiones(Long horarioId) {
        // Si el curso tiene una exigencia explícita, prima sobre el booleano antiguo.
        return jdbc.query("""
            SELECT s.id AS sesion_id,s.horario_id,s.dia,s.hora_inicio,s.hora_fin,g.inscritos,
              COALESCE(ct.tipo,CASE WHEN c.necesita_aula_especial=1 THEN 'COMPUTACION' ELSE 'PEDAGOGICA' END) requerido
            FROM sesion s JOIN grupo g ON g.id=s.grupo_id JOIN curso c ON c.id=g.curso_id
            LEFT JOIN curso_tipo_aula ct ON ct.curso_id=c.id
            WHERE s.horario_id=? ORDER BY s.dia,s.hora_inicio,s.id
            """, (r,n) -> new DatosSesion(r.getLong("sesion_id"),r.getLong("horario_id"),r.getInt("dia"),
                r.getTime("hora_inicio").toLocalTime(),r.getTime("hora_fin").toLocalTime(),
                r.getInt("inscritos"),r.getString("requerido")), horarioId);
    }
    private DatosSesion sesion(Long horarioId, Long sesionId) {
        return sesiones(horarioId).stream().filter(s -> s.sesionId().equals(sesionId))
                .findFirst().orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,"La sesión no pertenece al horario"));
    }
    private Horario bloquearBorrador(Long id) {
        var h = horarios.bloquear(id).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,"Horario inexistente"));
        requerir(h.getEstado() == EstadoHorario.BORRADOR,"El horario publicado no admite cambios de aula");
        return h;
    }
    /** Serializa asignaciones de horarios diferentes del mismo periodo académico.
     * El bloqueo se mantiene hasta el commit de la transacción Spring.
     */
    private void bloquearPeriodo(Long horarioId) {
        List<Long> ids = jdbc.query("""
            SELECT p.id FROM periodo_academico p
            JOIN horario h ON h.periodo_id=p.id WHERE h.id=? FOR UPDATE
            """, (r,n) -> r.getLong(1), horarioId);
        requerir(!ids.isEmpty(), "Horario inexistente");
    }

    private boolean disponible(DatosSesion s, Long aulaId, boolean validarTipo) {
        List<Aula> rooms = jdbc.query("SELECT * FROM aula WHERE id=? AND activa=TRUE", AulasService::aula, aulaId);
        if (rooms.isEmpty()) return false;
        Aula a = rooms.getFirst();
        if (validarTipo && !a.tipo().equals(s.requerido())) return false;
        if (a.capacidad() < s.inscritos()) return false;
        int solapes = jdbc.queryForObject("""
            SELECT COUNT(*) FROM sesion_aula sa
            JOIN sesion otra ON otra.id=sa.sesion_id
            JOIN horario h ON h.id=otra.horario_id
            JOIN horario actual ON actual.id=?
            WHERE h.periodo_id=actual.periodo_id
              AND sa.aula_id=? AND otra.dia=? AND otra.id<>?
              AND otra.hora_inicio < ? AND otra.hora_fin > ?
              AND (h.estado='BORRADOR' OR
                   EXISTS (SELECT 1 FROM v_horario_vigente v WHERE v.horario_id=h.id))
            """, Integer.class, s.horarioId(),aulaId,s.dia(),s.sesionId(),s.hasta(),s.desde());
        return solapes == 0;
    }
    private void aplicar(Long sesionId, Long aulaId) {
        jdbc.update("DELETE FROM sesion_aula WHERE sesion_id=?",sesionId);
        if (aulaId != null) jdbc.update("INSERT INTO sesion_aula(sesion_id,aula_id) VALUES(?,?)",sesionId,aulaId);
    }

    @Transactional
    public void asignar(Long horarioId, Long sesionId, Long aulaId) {
        listo();
        bloquearPeriodo(horarioId);
        bloquearBorrador(horarioId);
        var s = sesion(horarioId,sesionId);
        if (aulaId != null) requerir(disponible(s,aulaId,true),
            "Aula incompatible, sin capacidad u ocupada en OTRO horario del mismo periodo");
        aplicar(sesionId,aulaId);
    }

    @Transactional
    public Resultado automatico(Long horarioId) {
        listo();
        bloquearPeriodo(horarioId);
        bloquearBorrador(horarioId);
        return ejecutarAutomatico(horarioId,false);
    }

    /** Completa sesiones sin aula en horarios publicados sin cambiar las asignaciones previas.
     * La acción es explícita y se restringe al catálogo administrativo.
     */
    @Transactional
    public Resultado completarPublicado(Long horarioId) {
        listo();
        bloquearPeriodo(horarioId);
        var horario = horarios.bloquear(horarioId)
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,"Horario inexistente"));
        requerir(horario.getEstado()==EstadoHorario.PUBLICADO,
            "Esta operación se reserva para horarios publicados");
        return ejecutarAutomatico(horarioId,true);
    }

    /** Llamado al generar: también funciona dentro de la transacción existente. */
    public Resultado automaticoEnTransaccion(Long horarioId) {
        if (!hayTablas()) return new Resultado(0,0); // Compatibilidad con pruebas demo H2 sin V50.
        bloquearPeriodo(horarioId);
        return ejecutarAutomatico(horarioId,false);
    }

    private int opciones(DatosSesion s, List<Aula> activas) {
        int opciones=0;
        for (Aula a: activas) if (a.tipo().equals(s.requerido()) &&
            a.capacidad()>=s.inscritos() && disponible(s,a.id(),true)) opciones++;
        return opciones;
    }

    /** Primero atiende sesiones con menos aulas posibles y luego ajusta cupos. */
    private Resultado ejecutarAutomatico(Long horarioId, boolean soloFaltantes) {
        int asignadas=0,sinAula=0;
        List<Aula> activas = jdbc.query(
            "SELECT * FROM aula WHERE activa=TRUE ORDER BY capacidad,codigo",AulasService::aula);
        List<DatosSesion> pendientes = new ArrayList<>();
        for (var s : sesiones(horarioId)) {
            var actual = jdbc.query("SELECT aula_id FROM sesion_aula WHERE sesion_id=?",
                (r,n)->r.getLong(1),s.sesionId());
            if (!actual.isEmpty()) {
                if (disponible(s,actual.getFirst(),true)) { asignadas++; continue; }
                if (soloFaltantes) { sinAula++; continue; }
                aplicar(s.sesionId(),null);
            }
            pendientes.add(s);
        }
        Map<Long,Integer> opcionesPorSesion = new HashMap<>();
        for (var s : pendientes) opcionesPorSesion.put(s.sesionId(),opciones(s,activas));
        pendientes.sort(Comparator.<DatosSesion>comparingInt(s -> opcionesPorSesion.get(s.sesionId()))
            .thenComparing(Comparator.comparingInt(DatosSesion::inscritos).reversed()));
        for (var s: pendientes) {
            Long elegida=null;
            for (var a:activas) if (a.tipo().equals(s.requerido()) &&
                a.capacidad()>=s.inscritos() && disponible(s,a.id(),true)) {
                elegida=a.id();break;
            }
            if (elegida!=null) {aplicar(s.sesionId(),elegida);asignadas++;}
            else sinAula++;
        }
        return new Resultado(asignadas,sinAula);
    }

    /** Si se mueve una sesión, revalida su salón con TODOS los horarios del período. */
    public void despuesDeMover(Long horarioId, Long sesionId) {
        if (!hayTablas()) return;
        bloquearPeriodo(horarioId);
        var s = sesion(horarioId,sesionId);
        var actual = jdbc.query("SELECT aula_id FROM sesion_aula WHERE sesion_id=?",
            (r,n)->r.getLong(1),sesionId);
        if (!actual.isEmpty() && disponible(s,actual.getFirst(),true)) return;
        List<Aula> activas = jdbc.query(
            "SELECT * FROM aula WHERE activa=TRUE ORDER BY capacidad,codigo",AulasService::aula);
        for (var a : activas) if (disponible(s,a.id(),true)) {
            aplicar(sesionId,a.id()); return;
        }
        aplicar(sesionId,null);
    }
    /** Si hay aulas registradas, publica únicamente con todas las sesiones asignadas. */
    public void antesDePublicar(Long horarioId) {
        if (!hayTablas()) return;
        int activas = jdbc.queryForObject("SELECT COUNT(*) FROM aula WHERE activa=TRUE", Integer.class);
        if (activas == 0) return; // Compatibilidad con instalaciones que aún no cargan aulas.
        Resultado r=automaticoEnTransaccion(horarioId);
        requerir(r.sinAula() == 0, "Faltan aulas para " + r.sinAula() + " sesión(es). Revisa tipo, cupo y conflictos entre horarios del período.");
    }
    /** CSV anónimo, con consulta pública ya validada por ConsultaPublicaService. */
    @Transactional(readOnly=true)
    public String csvConAulas(ConsultaPublicaService consultas, Long periodoId, Long cursoId) {
        var horario = consultas.horarioVigente(periodoId); // 404 si no hay publicado vigente
        var sesiones = consultas.sesionesCurso(periodoId,cursoId);
        Map<Long,Asignacion> mapa=new HashMap<>();
        for (var item : porHorario(horario.id(),true)) mapa.put(item.sesionId(),item);
        StringBuilder csv=new StringBuilder("\uFEFFDia,Inicio,Fin,Curso,Grupo,Docente,Aula,Edificio,Tipo de aula\r\n");
        for (Respuestas.SesionDto s : sesiones) {
            Asignacion a = mapa.get(s.id());
            Object[] valores={nombreDia(s.dia()),s.horaInicio(),s.horaFin(),s.curso(),
                s.grupo(),s.docente(),a==null ? "Pendiente":a.codigo(),
                a==null ? "":a.edificio(),a==null ? "":a.tipo()};
            for (int i=0;i<valores.length;i++) {
                if (i>0) csv.append(',');
                csv.append(celdaCsv(valores[i]));
            }
            csv.append("\r\n");
        }
        return csv.toString();
    }
    private String nombreDia(int d) {
        return switch (d) {
            case 1 -> "Lunes"; case 2 -> "Martes"; case 3 -> "Miercoles";
            case 4 -> "Jueves"; case 5 -> "Viernes"; case 6 -> "Sabado";
            default -> String.valueOf(d);
        };
    }
    /** Evita fórmulas al abrir el CSV en Excel y conserva correctamente las comillas. */
    private String celdaCsv(Object dato) {
        String v = dato == null ? "" : String.valueOf(dato);
        if (!v.isEmpty() && "=+-@\t\r\n".indexOf(v.charAt(0))>=0) v="'"+v;
        return "\"" + v.replace("\"","\"\"") + "\"";
    }

    @Transactional(readOnly=true)
    public List<Asignacion> porHorario(Long horarioId, boolean publico) {
        listo();
        var h = horarios.findById(horarioId).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,"Horario inexistente"));
        if (publico) requerir(h.getEstado() == EstadoHorario.PUBLICADO &&
                 horarios.findVigenteByPeriodoId(h.getPeriodo().getId()).map(v->v.getId().equals(horarioId)).orElse(false),
                 "Solo se permite consultar el horario publicado vigente");
        return jdbc.query("""
           SELECT sa.sesion_id, a.id aula_id,a.codigo,a.nombre,a.tipo,a.edificio,a.capacidad
           FROM sesion_aula sa JOIN aula a ON a.id=sa.aula_id JOIN sesion s ON s.id=sa.sesion_id
           WHERE s.horario_id=? ORDER BY sa.sesion_id
           """,AulasService::asignacion,horarioId);
    }
}
