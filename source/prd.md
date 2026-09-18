# PRD — Sistema de gestión de pedidos para vendedores

_Modo: `client`_

## Visión y objetivos

Plataforma que permite a los vendedores registrar pedidos desde el celular y a administración verlos, gestionarlos y aprobarlos desde un panel centralizado.

- Digitalizar la carga de pedidos por parte de los vendedores, eliminando el registro manual.
- Centralizar en administración la visibilidad y aprobación de todos los pedidos.

## User personas

| Persona | Fuente |
|---|---|
| PER-01 — Administrador | stakeholder: Administrador |
| PER-02 — Vendedor | stakeholder: Vendedor |
| PER-03 — Administración | stakeholder: Administración |

## In-Scope

| Item | Fuente |
|---|---|
| Un vendedor solo puede modificar sus propios pedidos | RN-01 |
| Un pedido aprobado no puede modificarse | RN-02 |
| Crear pedido | proceso: Crear pedido |
| Modificar pedido | proceso: Modificar pedido |
| Aprobar pedido | proceso: Aprobar pedido |
| Consultar pedidos | proceso: Consultar pedidos |

## Out-of-Scope

| Item | Motivo |
|---|---|
| Integración con sistemas ERP | RN-03: el cliente pidió explícitamente no integrar con ningún ERP por el momento. |
| Facturación electrónica | RN-04: el cliente indicó que queda para una fase futura, fuera de este proyecto. |

## Criterios de éxito

- Un vendedor puede cargar un pedido completo desde el celular sin intervención de administración.
- Administración puede ver y aprobar pedidos desde un panel centralizado.
- Ningún vendedor puede modificar pedidos ajenos ni pedidos ya aprobados (RN-01, RN-02).

## Open questions

- ¿Qué debe suceder si un vendedor carga un pedido de un producto que no tiene stock? (heredado de discovery-state.json, sin resolver)
