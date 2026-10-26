import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * Prueba integral exclusivamente contra una instancia MySQL temporal aislada.
 * No instala el esquema ni los procedimientos. El lanzador debe preparar el clon.
 * Uso: java -cp mysql-connector-j.jar PruebaIntegralAlmuerzo.java
 *       <puerto-distinto-de-3306> <datadir-absoluto> <server_uuid> <resultado.json>
 */
public class PruebaIntegralAlmuerzo {
    private static final String SCHEMA = "horarios_ueb";
    private static final String APPLY = "CALL horarios_ueb.sp_almuerzo_2026_2_aplicar()";
    private static final String CONFIRM = "CALL horarios_ueb.sp_almuerzo_2026_2_confirmar()";
    private static final String ROLLBACK = "ROLLBACK AND NO CHAIN NO RELEASE";
    private static final String LIMITED = "almuerzo_operador_prueba";
    private static final String LIMITED_ACCOUNT = "'almuerzo_operador_prueba'@'127.0.0.1'";
    private static final List<String> TABLES = List.of("periodo_academico", "horario", "sesion",
        "grupo", "curso", "docente", "restriccion_horaria", "docente_especialidad");
    private static final Set<String> MOVED = Set.of("12", "13", "14", "18", "23");
    private final int port;
    private final String datadir;
    private final String uuid;
    private final Path output;
    private final List<Map<String,Object>> results = new ArrayList<>();
    private final Map<String,Object> measurements = new LinkedHashMap<>();
    private final List<Map<String,String>> installedProcedures = new ArrayList<>();
    private final Instant started = Instant.now();
    private Snapshot baseline;
    private Map<String,String> baselineHashes;
    private Map<String,Object> currentCase;
    private Long observedV3Count;

    private PruebaIntegralAlmuerzo(String[] args) {
        if (args.length != 4) throw new IllegalArgumentException("Se requieren puerto, datadir, UUID y archivo JSON");
        port = Integer.parseInt(args[0]);
        if (port <= 0 || port > 65535 || port == 3306) throw new IllegalArgumentException("Puerto temporal invalido");
        if (!Path.of(args[1]).isAbsolute()) throw new IllegalArgumentException("datadir debe ser absoluto");
        datadir = normalized(args[1]);
        uuid = args[2];
        if (!uuid.matches("[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")) {
            throw new IllegalArgumentException("server_uuid invalido");
        }
        output = Path.of(args[3]).toAbsolutePath().normalize();
    }

    public static void main(String[] args) throws Exception {
        var suite = new PruebaIntegralAlmuerzo(args);
        Throwable failure = null;
        try {
            Class.forName("com.mysql.cj.jdbc.Driver");
            suite.run();
        } catch (Throwable ex) {
            failure = ex;
            ex.printStackTrace(System.err);
        } finally {
            suite.report(failure);
        }
        if (failure != null) System.exit(1);
    }

    private Connection connect(String user) throws SQLException {
        String url = "jdbc:mysql://127.0.0.1:" + port + "/" + SCHEMA
            + "?sslMode=DISABLED&allowPublicKeyRetrieval=true&connectionTimeZone=America/Bogota"
            + "&connectTimeout=5000&socketTimeout=15000&allowMultiQueries=false";
        Connection c = DriverManager.getConnection(url, user, "");
        try { guard(c); return c; }
        catch (Throwable ex) { c.close(); throw ex; }
    }

    private Connection root() throws SQLException { return connect("root"); }

    private void guard(Connection c) throws SQLException {
        try (var st = c.createStatement(); var rs = st.executeQuery(
                "SELECT @@port, @@server_uuid, @@datadir, DATABASE()")) {
            require(rs.next(), "No se pudo comprobar la identidad del servidor");
            require(rs.getInt(1) == port && rs.getInt(1) != 3306, "Puerto no autorizado");
            require(uuid.equalsIgnoreCase(rs.getString(2)), "UUID no autorizado");
            require(datadir.equals(normalized(rs.getString(3))), "datadir no autorizado");
            require(SCHEMA.equals(rs.getString(4)), "Esquema no autorizado");
        }
    }

    private static String normalized(String value) {
        return Path.of(value).toAbsolutePath().normalize().toString().replace('\\', '/')
            .replaceAll("/+$", "").toLowerCase(Locale.ROOT);
    }

    private void write(Connection c, String sql) throws SQLException {
        guard(c);
        var outputs=execute(c, sql);
        if (currentCase!=null && (sql.equals(APPLY) || sql.equals(CONFIRM))) {
            observation("salidas_procedimientos",Map.of("sql",sql,"resultados",outputs));
        }
        if (sql.equals(APPLY)) {
            require(!outputs.isEmpty() && outputs.get(0).size()==1,"Falta reporte de aplicar");
            var actual=outputs.get(0).get(0);
            for (var expected:Map.of("sesiones_modificadas","5","periodos_modificados","1",
                    "sesiones_borrador","24","sesiones_historicas","8","conflictos_almuerzo","0",
                    "invariantes_verificados","1","sesiones_programadas_grupo_21","1",
                    "sesiones_requeridas_grupo_21","2").entrySet()) {
                require(expected.getValue().equals(actual.get(expected.getKey())),
                    "Reporte aplicar incorrecto para "+expected.getKey()+": "+actual.get(expected.getKey()));
            }
            require(actual.get("huellas_verificadas")!=null,"Reporte aplicar sin huellas comprobadas");
        }
    }

    private static List<List<Map<String,String>>> execute(Connection c, String sql) throws SQLException {
        var outputs=new ArrayList<List<Map<String,String>>>();
        try (Statement st = c.createStatement()) {
            boolean hasResult = st.execute(sql);
            for (;;) {
                if (hasResult) {
                    try (ResultSet rs = st.getResultSet()) { outputs.add(rows(rs)); }
                } else if (st.getUpdateCount() == -1) break;
                hasResult = st.getMoreResults(Statement.CLOSE_CURRENT_RESULT);
            }
        }
        return outputs;
    }

    private static List<Map<String,String>> rows(ResultSet rs) throws SQLException {
        var result=new ArrayList<Map<String,String>>();
        int columns=rs.getMetaData().getColumnCount();
        while (rs.next()) {
            var row=new LinkedHashMap<String,String>();
            for(int i=1;i<=columns;i++) row.put(rs.getMetaData().getColumnLabel(i),rs.getString(i));
            result.add(Collections.unmodifiableMap(row));
        }
        return List.copyOf(result);
    }

    private List<Map<String,String>> query(Connection c,String sql) throws SQLException {
        guard(c);
        try (var st=c.createStatement(); var rs=st.executeQuery(sql)) { return rows(rs); }
    }

    @SuppressWarnings("unchecked")
    private void observation(String key,Object value) {
        if(currentCase!=null) ((List<Object>) currentCase.computeIfAbsent(key,k->new ArrayList<>())).add(value);
    }

    private Map<String,String> hashes(Connection c) throws SQLException {
        write(c,"SET SESSION group_concat_max_len=1048576");
        write(c,"CALL horarios_ueb.sp_almuerzo_2026_2_huellas(@prueba_huellas)");
        var values=new LinkedHashMap<String,String>();
        for (String key:List.of("periodo","horario","sesion","grupo","curso","docente","restriccion","docente_especialidad")) {
            values.put(key,scalar(c,"SELECT JSON_UNQUOTE(JSON_EXTRACT(@prueba_huellas,'$."+key+"'))"));
            require(values.get(key)!=null && values.get(key).matches("[0-9a-f]{64}"),"Huella SQL invalida: "+key);
        }
        return Collections.unmodifiableMap(values);
    }

    private void installation(Connection c) throws SQLException {
        installedProcedures.addAll(query(c,"SELECT ROUTINE_NAME,ROUTINE_TYPE,SECURITY_TYPE,SQL_DATA_ACCESS,"
            +"SHA2(ROUTINE_DEFINITION,256) AS cuerpo_sha256 FROM information_schema.routines "
            +"WHERE ROUTINE_SCHEMA='horarios_ueb' AND ROUTINE_NAME LIKE 'sp_almuerzo_2026_2_%' ORDER BY ROUTINE_NAME"));
        var expected=Set.of("sp_almuerzo_2026_2_aplicar","sp_almuerzo_2026_2_confirmar",
            "sp_almuerzo_2026_2_huellas","sp_almuerzo_2026_2_verificar");
        require(installedProcedures.size()==expected.size(),"No se instalaron exactamente cuatro auxiliares");
        for(var procedure:installedProcedures) {
            require(expected.contains(procedure.get("ROUTINE_NAME")),"Auxiliar inesperado");
            require("PROCEDURE".equals(procedure.get("ROUTINE_TYPE")),"Auxiliar no es procedimiento");
            require("INVOKER".equals(procedure.get("SECURITY_TYPE")),"Auxiliar no usa SQL SECURITY INVOKER");
            require(procedure.get("cuerpo_sha256")!=null,"No es visible el cuerpo del auxiliar");
        }
    }

    private String scalar(Connection c, String sql) throws SQLException {
        guard(c);
        try (var st = c.createStatement(); var rs = st.executeQuery(sql)) {
            require(rs.next(), "Consulta escalar sin resultado");
            return rs.getString(1);
        }
    }

    private Snapshot snapshot(Connection c) throws SQLException {
        guard(c);
        var tables = new LinkedHashMap<String,Data>();
        for (String table : TABLES) {
            String order = table.equals("docente_especialidad") ? "docente_id,especialidad" : "id";
            try (var st = c.createStatement(); var rs = st.executeQuery("SELECT * FROM `" + table + "` ORDER BY " + order)) {
                var columns = new ArrayList<String>();
                int count = rs.getMetaData().getColumnCount();
                for (int i=1; i<=count; i++) columns.add(rs.getMetaData().getColumnName(i));
                var rows = new ArrayList<List<String>>();
                while (rs.next()) {
                    var values = new ArrayList<String>();
                    for (int i=1; i<=count; i++) values.add(rs.getString(i));
                    rows.add(Collections.unmodifiableList(values));
                }
                tables.put(table, new Data(List.copyOf(columns), List.copyOf(rows)));
            }
        }
        return new Snapshot(Collections.unmodifiableMap(tables));
    }

    private void unchanged(Connection c) throws SQLException {
        Snapshot actual=snapshot(c);
        require(baseline.equals(actual), "Los datos no coinciden integramente con PRE");
        observation("comprobaciones_pre",delta(actual));
    }

    private void pending(Connection c) throws SQLException {
        require("PENDIENTE_CONFIRMACION".equals(scalar(c,"SELECT @almuerzo_2026_2_estado")), "Falta estado pendiente");
        require("5".equals(scalar(c,"SELECT @almuerzo_2026_2_filas_sesion")), "No son cinco sesiones");
        require("1".equals(scalar(c,"SELECT @almuerzo_2026_2_filas_periodo")), "No es un periodo");
        require("1".equals(scalar(c,"SELECT @almuerzo_2026_2_conexion=CONNECTION_ID()")), "Conexion de operacion incorrecta");
        require("1".equals(scalar(c,"SELECT @almuerzo_2026_2_invariantes_verificados")),"Faltan invariantes verificados");
        Snapshot current=snapshot(c);
        require(expectedPost().equals(current), "POST pendiente no es el delta aprobado");
        observation("verificaciones_pendientes",Map.of("delta_datos",delta(current),"huellas_sql",hashes(c)));
    }

    private void expectSql(Connection c, String sql, int code, String marker) throws SQLException {
        try { write(c,sql); }
        catch (SQLException ex) {
            require(ex.getErrorCode()==code,"Codigo SQL inesperado: " + ex.getErrorCode() + "; " + ex.getMessage());
            require(marker==null || ex.getMessage().contains(marker),"Falta marcador esperado " + marker + ": " + ex.getMessage());
            observation("rechazos_comprobados",Map.of("sql",sql,"codigo_mysql",ex.getErrorCode(),
                "sqlstate",Objects.toString(ex.getSQLState(),""),"mensaje",ex.getMessage()));
            return;
        }
        throw new AssertionError("La sentencia debio fallar con " + code + ": " + sql);
    }

    private Snapshot expectedPost() {
        var tables = new LinkedHashMap<String,Data>(baseline.tables());
        for (String table : List.of("periodo_academico","sesion")) {
            Data original = baseline.tables().get(table);
            int idColumn = original.columns().indexOf("id");
            var rows = new ArrayList<List<String>>();
            for (var row : original.rows()) {
                var copy = new ArrayList<>(row);
                String id = row.get(idColumn);
                if (table.equals("periodo_academico") && id.equals("2")) {
                    copy.set(original.columns().indexOf("almuerzo_inicio"), "13:00:00");
                    copy.set(original.columns().indexOf("almuerzo_fin"), "14:00:00");
                } else if (table.equals("sesion") && MOVED.contains(id)) {
                    copy.set(original.columns().indexOf("hora_inicio"), "15:00:00");
                    copy.set(original.columns().indexOf("hora_fin"), "17:00:00");
                }
                rows.add(Collections.unmodifiableList(copy));
            }
            tables.put(table, new Data(original.columns(),List.copyOf(rows)));
        }
        return new Snapshot(Collections.unmodifiableMap(tables));
    }

    private static Map<String,List<String>> keyed(Data data) {
        var result=new LinkedHashMap<String,List<String>>();
        int id=data.columns().indexOf("id");
        for(var row:data.rows()) {
            String key=id>=0?row.get(id):json(List.of(row.get(data.columns().indexOf("docente_id")),
                row.get(data.columns().indexOf("especialidad"))));
            require(result.put(key,row)==null,"Clave repetida en snapshot: "+key);
        }
        return result;
    }

    private Map<String,Object> delta(Snapshot current) {
        var details=new ArrayList<Map<String,Object>>();
        var counts=new LinkedHashMap<String,Object>();
        int modified=0,inserted=0,deleted=0,fields=0;
        for(String table:TABLES) {
            Data previous=baseline.tables().get(table), after=current.tables().get(table);
            require(previous.columns().equals(after.columns()),"Cambio de columnas en "+table);
            var beforeRows=keyed(previous); var afterRows=keyed(after);
            var keys=new java.util.LinkedHashSet<>(beforeRows.keySet()); keys.addAll(afterRows.keySet());
            int changes=0;
            for(String key:keys) {
                var oldRow=beforeRows.get(key); var newRow=afterRows.get(key);
                if(Objects.equals(oldRow,newRow)) continue;
                changes++;
                if(oldRow==null) inserted++; else if(newRow==null) deleted++; else modified++;
                var changedFields=new ArrayList<Map<String,Object>>();
                for(int i=0;i<previous.columns().size();i++) {
                    String before=oldRow==null?null:oldRow.get(i), next=newRow==null?null:newRow.get(i);
                    if(Objects.equals(before,next)) continue;
                    fields++;
                    var change=new LinkedHashMap<String,Object>();
                    change.put("columna",previous.columns().get(i)); change.put("antes",before); change.put("despues",next);
                    changedFields.add(change);
                }
                details.add(Map.of("tabla",table,"clave",key,"campos",changedFields));
            }
            counts.put(table,Map.of("filas_antes",beforeRows.size(),"filas_despues",afterRows.size(),"filas_distintas",changes));
        }
        return Map.of("filas_modificadas",modified,"filas_insertadas",inserted,"filas_eliminadas",deleted,
            "campos_modificados",fields,"tablas",counts,"cambios",details);
    }

    private static Map<String,Object> historical(Snapshot snapshot) {
        var result=new LinkedHashMap<String,Object>();
        for(String table:List.of("periodo_academico","horario","sesion","grupo")) {
            Data data=snapshot.tables().get(table);
            String key=switch(table) { case "periodo_academico" -> "id"; case "horario","grupo" -> "periodo_id"; default -> "horario_id"; };
            int index=data.columns().indexOf(key);
            result.put(table,Map.of("columnas",data.columns(),"filas",data.rows().stream().filter(row->"1".equals(row.get(index))).toList()));
        }
        return result;
    }

    private static String digest(Object value) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(json(value).getBytes(StandardCharsets.UTF_8)));
    }

    private void measure(Connection c,String stage,boolean expectBaseline) throws Exception {
        Snapshot actual=snapshot(c);
        require((expectBaseline?baseline:expectedPost()).equals(actual),"Snapshot incorrecto en "+stage);
        var measured=new LinkedHashMap<String,Object>();
        measured.put("conexion",query(c,"SELECT CONNECTION_ID() AS conexion,CURRENT_USER() AS cuenta_efectiva,USER() AS cuenta_cliente,CURRENT_ROLE() AS roles"));
        measured.put("delta_desde_pre",delta(actual));
        var actualHashes=hashes(c);
        measured.put("huellas_sql",actualHashes);
        measured.put("huellas_iguales_pre",baselineHashes.equals(actualHashes));
        if(expectBaseline) require(baselineHashes.equals(actualHashes),"ROLLBACK no restauro las huellas SQL");
        var historicalBefore=historical(baseline); var historicalNow=historical(actual);
        boolean preserved=historicalBefore.equals(historicalNow);
        require(preserved,"Cambio el periodo 2026-1, su publicado, sesiones o grupos");
        measured.put("historico_intacto",preserved);
        measured.put("historico_sha256_pre",digest(historicalBefore));
        measured.put("historico_sha256_actual",digest(historicalNow));
        measured.put("periodos_y_horarios",query(c,"""
            SELECT p.id AS periodo_id,p.nombre,p.almuerzo_inicio,p.almuerzo_fin,
                   h.id AS horario_id,h.estado,COUNT(s.id) AS sesiones
              FROM periodo_academico p LEFT JOIN horario h ON h.periodo_id=p.id
              LEFT JOIN sesion s ON s.horario_id=h.id
             GROUP BY p.id,p.nombre,p.almuerzo_inicio,p.almuerzo_fin,h.id,h.estado
             ORDER BY p.id,h.id
            """));
        measured.put("sesiones_previstas",query(c,"""
            SELECT s.id,s.horario_id,s.grupo_id,g.codigo AS grupo,c.nombre AS curso,
                   d.id AS docente_id,d.nombre AS docente,s.dia,s.hora_inicio,s.hora_fin,
                   c.necesita_aula_especial
              FROM sesion s JOIN grupo g ON g.id=s.grupo_id JOIN curso c ON c.id=g.curso_id
              JOIN docente d ON d.id=g.docente_id WHERE s.id IN (12,13,14,18,23) ORDER BY s.id
            """));
        measured.put("conflictos_parametros_actuales",query(c,"""
            SELECT h.id AS horario_id,COUNT(v.sesion_id) AS conflictos
              FROM horario h LEFT JOIN v_sesion_conflicto_parametros v ON v.horario_id=h.id
             GROUP BY h.id ORDER BY h.id
            """));
        measured.put("conflictos_si_almuerzo_13_14",query(c,"""
            SELECT h.id AS horario_id,COUNT(s.id) AS sesiones_afectadas
              FROM horario h LEFT JOIN sesion s ON s.horario_id=h.id
               AND s.hora_inicio<'14:00:00' AND s.hora_fin>'13:00:00'
             GROUP BY h.id ORDER BY h.id
            """));
        measured.put("choques_docente_o_grupo",query(c,"""
            SELECT COUNT(*) AS conflictos FROM sesion a JOIN sesion b
              ON b.horario_id=a.horario_id AND b.dia=a.dia AND b.id>a.id
              JOIN grupo ga ON ga.id=a.grupo_id JOIN grupo gb ON gb.id=b.grupo_id
             WHERE (a.grupo_id=b.grupo_id OR ga.docente_id=gb.docente_id)
               AND a.hora_inicio<b.hora_fin AND a.hora_fin>b.hora_inicio
            """));
        measured.put("incumplimientos_disponibilidad_firme",query(c,"""
            SELECT COUNT(*) AS conflictos FROM sesion s JOIN grupo g ON g.id=s.grupo_id
             WHERE (EXISTS(SELECT 1 FROM restriccion_horaria r WHERE r.docente_id=g.docente_id
                       AND r.tipo='FIRME' AND r.sentido='DISPONIBLE')
                 AND NOT EXISTS(SELECT 1 FROM restriccion_horaria r WHERE r.docente_id=g.docente_id
                       AND r.tipo='FIRME' AND r.sentido='DISPONIBLE' AND r.dia=s.dia
                       AND r.hora_inicio<=s.hora_inicio AND r.hora_fin>=s.hora_fin))
                OR EXISTS(SELECT 1 FROM restriccion_horaria r WHERE r.docente_id=g.docente_id
                       AND r.tipo='FIRME' AND r.sentido='NO_DISPONIBLE' AND r.dia=s.dia
                       AND s.hora_inicio<r.hora_fin AND s.hora_fin>r.hora_inicio)
            """));
        measured.put("frecuencias",query(c,"""
            SELECT h.id AS horario_id,g.id AS grupo_id,COUNT(s.id) AS programadas,c.sesiones_semanales AS requeridas
              FROM grupo g JOIN curso c ON c.id=g.curso_id JOIN horario h ON h.periodo_id=g.periodo_id
              LEFT JOIN sesion s ON s.horario_id=h.id AND s.grupo_id=g.id
             GROUP BY h.id,g.id,c.sesiones_semanales ORDER BY h.id,g.id
            """));
        measured.put("excesos_cupo_o_frecuencia_maxima",query(c,"""
            SELECT COUNT(*) AS conflictos FROM grupo g JOIN periodo_academico p ON p.id=g.periodo_id
              JOIN curso c ON c.id=g.curso_id
             WHERE c.sesiones_semanales>p.max_sesiones_semana
                OR g.inscritos>FLOOR(g.cupo_maximo*(1+p.tolerancia_cupo_pct/100))
            """));
        for(String rule:List.of("conflictos_parametros_actuales","choques_docente_o_grupo",
                "incumplimientos_disponibilidad_firme","excesos_cupo_o_frecuencia_maxima")) {
            @SuppressWarnings("unchecked") var ruleRows=(List<Map<String,String>>)measured.get(rule);
            for(var row:ruleRows) require("0".equals(row.get("conflictos")),"Conflictos en "+rule+" durante "+stage);
        }
        measured.put("flyway",query(c,"SELECT installed_rank,version,description,checksum,success FROM flyway_schema_history ORDER BY installed_rank"));
        observedV3Count=Long.valueOf(scalar(c,"SELECT COUNT(*) FROM flyway_schema_history WHERE version='3'"));
        measured.put("migraciones_v3",observedV3Count);
        measured.put("defaults_almuerzo",query(c,"SELECT column_name,column_default FROM information_schema.columns "
            +"WHERE table_schema='horarios_ueb' AND table_name='periodo_academico' AND column_name IN ('almuerzo_inicio','almuerzo_fin') ORDER BY ordinal_position"));
        measurements.put(stage,measured);
    }

    private void run() throws Exception {
        try (var c=root()) {
            require("8.0.45".equals(scalar(c,"SELECT VERSION()")),"Se requiere MySQL 8.0.45");
            installation(c);
            baseline=snapshot(c);
            baselineHashes=hashes(c);
            require(baseline.tables().get("sesion").rows().size()==32,"La referencia debe tener 32 sesiones");
            require("24".equals(scalar(c,"SELECT COUNT(*) FROM sesion WHERE horario_id=2")),"Faltan 24 sesiones del borrador");
            require("8".equals(scalar(c,"SELECT COUNT(*) FROM sesion WHERE horario_id=1")),"Faltan ocho sesiones historicas");
            measure(c,"PRE",true);
        }
        test("01_aplicar_y_rollback",()-> {
            try (var a=root(); var observer=root()) {
                write(a,APPLY); pending(a); unchanged(observer);
                measure(a,"POST_pendiente_antes_rollback",false);
                write(a,ROLLBACK); unchanged(a); unchanged(observer);
                measure(observer,"TRAS_ROLLBACK",true);
            }
        });
        test("02_confirmar_tras_rollback_rechazado",()-> {
            try (var a=root(); var observer=root()) {
                write(a,APPLY); pending(a); write(a,ROLLBACK);
                expectSql(a,CONFIRM,1305,null);
                require("ERROR_REVERTIDO".equals(scalar(a,"SELECT @almuerzo_2026_2_estado")),"No marco la perdida de transaccion");
                unchanged(a); unchanged(observer);
            }
        });
        test("03_rechazar_cambio_previo_con_24_sesiones",()-> {
            try (var a=root(); var observer=root()) {
                write(a,"UPDATE sesion SET hora_inicio='17:00:00',hora_fin='19:00:00' WHERE id=9 AND horario_id=2");
                Snapshot changed=snapshot(a);
                require(!baseline.equals(changed),"No se altero el fixture");
                require("24".equals(scalar(a,"SELECT COUNT(*) FROM sesion WHERE horario_id=2")),"Cambio el conteo de 24");
                expectSql(a,APPLY,1644,"[ALM-03]");
                require(changed.equals(snapshot(a)) && changed.equals(snapshot(observer)),"El rechazo altero datos");
                write(a,"UPDATE sesion SET hora_inicio='07:00:00',hora_fin='09:00:00' WHERE id=9 AND horario_id=2");
                unchanged(a); unchanged(observer);
            }
        });
        test("04_no_revertir_transaccion_ajena",()-> {
            try (var a=root(); var observer=root()) {
                write(a,"START TRANSACTION READ WRITE");
                write(a,"UPDATE docente SET nombre=CONCAT(nombre,' [txn-ajena]') WHERE id=6");
                expectSql(a,APPLY,1568,null);
                require(scalar(a,"SELECT nombre FROM docente WHERE id=6").endsWith(" [txn-ajena]"),"Se revirtio la transaccion previa");
                unchanged(observer); write(a,ROLLBACK); unchanged(a); unchanged(observer);
            }
        });
        test("05_confirmacion_en_otra_conexion_rechazada",()-> {
            try (var a=root(); var b=root()) {
                write(a,APPLY); pending(a);
                expectSql(b,CONFIRM,1644,"[ALM-17]");
                pending(a); unchanged(b); write(a,ROLLBACK); unchanged(a); unchanged(b);
            }
        });
        test("06_bloqueos_de_sesion_periodo_y_rango_restricciones",()-> {
            try (var a=root(); var b=root()) {
                write(a,APPLY); pending(a); write(b,"SET SESSION innodb_lock_wait_timeout=1");
                expectSql(b,"UPDATE sesion SET hora_inicio='17:00:00',hora_fin='19:00:00' WHERE id=9",1205,null);
                expectSql(b,"UPDATE periodo_academico SET nombre='2026-2 bloqueado' WHERE id=2",1205,null);
                expectSql(b,"INSERT INTO restriccion_horaria (docente_id,dia,hora_inicio,hora_fin,tipo,sentido) VALUES (1,1,'15:00:00','17:00:00','FIRME','NO_DISPONIBLE')",1205,null);
                pending(a); unchanged(b); write(a,ROLLBACK); unchanged(a); unchanged(b);
            }
        });
        test("07_confirmacion_fallida_revierte_toda_la_operacion",()-> {
            try (var a=root(); var observer=root()) {
                write(a,APPLY); pending(a);
                write(a,"UPDATE sesion SET hora_inicio='17:00:00',hora_fin='19:00:00' WHERE id=9 AND horario_id=2");
                expectSql(a,CONFIRM,1644,"[ALM-03]");
                require("ERROR_REVERTIDO".equals(scalar(a,"SELECT @almuerzo_2026_2_estado")),"Falta estado de reversion automatica");
                unchanged(a); unchanged(observer);
            }
        });
        test("08_desconexion_revierte_y_no_permite_continuar",()-> {
            try (var a=root(); var observer=root()) {
                write(a,APPLY); pending(a); unchanged(observer);
            }
            try (var b=root()) { unchanged(b); expectSql(b,CONFIRM,1644,"[ALM-17]"); unchanged(b); }
        });
        test("09_confirmacion_persistente_con_permisos_minimos",()-> {
            try (var admin=root()) {
                write(admin,"CREATE USER " + LIMITED_ACCOUNT + " IDENTIFIED BY ''");
                for (String table:TABLES) write(admin,"GRANT SELECT ON `horarios_ueb`.`"+table+"` TO "+LIMITED_ACCOUNT);
                write(admin,"GRANT UPDATE (hora_inicio,hora_fin) ON horarios_ueb.sesion TO "+LIMITED_ACCOUNT);
                write(admin,"GRANT UPDATE (almuerzo_inicio,almuerzo_fin) ON horarios_ueb.periodo_academico TO "+LIMITED_ACCOUNT);
                for (String suffix:List.of("aplicar","confirmar","huellas","verificar")) {
                    write(admin,"GRANT EXECUTE ON PROCEDURE horarios_ueb.sp_almuerzo_2026_2_"+suffix+" TO "+LIMITED_ACCOUNT);
                }
                unchanged(admin);
            }
            try (var a=connect(LIMITED); var observer=root()) {
                require(scalar(a,"SELECT CURRENT_USER()").startsWith(LIMITED+"@"),"No se uso la cuenta limitada");
                observation("operador",query(a,"SELECT CONNECTION_ID() AS conexion,CURRENT_USER() AS cuenta_efectiva,USER() AS cuenta_cliente,CURRENT_ROLE() AS roles"));
                observation("permisos_operador",query(a,"SHOW GRANTS"));
                write(a,APPLY); pending(a); unchanged(observer);
                write(a,CONFIRM);
                require("CONFIRMADO".equals(scalar(a,"SELECT @almuerzo_2026_2_estado")),"Falta confirmacion");
                require(expectedPost().equals(snapshot(a)),"POST de operador difiere del delta exacto");
            }
            try (var observer=root()) {
                require(expectedPost().equals(snapshot(observer)),"Los cambios no persistieron en otra conexion");
                require("0".equals(scalar(observer,"SELECT COUNT(*) FROM flyway_schema_history WHERE version='3'")),"Se aplico V3");
                require("2".equals(scalar(observer,"SELECT COUNT(*) FROM flyway_schema_history")),"Cambio el historial Flyway");
                require("12:00:00".equals(scalar(observer,"SELECT column_default FROM information_schema.columns WHERE table_schema='horarios_ueb' AND table_name='periodo_academico' AND column_name='almuerzo_inicio'")),"Cambio DEFAULT inicio");
                require("13:00:00".equals(scalar(observer,"SELECT column_default FROM information_schema.columns WHERE table_schema='horarios_ueb' AND table_name='periodo_academico' AND column_name='almuerzo_fin'")),"Cambio DEFAULT fin");
                require("0".equals(scalar(observer,"SELECT COUNT(*) FROM v_sesion_conflicto_parametros")),"Hay conflictos tras confirmar");
                require("1".equals(scalar(observer,"SELECT COUNT(*) FROM sesion WHERE horario_id=2 AND grupo_id=21")),"Cambio el pendiente del grupo 21");
                measure(observer,"POST_confirmado_en_nueva_conexion",false);
            }
        });
    }

    private void test(String name, Checked body) throws Exception {
        long begin=System.nanoTime();
        var result=new LinkedHashMap<String,Object>();
        result.put("caso",name);
        currentCase=result;
        try {
            body.run(); result.put("resultado","OK"); System.out.println("OK "+name);
        } catch (Exception|AssertionError ex) {
            result.put("resultado","FALLO"); result.put("error",ex.toString());
            throw ex;
        } finally {
            result.put("duracion_ms",(System.nanoTime()-begin)/1_000_000);
            results.add(result);
            currentCase=null;
        }
    }

    private void report(Throwable error) throws Exception {
        var data=new LinkedHashMap<String,Object>();
        data.put("inicio_utc",started.toString()); data.put("fin_utc",Instant.now().toString());
        data.put("puerto_temporal",port); data.put("server_uuid",uuid); data.put("datadir_temporal",datadir);
        data.put("esquema",SCHEMA); data.put("resultado",error==null?"OK":"FALLO");
        data.put("casos",results); data.put("casos_correctos",results.stream().filter(r->Objects.equals(r.get("resultado"),"OK")).count());
        data.put("procedimientos_instalados",installedProcedures);
        data.put("cantidad_procedimientos_instalados",installedProcedures.size());
        data.put("mediciones",measurements);
        data.put("error",error==null?null:error.toString());
        data.put("verificacion_origen","Comparacion externa de dumps por probar_control_almuerzo.ps1");
        data.put("v3_aplicada",observedV3Count==null?null:observedV3Count>0);
        Files.createDirectories(output.getParent()); Files.writeString(output,json(data)+"\n");
        System.out.println("Resultado JSON: "+output);
    }

    private static String json(Object value) {
        if (value==null) return "null";
        if (value instanceof Number || value instanceof Boolean) return value.toString();
        if (value instanceof Map<?,?> map) {
            var fields=new ArrayList<String>();
            map.forEach((k,v)->fields.add(json(String.valueOf(k))+":"+json(v)));
            return "{"+String.join(",",fields)+"}";
        }
        if (value instanceof Iterable<?> list) {
            var values=new ArrayList<String>(); for (Object item:list) values.add(json(item));
            return "["+String.join(",",values)+"]";
        }
        var out=new StringBuilder("\"");
        for (char c:value.toString().toCharArray()) {
            switch(c) {
                case '"' -> out.append("\\\""); case '\\' -> out.append("\\\\");
                case '\n' -> out.append("\\n"); case '\r' -> out.append("\\r"); case '\t' -> out.append("\\t");
                default -> { if(c<32) out.append(String.format("\\u%04x",(int)c)); else out.append(c); }
            }
        }
        return out.append('"').toString();
    }

    private static void require(boolean condition,String message) { if(!condition) throw new AssertionError(message); }
    private record Data(List<String> columns,List<List<String>> rows) {}
    private record Snapshot(Map<String,Data> tables) {}
    @FunctionalInterface private interface Checked { void run() throws Exception; }
}
