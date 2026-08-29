# `nexolu-comms-api` — API reference

Servicio FastAPI que centraliza envío de WhatsApp y correo para todo el
ecosistema Nexolú. Repo:
[`nexolu-comms-api`](https://github.com/mattchaparro/nexolu-comms-api).
**Estado real: desplegado en producción, pero sin tráfico de negocio hoy**
— ver [`../integrations/whatsapp-comms.md`](../integrations/whatsapp-comms.md)
para el detalle de por qué y qué falta para el corte.

## Arquitectura

```
nexolu_comms_api/
├── api/
│   ├── webhooks.py       # GET/POST /webhooks/whatsapp/{app_id}
│   └── v1/
│       ├── notifications.py   # POST /v1/notifications/send
│       ├── whatsapp.py         # POST /v1/whatsapp/read-receipt
│       ├── usage.py             # GET /v1/usage/*, /v1/platform/*
│       ├── admin_apps.py         # /v1/admin/apps
│       └── admin_providers.py     # /v1/admin/apps/{id}/providers/*
└── core/
    ├── auth/       # AppIdentity, fallback a NEXOLU_APPS_JSON legado
    ├── channels/    # ChannelSender: whatsapp.py, email.py
    ├── db/           # CommsApp, ProviderCredential, Notification
    ├── security/      # hash SHA-256, cifrado Fernet
    └── webhooks/        # firma/reenvío HMAC
```

Sin tablas de negocio: solo `notifications` (auditoría + costos) y
`comms_apps`/`provider_credentials` (identidad/credenciales).

## Endpoints

| Método | Path | Auth | Qué hace |
|---|---|---|---|
| GET | `/health` | — | Liveness |
| GET | `/v1/channels` | — | Lista canales disponibles (`email`, `whatsapp`) |
| POST | `/v1/notifications/send` | App | Envío multi-canal en una llamada; una fila `Notification` por canal |
| POST | `/v1/whatsapp/read-receipt` | App | Marca leído + "escribiendo..." |
| GET | `/v1/usage/summary`, `/v1/usage/daily` | App | Gasto propio |
| GET | `/v1/platform/usage`, `/v1/platform/notifications` | Plataforma | Gasto/logs de TODAS las apps |
| GET | `/webhooks/whatsapp/{app_id}` | verify_token | Handshake de suscripción de Meta |
| POST | `/webhooks/whatsapp/{app_id}` | `X-Hub-Signature-256` (opcional) | Recibe evento de Meta, reenvía al `callback_url` de la app |
| GET/POST/PATCH | `/v1/admin/apps*` | Plataforma | CRUD de apps cliente + rotación de key |
| POST/GET | `/v1/admin/apps/{id}/providers/meta-whatsapp`, `/brevo` (+ `/secrets`) | Plataforma | Credenciales de proveedor por app |

## Autenticación

Mismo patrón que `nexolu-ia-core`: `get_current_app` (Bearer, hash SHA-256
contra `comms_apps.api_key_hash`, con fallback legado a `NEXOLU_APPS_JSON`
mientras no corra el backfill en ese ambiente) + `require_platform_access`
(`NEXOLU_PLATFORM_API_KEY`, protege `/v1/platform/*` y todo
`/v1/admin/apps/*`). API key con prefijo `ncm_`.

## Proveedores

| Canal | Proveedor | Credenciales por app |
|---|---|---|
| WhatsApp | Meta Cloud API (`POST /{phone_number_id}/messages`) | `phone_number_id`, `access_token`, `waba_id`, + 3 secretos de webhook |
| Email | **Brevo** (no SES/SMTP/Resend) | `from_email`/`from_name`, `brevo_api_key` opcional (si no, cae a la key de plataforma) |

Cada app tiene su **propio** número/WABA — no se comparte uno solo entre
todo el ecosistema.

## Webhooks entrantes (Meta → comms-api)

Uno **por app** (no por negocio, Meta registra a nivel App/WABA). Handshake
por `hub.verify_token`; evento entrante verificado con `X-Hub-Signature-256`
(HMAC-SHA256 con `meta_app_secret`, **opcional** — si no está configurado se
salta con warning, no bloquea). Responde `200` inmediato y reenvía el
payload crudo **en background** al `callback_url` de la app, firmado con el
mismo esquema HMAC saliente que usa `nexolu-payments-core`
(`X-Nexolu-Signature`/`X-Nexolu-Timestamp`). **Sin cola ni reintento**: si
el `callback_url` no responde, el evento se pierde (queda logueado, no
persistido).

## Reporting de costos

`Notification.cost_micros`: WhatsApp estimado por categoría de plantilla
(marketing/utility/authentication/service, tarifas configurables); Brevo
siempre `None` (no lo informa por envío).

## Docs internos

Sin carpeta `docs/` — todo vive en el `README.md` de la raíz (arquitectura,
tabla de endpoints, limitaciones conocidas: sin idempotencia en
`/notifications/send`, sin gestión de plantillas, webhooks sin reintento).
