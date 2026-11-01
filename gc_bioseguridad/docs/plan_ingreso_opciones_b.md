# Ingreso y planificación (app móvil)

Contexto: el portal registra **un ingreso por visita planificada (granja + día)**. En garita puede entrar una cuadrilla en un solo paso físico.

## Base: granjas de trabajo (Mis granjas)

Las granjas configuradas en **Mis granjas** filtran qué planificaciones se consideran en el punto. Si no hay ninguna configurada, se muestra un aviso breve al abrir ingreso y **no se filtra** por granja de trabajo (coincidencias de la cuadrilla en todo el plan del día).

## Casos de match

| Caso | Comportamiento |
|------|----------------|
| **1** | Una sola visita candidata en alcance → se vincula automáticamente. |
| **2** | Varias visitas candidatas → hoja para **elegir una granja**; al volver, solo quedan visitas no consumidas ese día para ese DNI. |
| **3** | Varios proveedores/cuadrillas en el mismo formulario → caso 1 o 2 **por DNI**; al guardar, **un ingreso por visita** resuelta. |
| **4** | Sin Mis granjas → aviso corto + plan sin filtro de granja de trabajo. |

## Vehículos

La placa solo cuenta como **planificada** si está en la **misma visita** que la cuadrilla (personas) ya resuelta (`vehiculoDe` en esa `PlanVisita`). No se marca planificado por la misma placa en otra visita del día.

## Estatus sanitario de granja

Solo se consulta cuando hay granja **explícita** en el formulario o visita planificada ya resuelta. No se infiere la única granja de Mis granjas en ingreso **no planificado**.

## Opciones históricas (sanidad)

### B1 — Un ingreso por DNI y día

Un registro; otras visitas del día pueden quedar sin ingreso en portal.

### B2 — Un ingreso por visita (modelo actual)

N ingresos cuando hay N visitas distintas en el mismo escaneo; sin checks de “incluir visita” (elección previa por granja).

### B3 — Backend extendido

Campo `punto_control` o detalle multi-visita en servidor; requiere PHP/SQL.

**Recomendación técnica:** Capa A + **B2** (elección de granja + un registro por visita).
