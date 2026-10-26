package co.edu.uelbosque.asignacionhorarios.service;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import co.edu.uelbosque.asignacionhorarios.model.Curso;
import co.edu.uelbosque.asignacionhorarios.repository.CursoRepository;
import co.edu.uelbosque.asignacionhorarios.repository.DocenteRepository;
import co.edu.uelbosque.asignacionhorarios.repository.GrupoRepository;

@Service
public class HabilitacionDocenteService {

    private final DocenteRepository docentes;
    private final CursoRepository cursos;
    private final GrupoRepository grupos;

    public HabilitacionDocenteService(
            DocenteRepository docentes,
            CursoRepository cursos,
            GrupoRepository grupos) {

        this.docentes = docentes;
        this.cursos = cursos;
        this.grupos = grupos;
    }

    @Transactional(readOnly = true)
    public List<Long> obtenerCursos(Long docenteId) {

        var docente = Util.requerido(
            docentes.findById(docenteId),
            "Docente"
        );

        return docente.getCursosHabilitados()
            .stream()
            .map(Curso::getId)
            .sorted()
            .toList();
    }

    @Transactional
    public List<Long> actualizarCursos(
            Long docenteId,
            Set<Long> cursosIds) {

        var docente = Util.requerido(
            docentes.findById(docenteId),
            "Docente"
        );

        Util.exigir(
            cursosIds != null && !cursosIds.contains(null),
            "La lista de cursos no es válida"
        );

        var cursosEncontrados =
            cursos.findAllById(cursosIds);

        Set<Long> idsEncontrados = cursosEncontrados
            .stream()
            .map(Curso::getId)
            .collect(Collectors.toSet());

        Util.exigir(
            idsEncontrados.equals(cursosIds),
            "Uno o más cursos no existen"
        );

        // Impedir retirar cursos con grupos asignados.
        var gruposDocente =
            grupos.findByDocenteId(docenteId);

        for (var grupo : gruposDocente) {

            Long cursoAsignado =
                grupo.getCurso().getId();

            Util.exigir(
                cursosIds.contains(cursoAsignado),
                "No puedes retirar la asignatura " +
                grupo.getCurso().getNombre() +
                " porque el docente tiene grupos asociados"
            );
        }

        docente.getCursosHabilitados().clear();

        docente.getCursosHabilitados().addAll(
            new LinkedHashSet<>(cursosEncontrados)
        );

        docentes.save(docente);

        return docente.getCursosHabilitados()
            .stream()
            .map(Curso::getId)
            .sorted()
            .toList();
    }
}