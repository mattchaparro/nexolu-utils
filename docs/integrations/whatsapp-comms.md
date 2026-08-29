# WhatsApp y email: estado actual, y el corte pendiente a `nexolu-comms-api`

Resume la abstracción de mensajería del POS, qué implementación está activa
hoy, y qué falta para migrar al servicio compartido.

## Estado real (verificado en código, no solo en docs)

**Hoy el POS manda WhatsApp directo a Meta.** `nexolu-comms-api` está
desplegado en producción y correctamente aprovisionado a nivel de infra
(dominio propio `comms.nexolu.co`, deploy automatizado), pero **cero
tráfico real de negocio pasa por él todavía**.

El switch vive en `nexolu-pos-api`:

```php
// config/services.php -> comms_core.driver, env MESSAGING_DRIVER
// AppServiceProvider.php
$this->app->bind(MessagingChannel::class, fn () => new LoggingMessagingChannel(
    config('services.comms_core.driver') === 'nexolu_comms'
        ? $this->app->make(NexoluCommsChannel::class)
        : $this->app->make(WhatsAppCloudClient::class)
));
```

`MESSAGING_DRIVER` default: **`whatsapp_direct`** (tanto en `.env.example`
como en `nexolu-infra/README.md`, con el comentario explícito "cambiar a
`nexolu_comms` cuando se decida el cutover").

## Las dos implementaciones, del lado del POS

Ambas implementan las mismas interfaces
(`App\Services\Messaging\Contracts\MessagingChannel` +
`MessagingCostReporter`), así que cambiar el driver es **una variable de
entorno + dos bindings**, sin tocar ningún consumidor (jobs, comandos):

| Driver | Clase | Qué hace |
|---|---|---|
| `whatsapp_direct` (activo hoy) | `WhatsAppCloudClient` | Llama directo a Graph API de Meta con `WHATSAPP_ACCESS_TOKEN`/`WHATSAPP_PHONE_NUMBER_ID` propios del POS |
| `nexolu_comms` (listo, sin activar) | `NexoluCommsChannel` | `POST {COMMS_CORE_BASE_URL}/v1/notifications/send` con `COMMS_CORE_API_KEY` |

`NexoluCommsCostReporter` (reporta gasto vía `GET
{COMMS_CORE_BASE_URL}/v1/usage/summary`) y `NexoluCommsWebhookController`
(recibe en `POST /api/webhooks/nexolu-comms/whatsapp`) también ya existen y
están completos del lado del POS.

## Qué falta para el corte real

Según `nexolu-pos-api/docs/CUTOVER_PER_BUSINESS.md`: el aviso proactivo de
WhatsApp/email del inicio de transición de un negocio "depende de
credenciales pendientes de `comms-api` (Brevo, WhatsApp) para volverse
proactivo" — es decir, hace falta terminar de provisionar las credenciales
de proveedor de la app `pos` en `nexolu-comms-api` (vía el panel admin,
`POST /v1/admin/apps/pos/providers/meta-whatsapp` y `/brevo`) antes de
poder cambiar `MESSAGING_DRIVER=nexolu_comms` con confianza.

## Webhook entrante de WhatsApp: dos caminos posibles

- **Hoy** (`whatsapp_direct`): Meta manda el webhook directo a
  `https://pos-backend.nexolu.co/api/webhooks/whatsapp`.
- **Post-corte** (`nexolu_comms`): Meta manda el webhook a
  `https://comms.nexolu.co/webhooks/whatsapp/pos`; `nexolu-comms-api` lo
  reenvía firmado (HMAC `X-Nexolu-Signature`/`X-Nexolu-Timestamp`) a
  `https://pos-backend.nexolu.co/api/webhooks/nexolu-comms/whatsapp`, que
  reusa el mismo `InboundMessageDispatcher` que el webhook directo — el
  procesamiento del mensaje entrante es idéntico en ambos casos, solo
  cambia quién lo entrega.

**Nunca** apuntar el webhook de WhatsApp a `pos.nexolu.co` — ese es el
monolito legacy.

## Referencia

- Detalle completo de `nexolu-comms-api`: [`../apis/comms-api.md`](../apis/comms-api.md).
- Gestión de credenciales vía panel admin: [`../apis/admin-bff.md`](../apis/admin-bff.md#comms).
