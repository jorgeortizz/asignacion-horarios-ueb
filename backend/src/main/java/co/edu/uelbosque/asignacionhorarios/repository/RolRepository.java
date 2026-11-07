package co.edu.uelbosque.asignacionhorarios.repository;

import co.edu.uelbosque.asignacionhorarios.model.CodigoRol;
import co.edu.uelbosque.asignacionhorarios.model.Rol;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RolRepository extends JpaRepository<Rol, Long> {
    Optional<Rol> findByCodigo(CodigoRol codigo);
}
