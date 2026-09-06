# Declaración de Uso de IA (DUIA) — TP3, Semana 3

Documento vivo: se agrega una fila más cuando se resuelva la Parte 5
(pendiente de que la cátedra entregue la consulta fija).

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| OpenCode (Gemini 2.5 Flash como backend) | Generar y corregir el script de poblado masivo (Parte 1): 50.000 productos, 20.000 usuarios, 200.000 pedidos con detalles | "Necesito un script SQL para PostgreSQL que pueble masivamente food_store_tp3_copia... [spec completa con reglas de negocio, respeta CHECK/UNIQUE existentes]" | Se aceptó tras dos correcciones. (1) Primer intento: bug real detectado en ejecución — `tmp_productos` no proyectaba `precio_lista`, corregido en un solo campo tras diagnosticar la causa exacta. (2) Segundo bug, más grave, detectado recién al medir la Parte 2: una subconsulta `LATERAL` no correlacionada con `gs.n` causaba que `random()` se evaluara una sola vez para toda la consulta — 199.994 de 200.000 filas de `detalle_pedido` colapsaron al mismo producto. Se corrigió con un script nuevo (`fix_detalle_pedido.sql`) que repobló solo los pedidos afectados, verificado con conteos de distintos antes y después |
| OpenCode | Proponer optimizaciones para 3 consultas reales (Parte 2): facturación por categoría/mes, ranking de usuarios por gasto, top 5 productos más vendidos | Se pegaron los 3 planes reales de `EXPLAIN ANALYZE` y se pidió una propuesta justificada en el propio plan para cada uno, o explicar por qué no había nada que optimizar | Mixto, documentado por consulta: en la Consulta B, OpenCode identificó el `Sort Method: external merge Disk` como el único nodo que toca disco y propuso subir `work_mem`; se aplicó (`work_mem = 16MB`) con mejora real del ~24% (sort pasó a memoria). En las Consultas A y C, OpenCode concluyó explícitamente que no había optimización que valiera la pena (ambas ya corren en memoria sin derrame, y ningún índice ahorraría trabajo real dado que se agrega sobre ~100% de la tabla); se validó esa conclusión contra el plan real antes de aceptarla, sin aplicar ningún cambio |
| ChatGPT | Explicar en lenguaje natural, nodo por nodo, el plan ya optimizado de la Consulta B, sin más contexto que el texto del plan (Parte 3) | "Explicame este plan de EXPLAIN ANALYZE de PostgreSQL, nodo por nodo" + el plan pegado tal cual | Se aceptó la interpretación semántica (correcta identificación de la discrepancia de estimación del GroupAggregate, distinción correcta entre tiempo acumulado y propio en el Hash Join). Se detectó y corrigió un error real de cálculo: subestimó el costo exclusivo del nodo Sort en ~75% (12ms reportado vs ~43ms real, calculado restando correctamente contra el hijo) y agrupó los 3 Hash Join sin descomponerlos, ocultando cuál era realmente el más costoso |
| OpenCode | Generar SQL a partir de dos specs precisas (Parte 4): consulta de resumen (productos activos por categoría) y consulta con subconsulta (productos sobre el precio promedio) | Dos specs con tablas, filtro de vigencia (`activo = TRUE`), columnas de salida, orden y criterio de corte explícitos | Se aceptaron ambas consultas sin modificaciones — correctas en su primera versión. Se verificó equivalencia contra una segunda versión con estructura distinta usando `EXCEPT` en ambas direcciones: 0 filas de diferencia en los dos casos |

## Nota sobre la elección de backend para OpenCode

Se probaron GitHub Copilot (bug de reconexión en bucle al listar
modelos, no se pudo usar) y varios modelos de Google Gemini (los planes
"Pro" no disponibles en el tier gratuito para cuentas nuevas; el modelo
Flash 2.5 quedó descontinuado durante la sesión de trabajo). Finalmente
se usó el modelo por defecto de OpenCode (OpenCode Zen / "Big Pickle"),
gratuito y sin necesidad de configurar un proveedor externo.
