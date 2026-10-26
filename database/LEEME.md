# Base de datos V2 · Módulo de Asignación de Horarios Docente-Curso

Universidad El Bosque · Programa de Ingeniería de Sistemas · Fase 2

Este paquete contiene la **versión V2** del esquema, tal como se verificó en la segunda revisión técnica. No es un modelo nuevo: siguen las 7 entidades del informe, la tabla auxiliar `docente_especialidad` y las mismas relaciones.
Versiones de MySQL probadas: **9.7.2 y 9.7.4 LTS**. Herramienta de migraciones: Flyway 13.10.3.

## Contenido

| Carpeta / archivo | Para qué sirve |
|---|---|
| `migraciones/V1__esquema_inicial.sql` | Migración Flyway 1: el esquema de la primera entrega. **No se edita.** |
| `migraciones/V2__revision_tecnica.sql` | Migración Flyway 2: las correcciones de la segunda revisión. |
| `migraciones/preflight_V2.sql` | Verificación previa (solo lectura) antes de pasar una base existente de V1 a V2. |
| `migraciones/pendientes/P1…`, `P2…`, `P3…` | Reglas que esperan las decisiones D1, D2 y D3 del Comité. **No se aplican** hasta su aprobación. |
| `01_schema.sql` | Esquema completo para desarrollo; equivale exactamente a V1 + V2 y no borra nada. |
| `00_reset_dev.sql` | Solo desarrollo: reinicia la base, previa confirmación explícita. |
| `02_seed.sql` | Datos de prueba ficticios. |
| `03_queries.sql` | 16 consultas de referencia, cada una con su resultado esperado. |
| `04_tests.sql`, `05_tests_pendientes.sql`, `06_tests_pendiente_P2.sql` | Pruebas SQL: 165 del esquema V2, 22 de P1+P3 y 10 de P2. |
| `INFORME_REVISION_TECNICA.md` | Problemas encontrados, decisiones pendientes y procedimiento de migración V1 → V2. |
| `CONTRATO_JPA.md` | Contrato exacto para el backend: tablas, columnas, tipos, FK, enums y relaciones. |
| `README_BD.md` | Instalación, conexión desde Spring Boot, seguridad y respaldos. |
| `ANALISIS_MODELO_BD.md`, `modelo_er.*` | Análisis del modelo y diagrama entidad-relación. |
| `tools/` | Batería reproducible (`ejecutar_todo.sh`), huella del esquema y generador del contrato. |
| `evidencia/` | Salidas reales de las ejecuciones en 9.7.2 y 9.7.4. |
| `MANIFIESTO_SHA256.txt` | Huella de cada archivo, para comprobar que el paquete está íntegro. |

## Inicio rápido

**Proyecto Spring Boot:** copie **solo** `migraciones/V1__esquema_inicial.sql` y `migraciones/V2__revision_tecnica.sql` a `src/main/resources/db/migration/`. Configure `ddl-auto=none` (ver `README_BD.md`, sección 6).

**Base de desarrollo:**
```bash
mysql -u root -p < 01_schema.sql
mysql -u root -p < 02_seed.sql
mysql -u root -p --table < 04_tests.sql   # resumen final: fallidas = 0
```

**Base existente creada con el esquema anterior:** siga `INFORME_REVISION_TECNICA.md`, sección 4. El orden es respaldo → `preflight_V2.sql` → `flyway baseline` (versión 1) → `flyway migrate`.

## Comprobar la integridad del paquete
```bash
sha256sum -c MANIFIESTO_SHA256.txt
```

## Pendiente fuera de este paquete
- Las decisiones D1–D4 del Comité y la confirmación de `grupo.periodo_id` (A2).
- La integración con Spring Boot: entidades JPA y pruebas JUnit BK01–BK13.
