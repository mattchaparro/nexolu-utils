# Nexolú — resumen de la empresa y el producto

> **Este documento es apto para exportar a Drive / alimentar NotebookLLM
> para armar presentaciones.** No contiene IPs, credenciales ni nombres de
> clientes — solo arquitectura y producto a nivel conceptual. Para datos
> operativos reales (IPs, dominios, deploy), ver
> [`../infra/topology.md`](../infra/topology.md) (uso interno, no exportar).

## Qué es Nexolú

Nexolú es una compañía de software colombiana que desarrolla **Nexolú
POS**, un sistema de punto de venta SaaS para negocios colombianos —
tiendas, restaurantes y cafés, salones de belleza, y combinaciones de esas
verticales en un mismo negocio. Es **multi-tenant** (cada negocio es la
entidad raíz del sistema) y **multi-vertical**: un mismo negocio puede
tener venta de productos, cuentas abiertas/mesas, y servicios con agenda,
todo activado de forma independiente según lo que contrató.

## De dónde viene el producto

El producto original — todavía en producción, sirviendo negocios reales —
es un monolito Laravel + Inertia + Vue: un solo repositorio, backend y
frontend acoplados, sin una API real detrás. Nexolú está en medio de una
migración **en vivo**, módulo por módulo, hacia una arquitectura
**API-first**: un backend que sirve JSON puro (pensado para múltiples
clientes — el SPA nuevo, apps móviles a futuro, otros servicios) y un
frontend nuevo completamente desacoplado.

Es una migración sin "big bang": el sistema viejo sigue operando negocios
reales mientras se construye el nuevo, compartiendo la misma base de datos
durante toda la transición, y el corte se hace negocio por negocio, no de
una vez.

## La estrategia de plataforma: servicios "Core" reutilizables

La decisión de arquitectura más importante de Nexolú no es solo reescribir
el POS — es extraer la funcionalidad que **cualquier** producto de software
para negocios necesita (no solo un POS) en servicios independientes,
reutilizables desde el día uno por productos futuros:

- **IA Core**: motor de asistente de inteligencia artificial — chat,
  generación de insights, y ejecución de acciones sobre el negocio con
  confirmación humana explícita antes de cualquier escritura.
- **Comms Core**: envío de WhatsApp y correo electrónico, con reporting de
  costos unificado.
- **Payments Core**: cobros de suscripción vía pasarela de pago
  colombiana (Wompi), con soporte multi-comercio desde el diseño.

Ninguno de estos tres servicios sabe nada de "punto de venta" — no tienen
lógica de negocio del POS, ni acceso a sus datos. Cada producto que los usa
(hoy el POS, a futuro un producto de agenda para salones de belleza, un
producto de venta de entradas para eventos) les expone su propio catálogo
de lo que necesita, y el servicio Core simplemente lo orquesta. Ver
[`core-platform.md`](core-platform.md) para el detalle de esta estrategia.

## Producto: qué resuelve Nexolú POS

Para un negocio colombiano típico, Nexolú POS cubre:

- **Punto de venta**: venta directa, cuentas abiertas (mesas/comandas),
  comandera de cocina en tiempo real.
- **Inventario**: productos, ingredientes (para negocios de comida),
  variantes de producto, alertas de stock bajo.
- **Clientes y fiado**: gestión de clientes, cuentas por cobrar,
  recordatorios de cobro.
- **Servicios con agenda**: para salones de belleza y negocios de
  servicios — citas, órdenes de servicio, flujos configurables por etapa.
- **Compras y proveedores**: registro de compras, pagos a proveedores.
- **Finanzas**: gastos (incluyendo gastos fijos recurrentes), cierre de
  caja por turnos, contabilidad gerencial mensual/anual.
- **Reportes**: ventas por vendedor, historial, márgenes de inventario,
  resumen diario y vista general del negocio.
- **Asistente de IA**: un chat conversacional dentro del producto (y por
  WhatsApp) que responde preguntas sobre el negocio y puede ejecutar
  acciones simples (registrar un gasto, crear un producto) con
  confirmación explícita del usuario antes de escribir cualquier dato.
- **Multi-canal de notificaciones**: WhatsApp y correo para recibos,
  recordatorios, resúmenes diarios y alertas.

## Modelo de negocio

SaaS por suscripción, con planes diferenciados por el conjunto de
funcionalidades habilitadas (feature flags por negocio) — desde un plan
básico enfocado en venta simple hasta planes que habilitan contabilidad
gerencial, permisos granulares por empleado, y todos los módulos a la vez.

## Visión de plataforma

La apuesta de largo plazo no es "vender un POS" sino construir una
plataforma de software para negocios colombianos donde cada producto
nuevo (agenda para servicios, venta de entradas para eventos, y lo que
venga después) se construye más rápido porque IA, comunicaciones y pagos
ya están resueltos como infraestructura compartida — no se reinventan por
producto.
