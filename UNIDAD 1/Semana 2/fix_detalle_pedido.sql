-- fix_detalle_pedido.sql — food_store_tp3_copia (PostgreSQL)
-- Repobla detalle_pedido para TODOS los pedidos con total = 0.00
-- (los 200.000 generados por la carga masiva) y recalcula su total.
-- Corrección del bug: semilla y cantidad ahora están correlacionadas
-- con el pedido (gs.n), por lo que random() se evalúa por fila.
-- No inserta en producto, usuario ni pedido; solo toca pedido.total.

BEGIN;

-- ============================================================
-- 1) Pedidos objetivo: total = 0.00 (sin asumir IDs contiguos)
-- ============================================================
CREATE TEMP TABLE tmp_pedidos_cero AS
SELECT p.id,
       row_number() OVER (ORDER BY p.id) AS rn
FROM pedido p
WHERE p.total = 0.00;

-- ============================================================
-- 2) Pool de productos: TODOS los existentes
-- ============================================================
CREATE TEMP TABLE tmp_productos AS
SELECT id, precio_lista, row_number() OVER (ORDER BY id) AS rn
FROM producto;

CREATE INDEX idx_tmp_productos_rn ON tmp_productos(rn);

-- ============================================================
-- 3) Limpie el detalle defectuoso de esos pedidos
-- ============================================================
DELETE FROM detalle_pedido
WHERE pedido_id IN (SELECT id FROM tmp_pedidos_cero);

-- ============================================================
-- 4) Repoblación: semilla y cantidad correlacionadas por pedido
-- ============================================================
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
SELECT
    tp.id,
    pr.id,
    gd.cantidad,
    pr.precio_lista,
    gd.cantidad * pr.precio_lista
FROM generate_series(1, (SELECT count(*) FROM tmp_pedidos_cero)) AS gs(n)
JOIN tmp_pedidos_cero tp ON tp.rn = gs.n
CROSS JOIN LATERAL (
    SELECT
        1 + floor(random() * 3)::int                          AS n_items,
        (gs.n + floor(random() * 2147483647)::bigint) % 2147483647 AS semilla
) AS rnd
CROSS JOIN LATERAL generate_series(1, rnd.n_items) AS k(k)
CROSS JOIN LATERAL (
    SELECT 1 + ((rnd.semilla + k) % 5)::int AS cantidad
) AS gd
JOIN tmp_productos pr ON pr.rn =
    ((rnd.semilla + k - 1) % (SELECT max(rn) FROM tmp_productos)) + 1;

-- ============================================================
-- 5) Recalcular el total de esos mismos pedidos
-- ============================================================
UPDATE pedido p
SET total = d.suma
FROM (
    SELECT dp.pedido_id, SUM(dp.subtotal) AS suma
    FROM detalle_pedido dp
    JOIN tmp_pedidos_cero tc ON tc.id = dp.pedido_id
    GROUP BY dp.pedido_id
) d
WHERE p.id = d.pedido_id;

-- ============================================================
-- 6) Limpieza
-- ============================================================
DROP TABLE tmp_pedidos_cero;
DROP TABLE tmp_productos;

COMMIT;