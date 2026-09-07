# Parte 5 — Competencia de optimización entre equipos (TP3)

## Consulta común (entregada por el profesor)

Adaptada a los nombres reales de columna del esquema del grupo
(`precio_lista` en vez de `precio`, tal como aparece en `producto`):

```sql
SELECT id, nombre, precio_lista, stock
FROM producto
WHERE categoria_id = 1 AND activo = TRUE
      AND precio_lista BETWEEN 1000 AND 3000
ORDER BY precio_lista DESC;
```

## Estado inicial de la base

A diferencia del enunciado genérico de la consigna ("sin índice"), esta
base ya contaba con `idx_producto_categoria_activo ON producto(categoria_id)
WHERE activo = TRUE`, creado desde el `schema` original del TP1. Se
documenta esta diferencia porque afecta el punto de partida real de la
competencia.

## Medición 1 — plan inicial (con el índice preexistente)

```
Sort  (cost=858.59..872.49 rows=5559 width=38) (actual time=4.460..4.735 rows=5570.00 loops=1)
  Sort Key: precio_lista DESC
  ->  Index Scan using idx_producto_categoria_activo on producto (actual time=0.053..3.135 rows=5570.00 loops=1)
        Index Cond: (categoria_id = 1)
        Filter: ((precio_lista >= '1000') AND (precio_lista <= '3000'))
        Rows Removed by Filter: 6933
Execution Time: 4.966 ms
```

**Diagnóstico:** el índice existente solo indexa `categoria_id`; el
rango de precio se aplica como `Filter` posterior al escaneo, descartando
6.933 filas que no correspondían al rango pedido — trabajo desperdiciado.

## Propuesta de OpenCode

```sql
CREATE INDEX idx_producto_categoria_precio
  ON producto(categoria_id, precio_lista)
  WHERE activo = TRUE;
```

Justificación dada: incluir `precio_lista` como segunda columna del
índice (después de la igualdad por `categoria_id`) permite que el rango
`BETWEEN` se resuelva dentro del propio B-tree, eliminando el
`Rows Removed by Filter`. OpenCode predijo además que el `ORDER BY`
también se eliminaría del plan (al venir ya ordenado desde el índice).

## Validación de la propuesta (criterio de aceptación)

Al aplicar el índice y volver a medir, **el plan no cambió** — Postgres
siguió usando el índice viejo. Se investigó antes de descartar la
propuesta:

1. Se confirmó que el índice nuevo sí se había creado (`pg_indexes`).
2. Se corrió `ANALYZE producto` por si las estadísticas estaban
   desactualizadas — cambió levemente la estimación de filas, pero no
   la elección del índice.
3. Se probó, dentro de una transacción con `ROLLBACK` (sin tocar la base
   en firme), forzar el uso del índice nuevo eliminando temporalmente el
   viejo. Resultado: Postgres eligió `idx_producto_categoria_precio` vía
   `Bitmap Index Scan`, con `Rows Removed by Filter` eliminado y
   `Execution Time: 2.737 ms` — mejora real confirmada empíricamente
   antes de aplicar el cambio en firme.

**La predicción de OpenCode fue parcialmente correcta:** acertó en que
desaparecería el `Rows Removed by Filter`, pero se equivocó en que
también desaparecería el `Sort` — el plan final usa `Bitmap Heap Scan`
(no `Index Scan` directo), que no preserva el orden del índice, así que
el `Sort` sigue siendo necesario. Se documenta este matiz en vez de
aceptar la predicción completa sin contrastarla.

## Decisión final: eliminar el índice viejo

Con el índice nuevo confirmado como mejor en la práctica, y dado que
`idx_producto_categoria_precio` cubre el mismo caso de uso que
`idx_producto_categoria_activo` (filtro por categoría + activo) más el
rango de precio, se eliminó el índice viejo para evitar ambigüedad en
el optimizador:

```sql
DROP INDEX idx_producto_categoria_activo;
```

## Medición final — plan después

```
Sort  (cost=1157.69..1171.25 rows=5423 width=38) (actual time=2.322..2.494 rows=5570.00 loops=1)
  Sort Key: precio_lista DESC
  ->  Bitmap Heap Scan on producto (actual time=0.211..1.053 rows=5570.00 loops=1)
        Recheck Cond: ((categoria_id = 1) AND (precio_lista >= 1000) AND (precio_lista <= 3000) AND activo)
        Heap Blocks: exact=143
        ->  Bitmap Index Scan on idx_producto_categoria_precio (actual time=0.189..0.189 rows=5570.00 loops=1)
              Index Cond: ((categoria_id = 1) AND (precio_lista >= 1000) AND (precio_lista <= 3000))
Execution Time: 2.694 ms
```

## Registro de la competencia

| Equipo | Estrategia aplicada | Tiempo antes (ms) | Tiempo después (ms) | Mejora (x) |
|---|---|---|---|---|
| Este grupo | Índice compuesto `(categoria_id, precio_lista) WHERE activo = TRUE`, reemplazando el índice preexistente que solo cubría `categoria_id` | 4,966 | 2,694 | ~1,84× |
