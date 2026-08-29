# `nexolu-payments-core` — API reference

Pasarela de pagos genérica y **multi-merchant**, no un servicio de
suscripciones — no hay entidad `Subscription`/`Plan` en este repo, esa
lógica vive del lado del consumidor (el POS). Repo:
[`nexolu-payments-core`](https://github.com/mattchaparro/nexolu-payments-core).
Wompi es el único `PaymentProvider` implementado hoy, detrás de una interfaz
extensible. Flujo completo de checkout en
[`../integrations/payments-wompi.md`](../integrations/payments-wompi.md).

## Arquitectura

```
nexolu_payments_core/
├── api/v1/
│   ├── payments.py    # /v1/payments/* (público) + /v1/admin/* (provisioning)
│   └── webhooks.py     # POST /v1/webhooks/wompi (entrante)
├── core/
│   ├── memory/          # Merchant, Integration, ProviderCredential, FeeSchedule, Transaction, WebhookDelivery
│   ├── payments/          # service.py (orquestación), fees.py
│   ├── security/           # hash SHA-256, cifrado Fernet
│   └── webhooks/             # signing.py (HMAC saliente), dispatcher.py (reintentos)
└── providers/
    └── wompi.py           # Widget Checkout (legado) + API directa
```

## Conceptos: Merchant vs Integration

- **Merchant**: empresa dueña de la cuenta Wompi (ej. Nexolú como
  agregador, o un comercio con su propia cuenta a futuro).
- **Integration**: app cliente de un merchant (ej. `nexolu-pos-api`) — cada
  una con su propia `api_key`/`webhook_secret`, y un `environment`
  (`sandbox`/`production`).
- **ProviderCredential**: credenciales Wompi, únicas por `(merchant_id,
  provider_slug, environment)` — cuelgan del merchant, no de la
  integration.

## Endpoints

### Pagos (público, `Authorization: Bearer <integration-api-key>`)

| Método | Path | Qué hace |
|---|---|---|
| POST | `/v1/payments/intents` | Crea intent; el Core genera la `reference` |
| POST | `/v1/payments/intents/{reference}/charge` | Cobra vía API directa (CARD/NEQUI/PSE/BANCOLOMBIA_TRANSFER/PAYMENT_SOURCE) |
| GET | `/v1/payments/payment-methods` | Métodos habilitados para esa integration |
| GET | `/v1/payments/pse/financial-institutions` | Bancos PSE (proxy en vivo a Wompi) |
| POST | `/v1/payments/payment-sources` | Tokeniza tarjeta/Nequi para reuso |
| PUT | `/v1/payments/payment-sources/{id}/void` | Cancela una fuente tokenizada |
| GET | `/v1/payments/transactions/{reference}` | Estado (para polling mientras se espera el webhook) |

### Webhook entrante de Wompi

| Método | Path | Qué hace |
|---|---|---|
| POST | `/v1/webhooks/wompi` | Único endpoint para todos los merchants/ambientes; resuelve por `reference` |

### Provisioning/admin (`X-Payments-Provisioning-Key`)

| Recurso | Endpoints |
|---|---|
| **Merchants** | `GET/POST /v1/admin/merchants`, `GET /{id}` |
| **Integrations** | `GET/POST /merchants/{id}/integrations`, `GET/PATCH/DELETE /{id}`, `POST /{id}/regenerate-secret`, `GET /{id}/secrets` |
| **Credenciales Wompi** | `POST/GET /merchants/{id}/providers/wompi` (+ `/secrets`) |
| **Transacciones** | `GET /v1/admin/transactions` (cross-merchant, filtros), `POST /{id}/redeliver-webhook` (reintento manual) |

## Autenticación

| Quién | Cómo |
|---|---|
| App consumidora (ej. POS) | `Authorization: Bearer <integration-api-key>`, hash SHA-256 contra `integrations.api_key_hash`, join filtrando `Integration.is_active` + `Merchant.is_active` |
| Provisioning (backend admin) | `X-Payments-Provisioning-Key` == `PROVISIONING_KEY` (secreto de servidor único, `secrets.compare_digest`) |
| Wompi → Core (webhook) | Checksum propio de Wompi con `events_secret` de la credencial (no el esquema HMAC de abajo) |

Prefijo de API key: `nxl_...`.

## Esquema HMAC de webhooks salientes (Core → app consumidora)

- Algoritmo: HMAC-SHA256 sobre `f"{timestamp}." + raw_body`.
- Secreto: `Integration.webhook_secret` (prefijo `whsec_`).
- Headers: `X-Nexolu-Signature`, `X-Nexolu-Timestamp`.
- **Sin ventana de tolerancia de timestamp implementada acá** — control de
  replay/expiración queda del lado del receptor si lo necesita.
- Entrega síncrona, 3 intentos (backoff `0/1/2s`). Si se agotan o no hay
  `webhook_url`, queda en `WebhookDelivery` para reenvío manual — no hay
  cola de reintentos automática.
- Eventos: `payment.approved`, `.declined`, `.error`, `.voided`, `.pending`.

## Integración con Wompi

- **Widget Checkout** (legado): firma de integridad local, sin red.
- **API directa**: `GET /merchants/:public_key` (tokens de aceptación
  legal, sin auth) → `POST /transactions` (`Authorization: Bearer
  <private_key>`) → `POST /payment_sources` (tokenización) → `GET
  /pse/financial_institutions`.
- **Sandbox vs producción**: el Core infiere el host de Wompi del prefijo
  de la credencial (`_test_` → sandbox), **no** del campo `environment` del
  Core — son dos mecanismos independientes, hay que mantenerlos coherentes
  a mano al provisionar.
- Verificación de firma del webhook de Wompi: checksum
  `sha256(valores + timestamp + events_secret)`, mismo algoritmo que usaba
  `WompiService` en el legacy Laravel.

## Modelo de datos

| Tabla | Campos clave |
|---|---|
| `Merchant` | `slug`, `name`, `is_active` |
| `Integration` | `merchant_id`, `slug`, `environment`, `api_key`(cifrada)+`api_key_hash`, `webhook_url`, `webhook_secret`(cifrada), `widget_enabled` |
| `ProviderCredential` | `(merchant_id, provider_slug, environment)` único; `public_key`, `private_key`/`integrity_secret`/`events_secret` (cifrados) |
| `FeeSchedule` | `percent_fee` (2.65 default), `fixed_fee_cop` (700), `iva_percent` (19.0) |
| `Transaction` | `reference` (única, generada por el Core), `status`, `fee_cop`/`net_amount_cop`, `payload` crudo |
| `WebhookDelivery` | Registro de cada intento de notificación saliente |

## Docs internos

| Archivo | Qué cubre |
|---|---|
| `docs/APP_INTEGRATION.md` | Contrato de integración para una app cliente nueva |
| `docs/MULTI_MERCHANT_ARCHITECTURE.md` | Por qué `ProviderCredential` cuelga del Merchant, ruteo por `reference` |
| `docs/PRODUCTION_SETUP.md` | Runbook sandbox→producción, checklist de llaves reales |
