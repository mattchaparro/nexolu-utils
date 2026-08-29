# Documentación de Nexolú — índice

Punto de entrada a la documentación técnica completa del ecosistema. Si
sos nuevo en el equipo, empezá por [`onboarding.md`](onboarding.md), no
por acá directamente.

## Para desarrolladores (uso interno)

- **[onboarding.md](onboarding.md)** — checklist para gente nueva: accesos,
  orden de lectura, setup local.
- **[data-model.md](data-model.md)** — esquema MySQL compartido con el
  legacy, multi-tenant (`business_id`), feature flags.
- **[frontends.md](frontends.md)** — `nexolu-pos-front` y
  `nexolu-admin-front`: stack, auth, estructura, estado.

### `apis/` — un doc por servicio

- [`pos-api.md`](apis/pos-api.md) — backend Laravel del POS, inventario de
  rutas por módulo.
- [`ia-core.md`](apis/ia-core.md) — motor de IA compartido.
- [`comms-api.md`](apis/comms-api.md) — envío de WhatsApp/email.
- [`payments-core.md`](apis/payments-core.md) — pasarela de pagos
  multi-merchant (Wompi).
- [`admin-bff.md`](apis/admin-bff.md) — panel SuperAdmin (BFF + SPA).

### `integrations/` — cómo se conectan los servicios entre sí

- [`ia-core-tools.md`](integrations/ia-core-tools.md) — contrato
  chat/tools/drafts entre el POS e IA Core.
- [`whatsapp-comms.md`](integrations/whatsapp-comms.md) — estado real del
  envío de WhatsApp y el corte pendiente a Comms Core.
- [`payments-wompi.md`](integrations/payments-wompi.md) — flujo completo
  de checkout de suscripción y el esquema HMAC de webhooks.

### `infra/` — **uso interno, contiene IPs y datos operativos reales**

- [`topology.md`](infra/topology.md) — droplets, IPs, VPC, dominios,
  verificado en vivo contra DigitalOcean.
- [`deploy.md`](infra/deploy.md) — `deploy-menu.sh`, el panel admin, qué
  no pasa por ninguno de los dos, diferencias por ambiente.

## Para presentaciones / material externo

### `company/` — **apto para exportar a Drive, NotebookLLM, presentaciones**

Sin IPs, sin credenciales, sin nombres de negocios clientes — solo
arquitectura y producto a nivel conceptual.

- [`overview.md`](company/overview.md) — qué es Nexolú, el producto, el
  modelo de negocio, la visión de plataforma.
- [`core-platform.md`](company/core-platform.md) — la estrategia de los
  tres servicios "Core" (IA/Comms/Payments) como infraestructura
  compartida entre productos.

## Cómo mantener esto al día

Esta documentación se escribió leyendo el código real de cada repo (no
solo READMEs) el 2026-08-28. Los repos siguen cambiando — si encontrás algo
desactualizado acá, es más valioso corregir el doc que ignorarlo. Reglas
simples:

- Un endpoint nuevo, un módulo nuevo, una integración nueva → actualizar el
  doc correspondiente en el mismo PR (o uno de seguimiento inmediato), no
  "después".
- Datos operativos reales (IPs, dominios, droplets) solo van en
  [`infra/`](infra/) — nunca en `company/`.
- Si agregás un repo nuevo al ecosistema, agregarlo también a la tabla del
  [README raíz](../README.md#mapa-de-repos).
