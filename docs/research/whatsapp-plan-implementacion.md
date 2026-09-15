# Plan de implementación: WhatsApp como capacidad transversal

> Plan operativo derivado de
> [`whatsapp-capacidad-transversal.md`](whatsapp-capacidad-transversal.md)
> (el análisis) y del pedido de Alejandro (2026-09-15): todo lo que soporte
> `nexolu-comms-api` debe tener **su propio front dedicado** para operar
> procesos, configuraciones y capacidades **por negocio**.
>
> Este documento es el tablero del proyecto: se marca cada ítem al
> completarse. Las restricciones vigentes aplican a todo el plan: no tocar
> `pos-saas` ni `spa_app`, no desplegar ni modificar credenciales de
> producción desde las sesiones de implementación (el deploy lo dispara
> Alejandro por el panel admin / `deploy-menu.sh`).

## Decisiones de arranque (para no re-discutirlas)

1. **Se extiende `nexolu-comms-api`**, no se crea un servicio nuevo (análisis, sección D).
2. **El front dedicado es un repo nuevo: `nexolu-comms-front`** (Vue 3 + Vite + Tailwind 4 + PrimeVue 5 + Pinia + TanStack Query — el mismo stack de `nexolu-admin-front`, verificado en su `package.json`). Le habla **directo** a `comms.nexolu.co`, no a través del BFF admin: el panel admin sigue siendo de infraestructura; este es el panel operativo del canal.
3. **Auth del front** (ampliada por Alejandro, 2026-09-15): el panel es **connect.nexolu.co** y tiene DOS tipos de usuario con distinción dura:
   - **Admin de Nexolú** (`role=platform`): opera todo — apps internas (pos/spa/sga), todos los canales, usuarios. Entra por **SSO con auth.nexolu.co** (mismo canje de aserciones RS256 de nexolu-admin, audiencia `nexolu-connect`) o por el break-glass local (`PANEL_EMAIL`/`PANEL_PASSWORD_HASH`), que se conserva intacto.
   - **Cliente externo** (`role=client`): un negocio de afuera que usa Connect como producto. Modelo elegido: **un cliente externo ES una `CommsApp` propia** (igual que pos/spa, con sus credenciales/canales/uso) y el usuario queda atado a ella por `panel_memberships` — todo endpoint que consume queda filtrado a sus apps. Los usuarios los crea el admin desde el panel (sin self-signup todavía); pueden entrar por SSO (si su email existe en nexolu-auth) o con contraseña propia.
   Tarea operativa asociada: registrar el producto `nexolu-connect` en `AUTH_PRODUCTS_JSON` de nexolu-auth y fijar `NEXOLU_AUTH_PUBLIC_KEYS` en comms-api.
4. **Compatibilidad**: `provider_credentials` (canal por app / número compartido) sigue funcionando tal cual; `business_channels` (número propio por negocio) se agrega encima con fallback. Nada de lo existente se rompe: los 92 tests actuales deben seguir en verde en cada fase.

## Fase 0 — Endurecer comms-api (prereq de todo tráfico de negocio)

- [x] 0.1 `webhook_events`: persistir cada evento entrante **antes** del 200 a Meta; reenvío desde la tabla con reintentos exponenciales (60s → 5m → 25m → 2h → 6h → `dead`) en un worker asyncio del propio proceso; `delivered/failed/dead` + `last_error` consultables.
- [x] 0.2 Idempotencia en `POST /v1/notifications/send` vía header `Idempotency-Key` (respuesta cacheada por `(app_id, key)`).
- [x] 0.3 Firma de Meta exigible por app: flag `enforce_meta_signature` en la credencial `meta_whatsapp` (default `false` para no romper apps existentes; se enciende por app desde el panel). Con el flag activo, sin secret o con firma inválida → 401.
- [x] 0.4 Endpoints de plataforma para el front: listar/filtrar eventos de webhook, reintentar uno a mano (replay), ver el motivo del `dead`.
- [x] 0.5 Migración Alembic + tests de todo lo anterior.

## Fase 1 — Identidad por negocio

- [x] 1.1 Entidad `BusinessChannel` (`app_id`, `business_id`, `waba_id`, `phone_number_id`, token cifrado, `catalog_id`, `status`, timestamps) + repositorio + migración.
- [x] 1.2 Resolución de canal en el envío: `(app, business_id)` → `BusinessChannel` activo; si no hay, fallback al `provider_credentials` de la app (comportamiento de hoy). El costo se sigue registrando en `notifications` igual.
- [x] 1.3 Enrutamiento de webhooks: además del path por app, un endpoint único `/webhooks/whatsapp/platform` para la app Meta de Nexolú (Embedded Signup); resuelve el negocio por `metadata.phone_number_id` → `BusinessChannel` y reenvía al callback de la app dueña con el `business_id` resuelto en un header propio.
- [x] 1.4 Embedded Signup server-side: `POST /v1/onboarding/whatsapp/complete` (recibe el `code` + ids del popup, hace `GET /oauth/access_token`, `POST /{waba_id}/subscribed_apps`, `POST /{phone_number_id}/register`, guarda el canal). Configuración de la Meta App de plataforma en Settings (`meta_platform_app_id/secret`, `login_config_id`). Probado con mocks; el fin-a-fin real espera los trámites de Meta.
- [x] 1.5 Endpoints de plataforma: CRUD/estado de `business_channels`, desconectar/reconectar, marcar `disconnected` automático ante 401 de Meta.

## Fase 2 — `nexolu-comms-front` (el front dedicado)

- [x] 2.1 Auth `/panel` en comms-api: `POST /panel/auth/login` (JWT HS256, TTL configurable), `GET /panel/me`; todos los endpoints de plataforma aceptan también JWT de panel (además de la platform key, que queda para el BFF admin).
- [x] 2.2 Scaffold del repo (Vite + Vue 3 + TS + Tailwind 4 + PrimeVue 5 + Pinia + vue-router + TanStack Query), layout base, login, guardia de sesión.
- [x] 2.3 Pantallas fase A (sobre lo que ya existe): **Dashboard** (uso/costo por app y por día — `/v1/platform/usage`), **Apps** (CRUD, rotación de key), **Credenciales por app** (meta-whatsapp/brevo, revelar secretos, flag de firma), **Notificaciones** (log con filtros).
- [x] 2.4 Pantallas fase B (sobre Fase 0/1): **Webhooks** (eventos, estado de reenvío, replay, dead letter), **Negocios/Canales** (business_channels: estado, conectar — lanza Embedded Signup —, desconectar, credenciales).
- [x] 2.5 `.claude/launch.json` + prueba real en el Browser pane (flujo completo con comms-api local y SQLite).
- [x] 2.6 Deploy: **`connect.nexolu.co`** (preparado: deploy.sh de releases atómicas, vhost nginx, alta en deploy-menu y panel admin, runbook `docs/infra/connect-front.md`; el alta real — DNS A→134.122.19.243, deploy key, certbot, secretos — la ejecuta Alejandro) — solo preparar `deploy.sh`/nginx config como en los otros fronts; el alta real la hace Alejandro.

## Fase 2b — Multi-usuario y SSO (pedido de Alejandro, 2026-09-15)

- [x] 2b.1 `panel_users` (+`role` platform|client, password bcrypt opcional = solo-SSO) y `panel_memberships` (user ↔ app_id) + migración.
- [x] 2b.2 SSO auth.nexolu.co: verificación local de aserciones (puerto de `nexolu-admin/app/auth/nexolu_auth.py`, audiencia `nexolu-connect`) + `POST /panel/auth/sso/exchange`; login local acepta break-glass O usuario de BD.
- [x] 2b.3 Autorización con scoping: `require_platform_access` deja de aceptar JWTs de clientes; nuevo scope por membresías aplicado a apps/providers/webhook-events/business-channels/uso/notificaciones (un cliente solo ve lo suyo).
- [x] 2b.4 CRUD de usuarios (`/v1/admin/users`, solo plataforma) + pantalla **Usuarios** en el front.
- [x] 2b.5 Front: botón "Entrar con Nexolú" + canje de aserción (puerto de ssoAssertion.ts, producto `nexolu-connect`), rol en el store, sidebar/vistas condicionadas por rol.

## Fase 3 — Plantillas

- [x] 3.1 Módulo templates en comms-api: espejo local + proxy `POST/GET /{waba_id}/message_templates`, estado de aprobación vía webhook `message_template_status_update`.
- [x] 3.2 Pantalla **Plantillas** en el front (por app y por negocio): crear, ver estado/calidad, pausadas.
- [x] 3.3 `POST /v1/notifications/send` valida contra el espejo (plantilla existente y APPROVED) antes de llamar a Meta.

## Fase 3c — Flujos, contactos y tags (pedido de Alejandro, 2026-09-15: "estamos copiando a ManyChat")

Motor de automatización de conversaciones, el corazón de ManyChat, adaptado al guardrail de Connect: el flujo orquesta la CONVERSACIÓN (mensajes, botones, ramas, tags/variables); la acción de negocio real (cancelar la cita) la ejecuta la app dueña — por link web dentro del flujo o porque la app disparó/consume el flujo por API. Distinto de los "WhatsApp Flows" nativos de Meta (formularios), que comms-api ya envía desde antes.

- [x] 3c.1 Modelo: `contacts` (por app+negocio+teléfono, con **tags** y **fields** JSON — el modelo subscriber/tags/custom-fields de ManyChat), `flows` (disparador `keyword` o `api`, definición JSON de nodos) y `flow_sessions` (dónde va cada contacto, contexto de variables).
- [x] 3c.2 Motor (`core/flows/engine.py`): nodos `message`/`buttons` (máx. 3, regla de Meta)/`cta_url` (el "gestionar cita desde la web"), encadenamiento con `next`, espera de respuesta en botones, `add_tags`/`remove_tags`/`set_fields` por nodo, interpolación `{{contact.name}}`/`{{variable}}`, tope de nodos por corrida (anti-loop). Cada envío del motor queda en `notifications` (`reference=flow:<id>`).
- [x] 3c.3 Integración con webhooks: un `message` entrante primero avanza la sesión activa del contacto (botón/texto) o evalúa keywords de flujos activos; **el reenvío del evento a la app dueña no cambia** — el motor es una capa adicional opt-in.
- [x] 3c.4 `POST /v1/flows/trigger` (auth de app): la app dispara un flujo para un teléfono con variables (el caso real: el Spa agenda la cita → dispara `post_agenda` con `{{fecha}}`/`{{servicio}}`).
- [x] 3c.5 Admin por scope: CRUD de flujos (con validación de la definición), contactos (ver/editar tags y fields).
- [x] 3c.6 Panel: pantallas **Flujos** (crear/activar; editor por JSON validado con plantilla de ejemplo — el builder visual tipo ManyChat es una fase posterior, se dice explícito) y **Contactos** (tags/fields).

## Fase 4 — Catálogo y comercio

- [x] 4.1 `catalog_items` + `POST /v1/catalog/{business_id}/items` (batch normalizado → `items_batch` de Meta, `content_hash`, respeto del rate limit) + job de `check_batch_request_status`.
- [x] 4.2 Creación/conexión de catálogo (`owned_product_catalogs` + `product_catalogs` de la WABA) desde el panel y desde la API.
- [x] 4.3 Pantalla **Catálogo** en el front: estado de sync por ítem/negocio, errores de validación de Meta, re-sync.
- [x] 4.4 Envío de mensajes de producto en `/v1/notifications/send` (SPM/MPM/catalog_message como nuevos tipos de payload).
- [ ] 4.5 En `nexolu-pos-api`: `available_on_whatsapp` + observer + `SyncWhatsAppProductJob`; `case type=order` en `InboundMessageDispatcher` + `ProcessWhatsAppOrderJob` + pantalla de pedidos (fase POS, repo aparte de este plan de comms).

## Fase 5 — Operación (no es código de estas sesiones)

- [ ] 5.1 Trámites Meta: verificación de negocio Nexolú, Tech Provider Amendment, App Review (2 videos salen de la Fase 1.4 con número de prueba).
- [ ] 5.2 Provisionar credenciales `pos`/`spa`/`sga` en comms (panel) y cortar `MESSAGING_DRIVER=nexolu_comms` en POS.
- [ ] 5.3 Migración Luxury Nails (fases A–E del análisis, sección M).

## Registro de avance

| Fecha | Qué quedó |
|---|---|
| 2026-09-15 | Plan creado. Baseline comms-api: 92 tests en verde. |
| 2026-09-15 | **Fase 0 completa** en comms-api: `webhook_events` con persistencia previa al 200 + worker de reintentos con backoff (60s→6h, luego `dead`), `Idempotency-Key` en `/v1/notifications/send`, flag `enforce_meta_signature` por app, endpoints `/v1/admin/webhook-events` (listar/detalle/retry), migración Alembic `a1c4e7f2b9d3`. Suite: 106 tests en verde, ruff limpio. Sin desplegar (pendiente `alembic upgrade head` en el deploy). |
| 2026-09-15 | **Fase 1 completa** en comms-api: `BusinessChannel` (numero propio por negocio, token/PIN cifrados) con fallback al numero compartido de la app, auto-desconexion ante 401 de Meta, onboarding Embedded Signup server-side (`/v1/onboarding/whatsapp/*`, `MetaGraphClient`: exchange/subscribe/register), webhook de plataforma `/webhooks/whatsapp/platform` (firma obligatoria, enruta por `phone_number_id`, reenvia con `X-Nexolu-Business-Id`), admin `/v1/admin/business-channels`, migracion `c7d2f8a341e5`. Suite: 119 tests en verde, ruff limpio. |
| 2026-09-15 | **Fase 2 casi completa — nace `nexolu-comms-front` ("Nexolú Connect", nombre elegido por Alejandro)**: auth de panel en comms-api (`/panel/auth/login` + `/panel/me`, bcrypt+JWT, patrón nexolu-admin; el JWT vale como credencial en `/v1/admin/*` y `/v1/platform/*`; CORS configurable), repo nuevo con el stack/tema de nexolu-admin-front (módulo commsCore portado y apuntado directo a comms-api, con toggle "exigir firma de Meta"), pantallas nuevas: Dashboard (uso 30 días), Webhooks (triage + payload + replay), Negocios/Canales (desconexión manual). Probado de punta a punta en el navegador contra comms-api local sembrado (login → dashboard → webhooks con rejected/skipped/failed+backoff vivo → canales → modal de credenciales). type-check/lint/build en verde; comms-api: 125 tests. Pendiente 2.6 (deploy.sh/nginx + dominio, decisión de Alejandro) y un logo Connect (el PNG compartido trae el badge POS). |
| 2026-09-15 | **Fase 2b completa — multi-usuario y SSO**: `panel_users`+`panel_memberships` (migración `e9a3b5c718f2`), SSO auth.nexolu.co (aserciones RS256 verificadas localmente, audiencia `nexolu-connect`, replay guard — puerto de nexolu-admin), scoping por membresías en apps/providers/webhook-events/business-channels/uso/notificaciones (cliente externo = su `CommsApp`; lo ajeno responde 404), `require_platform_access` ya no acepta JWTs de clientes, CRUD `/v1/admin/users`, desactivar mata la sesión al instante. Front: botón "Entrar con Nexolú" + canje en el guard, menú por rol, pantalla **Usuarios**, botones de plataforma ocultos a clientes. Verificado en navegador: admin crea al cliente por la UI → login del cliente → solo ve su app/canal, `/usuarios` lo rebota. comms-api: **140 tests** en verde, ruff limpio; front: type-check/lint/build en verde. Pendiente operativo: registrar `nexolu-connect` en AUTH_PRODUCTS_JSON de nexolu-auth y fijar `NEXOLU_AUTH_PUBLIC_KEYS`; deploy `connect.nexolu.co` (2.6). |
| 2026-09-15 | **Fase 3 completa — Plantillas**: espejo `whatsapp_templates` (identidad natural waba+name+language, migración `b4f6d1a927c3`), `MetaGraphClient` con create/list/delete de `message_templates`, endpoints `/v1/admin/templates` (+`/sync`, `DELETE` que refleja el borrado multi-idioma de Meta) autorizados por scope, estado al día por webhook `message_template_status_update` (side-effect interno; el reenvío a la app no cambia), y `/v1/notifications/send` corta antes de llamar a Meta si la plantilla del espejo no está APPROVED (espejo opt-in: plantilla desconocida sigue enviando). Pantalla **Plantillas** en el panel (crear con cuerpo/pie, sincronizar, eliminar con aviso multi-idioma). Verificado en navegador con scoping en vivo (la clienta solo ve las de spa). comms-api: **151 tests** en verde; front en verde. |
| 2026-09-15 | **Fase 3c completa — Flujos, contactos y tags (el corazón de ManyChat)**: `contacts` (tags+fields por app/negocio/teléfono), `flows` (keyword/API) y `flow_sessions` (migración `d8e2c5f019a4`); motor en `core/flows/engine.py` (nodos message/buttons≤3/cta_url, interpolación `{{var}}`/`{{contact.name}}`, tags/fields por nodo, anti-loop, TTL 24h, el flujo más reciente gana); mensajes interactivos de botones y cta_url agregados al canal de WhatsApp; integración con webhooks SIN tocar el reenvío a la app (capa adicional; texto que no matchea = silencio, la conversación es de la app); `POST /v1/flows/trigger` para apps; admin por scope + pantallas **Flujos** (editor JSON validado con el ejemplo real precargado — builder visual queda para después) y **Contactos**. Verificado en vivo: flujo creado por la UI → trigger de la app → botón "Cancelaciones" → tag `pregunto_cancelacion` visible en el panel. comms-api: **166 tests**; front en verde. |
| 2026-09-15 | **Fase 4 completa (lado Connect) — Catálogo y comercio**: `catalog_items` (migración `f3a7c9e254b8`) con `content_hash` (lo que no cambió no se re-envía — rate limit ~100 batches/hora), `items_batch` oficial por `retailer_id` + `check_batch_request_status` por handle; `POST /v1/catalog/sync|check|status` para las apps; creación/conexión de catálogo (`owned_product_catalogs` + `product_catalogs` de la WABA, con el aviso de los Términos manuales del primer catálogo) desde `/v1/admin/catalogs`; el `catalog_id` viaja en la identidad (credencial de la app o `BusinessChannel`); mensajes de producto en el envío (`whatsapp_product`/`whatsapp_products`/`whatsapp_catalog`, payloads oficiales H.2–H.4). Pantalla **Catálogo** (estado por item, verificar lotes, configurar catálogo). Verificado en navegador (synced/pending/error). comms-api: **177 tests**; front en verde. **Pendiente 4.5** (lado POS: `available_on_whatsapp` + observer + case `order` — repo `nexolu-pos-api`, sesión aparte). |
| 2026-09-15 | **Iteración 1 (deploy connect.nexolu.co) preparada**: `nexolu-comms-front/deploy.sh` (patrón de releases atómicas de spa-front: build en servidor con topes, `mv -T`, rollback, validación de `.env` con las 3 VITE_* obligatorias) + vhost `connect.nexolu.co.conf` (copia canónica en nexolu-infra/nginx); `deploy-menu.sh` gana `comms-front`; registrado en el panel admin (SERVICE_REPOS/SERVICE_DROPLET_ROLE=core/_DEPLOY_SERVICES/SERVICE_ENV_FILES). Runbook completo en `nexolu-utils/docs/infra/connect-front.md`. admin: 140 tests en verde. DNS decidido: A→134.122.19.243 (nexolu-core). |
