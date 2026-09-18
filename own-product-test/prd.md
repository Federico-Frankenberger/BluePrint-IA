# PRD — Kiosco Stock App

**Modo:** `own_product` (producto propio, sin cliente externo)

## Visión y objetivos

Una plataforma para que los kiosqueros repongan stock más rápido: el sistema alerta automáticamente cuándo un producto cae debajo de un mínimo configurado y facilita el pedido al proveedor, en vez de depender del control manual de góndola que se usa hoy.

- Reducir el tiempo que le toma a un kiosquero detectar que un producto necesita reposición.
- Simplificar el paso de pedir mercadería al proveedor una vez detectado el faltante.

## Personas

- **Kiosquero** _(fuente: stakeholder: Kiosquero)_
- **Proveedor** _(fuente: stakeholder: Proveedor)_

## In-Scope

- Reponer stock _(fuente: proceso: Reponer stock)_
- Pedir mercadería al proveedor _(fuente: proceso: Pedir mercadería al proveedor)_
- Alertar cuando el stock de un producto cae debajo de un mínimo configurado _(fuente: RN-03)_

## Out-of-Scope

- Múltiples sucursales por kiosco — el fundador indicó que queda para una fase futura (RN-04).

## Criterios de éxito

- El kiosquero recibe una alerta antes de quedarse sin stock de un producto.
- El tiempo para detectar y pedir un faltante es menor que con el proceso manual actual (RN-02).

## Open questions

- **OQ-01** _(ref: RN-01)_: ¿Qué evidencia tenés de que los kiosqueros efectivamente pierden ventas por falta de stock? Sigue sin validar — no entra como hecho confirmado hasta que haya evidencia real.
