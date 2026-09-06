# Parte 4 — Consultas resumen y subconsultas bajo especificación precisa (TP3)

**Herramienta usada:** OpenCode (mismo chat de trabajo del resto del TP —
la consigna no exige aislamiento de contexto para esta parte, a diferencia
de la Parte 3, así que se usa como motor primario tal como indica la
cátedra).

---

## Spec 1 — Consulta de resumen (agregación)

**Especificación dada:**
> Generá una consulta SQL sobre el esquema de Food Store que devuelva,
> para cada categoría activa (activo = TRUE), el nombre de la categoría
> y la cantidad de productos activos que tiene, incluyendo las
> categorías sin productos activos con cantidad 0. Ordená de mayor a
> menor cantidad, y en empate, por nombre ascendente. No uses SELECT *.

**SQL generado por OpenCode (aceptado sin modificaciones):**
```sql
SELECT
    c.nombre,
    COUNT(p.id) AS cantidad_productos
FROM categoria c
LEFT JOIN producto p ON p.categoria_id = c.id AND p.activo = TRUE
WHERE c.activo = TRUE
GROUP BY c.id, c.nombre
ORDER BY cantidad_productos DESC, c.nombre ASC;
```

**Versión alternativa (subconsulta correlacionada en vez de JOIN):**
```sql
SELECT
    c.nombre,
    (SELECT COUNT(*)
     FROM producto p
     WHERE p.categoria_id = c.id AND p.activo = TRUE) AS cantidad_productos
FROM categoria c
WHERE c.activo = TRUE
ORDER BY cantidad_productos DESC, c.nombre ASC;
```

**Verificación de equivalencia (EXCEPT en ambas direcciones):** 0 filas
de diferencia. Consultas equivalentes.

---

## Spec 2 — Consulta con subconsulta

**Especificación dada:**
> Generá una consulta SQL sobre el esquema de Food Store que devuelva
> id, nombre y precio_lista de los productos activos (activo = TRUE)
> cuyo precio_lista sea mayor al precio_lista promedio de todos los
> productos activos. Ordená de mayor a menor precio_lista. No uses
> SELECT *.

**SQL generado por OpenCode (aceptado sin modificaciones):**
```sql
SELECT id, nombre, precio_lista
FROM producto
WHERE activo = TRUE
  AND precio_lista > (SELECT AVG(precio_lista) FROM producto WHERE activo = TRUE)
ORDER BY precio_lista DESC;
```

**Versión alternativa (CTE + CROSS JOIN en vez de subconsulta escalar):**
```sql
WITH promedio AS (
    SELECT AVG(precio_lista) AS precio_promedio
    FROM producto
    WHERE activo = TRUE
)
SELECT
    p.id,
    p.nombre,
    p.precio_lista
FROM producto p
CROSS JOIN promedio pr
WHERE p.activo = TRUE
  AND p.precio_lista > pr.precio_promedio
ORDER BY p.precio_lista DESC;
```

**Verificación de equivalencia (EXCEPT en ambas direcciones):** 0 filas
de diferencia. Consultas equivalentes.

---

## Conclusión

Ambas specs, al ser precisas (tablas involucradas, filtro de vigencia,
columnas de salida exactas, criterio de orden explícito), produjeron SQL
correcto de OpenCode en el primer intento, sin necesidad de corrección.
Las dos verificaciones con `EXCEPT` confirman formalmente que las
alternativas estructuralmente distintas (JOIN vs. subconsulta
correlacionada; subconsulta escalar vs. CTE) devuelven exactamente el
mismo resultado.
