# Instrucción inicial para Codex (copiar en la extensión)

Estoy en la rama `feature/backend-base` del repositorio del proyecto universitario «Módulo de Asignación de Horarios Docente-Curso».

Revisa el contenido de `backend/`, especialmente `pom.xml`, `README.md`, `AsignacionHorariosApplication.java`, `InicioController.java`, y las pruebas. Los documentos académicos que rigen las decisiones son el Informe Proyecto Primera Entrega (secciones 5.2, 5.3, 5.6 y 6.1–6.5) y la Metodología Scrum (Sprint 0).

**No modifiques archivos todavía.**

1. Comprueba que la organización respeta el patrón MVC monolítico.
2. Revisa que los starters declarados corresponden a Spring Boot 4.1.1 y que Java 25 es compatible.
3. Indícame cómo ejecutar `mvn clean test` y `mvn spring-boot:run` desde `backend/`.
4. Si detectas un error, explícalo antes de cambiar código.
5. No inventes las tablas ni las entidades JPA antes de revisar el esquema SQL elaborado con Claude.
6. Propón un plan pequeño para la fase 0B (entidades, JPA, MySQL y pruebas de persistencia).

Importante: no implementes aún RF01–RF10, el motor de generación, autenticación ni interfaz definitiva.
