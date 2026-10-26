# Integracion Java / MySQL V2

La referencia oficial es [CONTRATO_JPA.md](../database/CONTRATO_JPA.md), complementada por
[README_BD.md](../database/README_BD.md) y el [informe tecnico](../database/INFORME_REVISION_TECNICA.md).

## Mapeos y comportamiento

- Siete entidades y la coleccion `Docente.especialidades`; tablas, columnas y relaciones
  obligatorias explicitas. No se agregan cascadas de borrado ni orphanRemoval.
- Se mantienen los tipos publicos: `byte` para TINYINT y `short` para SMALLINT.
  `dia` sigue siendo numerico, 1=lunes a 6=sabado, con validacion antes de persistir.
  No se introduce DayOfWeek porque cambiaria sin necesidad la API existente.
- Los cuatro enums conservan sus constantes exactas y se enlazan como JDBC VARCHAR.
  `necesitaAulaEspecial` conserva boolean: Connector/J interpreta TINYINT(1) como BIT
  con su configuracion predeterminada; no se fuerza TINYINT en ese campo.
- `Horario.fechaCreacion` la genera la BD mediante CURRENT_TIMESTAMP. Hibernate recupera
  el valor al insertar; la columna es no insertable y no actualizable.
- `Horario.version` mantiene `@Version int`, equivalente a SQL INT. Se conservan los
  bloqueos PESSIMISTIC_WRITE del horario y las transacciones de movimiento/publicacion.
- Los metadatos incluyen las claves unicas de periodo, curso, grupo, restriccion y sesion.
- Los errores BD-01 a BD-12 producen HTTP 409 con `codigo`, `error` y `estado`.
  Los conflictos optimistas indican que se debe recargar. No se devuelve SQL al cliente.

## Consulta vigente

`GET /api/v1/periodos/{id}/horario-vigente` devuelve el HorarioDto del publicado vigente;
responde 404 cuando no existe. La consulta nativa usa `v_horario_vigente`: mayor
fecha_publicacion y, en empate, mayor id. El historial y las consultas por id conservan
su comportamiento.

## Perfiles y migraciones

- `mysql`: `ddl-auto=none`, nombres fisicos estandar, Flyway habilitado y clean deshabilitado.
  Se conservan las credenciales de aplicacion y migracion separadas del perfil existente.
- `demo`: H2 temporal, `ddl-auto=create-drop` exclusivamente para H2 y Flyway deshabilitado.
  `db/demo/vistas.sql` crea solo la vista equivalente despues de las tablas de Hibernate.
- Spring Boot 4.1.1 gestiona las versiones de starter Flyway, flyway-mysql y Connector/J.
  No se fijan versiones independientes.
- En `db/migration` solo se incluyen las copias entregadas V1 y V2, sin modificarlas.
  No se incorporan P1, P2 ni P3. Tampoco se cambia la politica de publicacion ni el bloqueo
  preventivo de cambios temporales de parametros cuando ya existen sesiones.

## Verificacion

Ejecutar desde `backend`: `mvn clean test`. Las pruebas de aplicacion usan explicitamente
el perfil demo, sin depender del perfil activo de la terminal.

La prueba `MySqlV2IntegrationTests` queda omitida por defecto. Para ejecutarla sobre una
BD V2 de pruebas ya preparada, configurar estas variables en PowerShell:

```powershell
$env:MYSQL_INTEGRATION = 'true'
$env:MYSQL_TEST_URL = 'jdbc:mysql://127.0.0.1:3306/horarios_ueb_pruebas?sslMode=DISABLED'
$env:MYSQL_TEST_USER = '<usuario>'
$env:MYSQL_TEST_PASSWORD = '<clave>'
mvn '-Dtest=MySqlV2IntegrationTests' test
```

Esta prueba fuerza `ddl-auto=validate`, deshabilita Flyway y solo consulta: verifica el
arranque con los mapeos y la consulta nativa usando Connector/J. No prepara la BD.

Pendiente con MySQL real: aplicar V1/V2 en una BD de pruebas con Flyway y su usuario DDL;
verificar el esquema con validate; probar los triggers BD-01 a BD-12 mediante operaciones
reales, los CHECK/collations exactos, el default de fecha con Connector/J y la concurrencia
entre conexiones. H2 y las excepciones JDBC simuladas no prueban esas garantias del motor.
