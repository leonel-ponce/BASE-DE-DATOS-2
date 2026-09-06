-- Carga masiva de prueba — food_store_tp3_copia (PostgreSQL)
-- +50.000 productos | +20.000 usuarios | +200.000 pedidos con detalle.
-- No modifica los registros del seed. Ejecutar en una COPIA de la base.
BEGIN;

CREATE TEMP TABLE tmp_productos_prev AS SELECT id FROM producto;
CREATE TEMP TABLE tmp_pedidos_prev   AS SELECT id FROM pedido;

-- ============================================================
-- 1) PRODUCTOS: 50.000 nuevos (12.500 por categoría)
-- ============================================================
INSERT INTO producto (nombre, precio_lista, stock, activo, categoria_id)
SELECT
    'Producto Test #' || gs.n,
    round((500 + random() * 4500)::numeric, 2),
    floor(random() * 201)::int,
    TRUE,
    cat.id
FROM generate_series(1, 50000) AS gs(n)
CROSS JOIN LATERAL (
    SELECT id
    FROM (
        SELECT id, row_number() OVER (ORDER BY id) AS rn
        FROM categoria
    ) ranked
    WHERE ranked.rn = ((gs.n - 1) % 4) + 1
) AS cat;

CREATE TEMP TABLE tmp_productos AS
SELECT id, precio_lista, row_number() OVER (ORDER BY id) AS rn
FROM producto
WHERE NOT EXISTS (SELECT 1 FROM tmp_productos_prev p WHERE p.id = producto.id);

DROP TABLE tmp_productos_prev;

-- ============================================================
-- 2) USUARIOS: 20.000 nuevos, email único, rol CLIENTE
-- ============================================================
INSERT INTO usuario (nombre, email, rol)
SELECT
    'Usuario Test #' || gs.n,
    'usuario.test.' || lpad(gs.n::text, 8, '0') || '@example.com',
    'CLIENTE'
FROM generate_series(1, 20000) AS gs(n)
ON CONFLICT (email) DO NOTHING;

CREATE TEMP TABLE tmp_usuarios AS
SELECT id, row_number() OVER (ORDER BY id) AS rn FROM usuario;

-- ============================================================
-- 3) PEDIDOS: 200.000 cabeceras (total provisorio 0.00)
-- ============================================================
INSERT INTO pedido (usuario_id, fecha_hora, forma_pago, estado, total)
SELECT
    u.id,
    now() - (random() * interval '180 days'),
    (ARRAY['EFECTIVO', 'TARJETA', 'TRANSFERENCIA']::forma_pago[])[1 + floor(random() * 3)::int],
    (ARRAY['PENDIENTE', 'EN_PREPARACION', 'ENTREGADO', 'CANCELADO']::estado_pedido[])[1 + floor(random() * 4)::int],
    0.00
FROM generate_series(1, 200000) AS gs(n)
JOIN tmp_usuarios u ON u.rn = ((gs.n - 1) % (SELECT max(rn) FROM tmp_usuarios)) + 1;

CREATE TEMP TABLE tmp_pedido_base AS
SELECT MIN(p.id) AS primer_id
FROM pedido p
WHERE NOT EXISTS (SELECT 1 FROM tmp_pedidos_prev t WHERE t.id = p.id);

DROP TABLE tmp_pedidos_prev;

-- ============================================================
-- 4) DETALLE_PEDIDO: 1–3 productos por pedido (sin repetir)
-- ============================================================
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
SELECT
    base.primer_id + gs.n - 1,
    pr.id,
    gd.cantidad,
    pr.precio_lista,
    gd.cantidad * pr.precio_lista
FROM generate_series(1, 200000) AS gs(n)
CROSS JOIN LATERAL (
    SELECT 1 + floor(random() * 3)::int AS n_items,
           floor(random() * 2147483647)::int AS semilla
) AS rnd
CROSS JOIN LATERAL generate_series(1, rnd.n_items) AS k(k)
CROSS JOIN LATERAL (
    SELECT 1 + floor(random() * 5)::int AS cantidad
) AS gd
JOIN tmp_productos pr ON pr.rn = ((rnd.semilla + k - 1) % (SELECT max(rn) FROM tmp_productos)) + 1
CROSS JOIN tmp_pedido_base base;

-- ============================================================
-- 5) TOTAL coherente con la suma de sus detalles
-- ============================================================
UPDATE pedido p
SET total = d.suma
FROM (
    SELECT pedido_id, SUM(subtotal) AS suma
    FROM detalle_pedido
    WHERE pedido_id >= (SELECT primer_id FROM tmp_pedido_base)
    GROUP BY pedido_id
) d
WHERE p.id = d.pedido_id;

DROP TABLE tmp_productos;
DROP TABLE tmp_usuarios;
DROP TABLE tmp_pedido_base;

COMMIT;