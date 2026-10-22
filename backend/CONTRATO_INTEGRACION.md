# Contrato provisional Java ↔ SQL (pendiente de Claude)

Esta implementación se basa en el `01_schema.sql` del ZIP original de Claude, **no** en su revisión aún no entregada. No se debe considerar cerrada la integración sin ejecutar `mvn clean test` y pruebas MySQL.

## Modelo

| Entidad Java | Tabla SQL | Observaciones |
|---|---|---|
| `PeriodoAcademico` | `periodo_academico` | parámetros institucionales en columnas, no hardcodeados al operar |
| `Docente` | `docente` | `tipo_vinculacion` enum STRING; especialidades en colección |
| `RestriccionHoraria` | `restriccion_horaria` | `tipo` + `sentido`, interpretación provisional |
| `Curso` | `curso` | frecuencia, duración y aula especial |
| `Grupo` | `grupo` | `periodo_id` adicional propuesto por Claude, todavía sujeto a aprobación |
| `Horario` | `horario` | `estado`, `fecha_creacion`, `fecha_publicacion`, `@Version` |
| `Sesion` | `sesion` | FK a horario/grupo y `dia`, `hora_inicio`, `hora_fin` |
| Colección `Docente.especialidades` | `docente_especialidad` | `@ElementCollection`, tabla auxiliar, no entidad principal |

## Reglas Java

Se reutilizan para generación y movimientos las revisiones de franja, almuerzo, choque de docente, disponibilidad y días consecutivos (esta última advertencia); se añaden bloque fijo y choque de grupo como defensas técnicas coherentes con las sesiones del proyecto. El cambio manual y la publicación requieren BORRADOR; el backend nunca edita un horario PUBLICADO. Esto es una **decisión conservadora provisional**: el Comité debe decidir la política de republicación.

**Datos de prueba H2** son desechables. **SQL original de Claude** incluye `DROP DATABASE`: jamás ejecutarlo en una base con datos valiosos. Se espera SQL actualizado sin operaciones destructivas de migración.

## Puntos por cerrar con Claude/Comité

1. Confirmar las columnas finales de `restriccion_horaria`, `grupo`, `horario`, `sesion`.
2. Verificar claves compuestas, índices, triggers y `@Version` con la versión MySQL instalada.
3. Confirmar si editar un publicado será prohibido, versionado o republicado; el MVP adopta prohibición preventiva en Java.
4. Confirmar cambios en parámetros con sesiones ya publicadas. Se bloquean preventivamente cambios de franja, almuerzo o duración cuando hay sesiones.
5. Confirmar conservación histórica de docente asignado y restricciones por periodo.
6. Las consultas `/sesiones` permiten filtrar por docente/curso; el filtro visual de casillas libres sin conflictos corresponde a la siguiente fase de interfaz.
7. `@ElementCollection` usa carga EAGER por simplicidad del MVP (volumen pequeño); puede optimizarse después.
8. El perfil MySQL debe **validar** contra scripts de Claude; nunca asumir que H2 asegura compatibilidad total.
