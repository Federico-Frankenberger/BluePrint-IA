# Criterios de aceptación consolidados

## HU-01

```gherkin
Given un vendedor autenticado
When completa los datos obligatorios del pedido y lo confirma
Then el sistema registra el pedido y lo asigna al vendedor actual
```

## HU-02

```gherkin
Given un pedido propio no aprobado
When el vendedor edita sus datos
Then el sistema guarda los cambios
```

## HU-03

```gherkin
Given un pedido que pertenece a otro vendedor
When un vendedor intenta modificarlo
Then el sistema rechaza la operación
```

## HU-04

```gherkin
Given un pedido con estado aprobado
When el vendedor intenta modificarlo
Then el sistema rechaza la operación
```

## HU-05

```gherkin
Given un pedido en estado pendiente
When el administrador lo aprueba
Then el sistema marca el pedido como aprobado y lo bloquea para edición
```

## HU-06

```gherkin
Given administración autenticada
When accede al listado de pedidos
Then el sistema muestra todos los pedidos con su estado actual
```

