# Checkout de suscripción: POS ↔ Payments Core ↔ Wompi

Flujo completo, de punta a punta, de un cobro de suscripción del POS. La
lógica de "esto es una orden pendiente que se activa cuando el pago se
confirma" vive **en el POS** — `nexolu-payments-core` es agnóstico de qué
representa el pago (no tiene entidad `Subscription`).

## Flujo paso a paso

1. **POS crea la orden pendiente** en su propia BD, al iniciar el checkout.
2. **POS → Payments Core**: `POST /v1/payments/intents` (`Bearer
   <api_key de su Integration>`, `amount_cop`, `customer`, `metadata`,
   `flow="api"`). El Core resuelve la credencial Wompi activa del merchant
   para el `environment` de esa integration, genera `reference =
   pay_<uuid>` (el POS **nunca** genera su propia reference — bug real ya
   corregido, ver nota abajo), y responde `payment_init` con el
   `public_key` para que el frontend tokenice.
3. **Frontend tokeniza la tarjeta directo con Wompi**
   (`POST /tokens/cards`) — el número de tarjeta **nunca** toca Payments
   Core.
4. **POS → Payments Core**: `POST
   /v1/payments/intents/{reference}/charge` con el `payment_method`
   (token, o `PAYMENT_SOURCE` para cobro recurrente). El Core llama `POST
   /transactions` en Wompi. **La respuesta síncrona no es la fuente de
   verdad del estado final** — solo confirma que Wompi aceptó *intentar*
   el cobro.
5. **Wompi procesa async** y llama `POST /v1/webhooks/wompi` (URL única
   para todos los merchants/ambientes) con `transaction.updated` + la
   `reference` original.
6. **Payments Core procesa el webhook**: resuelve la `Transaction` por
   `reference` → la `Integration` → la credencial Wompi **del
   `environment` de esa integration** → verifica firma (checksum Wompi,
   `events_secret`) → si es idempotente (ya no `pending`) no reprocesa →
   actualiza `status`, calcula `fee_cop`/`net_amount_cop` si `approved`.
7. **Payments Core notifica al POS**: `dispatch_transaction_event` arma el
   payload agnóstico, lo firma HMAC-SHA256 (`Integration.webhook_secret`,
   headers `X-Nexolu-Signature`/`X-Nexolu-Timestamp`) y hace `POST` a
   `Integration.webhook_url` — hasta 3 intentos síncronos (backoff
   `0/1/2s`).
8. **POS recibe el webhook**, verifica el HMAC con su copia de
   `webhook_secret`, y **activa la suscripción** (o marca el pago
   fallido). Esta última pieza de lógica de negocio vive 100% en
   `nexolu-pos-api`.
9. **Fallback**: mientras espera el webhook, el POS puede hacer polling a
   `GET /v1/payments/transactions/{reference}`. Si el webhook nunca llegó
   (receptor caído, `webhook_url` mal configurada), un operador fuerza
   reenvío con `POST /v1/admin/transactions/{id}/redeliver-webhook` desde
   el panel admin.

## Esquema HMAC (para implementar la verificación del lado receptor)

```
mensaje = f"{timestamp}." .encode() + raw_body_bytes
firma   = hmac_sha256(mensaje, integration.webhook_secret).hexdigest()

Headers recibidos:
  X-Nexolu-Timestamp: <timestamp usado en la firma>
  X-Nexolu-Signature: <firma hex>
```

Sin ventana de tolerancia de timestamp implementada del lado de Payments
Core — si el receptor quiere protegerse de replay, tiene que implementar
ese chequeo él mismo. Mismo esquema exacto usa `nexolu-comms-api` para
reenviar webhooks de WhatsApp entrantes.

## Multi-ambiente: el bug ya corregido, para no repetirlo

`ProviderCredential` es única por `(merchant_id, provider_slug,
environment)`. El commit `ecaf955` corrigió que
`handle_provider_webhook` buscaba la credencial **sin pasar
`environment`** (defaulteaba silenciosamente a `"sandbox"`) — cualquier
merchant con solo credencial `production` configurada nunca la encontraba,
y la transacción quedaba en `pending` para siempre, sin error visible
(el router responde 200 a Wompi igual). **Al dar de alta un merchant
nuevo en producción, confirmar explícitamente que la credencial Wompi
quedó con `environment=production` y que el host de la llave (`_test_` vs
no) coincide** — son dos mecanismos independientes que hay que mantener
coherentes a mano.

## Referencia

- Detalle completo de endpoints/modelo: [`../apis/payments-core.md`](../apis/payments-core.md).
- Gestión de merchants/credenciales vía panel admin: [`../apis/admin-bff.md`](../apis/admin-bff.md#payments-vadmin-paymentsenv--proxy-a-nexolu-payments-core).
