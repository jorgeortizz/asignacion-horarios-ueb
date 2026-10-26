package co.edu.uelbosque.asignacionhorarios.repository;
import co.edu.uelbosque.asignacionhorarios.model.*;
import java.util.*;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
public interface RestriccionHorariaRepository extends JpaRepository<RestriccionHoraria, Long> {
    List<RestriccionHoraria> findByDocenteIdOrderByDiaAscHoraInicioAsc(Long docenteId);
}
