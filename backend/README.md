# Backend · Módulo de Asignación de Horarios Docente-Curso

## Alcance de esta entrega: Sprint 0A

Esta es una **base ejecutable** de aplicación web monolítica Spring Boot con Spring MVC y Thymeleaf. Se ha creado una vista técnica en `/` para comprobar que la aplicación arranca. **No** implementa aún RF01–RF10 ni las entidades JPA.

Esta decisión es temporal: el Sprint 0 completo exige persistencia del modelo en MySQL. Se incorporará en 0B cuando se apruebe el esquema `01_schema.sql` desarrollado en paralelo con Claude.

### Versiones

- Java: JDK **25** (elección del informe técnico, §6.4).
- Spring Boot: **4.1.1** (parche estable de la línea 4.1 prevista en el informe).
- Maven: **3.6.3 o superior** (instalado y disponible como `mvn`).
- MySQL previsto: **9.7 LTS**, pendiente de integración.

### Requisitos previos

```powershell
java -version
javac -version
mvn -version
```

Java y `javac` deben indicar 25. Si `mvn` no se reconoce, instala Maven o genera y agrega un Maven Wrapper oficial antes de continuar. Este paquete no incluye `mvnw.cmd`.

### Compilar y probar

Desde la carpeta `backend/`:

```powershell
mvn clean test
mvn spring-boot:run
```

En el navegador, visita `http://localhost:8080/`.

Para generar el jar:

```powershell
mvn clean package
java -jar target/asignacion-horarios-0.0.1-SNAPSHOT.jar
```

Los comandos requieren conexión a Maven Central en su primer uso si aún no se tienen descargadas las dependencias.

### Organización

- `controller/`: controladores Spring MVC (solo `InicioController` técnico en esta etapa).
- `service/`: casos de uso y servicios; reservado para sprints siguientes.
- `model/`: las siete entidades aprobadas; pendiente de 0B.
- `repository/`: persistencia JPA; pendiente de 0B.
- `validation/`: reglas independientes, duras y preferencias; pendiente de Sprint 1.
- `resources/templates/`: plantillas Thymeleaf.
- `resources/static/`: archivos CSS/JS/recursos web.

### Criterios de comprobación (Sprint 0A)

- [ ] `mvn clean test` termina con `BUILD SUCCESS`.
- [ ] `mvn spring-boot:run` inicia el servidor sin error.
- [ ] La página `http://localhost:8080/` se visualiza.
- [ ] `git status` muestra solo cambios previstos; commit en `feature/backend-base`.
- [ ] Pull request revisado por un integrante según Definition of Done del documento Scrum.

### Integración pendiente (Sprint 0B)

1. Revisar `database/01_schema.sql`, el diagrama ER y el diccionario de datos de Claude.
2. Confirmar columnas, claves, tipos, relaciones y suposiciones con los documentos del proyecto.
3. Incorporar Spring Data JPA y MySQL Connector/J en `pom.xml`.
4. Mapear las siete entidades respetando el SQL aprobado.
5. Configurar URL/usuario/contraseña mediante variables de entorno, nunca en Git.
6. Adoptar `spring.jpa.hibernate.ddl-auto=validate` para **validar** el esquema, no crearlo automáticamente.
7. Ejecutar las pruebas de integración con MySQL y registrar evidencia.

### Advertencias

- Este módulo todavía **no** genera ni valida horarios.
- No crear tablas a partir de Hibernate sin aceptar antes el esquema de Claude.
- No subir contraseñas, `.env` ni datos personales reales.
- No sustituir la arquitectura MVC monolítica por una API React/SPA.
