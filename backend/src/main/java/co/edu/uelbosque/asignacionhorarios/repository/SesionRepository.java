package co.edu.uelbosque.asignacionhorarios.repository;
import co.edu.uelbosque.asignacionhorarios.model.*;
import java.util.*;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
public interface SesionRepository extends JpaRepository<Sesion, Long> {
    List<Sesion> findByHorarioIdOrderByDiaAscHoraInicioAsc(Long horarioId);
    long countByHorarioId(Long horarioId);
    void deleteByHorarioId(Long horarioId);
}
