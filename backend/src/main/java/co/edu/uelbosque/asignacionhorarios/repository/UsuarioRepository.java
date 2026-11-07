package co.edu.uelbosque.asignacionhorarios.repository;

import co.edu.uelbosque.asignacionhorarios.model.Usuario;
import java.util.Optional;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UsuarioRepository extends JpaRepository<Usuario, Long> {
    @EntityGraph(attributePaths = {"rol", "docente"})
    Optional<Usuario> findByIdentificadorIgnoreCase(String identificador);

    boolean existsByDocenteId(Long docenteId);
}
