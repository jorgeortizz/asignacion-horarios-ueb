package co.edu.uelbosque.asignacionhorarios.integration;

import co.edu.uelbosque.asignacionhorarios.repository.HorarioRepository;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

import static org.junit.jupiter.api.Assertions.*;

/** Opt-in: valida una BD V2 ya preparada, sin migrar ni modificar datos. */
@EnabledIfEnvironmentVariable(named="MYSQL_INTEGRATION", matches="true")
@ActiveProfiles("mysql")
@SpringBootTest(properties={
    "spring.datasource.url=${MYSQL_TEST_URL}",
    "spring.datasource.username=${MYSQL_TEST_USER}",
    "spring.datasource.password=${MYSQL_TEST_PASSWORD}",
    "spring.jpa.hibernate.ddl-auto=validate",
    "spring.flyway.enabled=false",
    "spring.sql.init.mode=never",
    "spring.jpa.defer-datasource-initialization=false"
})
class MySqlV2IntegrationTests {
    @Autowired ApplicationContext context;
    @Autowired JdbcTemplate jdbc;
    @Autowired HorarioRepository horarios;

    @Test void validaElContratoV2SinEjecutarFlyway() {
        // El arranque del contexto ejecuta Hibernate validate sobre las siete entidades.
        assertTrue(context.getBeansOfType(Flyway.class).isEmpty());
        assertEquals(8, jdbc.queryForObject("""
            SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
              AND table_name IN ('periodo_academico','docente','docente_especialidad',
                'restriccion_horaria','curso','grupo','horario','sesion')
            """, Integer.class));
    }

    @Test void ejecutaLaConsultaNativaDeVigenteConConnectorJ() {
        assertTrue(horarios.findVigenteByPeriodoId(-1L).isEmpty());
    }
}
