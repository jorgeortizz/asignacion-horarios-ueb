package co.edu.uelbosque.asignacionhorarios.repository;
import co.edu.uelbosque.asignacionhorarios.model.*;
import java.util.*;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
public interface GrupoRepository extends JpaRepository<Grupo, Long> {
    List<Grupo> findByPeriodoIdOrderById(Long periodoId);
    List<Grupo> findByDocenteId(Long docenteId);
    boolean existsByPeriodoIdAndCursoIdAndCodigo(Long periodoId, Long cursoId, String codigo);
}
