# Parte 3 — Lectura crítica de un plan interpretado por IA (TP3, Semana 3)

**Herramienta usada:** ChatGPT (chat nuevo, sin contexto previo de este
proyecto ni de la consulta SQL original — solo se le pegó el texto del
plan de `EXPLAIN ANALYZE`).

**Aclaración sobre el requisito de "plan con índice ya aplicado":** en
la Parte 2 de este TP, ninguna de las 3 consultas medidas tuvo una
optimización exitosa mediante índice — las tres requieren agregar sobre
prácticamente el 100% de la tabla, por lo que ningún índice hubiera
ayudado (se documentó esa decisión explícitamente en `resultados_parte2.md`).
La única mejora real fue `work_mem` en la Consulta B. Se usa ese plan
(el "después" de la Consulta B) para este ejercicio, dejando esta
aclaración en lugar de forzar un caso de índice que no existió.

## Plan analizado

Plan "después" de la Consulta B (facturación por categoría y mes, con
`work_mem = 16MB`), Execution Time real: 238,66 ms.

## Tabla de hallazgos

| Afirmación de la IA | ¿Correcta? | Corrección / evidencia del plan real |
|---|---|---|
| El `actual time` del Hash Join incluye el tiempo de sus nodos hijos, no es tiempo adicional propio | Sí | Correcto — distinción que otra IA, en una ronda anterior de este mismo TP, no hizo bien |
| El `GroupAggregate` esperaba 200.006 grupos y obtuvo solo 10 — la mayor discrepancia de estimación del plan | Sí | Correcto, coincide exactamente con `rows=200006` (estimado) vs `rows=10` (real) en el nodo |
| Todos los `Batches: 1` son buena señal, sin derrame a disco | Sí | Correcto en los 3 hashes del plan |
| El `Incremental Sort` es barato porque solo ordena 10 filas, aprovechando el orden ya parcial por mes | Sí | Correcto, coincide con `Presorted Key` y `Peak Memory: 25kB` |
| El `Sort` (200k filas) cuesta aproximadamente 12 ms, calculado como la ventana propia del nodo (201.589 a 213.526) | **No** | El método usado (restar el propio rango interno del nodo) no da el costo exclusivo real. Restando correctamente el `actual time` final del Sort menos el de su hijo directo (`170.506`, el Hash Join que le entrega los datos): `213.526 - 170.506 ≈ 43,0 ms` — **casi 4 veces más** que lo que reportó la IA |
| Agrupa los 3 `Hash Join` del plan en un solo bucket ("Hash/joins hasta ~170,5 ms") sin descomponerlos | Parcial / engañoso | Al descomponer cada join por separado (resta contra sus hijos), el join más caro resulta ser el de `detalle_pedido × pedido` (~56,3 ms), no evidenciado en absoluto por la agrupación que hizo la IA — que además pierde de vista cuál cruce puntual conviene revisar primero si se quisiera optimizar |

## Conclusión

La IA acertó en los puntos de interpretación semántica del plan (qué
hace cada nodo, por qué existe, si hay derrame a disco) y en identificar
la discrepancia de estimación real (`GroupAggregate`). Falló en la
cuantificación numérica del costo por nodo: usó una heurística
inconsistente que subestima al `Sort` en casi un 75% y oculta cuál de
los tres `Hash Join` es realmente el más costoso — precisamente la
información que se necesitaría para decidir dónde enfocar un esfuerzo
de optimización futuro. Esto refuerza el criterio del TP: la explicación
de una IA sobre un plan se contrasta con el cálculo real, no se acepta
tal cual.
