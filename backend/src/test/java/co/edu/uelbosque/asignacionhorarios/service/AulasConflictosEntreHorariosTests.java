package co.edu.uelbosque.asignacionhorarios.service;

import co.edu.uelbosque.asignacionhorarios.model.Horario;
import co.edu.uelbosque.asignacionhorarios.model.EstadoHorario;
import co.edu.uelbosque.asignacionhorarios.repository.HorarioRepository;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.Optional;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** Verifica el bloqueo de conflictos cruzados en SQL real, sin tocar MySQL. */
class AulasConflictosEntreHorariosTests {
    private JdbcTemplate base() {
        var ds = new DriverManagerDataSource("jdbc:h2:mem:aulas_" +
            UUID.randomUUID().toString().replace("-","") + ";DB_CLOSE_DELAY=-1", "sa", "");
        var db = new JdbcTemplate(ds);
        db.execute("CREATE TABLE periodo_academico(id BIGINT PRIMARY KEY)");
        db.execute("CREATE TABLE horario(id BIGINT PRIMARY KEY, periodo_id BIGINT, estado VARCHAR(20))");
        db.execute("CREATE TABLE curso(id BIGINT PRIMARY KEY, necesita_aula_especial INT)");
        db.execute("CREATE TABLE grupo(id BIGINT PRIMARY KEY, curso_id BIGINT, inscritos INT)");
        db.execute("CREATE TABLE sesion(id BIGINT PRIMARY KEY, horario_id BIGINT, grupo_id BIGINT, dia INT, hora_inicio TIME, hora_fin TIME)");
        db.execute("CREATE TABLE aula(id BIGINT PRIMARY KEY, codigo VARCHAR(32), nombre VARCHAR(100), tipo VARCHAR(30), edificio VARCHAR(80), piso VARCHAR(20), capacidad INT, activa BOOLEAN, observaciones VARCHAR(255))");
        db.execute("CREATE TABLE sesion_aula(sesion_id BIGINT PRIMARY KEY, aula_id BIGINT)");
        db.execute("CREATE TABLE curso_tipo_aula(curso_id BIGINT PRIMARY KEY, tipo VARCHAR(30))");
        db.execute("CREATE VIEW v_horario_vigente AS SELECT id AS horario_id, periodo_id FROM horario WHERE estado='PUBLICADO'");
        db.update("INSERT INTO periodo_academico VALUES(1),(2)");
        db.update("INSERT INTO horario VALUES(10,1,'BORRADOR'),(20,1,'PUBLICADO'),(30,2,'PUBLICADO')");
        db.update("INSERT INTO curso VALUES(1,1)");
        db.update("INSERT INTO grupo VALUES(1,1,20)");
        db.update("INSERT INTO sesion VALUES(1,10,1,1,'07:00:00','09:00:00'),(2,20,1,1,'08:00:00','10:00:00'),(3,30,1,1,'08:00:00','10:00:00')");
        db.update("INSERT INTO aula VALUES(1,'LAB-1','Laboratorio 1','COMPUTACION','A','1',35,TRUE,''),(2,'LAB-2','Laboratorio 2','COMPUTACION','A','1',35,TRUE,'')");
        return db;
    }
    private AulasService servicio(JdbcTemplate db) {
        HorarioRepository repo = mock(HorarioRepository.class);
        var h = new Horario(); h.setEstado(EstadoHorario.BORRADOR);
        when(repo.bloquear(10L)).thenReturn(Optional.of(h));
        return new AulasService(db,repo);
    }

    @Test void rechazaChoqueConHorarioPublicadoDelMismoPeriodo() {
        JdbcTemplate db=base();
        db.update("INSERT INTO sesion_aula VALUES(2,1)");
        var servicio=servicio(db);
        assertThrows(RuntimeException.class, () -> servicio.asignar(10L,1L,1L));
        assertEquals(0,db.queryForObject("SELECT COUNT(*) FROM sesion_aula WHERE sesion_id=1",Integer.class));
        servicio.asignar(10L,1L,2L);
        assertEquals(2L,db.queryForObject("SELECT aula_id FROM sesion_aula WHERE sesion_id=1",Long.class));
    }

    @Test void noBloqueaAulasPorUnPeriodoAcademicoDiferente() {
        JdbcTemplate db=base();
        db.update("INSERT INTO sesion_aula VALUES(3,1)");
        servicio(db).asignar(10L,1L,1L);
        assertEquals(1L,db.queryForObject("SELECT aula_id FROM sesion_aula WHERE sesion_id=1",Long.class));
    }
}
