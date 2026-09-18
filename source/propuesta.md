# Propuesta — Sistema de gestión de pedidos para vendedores

## Objetivo

Desarrollar una plataforma que permita a los vendedores registrar pedidos desde dispositivos móviles y a administración gestionarlos y aprobarlos desde un panel centralizado.

## Alcance

| Item | Fuente (PRD) | Historia(s) de usuario |
|---|---|---|
| Crear pedido | proceso: Crear pedido | HU-01 ⚠️ (tiene un ítem abierto, ver "A definir en el arranque") |
| Modificar pedido | proceso: Modificar pedido | HU-02 |
| Un vendedor solo puede modificar sus propios pedidos | RN-01 | HU-03 |
| Un pedido aprobado no puede modificarse | RN-02 | HU-04 |
| Aprobar pedido | proceso: Aprobar pedido | HU-05 |
| Consultar pedidos | proceso: Consultar pedidos | HU-06 |

## Fuera de alcance

| Item | Motivo |
|---|---|
| Integración con sistemas ERP | RN-03: el cliente pidió explícitamente no integrar con ningún ERP por el momento. |
| Facturación electrónica | RN-04: el cliente indicó que queda para una fase futura, fuera de este proyecto. |

## A definir en el arranque

- ¿Qué debe suceder si el producto solicitado no tiene stock? (HU-01, sin resolver)
- Atributos de Pedido/Producto/Cliente todavía no confirmados (bloquea el diagrama de clases).
- Cardinalidades entre Pedido/Producto/Cliente todavía no confirmadas (bloquea el ERD).

## Metodología

- Desarrollo iterativo
- Sprints de 2 semanas
- Entregas incrementales

## Estimación

- Duración estimada: 5–8 semanas
- Equipo: 1-2 desarrolladores + QA parcial
- Nivel de incertidumbre: Medio

## Inversión

- Desarrollo: $X
- Infraestructura: $X
- Mantenimiento: $X
