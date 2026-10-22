package co.edu.uelbosque.asignacionhorarios.repository;
import co.edu.uelbosque.asignacionhorarios.model.*;
import java.util.*;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
public interface HorarioRepository extends JpaRepository<Horario, Long> {
    List<Horario> findByPeriodoIdOrderByFechaCreacionDesc(Long periodoId);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select h from Horario h where h.id = :id")
    Optional<Horario> bloquear(@Param("id") Long id);
}
