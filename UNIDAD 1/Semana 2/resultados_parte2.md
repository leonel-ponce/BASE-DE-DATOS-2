# Parte 2 — Laboratorio de optimización (TP3, Semana 3)

Base utilizada: `food_store_tp3_copia` (copia de trabajo de `food_store_tp2`,
poblada masivamente con `carga_masiva_rendimiento.sql` y corregida con
`fix_detalle_pedido.sql` — ver más abajo el hallazgo que motivó esa
corrección). `ANALYZE` corrido sobre las 5 tablas antes de medir.

Se midieron 3 consultas propias sobre el esquema del proyecto, siguiendo
el flujo: medir antes → proponer con IA → validar la propuesta → medir
después → decidir con datos, nunca aplicar "porque lo dijo la IA".

---

## Nota previa: un hallazgo durante la medición de la Consulta A

Al correr por primera vez la Consulta A (top productos), el plan mostraba
una desviación de estimación enorme: el optimizador esperaba ~50.010
grupos y obtuvo solo **7**. Se investigó antes de seguir, en vez de asumir
que era un problema de índice:

```sql
SELECT COUNT(DISTINCT producto_id) FROM detalle_pedido;  -- devolvió 7
SELECT COUNT(DISTINCT total) FROM pedido WHERE total <> 0; -- devolvió 4
```

Causa real: el script de poblado masivo (`carga_masiva_rendimiento.sql`)
tenía una subconsulta `LATERAL` que generaba `semilla` y `cantidad` con
`random()` **sin referenciar la fila externa** (`gs.n`). PostgreSQL, al no
detectar correlación, evaluaba esa subconsulta **una sola vez para toda
la consulta** en vez de una vez por fila — resultado: 199.994 de 200.000
filas de `detalle_pedido` apuntaban al mismo producto, y los totales de
`pedido` colapsaron a 4 valores distintos.

Se corrigió con un script nuevo (`fix_detalle_pedido.sql`, generado con
OpenCode, revisado línea por línea, verificado leyendo el archivo real
antes de ejecutarlo) que repobló solo los pedidos afectados, forzando la
correlación con `gs.n`. Verificación post-fix: 49.981/50.010 productos
usados, 5 valores de cantidad, 108.414 totales distintos, sin huérfanos
de FK ni inconsistencias de total.

**Las mediciones de este documento son todas posteriores a esa
corrección**, salvo donde se indica lo contrario.

---

## Consulta B — Facturación por categoría y por mes

```sql
EXPLAIN ANALYZE
SELECT c.nombre AS categoria,
       date_trunc('month', ped.fecha_hora) AS mes,
       SUM(dp.subtotal) AS facturado
FROM   detalle_pedido dp
JOIN   pedido   ped ON ped.id = dp.pedido_id
JOIN   producto pr  ON pr.id  = dp.producto_id
JOIN   categoria c  ON c.id   = pr.categoria_id
WHERE  pr.activo = TRUE
GROUP  BY c.nombre, date_trunc('month', ped.fecha_hora)
ORDER  BY mes, facturado DESC;
```

### Plan ANTES (sin cambios)

```
Incremental Sort  (cost=42243.10..56243.42 rows=200006 width=48) (actual time=302.345..302.350 rows=10.00 loops=1)
  Sort Key: (date_trunc('month'::text, ped.fecha_hora)), (sum(dp.subtotal)) DESC
  Presorted Key: (date_trunc('month'::text, ped.fecha_hora))
  ->  GroupAggregate  (cost=42243.07..47243.22 rows=200006 width=48) (actual time=267.205..302.338 rows=10.00 loops=1)
        Group Key: (date_trunc('month'::text, ped.fecha_hora)), c.nombre
        ->  Sort  (cost=42243.07..42743.08 rows=200006 width=24) (actual time=262.229..280.715 rows=200006.00 loops=1)
              Sort Key: (date_trunc('month'::text, ped.fecha_hora)), c.nombre
              Sort Method: external merge  Disk: 6864kB
              ->  Hash Join (dp x ped x pr x c) ...
Planning Time: 3.109 ms
Execution Time: 312.362 ms
```

**Diagnóstico:** el nodo de agregación estima 200.006 filas de resultado
pero obtiene solo 10 — el optimizador no puede estimar bien la cardinalidad
de `date_trunc(fecha_hora)` combinada con `c.nombre` (de otra tabla, tras
el join). Por esa sobreestimación, elige ordenar en disco
(`external merge Disk: 6864kB`) en vez de en memoria. El plan no usa
paralelismo (sin `Workers Launched`), así que subir `work_mem` no corre
riesgo de perder paralelismo (a diferencia de un intento anterior sobre
otra base, donde sí se perdía).

**Cambio propuesto y aplicado:** `SET work_mem = '16MB';` (a nivel de
sesión, no cambia la configuración global del servidor).

### Plan DESPUÉS

```
Incremental Sort  (cost=33843.10..47843.42 rows=200006 width=48) (actual time=236.770..236.774 rows=10.00 loops=1)
  ->  GroupAggregate ...
        ->  Sort  (cost=33843.07..34343.08 rows=200006 width=24) (actual time=201.589..213.526 rows=200006.00 loops=1)
              Sort Method: quicksort  Memory: 14837kB
              ->  Hash Join (dp x ped x pr x c) ...
Planning Time: 0.459 ms
Execution Time: 238.660 ms
```

**Resultado:** `Sort Method` pasó de `external merge` (disco) a
`quicksort` (memoria, 14.837kB). **Execution Time: 312,36 ms → 238,66 ms
(mejora del ~24%).**

---

## Consulta C — Ranking de usuarios por gasto acumulado

```sql
EXPLAIN ANALYZE
SELECT u.id, u.nombre,
       SUM(ped.total) AS gasto,
       RANK() OVER (ORDER BY SUM(ped.total) DESC) AS puesto
FROM   pedido ped
JOIN   usuario u ON u.id = ped.usuario_id
GROUP  BY u.id, u.nombre
ORDER  BY puesto;
```

### Plan (medido ya con `work_mem = 16MB` heredado de la Consulta B)

```
Sort  (cost=11236.77..11286.79 rows=20005 width=67) (actual time=106.776..107.297 rows=20005.00 loops=1)
  ->  WindowAgg (RANK) ...
        ->  Sort (por SUM) ... Sort Method: quicksort  Memory: 1862kB
              ->  HashAggregate  Group Key: u.id  Batches: 1  Memory Usage: 8721kB
                    ->  Hash Join (pedido x usuario) ...
Planning Time: 0.264 ms
Execution Time: 108.740 ms
```

**Diagnóstico:** estimaciones de filas casi exactas en todo el plan.
`HashAggregate` con `Batches: 1`, sin derrame a disco. El `Seq Scan` sobre
`pedido` (200.004 filas) es necesario: la consulta agrega prácticamente
el 100% de la tabla.

**Cambio propuesto:** ninguno. Un índice no ayuda cuando no hay filas
que saltear, y el `work_mem` ya venía en un valor adecuado de la consulta
anterior. **No se aplicó ningún cambio — se documenta la decisión de no
optimizar, con la justificación de por qué no hace falta**, en vez de
forzar un cambio artificial.

**Execution Time: 108,74 ms.** Sin comparación antes/después porque no
se modificó nada.

---

## Consulta A — Top 5 productos más vendidos

```sql
EXPLAIN ANALYZE
SELECT pr.id, pr.nombre, SUM(dp.cantidad) AS unidades
FROM   detalle_pedido dp
JOIN   producto pr ON pr.id = dp.producto_id
WHERE  pr.activo = TRUE
GROUP  BY pr.id, pr.nombre
ORDER  BY unidades DESC
LIMIT  5;
```

### Plan (sobre datos ya corregidos, ver nota previa)

```
Limit  (cost=13818.52..13818.53 rows=5 width=36) (actual time=155.362..155.365 rows=5.00 loops=1)
  ->  Sort (top-N heapsort) ...
        ->  HashAggregate  (cost=12487.77..12987.87 rows=50010 width=36) (actual time=147.380..151.534 rows=49981.00 loops=1)
              Group Key: pr.id   Batches: 1  Memory Usage: 4377kB
              ->  Hash Join (dp x pr, 400.253 filas) ...
Planning Time: 0.269 ms
Execution Time: 156.114 ms
```

**Diagnóstico:** estimación de grupos correcta (50.010 esperados, 49.981
reales — coincide con la cobertura real de productos tras la corrección
del bug de poblado). `Batches: 1`, sin derrame a disco. El `Seq Scan`
sobre `detalle_pedido` (400.253 filas) es necesario porque la consulta
agrega prácticamente toda la tabla para armar el ranking.

**Cambio propuesto:** ninguno, mismo motivo que la Consulta C.

**Execution Time: 156,11 ms.**

---

## 2.2 Tabla comparativa (resumen)

| Consulta | Plan antes (nodo, cost, tiempo real) | Cambio aplicado | Plan después (nodo, cost, tiempo real) | Mejora |
|---|---|---|---|---|
| **B** — Facturación por categoría/mes | `Sort` externo a disco (`external merge Disk: 6864kB`), cost≈42243..56243, **312,36 ms** | `SET work_mem = '16MB'` (sesión) | `Sort` en memoria (`quicksort Memory: 14837kB`), cost≈33843..47843, **238,66 ms** | **~24% ↓** |
| **C** — Ranking usuarios por gasto | `HashAggregate` sin derrame, cost≈11236..11286, **108,74 ms** | Ninguno (justificado: agregación sobre ~100% de la tabla, sin filas que un índice pueda saltear) | — (no se remidió, no hubo cambio) | No aplica |
| **A** — Top 5 productos más vendidos | `HashAggregate` sin derrame, cost≈13818, **156,11 ms** | Ninguno (mismo motivo que C) | — | No aplica |

---

## Criterio de aceptación aplicado

Ninguna propuesta se aplicó "porque lo dijo la IA": en la Consulta B se
explicó, antes de medir, por qué se esperaba que `work_mem` sacara el
sort a disco (y se descartó el riesgo de perder paralelismo, verificando
primero que el plan no usaba workers). En las Consultas A y C se decidió
explícitamente **no** aplicar ningún cambio, documentando el motivo (no
hay filas que saltear), en vez de forzar una optimización artificial
para tener "algo que mostrar".

Además, se documenta un hallazgo no buscado: el bug del `LATERAL` no
correlacionado en el poblado masivo, detectado precisamente porque se
verificó una estimación de plan sospechosa en vez de asumir que un
`HashAggregate` con 7 grupos era normal.
