package co.edu.uelbosque.asignacionhorarios.repository;

import co.edu.uelbosque.asignacionhorarios.model.*;
import java.util.*;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

public interface DocenteRepository extends JpaRepository<Docente, Long> {
    List<Docente> findByNombreContainingIgnoreCase(String nombre);

    @Query("""
            SELECT DISTINCT d
            FROM Docente d
            JOIN d.cursosHabilitados c
            WHERE c.id = :cursoId
            """)
    List<Docente> buscarHabilitadosPorCurso(
            @Param("cursoId") Long cursoId);
}
