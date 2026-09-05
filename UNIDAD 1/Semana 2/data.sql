-- =====================================================================
-- Food Store — data.sql
-- Seed de datos inicial para el proyecto integrador (Base de Datos II)
-- Se ejecuta DESPUÉS de "schema" (UNIDAD 1/Semana 2/schema).
--
-- Nota: este archivo no existía en las entregas de TP1 ni TP2 (ninguno
-- de los dos lo exigía como entregable). Se crea ahora porque el TP3
-- (Semana 3) lo requiere como prerrequisito explícito.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1) CATEGORIAS
-- ---------------------------------------------------------------------
INSERT INTO categoria (nombre, activo) VALUES
    ('Pizzas',    TRUE),
    ('Empanadas', TRUE),
    ('Bebidas',   TRUE),
    ('Postres',   TRUE);

-- ---------------------------------------------------------------------
-- 2) PRODUCTOS (repartidos entre las 4 categorías)
-- ---------------------------------------------------------------------
INSERT INTO producto (nombre, precio_lista, stock, activo, categoria_id) VALUES
    ('Muzzarella',       1000.00, 25, TRUE, (SELECT id FROM categoria WHERE nombre = 'Pizzas')),
    ('Napolitana',       1500.00, 18, TRUE, (SELECT id FROM categoria WHERE nombre = 'Pizzas')),
    ('Fugazzeta',        1450.00, 12, TRUE, (SELECT id FROM categoria WHERE nombre = 'Pizzas')),
    ('Carne',             350.00, 40, TRUE, (SELECT id FROM categoria WHERE nombre = 'Empanadas')),
    ('Jamón y queso',     350.00, 35, TRUE, (SELECT id FROM categoria WHERE nombre = 'Empanadas')),
    ('Verdura',           320.00, 30, TRUE, (SELECT id FROM categoria WHERE nombre = 'Empanadas')),
    ('Coca 1.5L',         800.00, 50, TRUE, (SELECT id FROM categoria WHERE nombre = 'Bebidas')),
    ('Agua mineral',      400.00, 60, TRUE, (SELECT id FROM categoria WHERE nombre = 'Bebidas')),
    ('Flan casero',       600.00, 15, TRUE, (SELECT id FROM categoria WHERE nombre = 'Postres')),
    ('Helado 1kg',       1200.00, 10, TRUE, (SELECT id FROM categoria WHERE nombre = 'Postres'));

-- ---------------------------------------------------------------------
-- 3) USUARIOS
-- ---------------------------------------------------------------------
INSERT INTO usuario (nombre, email, rol, activo) VALUES
    ('Admin Sistema', 'admin@foodstore.com', 'ADMIN',   TRUE),
    ('Ana Gómez',      'ana.gomez@mail.com', 'CLIENTE', TRUE),
    ('Luis Paz',        'luis.paz@mail.com', 'CLIENTE', TRUE),
    ('Marta Ruiz',     'marta.ruiz@mail.com','CLIENTE', TRUE),
    ('Juan Torres',   'juan.torres@mail.com','CLIENTE', TRUE);

-- ---------------------------------------------------------------------
-- 4) PEDIDOS + DETALLES DE EJEMPLO
--    (el total de cada pedido se calcula manualmente para respetar el
--    CHECK chk_pedido_total y quedar coherente con la suma de detalles)
-- ---------------------------------------------------------------------

-- Pedido 1: Ana Gómez — 2 Muzzarella + 1 Coca 1.5L
INSERT INTO pedido (usuario_id, forma_pago, estado, total)
VALUES ((SELECT id FROM usuario WHERE email = 'ana.gomez@mail.com'),
        'EFECTIVO', 'ENTREGADO', 2800.00);

INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
SELECT
    (SELECT id FROM pedido ORDER BY id DESC LIMIT 1),
    (SELECT id FROM producto WHERE nombre = 'Muzzarella'), 2, 1000.00, 2000.00
UNION ALL
SELECT
    (SELECT id FROM pedido ORDER BY id DESC LIMIT 1),
    (SELECT id FROM producto WHERE nombre = 'Coca 1.5L'), 1, 800.00, 800.00;

-- Pedido 2: Luis Paz — 1 Napolitana
INSERT INTO pedido (usuario_id, forma_pago, estado, total)
VALUES ((SELECT id FROM usuario WHERE email = 'luis.paz@mail.com'),
        'TARJETA', 'EN_PREPARACION', 1500.00);

INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
SELECT
    (SELECT id FROM pedido ORDER BY id DESC LIMIT 1),
    (SELECT id FROM producto WHERE nombre = 'Napolitana'), 1, 1500.00, 1500.00;

-- Pedido 3: Marta Ruiz — 4 Agua mineral + 2 Flan casero
INSERT INTO pedido (usuario_id, forma_pago, estado, total)
VALUES ((SELECT id FROM usuario WHERE email = 'marta.ruiz@mail.com'),
        'EFECTIVO', 'PENDIENTE', 2800.00);

INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
SELECT
    (SELECT id FROM pedido ORDER BY id DESC LIMIT 1),
    (SELECT id FROM producto WHERE nombre = 'Agua mineral'), 4, 400.00, 1600.00
UNION ALL
SELECT
    (SELECT id FROM pedido ORDER BY id DESC LIMIT 1),
    (SELECT id FROM producto WHERE nombre = 'Flan casero'), 2, 600.00, 1200.00;

-- Pedido 4: Juan Torres — 3 Empanadas de carne, cancelado
INSERT INTO pedido (usuario_id, forma_pago, estado, total)
VALUES ((SELECT id FROM usuario WHERE email = 'juan.torres@mail.com'),
        'TRANSFERENCIA', 'CANCELADO', 1050.00);

INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
SELECT
    (SELECT id FROM pedido ORDER BY id DESC LIMIT 1),
    (SELECT id FROM producto WHERE nombre = 'Carne'), 3, 350.00, 1050.00;

COMMIT;

-- =====================================================================
-- VERIFICACIÓN (correr aparte, no forma parte de la carga)
-- =====================================================================
-- SELECT 'categoria' t, count(*) FROM categoria
-- UNION ALL SELECT 'producto', count(*) FROM producto
-- UNION ALL SELECT 'usuario', count(*) FROM usuario
-- UNION ALL SELECT 'pedido', count(*) FROM pedido
-- UNION ALL SELECT 'detalle_pedido', count(*) FROM detalle_pedido;
-- Esperado: 4 / 10 / 5 / 4 / 6
