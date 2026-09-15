# WhatsApp Business Platform como capacidad transversal de Nexolú

> Resultado de la investigación pedida en
> [`whatsapp-catalogo-carrito-manychat-brief.md`](whatsapp-catalogo-carrito-manychat-brief.md)
> (2026-09-14). Estructura A–O según la sección 42 del brief; tablas de
> capacidad según la sección 43; las dos preguntas de la sección 44
> respondidas al final.
>
> **Convención de veracidad** — cada afirmación importante está marcada:
> - **[OFICIAL]** confirmado en documentación vigente de Meta (developers.facebook.com / business.whatsapp.com) o de ManyChat (help.manychat.com), con enlace.
> - **[SECUNDARIO]** solo confirmado en fuentes de terceros (BSPs, blogs de partners); tratar como probable pero verificar antes de depender de ello.
> - **[CÓDIGO]** verificado leyendo los repos de Nexolú en esta sesión.
> - **[PROPUESTA]** diseño propio; no existe todavía.
>
> Cambio de alcance respecto al brief: Alejandro pidió que esto sirva para
> **cualquier** app de Nexolú (POS, Spa, colegio). Por eso el documento se
> organiza por **capacidad**, no por app, y dice qué vive en el servicio
> compartido y qué queda en cada app.

---

## A. Resumen ejecutivo

1. **Sí se puede construir el módulo completo** (conectar número, catálogo gestionado desde Nexolú, sincronización automática, carritos entrantes, IA que convierte conversación en venta). Ninguna pieza requiere ser BSP/Solution Partner: el modelo correcto para Nexolú hoy es **Tech Provider** con **Embedded Signup**. [OFICIAL]
2. **El carrito de WhatsApp llega como webhook `type: "order"`** con `catalog_id`, `product_retailer_id`, `quantity`, `item_price`, `currency` y un `text` opcional del cliente. Payload real confirmado en la referencia oficial (sección H). [OFICIAL]
3. **WhatsApp NO cobra el pedido en Colombia.** Pagos nativos solo existen en India y Brasil (con recortes en Brasil desde enero 2026). El carrito genera un pedido; el cobro es problema de Nexolú → encaja con `nexolu-payments-core` (Wompi) o pago contra entrega. [OFICIAL el modelo; países confirmados en secundarias]
4. **El catálogo se administra 100% por API** (`POST /{business_id}/owned_product_catalogs`, `POST /{catalog_id}/items_batch` con CREATE/UPDATE/DELETE por `retailer_id`, `POST /{waba_id}/product_catalogs` para conectarlo a la WABA). El único paso manual documentado: aceptar los Términos de catálogo creando el primer catálogo vía Business Manager, y que el cliente agregue método de pago en WhatsApp Manager. [OFICIAL]
5. **Variantes/modificadores no existen en el carrito de WhatsApp.** Nada en la doc oficial de carritos menciona opciones o personalización por ítem. Para Estación Polar ("arma tu granizado") y restaurantes, la personalización se resuelve con mensajes interactivos/IA y se materializa en `OrderItem.modifiers` de Nexolú. [OFICIAL por ausencia + diseño PROPUESTA]
6. **`nexolu-comms-api` es la base correcta y se debe extender, no duplicar.** Ya resuelve: credenciales Meta por app cifradas (Fernet), envío texto/plantilla/Flow, webhook por app con verificación de firma y reenvío HMAC, costos. Le faltan cinco cosas: Embedded Signup, credenciales **por negocio** (hoy son por app), módulo de catálogo/comercio, gestión de plantillas, y cola con reintentos/idempotencia en el reenvío de webhooks (hoy es fire-and-forget: si el callback falla, el evento se pierde — limitación documentada en su README). [CÓDIGO]
7. **El número de Luxury Nails se puede migrar conservándolo.** La WABA creada vía Embedded Signup de ManyChat pertenece al negocio (modelo Tech Partner), no a ManyChat. Hay dos rutas (sección M): quedarse en la misma WABA y cambiar la app suscrita (preferida), o migrar el número a una WABA nueva con la API de migración (`migrate_phone_number=true`), que conserva display name, calidad, límites y plantillas de alta calidad. [OFICIAL]
8. **El historial de chats NO se transfiere en ninguna ruta.** Cloud API no almacena ni expone historial; lo que vive en ManyChat (contactos, tags, campos, flujos) se queda en ManyChat y hay que exportarlo antes. `manychat-mcp` sirve para leer suscriptores por id/nombre/campo y disparar flows, pero **no tiene endpoint de listado masivo** (la API pública de ManyChat no lo ofrece); la exportación masiva es por la UI de ManyChat. [OFICIAL + CÓDIGO]
9. **Coexistence no aplica al caso ManyChat→Nexolú.** Coexistence es "WhatsApp Business App + Cloud API en el mismo número", no "dos plataformas de API". Para convivencia temporal ManyChat+Nexolú lo que existe es que **varias apps Meta pueden estar suscritas a la misma WABA y todas reciben los webhooks** (duplicación deliberada) — sirve para una ventana corta de transición, no como estado permanente. [OFICIAL]
10. **Precios: por mensaje desde julio 2025** (ya no por conversación). Marketing siempre se cobra; utility es gratis dentro de la ventana de servicio de 24h; service es gratis; ventana gratuita de 72h desde anuncios click-to-WhatsApp. Colombia está entre los países más baratos (~US$0.0008 por utility según secundarias; verificar en el rate card oficial, que desde abril 2026 factura en COP). [OFICIAL el modelo; tarifas exactas en el rate card]
11. **Límites de envío arrancan en 250 destinatarios únicos/24h** por portafolio no verificado y escalan (1K → …) con verificación y calidad. Para el colegio (notificaciones utility masivas a familias) esto importa el primer mes. [OFICIAL]
12. **Requisitos de plataforma para Nexolú como Tech Provider**: verificación de negocio de Nexolú + firma del Tech Provider Amendment + App Review con dos videos (enviar mensaje y crear plantilla) + acceso avanzado a `whatsapp_business_messaging` y `whatsapp_business_management`. Hasta completar todo, el límite es 10 clientes onboardeados por ventana de 7 días (luego 200). [OFICIAL]
13. **Por app, la capacidad se reparte así**: POS necesita el paquete completo (catálogo+carrito+pedidos); el Spa necesita plantillas/difusiones/agendamiento (el catálogo de tipo "servicios" existe oficialmente, pero el flujo de cita se resuelve mejor con listas interactivas/Flows); el SGA solo necesita plantillas utility — y su cuello real es el dato (6 de cada 10 familias sin teléfono), no el canal. [CÓDIGO + datos reales]
14. **Nada de esto toca producción legacy.** El diseño usa `comms.nexolu.co` (droplet core) y las APIs nuevas; `pos-saas`, `spa_app` y el droplet `134.122.116.201` no se tocan, cumpliendo las restricciones vigentes.
15. **Plan por fases** (sección O): MVP = credenciales por negocio + Embedded Signup + corte del POS a comms; V2 = catálogo+carrito+pedidos en POS; V3 = IA vendedora + migración Luxury + SGA.

---

## B. Qué SÍ puede hacer Nexolú

Tablas en el formato de la sección 43 del brief.

### B.1 Identidad y onboarding

| Capacidad | Estado | Fuente oficial | Requisitos | Permisos | Limitaciones |
|---|---|---|---|---|---|
| Onboardear negocios con su propia WABA/número desde el panel de Nexolú (Embedded Signup) | **Sí** | [Embedded Signup — Overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/overview/) | App Meta de Nexolú, Facebook Login for Business, App Review aprobado para producción | `whatsapp_business_management`, `whatsapp_business_messaging` (acceso avanzado) | 10 clientes/7 días sin verificación completa; 200 con ella. Cliente agrega su propio método de pago (modelo Tech Provider) |
| Recibir WABA ID, Phone Number ID y token intercambiable al final del flujo | **Sí** | [Onboarding customers as a Tech Provider](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-customers-as-a-tech-provider) | Intercambio server-side del `code` por un business integration system user token (`GET /oauth/access_token`) | — | El token es por cliente onboardeado; guardarlo cifrado (patrón `EncryptedJSON` ya existente en comms-api) |
| Ser Tech Provider sin ser BSP | **Sí** | [Become a Tech Provider](https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/get-started-for-tech-providers) | Verificación de negocio de Nexolú, Tech Provider Amendment (Adobe Sign), App Review con 2 videos | — | Access verification ya NO se exige (cambio reciente). Nexolú no factura la mensajería del cliente: Meta le cobra directo al cliente |

### B.2 Mensajería y plantillas

| Capacidad | Estado | Fuente oficial | Requisitos | Permisos | Limitaciones |
|---|---|---|---|---|---|
| Enviar texto libre, plantillas, Flows | **Sí** (ya en producción en Nexolú) | [Message API](https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/whatsapp-business-phone-number/message-api) | Ventana de 24h para texto libre; plantilla aprobada fuera de ella | `whatsapp_business_messaging` | Límites de envío por nivel (250→1K→…); throughput estándar |
| Crear/gestionar plantillas por API | **Sí** | [Templates overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/overview) | `POST /{waba_id}/message_templates`; revisión automática hasta 24h | `whatsapp_business_management` | 100 creaciones/hora; 250 plantillas por WABA sin verificar, 6.000 verificada; pausado automático por calidad; límite por-usuario de plantillas de marketing |
| Marcar leído + "escribiendo…" | **Sí** (ya implementado) | Message API (status read + typing_indicator) | — | `whatsapp_business_messaging` | — |

### B.3 Webhooks

| Capacidad | Estado | Fuente oficial | Requisitos | Permisos | Limitaciones |
|---|---|---|---|---|---|
| Recibir mensajes entrantes, estados, interactivos y **pedidos (`order`)** | **Sí** | [Webhooks overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/overview) · [Order webhook](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/order/) | Suscripción del app a la WABA (`POST /{waba_id}/subscribed_apps`), verificación `X-Hub-Signature-256` | `whatsapp_business_management` | El webhook es por **app Meta**, no por número; el enrutamiento por negocio se hace con `phone_number_id` del payload |
| Varias apps suscritas a la misma WABA (transición) | **Sí** | [Webhooks for WABAs](https://developers.facebook.com/docs/graph-api/webhooks/getting-started/webhooks-for-whatsapp/) | — | — | **Todas** reciben los eventos → duplicación; usable solo como ventana corta de migración |
| Callback alternativo por WABA o por número (overrides) | **Sí** | [Webhook overrides](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/) | — | — | Precedencia: número > WABA > app |

### B.4 Catálogo y comercio

| Capacidad | Estado | Fuente oficial | Requisitos | Permisos | Limitaciones |
|---|---|---|---|---|---|
| Crear catálogo por API | **Sí** | [Product Catalog reference](https://developers.facebook.com/docs/marketing-api/reference/product-catalog/) | `POST /{business_id}/owned_product_catalogs` (`name`, `vertical`=commerce) | `catalog_management`, `business_management` | **Condicionado**: los Términos de servicio de catálogo se aceptan creando el primer catálogo vía Business Manager (paso manual único por negocio) |
| Crear/actualizar/borrar productos por API (batch, con `retailer_id`) | **Sí** | [items_batch](https://developers.facebook.com/docs/marketing-api/reference/product-catalog/items_batch/) | `POST /{catalog_id}/items_batch`, `item_type=PRODUCT_ITEM`, requests CREATE/UPDATE/DELETE; `allow_upsert` default true | `catalog_management` | Hasta 5.000 ítems/request (recomendado <3.000), payload ≤28 MB, ~100 llamadas/hora por catálogo (error 80014 = rate limit); revisión automática de ítems al entrar a un catálogo conectado a WABA |
| Conectar el catálogo a la WABA por API | **Sí** | [WABA product_catalogs edge](https://developers.facebook.com/docs/graph-api/reference/whats-app-business-account/product_catalogs/) | `POST /{waba_id}/product_catalogs` con `catalog_id` | `whatsapp_business_management`, `catalog_management`, `whatsapp_business_messaging` | **Un solo catálogo conectado por WABA** (el GET devuelve "el catálogo", singular) |
| Actualizar precio/nombre/descripción/imagen y disponibilidad | **Sí** | [Catalogs overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/catalogs-overview/) | UPDATE por `retailer_id` (campo `availability`: "in stock" / "out of stock") | `catalog_management` | Cambios visibles "de inmediato al sincronizar el cliente"; un ítem que queda no disponible **se remueve de los carritos existentes** con aviso al cliente ("One or more items in your cart have been updated") |
| Catálogo de **servicios** (citas, consultas) | **Sí** | [Catalogs overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/catalogs-overview/) — distingue "Products" y "Services (appointments, consultations, subscriptions)" | — | — | La doc pública detalla menos este tipo; para el Spa, validar en implementación si el ítem-servicio soporta lo que el flujo de cita necesita |
| Enviar producto individual / múltiples / catálogo completo / carrusel | **Sí** | [Single](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/single-product-messages) · [Multi](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/multi-product-messages) · [Catalog message](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/catalog-messages) | Payloads en sección H | `whatsapp_business_messaging` | MPM: máx. 30 productos por mensaje; catalog_message: body ≤1024, footer ≤60; al menos un `product_retailer_id` debe existir en el catálogo |
| Recibir el carrito como pedido | **Sí** | [Order webhook](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/order/) | Webhook `messages` con `type: "order"` | — | Hasta 99 unidades por ítem; sin variantes, sin notas por ítem (solo un `text` global), sin dirección ni datos de pago |

### B.5 IA y herramientas

| Capacidad | Estado | Fuente oficial / código | Requisitos | Permisos | Limitaciones |
|---|---|---|---|---|---|
| IA conversacional sobre WhatsApp con tools de negocio | **Sí** (patrón ya en producción) | [CÓDIGO] `nexolu-ia-core` + `docs/integrations/ia-core-tools.md`: el Core corre el loop de tools, la app ejecuta (`POST /api/ai/tools/invoke`), escrituras pasan por `Draft` + confirmación (tarjeta o WhatsApp Flow) | Extender el catálogo de tools del POS | — | 6 iteraciones de tools por mensaje (configurable en el Core) |

---

## C. Qué NO puede hacer Nexolú (o no así)

| Capacidad | Estado | Detalle | Alternativa |
|---|---|---|---|
| Cobrar el pedido dentro de WhatsApp en Colombia | **No** | Pagos nativos solo India (UPI) y Brasil (Pix; tarjetas descontinuadas en enero 2026). Colombia aparece solo "en pruebas" en fuentes secundarias. [OFICIAL el alcance; ver [payments-in](https://developers.facebook.com/documentation/business-messaging/whatsapp/payments/payments-in/pg/)] | El webhook `order` dispara el pedido en Nexolú; el cobro sale por `nexolu-payments-core` (link de pago Wompi enviado por WhatsApp) o contra entrega |
| Variantes/opciones/modificadores en el carrito | **No confirmado** — la doc de carritos y del webhook `order` no contempla nada por-ítem más allá de cantidad y precio | [OFICIAL por ausencia] | Producto base en catálogo + personalización vía IA/listas interactivas; `OrderItem.modifiers` en la app (sección K) |
| Notas por ítem en el carrito | **No** | Solo existe `order.text` (un texto global del cliente) | Igual que arriba |
| Varios catálogos por WABA | **No** | Un catálogo conectado por WABA [OFICIAL] | Colecciones/secciones dentro del catálogo; o filtrar qué se publica con `available_on_whatsapp` |
| Transferir historial de chats al migrar de ManyChat | **No** | Cloud API no almacena mensajes; no hay API de historial. La migración de número entre WABAs transfiere display name, calidad, límites, estatus OBA y plantillas de alta calidad — **no chats** [OFICIAL] | Exportar contactos/tags de ManyChat antes (UI; la API no lista masivamente), y el teléfono del negocio conserva su propia app si se usó |
| Exportar contactos de ManyChat por API masivamente | **No** | [CÓDIGO] `manychat-mcp` cubre la API pública completa y no existe endpoint de listado; solo búsqueda por nombre/campo y lectura por id | Exportación CSV desde la UI de ManyChat (verificar en la cuenta de Luxury) |
| Coexistence ManyChat + Nexolú | **No** (concepto equivocado) | Coexistence es App-de-celular + Cloud API, no dos plataformas API. Además bajo Coexistence el **catálogo no está soportado**, throughput fijo ~20 msg/s, sin grupos [SECUNDARIO: [360dialog](https://docs.360dialog.com/docs/resources/phone-numbers/coexistence); página oficial no accesible en esta sesión] | Convivencia corta con doble suscripción de apps a la WABA (sección M) |
| Nexolú facturando la mensajería de sus clientes | **No** (como Tech Provider) | El cliente pone su método de pago en WhatsApp Manager; solo los Solution Partners comparten línea de crédito [OFICIAL] | Si algún día conviene absorber el costo, eso es volverse Solution Partner — complejidad innecesaria hoy (sección 16 del brief: confirmado) |
| Ocultar el paso manual único de Términos | **No** | Primer catálogo del negocio: aceptar ToS vía Business Manager; método de pago: WhatsApp Manager [OFICIAL] | Documentarlo como checklist guiado de onboarding en el panel |

---

## D. Arquitectura recomendada

**[PROPUESTA]**, organizada por capacidad como pidió Alejandro. Principio: **extender `nexolu-comms-api` hasta convertirlo en el "Nexolú WhatsApp Core"**, no crear otro servicio. Razones verificadas en código: ya tiene la mitad del problema resuelto (credenciales cifradas por app, envío, webhooks con firma entrante y reenvío HMAC saliente, auditoría de costos, panel admin), ya está desplegado en `comms.nexolu.co`, y crear un segundo servicio duplicaría identidad/credenciales/webhooks que son exactamente la parte compartida.

```text
                                Meta / WhatsApp Business Platform
                                  Graph API            Webhooks
                                     ▲                    │
                                     │                    ▼
        ┌────────────────────────────┴────────────────────────────────┐
        │                nexolu-comms-api  ("WhatsApp Core")          │
        │                                                             │
        │  CAPA 1 · Identidad     Embedded Signup, tokens por negocio,│
        │                         WABA/número/catalog ids, registro   │
        │  CAPA 2 · Mensajería    texto / plantilla / Flow /          │
        │                         interactivos de producto (SPM/MPM/  │
        │                         catálogo); gestión de plantillas    │
        │  CAPA 3 · Webhooks      firma Meta → persistir evento →     │
        │                         cola + reintento → reenvío HMAC     │
        │  CAPA 4 · Catálogo      proxy items_batch por negocio,      │
        │                         estado de sync por retailer_id      │
        │  (transversal)          auditoría, costos, panel admin      │
        └──────┬──────────────┬──────────────┬──────────────┬─────────┘
               │ HMAC         │ HMAC         │ HMAC         │
               ▼              ▼              ▼              ▼
        nexolu-pos-api   nexolu-spa-api   sga-api      (futuras apps)
        catálogo+carrito  plantillas,     plantillas    
        +pedidos+IA       difusiones,     utility a     
        vendedora         citas, IA       familias      
               │              │
               ▼              ▼
        nexolu-ia-core (sin cambios: cada app expone sus tools)
```

**Qué vive dónde** (la decisión central del diseño):

| Capacidad | Servicio compartido (comms-api) | Cada app |
|---|---|---|
| Identidad de número/WABA, Embedded Signup, tokens | ✅ todo | Solo un botón "Conectar WhatsApp" que abre el flujo y un callback |
| Envío (texto/plantilla/Flow/producto) | ✅ ejecución + auditoría + costo | Decide qué, a quién y cuándo (BroadcastService, StageMessage, jobs) |
| Plantillas | ✅ CRUD proxy contra Meta + estado de aprobación | Contenido y categoría de cada plantilla |
| Webhooks | ✅ recepción, firma, persistencia cruda, cola, reenvío firmado | Parseo de negocio (`InboundMessageDispatcher` en POS ya lo hace), idempotencia propia (ya existe: `Cache::add("wa_msg:{wamid}")`) |
| Catálogo | ✅ proxy `items_batch` + tabla de estado de sync por ítem | Fuente de verdad de productos, decide `retailer_id`, dispara sync al cambiar un producto |
| Pedidos/carritos | ❌ (solo reenvía el webhook `order` crudo) | Validación, matching de cliente, creación de Order, inventario |
| IA | ❌ | Tools por app vía nexolu-ia-core (patrón Draft+confirmación intacto) |
| Conversaciones | ❌ | POS y Spa ya tienen su modelo propio (`WhatsappConversation`) |

**El cambio estructural clave**: hoy `provider_credentials` es por **app** (una fila `meta_whatsapp` para todo el POS). Con Embedded Signup cada **negocio** trae su propia WABA/número/token. [PROPUESTA] Nueva tabla `business_channels` (sección E) con `(app_id, business_id)` como eje, manteniendo `provider_credentials` como fallback del número compartido de la app — así el POS multi-tenant actual no se rompe y los negocios migran uno a uno a número propio.

**Enrutamiento de webhooks**: sigue habiendo un solo endpoint por app (`/webhooks/whatsapp/{app_id}`) para el número compartido, y como todos los negocios onboardeados por Embedded Signup entran por la **misma app Meta de Nexolú**, comms-api resuelve el negocio por `metadata.phone_number_id` contra `business_channels` y reenvía al `callback_url` de la app dueña con `business_id` resuelto. Los [webhook overrides](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/) por WABA quedan como herramienta de contingencia, no como mecanismo principal.

**Lo que hay que arreglar de comms-api antes de ponerle tráfico de negocio** [CÓDIGO, confirmado en `api/webhooks.py` y README]:
1. Reenvío de webhooks **sin cola ni reintento** — un `order` perdido es una venta perdida. Persistir el evento crudo (tabla `webhook_events`) y reenviar desde un worker con reintentos exponenciales.
2. `POST /v1/notifications/send` **sin idempotencia** — aceptar un `Idempotency-Key`.
3. Firma de Meta **opcional** (si no hay `meta_app_secret` configurado, pasa con warning) — volverla obligatoria para apps con tráfico real.

---

## E. Modelo de datos

**[PROPUESTA]** — separado por servicio, como la arquitectura.

### E.1 En `nexolu-comms-api` (compartido)

```text
business_channels            -- la novedad central: identidad WhatsApp POR NEGOCIO
  id, app_id (FK comms_apps), business_id (opaco para comms, definido por la app),
  waba_id, phone_number_id, display_phone_number,
  access_token (cifrado), token_expires_at (NULL = sin expiración documentada),
  catalog_id (NULL hasta V2), status (pending|active|disconnected),
  connected_at, disconnected_at

webhook_events               -- persistencia cruda + cola de reenvío
  id, app_id, business_channel_id (NULL si número compartido),
  phone_number_id, event_type (message|status|order|template|account),
  payload (JSON crudo), signature_valid (bool),
  forward_status (pending|delivered|failed|dead), attempts, next_retry_at,
  received_at, delivered_at

catalog_items                -- estado de sync, NO fuente de verdad
  id, business_channel_id, retailer_id,
  content_hash,              -- hash del último payload enviado; evita UPDATEs inútiles
  sync_status (pending|synced|error), last_error, batch_handle, last_synced_at
  UNIQUE (business_channel_id, retailer_id)

templates                    -- espejo del estado en Meta
  id, business_channel_id | app_id, name, language, category,
  meta_template_id, status (PENDING|APPROVED|REJECTED|PAUSED), quality, components (JSON)
```

`comms_apps`, `provider_credentials` y `notifications` quedan como están [CÓDIGO]; `provider_credentials` pasa a ser "el número compartido de la app" y `business_channels` "el número propio de un negocio". `Notification` ya tiene `business_id` y `reference` — no se toca.

### E.2 En cada app (dueña del negocio)

El POS ya tiene productos, clientes, ventas. Lo nuevo del brief (secciones 4, 9, 21) se queda en la app, ajustado:

```text
products                     -- existente; se agregan:
  available_on_whatsapp (bool), whatsapp_retailer_id (NULL → derivar de SKU/id)

orders / order_items         -- existentes en POS; se agregan:
  orders.source ('whatsapp'), orders.whatsapp_order_wamid (idempotencia),
  orders.whatsapp_phone, orders.price_mismatch (bool, sección K)
  order_items.modifiers (JSON) -- variantes resueltas por IA/interactivos, NO por Meta

whatsapp_conversations       -- Spa ya lo tiene; POS ya rastrea por wamid+Cache
customers                    -- matching por teléfono normalizado (ChannelPhone ya existe en ambas apps)
```

La estructura `whatsapp_catalog_products` del brief (sección 4) **se muda a comms-api** como `catalog_items`: el estado de sincronización es plomería del canal, no dato de negocio — y así Spa y futuras apps lo heredan gratis.

---

## F. Endpoints de Meta necesarios

Todos [OFICIAL]; versión actual de Graph API en la doc: v25.0.

| # | Endpoint | Para qué | Doc |
|---|---|---|---|
| 1 | `GET /oauth/access_token?client_id&client_secret&code` | Cambiar el `code` de Embedded Signup por el business token del cliente | [Onboarding as Tech Provider](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-customers-as-a-tech-provider) |
| 2 | `POST /{waba_id}/subscribed_apps` | Suscribir la app de Nexolú a los webhooks de esa WABA | ídem |
| 3 | `POST /{phone_number_id}/register` (`messaging_product`, `pin`) | Activar el número en Cloud API | ídem |
| 4 | `POST /{phone_number_id}/messages` | Todo envío: texto, plantilla, Flow, `interactive.product`, `interactive.product_list`, `interactive.catalog_message` | [Message API](https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/whatsapp-business-phone-number/message-api) |
| 5 | `POST /{waba_id}/message_templates` / `GET` | Crear y listar plantillas | [Templates](https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/overview) |
| 6 | `POST /{business_id}/owned_product_catalogs` (`name`, `vertical`) | Crear el catálogo del negocio | [Product Catalog](https://developers.facebook.com/docs/marketing-api/reference/product-catalog/) |
| 7 | `POST /{catalog_id}/items_batch` (`item_type=PRODUCT_ITEM`, `requests[]`, `allow_upsert`) | CRUD de productos por `retailer_id`; devuelve `handles` + `validation_status` | [items_batch](https://developers.facebook.com/docs/marketing-api/reference/product-catalog/items_batch/) |
| 8 | `GET /{catalog_id}/check_batch_request_status` | Verificar resultado del batch (por `handle`) | [Batch status](https://developers.facebook.com/docs/marketing-api/catalog-batch/guides/get-batch-request/) |
| 9 | `POST /{waba_id}/product_catalogs` (`catalog_id`) / `GET` | Conectar/consultar el catálogo de la WABA | [product_catalogs edge](https://developers.facebook.com/docs/graph-api/reference/whats-app-business-account/product_catalogs/) |
| 10 | `POST /{destination_waba_id}/phone_numbers` (`cc`, `phone_number`, `migrate_phone_number=true`) → `/request_code` → `/verify_code` → `/register` | Migración de número entre WABAs (ruta B de la sección M) | [Migrate programmatically](https://developers.facebook.com/docs/whatsapp/business-management-api/guides/migrating-phone-numbers-between-wabas-programmatically) |
| 11 | Webhook entrante `messages` (incluye `type: "order"`), `statuses`, `message_template_status_update`, `account_update` | Todo lo entrante | [Webhooks](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/overview) |

## G. Permisos de Meta

[OFICIAL]

| Permiso | Para qué | Nivel |
|---|---|---|
| `whatsapp_business_messaging` | Enviar/recibir mensajes en nombre de clientes | **Avanzado** (App Review con video de envío) |
| `whatsapp_business_management` | WABAs de clientes, números, plantillas, suscripción de webhooks | **Avanzado** (App Review con video de plantilla) |
| `catalog_management` | Crear/leer/actualizar/borrar catálogos y productos | Requerido para toda la capa de catálogo |
| `business_management` | Actualizar catálogo / operar sobre el Business del cliente | Acompaña a `catalog_management` |
| `public_profile` | Base del login | Estándar |

Más: verificación de negocio de Nexolú, Tech Provider Amendment firmado, y la app con ícono, política de privacidad y categoría.

## H. Payloads confirmados por documentación oficial

Todos copiados de la doc vigente [OFICIAL]; ninguno inventado. `<>` = placeholder.

### H.1 Webhook de pedido (carrito enviado por el cliente)

De [Order messages webhook reference](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/order/) — se dispara cuando "un usuario de WhatsApp ordena uno o más productos vía mensaje de catálogo, producto individual o múltiples productos":

```json
{
  "object": "whatsapp_business_account",
  "entry": [{
    "id": "102290129340398",
    "changes": [{
      "value": {
        "messaging_product": "whatsapp",
        "metadata": {
          "display_phone_number": "15550783881",
          "phone_number_id": "106540352242922"
        },
        "contacts": [{ "profile": { "name": "Sheena Nelson" }, "wa_id": "16505551234" }],
        "messages": [{
          "from": "16505551234",
          "id": "wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQUFERjg0NDEzNDdFODU3MUMxMAA=",
          "timestamp": "1750096325",
          "type": "order",
          "order": {
            "catalog_id": "194836987003835",
            "text": "Love these!",
            "product_items": [
              { "product_retailer_id": "di9ozbzfi4", "quantity": 2, "item_price": 30, "currency": "USD" },
              { "product_retailer_id": "nqryix03ez", "quantity": 1, "item_price": 25, "currency": "USD" }
            ]
          }
        }]
      },
      "field": "messages"
    }]
  }]
}
```

Respuestas a la sección 8 del brief, sobre este payload: llega `retailer_id` (✔), cantidad (✔), precio unitario **que vio el cliente** (✔ — por eso la validación de precio de la sección K), catálogo (✔), variantes (✘ no existen), notas por ítem (✘, solo `text` global), modificación del carrito por API (✘ no documentada), confirmación automática (la hace Nexolú respondiendo, no Meta), concepto oficial de "order" (✔ este webhook), pago (✘ en Colombia).

### H.2 Enviar producto individual (SPM)

De [Single-product messages](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/single-product-messages) — `POST /<PHONE_NUMBER_ID>/messages`:

```json
{
  "messaging_product": "whatsapp",
  "recipient_type": "individual",
  "to": "<PHONE_NUMBER>",
  "type": "interactive",
  "interactive": {
    "type": "product",
    "body": { "text": "<BODY_TEXT>" },
    "footer": { "text": "<FOOTER_TEXT>" },
    "action": {
      "catalog_id": "<CATALOG_ID>",
      "product_retailer_id": "<RETAILER_ID>"
    }
  }
}
```

### H.3 Enviar múltiples productos (MPM, hasta 30)

De [Multi-product messages](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/multi-product-messages):

```json
{
  "messaging_product": "whatsapp",
  "recipient_type": "individual",
  "to": "<PHONE_NUMBER>",
  "type": "interactive",
  "interactive": {
    "type": "product_list",
    "header": { "type": "text", "text": "<HEADER>" },
    "body": { "text": "<BODY>" },
    "footer": { "text": "<FOOTER>" },
    "action": {
      "catalog_id": "<CATALOG_ID>",
      "sections": [{
        "title": "<SECTION_TITLE>",
        "product_items": [
          { "product_retailer_id": "<SKU-1>" },
          { "product_retailer_id": "<SKU-2>" }
        ]
      }]
    }
  }
}
```

Header y body obligatorios; al menos un producto debe existir en el catálogo o la API devuelve error.

### H.4 Enviar el catálogo completo

De [Catalog messages](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/catalog-messages):

```json
{
  "messaging_product": "whatsapp",
  "recipient_type": "individual",
  "to": "<TO>",
  "type": "interactive",
  "interactive": {
    "type": "catalog_message",
    "body": { "text": "<BODY_TEXT, máx 1024>" },
    "action": {
      "name": "catalog_message",
      "parameters": { "thumbnail_product_retailer_id": "<OPCIONAL>" }
    },
    "footer": { "text": "<FOOTER, máx 60>" }
  }
}
```

### H.5 Sincronizar productos (batch)

De [items_batch](https://developers.facebook.com/docs/marketing-api/reference/product-catalog/items_batch/) — `POST /{catalog_id}/items_batch`:

```json
{
  "item_type": "PRODUCT_ITEM",
  "allow_upsert": true,
  "requests": [{
    "method": "UPDATE",
    "data": {
      "id": "granizado-mango-8oz",
      "title": "Granizado de Mango",
      "description": "8 oz, fruta natural",
      "price": "9000 COP",
      "availability": "in stock",
      "condition": "new",
      "image_link": "https://<imagen-publica>",
      "link": "https://<pagina-del-producto>",
      "brand": "Estación Polar"
    }
  }]
}
```

En batch el campo `id` del `data` **es** el `retailer_id` (el mismo que vuelve como `product_retailer_id` en el webhook `order` y el que se usa en SPM/MPM). `UPDATE` con `allow_upsert` crea el ítem si no existe; la respuesta trae `handles` (para `check_batch_request_status`) y `validation_status` con errores por ítem. Los valores exactos del ejemplo (precio en COP, textos) son ilustrativos; el formato `"<monto> <moneda>"` y los nombres de campo son los oficiales.

---

## I. Flujo Embedded Signup

[OFICIAL el mecanismo; PROPUESTA el reparto Nexolú]

```text
Panel de la app (POS/Spa/SGA)          nexolu-comms-api                    Meta
─────────────────────────────          ────────────────                    ────
1. "Conectar WhatsApp"  ──────────────► genera sesión de onboarding
2. Abre popup de Embedded Signup (JS SDK de Facebook Login for Business,
   config_id de la configuración de login de Nexolú) ─────────────────────► login del cliente,
                                                                            elige/crea Business,
                                                                            WABA y número, OTP
3. El popup devuelve `code` + (waba_id, phone_number_id) ◄─────────────────┘
4. Front lo postea a comms-api  ──────► GET /oauth/access_token (code)  ──► business token
                                        POST /{waba_id}/subscribed_apps ──► webhooks activos
                                        POST /{phone_number_id}/register ─► número activo (pin 2FA)
                                        guarda business_channels (token cifrado)
5. comms-api avisa a la app (callback firmado) ── la app marca "WhatsApp conectado"
```

Decisiones concretas:
- **Qué se guarda**: `waba_id`, `phone_number_id`, business token cifrado (Fernet, patrón existente), pin 2FA que Nexolú registró. **Qué nunca**: credenciales de Facebook del cliente (nunca pasan por Nexolú: el flujo es popup de Meta) ni el `client_secret` fuera del entorno del servidor.
- **Expiración**: el business integration system user token es el indicado para Tech Providers, pensado para operar "sin re-autenticación futura" [OFICIAL]; la duración exacta se define en la configuración de Facebook Login for Business (hay modalidad de 60 días con [Refresh API](https://developers.facebook.com/docs/business-management-apis/system-users/install-apps-and-generate-tokens/) y modalidad sin expiración). **Verificar al crear la config** y guardar `token_expires_at` desde el día uno, con job de refresco si aplica.
- **Desconectar**: el cliente puede revocar desde Meta Business Suite en cualquier momento → comms-api debe tratar el error de token inválido como `status=disconnected`, no como bug. Reconectar = repetir el flujo.
- **Pasos manuales que le quedan al cliente** (no eliminables): agregar método de pago en WhatsApp Manager; aceptar ToS de catálogo la primera vez (sección J); verificación de negocio del cliente si quiere display name aprobado y límites altos.

## J. Flujo de catálogo

[PROPUESTA sobre APIs OFICIALES]

```text
POS crea/edita producto con available_on_whatsapp=true
  → ProductObserver dispara SyncWhatsAppProductJob (cola de la app)
    → POST comms-api /v1/catalog/{business_id}/items  (batch de 1..N ítems normalizados)
      → comms-api compara content_hash (evita UPDATE inútil)
      → POST /{catalog_id}/items_batch a Meta (agrupa, respeta ~100 llamadas/hora)
      → guarda handle; job posterior consulta check_batch_request_status
      → catalog_items.sync_status = synced | error(last_error)
  ← la app consulta GET /v1/catalog/{business_id}/status para pintar el semáforo en el POS
```

- **Setup inicial desde el POS** (sección 6 del brief): `Configuración → WhatsApp → Conectar` (flujo I) `→ Crear catálogo` (comms: `POST owned_product_catalogs` + `POST /{waba_id}/product_catalogs`) `→ Sincronizar productos` (batch inicial masivo) `→ ON`. El usuario no vuelve a entrar a Meta, **salvo** los dos pasos manuales únicos ya dichos.
- **Inventario** (sección 23): comparadas las dos opciones, la recomendación es **ambas a la vez**: (a) sincronizar `availability` ("in stock"/"out of stock") cuando el stock cruza cero — Meta además saca el ítem de los carritos abiertos con aviso al cliente [OFICIAL], y (b) validar stock al recibir el `order` de todas formas, porque la sync tiene latencia y rate limit. Nunca stock numérico en Meta: no existe un campo de cantidad para esto en el catálogo de WhatsApp.
- **Promociones** (sección 25): el campo estándar `sale_price` de catálogo existe en Commerce; su render en WhatsApp debe verificarse en implementación [no confirmado en la doc consultada]. El cálculo definitivo de promos siempre lo hace Nexolú al armar el Order.
- **Reconciliación**: job nocturno que lista el catálogo en Meta y lo compara contra `catalog_items` (detecta drift y borrados manuales).
- **Estación Polar** (sección 27): granizados/helados como ítems simples con foto; "arma tu granizado" NO va al catálogo (sin variantes) — va por IA/listas y termina en `order_items.modifiers`.
- **Luxury** (sección 28): el catálogo tipo "servicios" existe [OFICIAL], pero el objetivo del Spa es **agendar**, no carrito → mejor: plantillas + listas interactivas + Flow de agendamiento apuntando a `agenda.nexolu.co/<slug>`, y catálogo solo para los productos físicos que sí vende.

## K. Flujo carrito → pedido

[PROPUESTA sobre el webhook OFICIAL de H.1]

```text
Meta → comms-api /webhooks/whatsapp/{app_id}
  → verifica X-Hub-Signature-256 → persiste webhook_events → 200 inmediato
  → worker reenvía firmado (HMAC X-Nexolu-Signature) al callback de la app, con reintentos
POS /api/webhooks/nexolu-comms/whatsapp
  → InboundMessageDispatcher [CÓDIGO: ya existe, ya deduplica por wamid]
  → NUEVO: case type=order → ProcessWhatsAppOrderJob:
     1. idempotencia por wamid (orders.whatsapp_order_wamid UNIQUE)
     2. customer matching por from normalizado (ChannelPhone) → crear si no existe
     3. por cada product_item: retailer_id → producto; validar activo + sede + stock
     4. PRECIO: comparar item_price contra el precio vigente
        · igual → Order confirmable
        · distinto → Order en estado 'requiere_confirmacion', price_mismatch=true,
          y mensaje al cliente con el total correcto pidiendo OK (sección 24 del brief)
     5. crear Order(source=whatsapp) + OrderItems; reservar/descontar según política
     6. responder: confirmación + link de pago (payments-core/Wompi) o instrucciones
     7. POS: el pedido aparece en la pantalla de pedidos / cocina
```

Síncrono vs asíncrono (sección 20): **síncrono solo** el 200 a Meta y la firma; todo lo demás en colas. Jobs: en comms `ForwardWebhookJob`, `SyncCatalogBatchJob`, `CheckBatchStatusJob`; en la app `ProcessWhatsAppOrderJob`, `SendWhatsAppMessageJob` (ya existe el equivalente), `SyncWhatsAppProductJob`.

## L. Flujo IA

[CÓDIGO el patrón; PROPUESTA la extensión]

El patrón de `nexolu-ia-core` no cambia: el Core corre el loop, la app ejecuta tools re-validando tenant, y **toda escritura pasa por Draft + confirmación** — por WhatsApp la confirmación ya tiene mecanismo nativo: el Flow (`interactive.flow`) que comms-api ya sabe enviar [CÓDIGO: `_build_payload` en `core/channels/whatsapp.py`].

Tools nuevas del POS (extensión del catálogo actual de 8):

| Tool | Tipo | Reusa |
|---|---|---|
| `buscar_productos`, `consultar_producto`, `consultar_stock`, `consultar_precios`, `consultar_promociones` | lectura | Services de productos/inventario existentes |
| `preparar_pedido`, `agregar_producto_pedido`, `calcular_pedido` | lectura (arman borrador en memoria del Draft) | Misma validación de la sección K |
| `confirmar_pedido` | **escritura** → Draft → Flow de confirmación → `create_order()` | `ProcessWhatsAppOrderJob` internals |
| `cancelar_pedido` | escritura con confirmación | — |
| `enviar_productos_whatsapp` | acción de canal: manda SPM/MPM con los `retailer_id` que la IA eligió | comms-api H.2/H.3 |

Ejemplo del brief ("algo para 4 personas, máximo 60 mil"): la IA busca con `buscar_productos`, responde con un **MPM real** de hasta 30 productos (la recomendación se ve como catálogo nativo, no como texto), el cliente arma el carrito en WhatsApp y el pedido entra por el flujo K — la IA no inventa precios porque el carrito vuelve con `retailer_id` reales. WhatsApp queda como frontend; la lógica en la app (sección 12 del brief: cumplida por construcción).

Para el Spa, mismas capas con tools propias (`consultar_disponibilidad`, `preparar_cita`…) cuando toque; para el SGA, **no hay IA conversacional**: solo plantillas utility.

## M. Migración ManyChat → Nexolú (Luxury Nails), paso a paso

**Qué es hoy la conexión ManyChat** [OFICIAL/ManyChat]: ManyChat es Tech Partner de Meta y conecta números vía Cloud API con Embedded Signup — la WABA, el número y el Business Portfolio **pertenecen al negocio** (Luxury), y ManyChat solo tiene su app suscrita. "Migrar" NO es cambiar un token: es cambiar **qué app Meta está suscrita a la WABA** (ruta A) o **a qué WABA pertenece el número** (ruta B).

### Fase A — Preparación (sin tocar nada)

1. Inventario en Meta Business Suite de Luxury: ¿quién es dueño del Business Portfolio? ¿la WABA aparece bajo el Business de Luxury o bajo uno creado por ManyChat? (Determina ruta A o B.)
2. Inventario en ManyChat: flujos activos, plantillas aprobadas, tags, campos custom, cantidad de suscriptores.
3. **Exportar contactos/tags/campos desde la UI de ManyChat** (CSV). La API no lista masivamente [CÓDIGO: `manychat-mcp` no tiene `list_subscribers` porque el endpoint no existe]; para enriquecer registros puntuales sí sirven `find_subscriber_by_name` / `get_subscriber` / tags.
4. Congelar cambios de flujos en ManyChat una semana antes.

### Fase B — Nexolú listo (independiente de ManyChat)

5. Todo lo de las secciones D/E/I desplegado: comms-api con `business_channels`, webhooks con cola, Embedded Signup funcionando, y probado de punta a punta con un **número de prueba** de la app Meta de Nexolú.
6. Recrear en Nexolú las plantillas que Luxury usa (las de ManyChat que estén APPROVED y de alta calidad migran solas en la ruta B [OFICIAL]; en la ruta A ya están en la WABA y no hay que hacer nada).
7. El spa-api ya envía por comms (`NexoluCommsChannel` [CÓDIGO]); provisionar credenciales de la app `spa` en comms.

### Fase C — El corte

**Ruta A — misma WABA, cambiar de app (preferida si la WABA es del Business de Luxury):**
8. Correr el Embedded Signup de Nexolú con la cuenta de Luxury **seleccionando la WABA y número existentes** → Nexolú obtiene business token + `subscribed_apps` + `register` (el número ya está en Cloud API; el re-register con el pin de 2FA lo toma para la infraestructura de Nexolú).
9. Ventana de convivencia: ManyChat y Nexolú están ambas suscritas → **ambas reciben todos los webhooks** [OFICIAL]. Configurar el spa-api para solo-lectura (log) 24–48h mientras se valida, para no responder doble.
10. Desconectar ManyChat: desde ManyChat (Settings → WhatsApp → remove integration) o desde Meta (quitar la app de ManyChat de la WABA). La advertencia de ManyChat de "borrar el número del Business Manager para reutilizarlo" aplica a *reconectarlo a otra plataforma tipo app*; en esta ruta el número nunca sale de su WABA. [ManyChat/OFICIAL]

**Ruta B — WABA nueva (si la WABA actual quedó bajo un Business que no conviene conservar):**
8'. Desactivar 2FA del número en la WABA origen (lo hace Luxury) [OFICIAL].
9'. `POST /{waba_destino}/phone_numbers` con `cc`, `phone_number`, `migrate_phone_number=true` → `request_code`/`verify_code` (SMS al número) → `register` con pin nuevo. Migran: display name, calidad, límites, estatus OBA, plantillas de alta calidad (llegan auto-aprobadas con calidad UNKNOWN 24h). [OFICIAL]
10'. La WABA origen queda vacía; ManyChat deja de funcionar solo (su app apunta a un número que ya no está).

En ambas rutas: **downtime esperable de minutos** (el re-registro es el único momento crítico); la doc de migración programática no reporta downtime obligatorio [OFICIAL].

### Fase D — Validación (checklist de la sección 39 del brief)

11. Entrante texto → llega a spa-api con firma válida; saliente texto dentro de ventana; plantilla fuera de ventana; multimedia entrante (hoy POS lo trata como unsupported — decidir en spa); respuesta automática de etapa (`StageMessage`); webhook de status; costos en `/v1/usage`.
12. Mientras tanto **ManyChat puede seguirse usando para lo que no toque el número** — nada, en realidad: tras el corte, los flows de ManyChat ya no envían. El plan "disparar flows de ManyChat vía manychat-mcp mientras el número siga allá" aplica solo ANTES del corte, como puente para que el spa nuevo automatice sin migrar todavía.

### Fase E — Producción

13. Encender respuestas automáticas del spa (quitar el modo log), monitorear calidad del número en WhatsApp Manager 2 semanas, y recién entonces difusiones (`BroadcastService` ya filtra por `accepts_marketing` [CÓDIGO] — eso protege la calidad del número, que es lo que Meta castiga).

**Historial** (sección 40 del brief, respuesta cerrada): en el teléfono del negocio no hay nada que migrar (el número vive en Cloud API, sin app de teléfono); el historial de conversaciones vive en ManyChat y **se queda allá** (conservar la cuenta en solo-lectura o exportar); Meta no entrega historial por API; Nexolú arranca con las conversaciones en cero + el CSV de contactos importado a `clients` del spa (matching por teléfono, `ChannelPhone`).

## N. Riesgos

| # | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| 1 | App Review de Meta se demora o rechaza (videos, casos de uso) | Media | Bloquea onboarding en producción (límite 10 clientes mientras tanto) | Empezar el trámite en el MVP, no en V2; los 10 slots alcanzan para POS+Spa+SGA+pruebas |
| 2 | Pérdida de webhooks `order` por el reenvío sin cola de comms-api | Alta hoy | Ventas perdidas silenciosamente | Arreglo #1 de la sección D **antes** de cualquier tráfico de comercio |
| 3 | Calidad del número degradada por difusiones (pausa de plantillas, baja de límites) | Media | El negocio pierde el canal completo | Opt-in estricto (ya implementado en Spa), monitoreo de quality_score, warm-up gradual |
| 4 | Precio desincronizado entre POS y catálogo | Media | Cliente ve un precio y se le cobra otro → disputa | Flujo K paso 4: nunca cobrar distinto sin confirmación explícita |
| 5 | Rate limit de items_batch (~100 llamadas/hora/catálogo) con menús que cambian mucho | Baja | Sync atrasada | Agrupar cambios (debounce por negocio), `content_hash` para no reenviar idéntico |
| 6 | El corte de Luxury responde doble durante la convivencia (ManyChat + Nexolú suscritas) | Media | Clientas confundidas | Modo log 24–48h (Fase C paso 9) y corte de ManyChat en horario valle |
| 7 | Token de negocio revocado desde Meta Business Suite sin aviso | Baja | Envíos fallan para ese negocio | Tratar 401 de Meta como `disconnected` + alerta + botón de reconexión |
| 8 | Suponer que el catálogo sirve para el flujo de citas del Spa | Media | Retrabajo | Decisión ya tomada aquí: Spa usa interactivos/Flows; catálogo solo para productos físicos |
| 9 | SGA: invertir en canal con 6/10 familias sin teléfono | Alta | Esfuerzo sin alcance real | El SGA solo consume plantillas utility vía comms (costo marginal ~0 de desarrollo); la campaña de recolección de datos es el proyecto real |
| 10 | Cambios de precios/reglas de Meta (el modelo cambió en 2025 y sigue ajustándose en 2026) | Media | Presupuestos desactualizados | `cost_micros` configurable ya existe [CÓDIGO]; revisar el rate card oficial trimestralmente |

## O. Plan por fases

**MVP — "un negocio conecta su número" (identidad + mensajería):**
1. Endurecer comms-api: cola/reintentos de webhooks, idempotencia de envío, firma Meta obligatoria (sección D).
2. `business_channels` + Embedded Signup de punta a punta con número de prueba.
3. Trámites Meta en paralelo: verificación de negocio de Nexolú, Tech Provider Amendment, App Review (los dos videos salen del flujo del punto 2).
4. Cortar el POS a `MESSAGING_DRIVER=nexolu_comms` (todo el código ya existe [CÓDIGO]; falta provisionar credenciales) y provisionar la app `spa`.
5. SGA: alta como app en comms + 2–3 plantillas utility (boletines, citaciones, cobros). Con esto el colegio queda servido; su límite es el dato, no el software.

**V2 — catálogo + carrito + pedidos (POS):**
6. Módulo catálogo en comms (secciones E.1/J) + `available_on_whatsapp` y observer en POS.
7. `type=order` en el dispatcher del POS + `ProcessWhatsAppOrderJob` (sección K) + pantalla de pedidos WhatsApp.
8. Pago: link Wompi vía payments-core en la confirmación del pedido.
9. Piloto con Estación Polar (catálogo simple, sin variantes).

**V3 — IA + migración + escala:**
10. Tools de venta del POS (sección L) con confirmación por Flow.
11. **Migración de Luxury Nails** (sección M) — a esta altura Nexolú ya operó números reales durante semanas.
12. Difusiones del Spa por su propio número; carrusel de productos; reconciliación nocturna de catálogo; multi-sede si aplica.

---

## Respuestas a la sección 44 del brief

**1. ¿Puedo construir en Nexolú un módulo donde un negocio conecte su número, gestione su catálogo desde Nexolú, sincronice automáticamente, reciba carritos/pedidos y la IA convierta la conversación en venta?**

**Sí, pero:**
- **El cobro no ocurre en WhatsApp** (Colombia sin pagos nativos): el "convertir en venta" termina con link de pago o pago en el local — el pedido sí entra completo y automático.
- **Nexolú debe pasar por Tech Provider + App Review primero** (verificación de negocio, amendment firmado, 2 videos, acceso avanzado a 2 permisos); hasta entonces, máximo 10 clientes conectados por semana móvil — suficiente para todo el ecosistema actual, pero es el camino crítico del calendario.
- **Quedan dos pasos manuales únicos por negocio** que Meta no deja automatizar: aceptar los ToS de catálogo en Business Manager la primera vez, y agregar método de pago en WhatsApp Manager (el negocio le paga la mensajería a Meta directamente).
- **Sin variantes ni notas por ítem en el carrito**: restaurantes y "arma tu granizado" se resuelven con IA/mensajes interactivos y `modifiers` en Nexolú, no con el catálogo.
- **Un solo catálogo por WABA** y disponibilidad binaria (in/out of stock): el inventario fino se valida al crear el pedido en Nexolú, siempre.

**2. ¿Puedo tomar el número de Luxury Nails que hoy usa ManyChat y migrarlo a Nexolú conservando el número, y qué pasos sigo?**

**Sí, pero:**
- **El número y la WABA ya son de Luxury, no de ManyChat** (modelo Tech Partner): la migración es cambiar la app suscrita (ruta A, preferida) o mover el número a otra WABA (ruta B con `migrate_phone_number=true`); los pasos exactos y en orden están en la sección M, fases A–E. Confirmar en Fase A, mirando el Business Manager de Luxury, cuál ruta aplica.
- **El historial de chats no viaja** por ninguna ruta, y los contactos/tags de ManyChat hay que exportarlos **antes** desde la UI (la API de ManyChat no lista suscriptores en masa — verificado contra `manychat-mcp`, que cubre esa API).
- **Las plantillas** sobreviven en la ruta A (quedan en la misma WABA) y migran auto-aprobadas solo las de alta calidad en la ruta B; los flujos/automatizaciones de ManyChat no migran nunca — se reconstruyen como lógica del spa-api, que es justamente el diseño deseado.
- **Habrá una ventana de webhooks duplicados** si se usa la convivencia de dos apps suscritas; se maneja con el modo log de 24–48h. Downtime real esperable: minutos, alrededor del re-registro del número.
- **Coexistence (el feature oficial) no es para esto** — es App-de-celular + API, y además deshabilita catálogo; no usarlo en este plan.

---

## Fuentes principales

**Meta (oficial):** [Catalogs overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/catalogs-overview/) · [Sell products & services](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/sell-products-and-services/) · [Order webhook](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/order/) · [Single-product](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/single-product-messages) · [Multi-product](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/multi-product-messages) · [Catalog message](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/catalog-messages) · [Product Catalog](https://developers.facebook.com/docs/marketing-api/reference/product-catalog/) · [items_batch](https://developers.facebook.com/docs/marketing-api/reference/product-catalog/items_batch/) · [WABA product_catalogs](https://developers.facebook.com/docs/graph-api/reference/whats-app-business-account/product_catalogs/) · [Embedded Signup](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/overview/) · [Onboarding as Tech Provider](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-customers-as-a-tech-provider) · [Become a Tech Provider](https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/get-started-for-tech-providers) · [Access tokens](https://developers.facebook.com/documentation/business-messaging/whatsapp/access-tokens/) · [Webhook overrides](https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/override/) · [Templates](https://developers.facebook.com/documentation/business-messaging/whatsapp/templates/overview) · [Pricing](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing) · [Messaging limits](https://developers.facebook.com/documentation/business-messaging/whatsapp/messaging-limits) · [Phone numbers](https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers) · [Migrate numbers programmatically](https://developers.facebook.com/docs/whatsapp/business-management-api/guides/migrating-phone-numbers-between-wabas-programmatically)

**ManyChat:** [Remove WhatsApp integration](https://help.manychat.com/hc/en-us/articles/14281346866460-How-to-remove-WhatsApp-integration-from-Manychat) (el sitio bloquea lectura automatizada; citado desde su resumen indexado) · [Common issues during WhatsApp sign up](https://help.manychat.com/hc/en-us/articles/21611097151260-Common-issues-during-WhatsApp-sign-up-and-how-to-fix-them)

**Secundarias (marcadas como tal en el texto):** [360dialog — Coexistence](https://docs.360dialog.com/docs/resources/phone-numbers/coexistence) · rate cards de terceros para la tarifa de Colombia (verificar contra el [rate card oficial](https://business.whatsapp.com/products/platform-pricing)).

**Código Nexolú verificado en esta sesión:** `nexolu-comms-api` (entities, canal WhatsApp, webhooks), `nexolu-pos-api` (contrato de mensajería, `InboundMessageDispatcher`, rutas de webhook, `NexoluCommsChannel`), `nexolu-spa-api` (`BroadcastService`, `MessageDispatcher`, `Segmento`, `NexoluCommsChannel`, `LecturaSolamente`), `manychat-mcp` (las 18 tools), `sga-api` (sin mensajería hoy), y los docs de `nexolu-utils`.
