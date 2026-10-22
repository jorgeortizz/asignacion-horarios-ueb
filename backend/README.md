# Backend — Asignación de horarios docente-curso

Universidad El Bosque · Proyecto Núcleo 1 · Java 25 · Spring Boot 4.1.1 · Maven.

**Entrega de código inicial ampliado (backend):** 7 entidades JPA, 7 repositorios, servicios de registro, parametrización, reglas independientes, generación heurística, movimientos, publicación, consultas, exportación CSV y controladores REST. No incluye interfaz final de arrastrar y soltar ni autenticación institucional.

## Cómo incorporarlo al repositorio

1. En la rama `feature/backend-base`, guarda una copia de seguridad si modificaste `backend/`.
2. Extrae este ZIP en la **raíz** de `asignacion-horarios-ueb/` (contiene `backend/`). Combina las carpetas; no crees `backend/backend`.
3. Revisa los archivos modificados en Source Control antes de cualquier commit.

## Arranque sin MySQL (solo desarrollo)

```powershell
cd backend
mvn clean test
mvn spring-boot:run
```

El perfil por defecto es `demo`: utiliza **H2 en memoria** para permitir desarrollar y probar la lógica mientras Claude corrige la BD. Las tablas se recrean cada vez; **nunca** uses este perfil para entregar datos ni sustituyas MySQL por H2 en la evaluación final. Página: http://localhost:8080 y endpoints en `/api/v1`.

## Integración futura de MySQL

Primero aplicar el SQL definitivo que entregue Claude en una BD de desarrollo. Revisar diferencias con `CONTRATO_INTEGRACION.md`. En PowerShell:

```powershell
$env:SPRING_PROFILES_ACTIVE="mysql"
$env:DB_URL="jdbc:mysql://localhost:3306/horarios_ueb"
$env:DB_USER="horarios_app"
$env:DB_PASSWORD="..."  # No guardar ni publicar contraseñas reales
mvn spring-boot:run
```

En el perfil `mysql`, `spring.jpa.hibernate.ddl-auto=validate`: Hibernate **no crea ni modifica** las tablas. Si el SQL final cambia, habrá que ajustar los mapeos JPA; no habilitar `update` o `create` en la base institucional.

## API inicial (contrato JSON)

| Método | Ruta | Uso |
|---|---|---|
| POST | `/api/v1/periodos` | Registrar periodo con parámetros iniciales |
| GET | `/api/v1/periodos` | Periodos existentes |
| GET | `/api/v1/periodos/{id}` | Consultar periodo |
| PUT | `/api/v1/periodos/{id}/parametros` | Ajustar parámetros |
| POST | `/api/v1/docentes` | Registrar docente y restricciones |
| GET | `/api/v1/docentes` | Consultar docentes |
| GET | `/api/v1/docentes/{id}/restricciones` | Consultar restricciones |
| POST | `/api/v1/cursos` | Registrar curso |
| GET | `/api/v1/cursos` | Consultar cursos |
| POST | `/api/v1/grupos` | Registrar grupo por periodo |
| GET | `/api/v1/periodos/{id}/grupos` | Consultar grupos |
| POST | `/api/v1/periodos/{id}/generar` | Crear propuesta en borrador; informa faltantes |
| GET | `/api/v1/periodos/{id}/horarios` | Consultar histórico |
| GET | `/api/v1/horarios/{id}` | Consultar detalle |
| POST | `/api/v1/horarios/{id}/validar` | Previsualizar movimiento |
| PUT | `/api/v1/horarios/{id}/sesiones/{sesionId}` | Mover sesión si es válido |
| POST | `/api/v1/horarios/{id}/publicar` | Validar todo y publicar |
| GET | `/api/v1/horarios/{id}/sesiones` | Consultar por `docenteId`/`cursoId`; publicados por defecto |
| GET | `/api/v1/horarios/{id}/exportar.csv` | Descargar CSV publicado |

Ver `EJEMPLOS_API.http` para ejecutar una secuencia con VS Code REST Client (o adaptar los JSON a Postman). El perfil H2 no trae seed automático: crea periodo, docente, curso y grupo antes de generar.

## Alcance pendiente

* Ajustar mappings al **SQL final** que entregue Claude; prueba de integración real contra MySQL pendiente.
* Validación del Comité sobre sentido de restricciones, grupo por periodo y política de horarios publicados.
* Pruebas de integración/concurrencia con MySQL, rendimiento con datos 2026-2 y seguridad de acceso.
* Interfaces Thymeleaf definitivas, SortableJS, filtros sin recarga y botón para deshacer el último movimiento.
* Motor heurístico **no garantiza optimalidad**; produce una propuesta reproducible e informa sesiones no ubicadas.

Los endpoints no incluyen autenticación ni control de permisos: mantener servidor y base de desarrollo **solo en localhost**, sin exponerlos públicamente.
