# `nexolu-pos-api` — API reference

Backend API-first (Laravel 13, PHP 8.4) del POS. Repo:
[`nexolu-pos-api`](https://github.com/mattchaparro/nexolu-pos-api). Sirve al
frontend nuevo ([`nexolu-pos-front`](../frontends.md)) y a dos servicios
Python hermanos (`nexolu-ia-core`, `nexolu-payments-core`) vía endpoints
server-to-server. Contexto general de la migración en el
[README raíz](../../README.md).

## Arranque y stack

- PHP 8.4, Laravel `^13.8`, Sanctum `^4.0`, Spatie Laravel Permission
  `^8.3`, Sentry Laravel, Laravel Boost (MCP para agentes de IA en dev).
- Local: `./vendor/bin/sail up -d` — `APP_PORT=8000`, `VITE_PORT=5174`
  (nunca 5173, ese es el puerto real de `nexolu-pos-front`).
- `QUEUE_CONNECTION=redis` **obligatorio** — el esquema compartido con el
  legacy no tiene tablas `jobs`/`job_batches`.
- `APP_TIMEZONE=America/Bogota` + `DB_TIMEZONE=-05:00` fijos (Colombia no
  tiene horario de verano).
- Producción: `deploy.sh` (`git pull` + `migrate:baseline` + `migrate
  --force` + `permissions:sync`), invocado por
  [`deploy-menu.sh`](../infra/deploy.md).

## Autenticación

- `POST /api/v1/login` → Sanctum **personal access token**, expira a las 4h
  (`SANCTUM_TOKEN_EXPIRATION=240`, replica la expiración de sesión del
  legacy).
- API-only: cualquier guest recibe 401 JSON, nunca redirect HTML.
- **`business_id` nunca viaja en el request** — se resuelve 100% del
  usuario autenticado vía el trait `BelongsToBusiness`: en creación lo
  sobreescribe siempre (cierra la puerta a inyección de tenant), en lectura
  agrega un global scope automático. Fuera de contexto autenticado
  (comandos, jobs, tests) el scope no aplica.
- Autorización granular con Spatie Permission — `PermissionCatalog` es la
  fuente única de verdad (~8 categorías, sincronizadas con `php artisan
  permissions:sync`). Middlewares clave: `permission:<perms>`,
  `business-admin` (solo dueño/admin), `feature:<flag>` (ver
  [`data-model.md`](../data-model.md#feature-flags)), `superadmin`.

## Inventario de rutas

`routes/api.php` (557 líneas) + `routes/superadmin.php` (114 líneas, montado
bajo `/api/v1/superadmin`). Todo bajo `v1` salvo el puñado de rutas de
contrato fijo con servicios externos.

### Fuera de `/v1` (contrato server-to-server / público firmado)

| Método | Path | Quién lo llama | Auth |
|---|---|---|---|
| POST | `/api/ai/tools/invoke` | `nexolu-ia-core` | API key (`ia-core.key`) |
| GET | `/api/ai/tools/catalog` | `nexolu-ia-core` | API key (`ia-core.key`) |
| POST | `/api/admin/businesses/{business:slug}/run-migration-patches` | Panel superadmin del legacy | API key (`legacy.admin-key`) |
| GET/POST | `/api/webhooks/whatsapp` | Meta (WhatsApp Cloud API) | `verify_token` (GET) / sin firma (POST) |
| POST | `/api/webhooks/payments-core` | `nexolu-payments-core` | HMAC (`X-Nexolu-Signature`/`X-Nexolu-Timestamp`) |
| POST | `/api/webhooks/nexolu-comms/whatsapp` | `nexolu-comms-api` | HMAC (mismo esquema) |
| GET | `/api/notifications/low-stock/{business}/snooze` | Clic humano (email) | URL firmada |
| GET | `/api/public/receipts/{type}/{id}` | Proveedor de WhatsApp | URL firmada, 24h |

Detalle completo de estas integraciones en
[`../integrations/`](../integrations/).

### `/v1` — por módulo (resumen; ver código para el detalle línea a línea)

| Módulo | Endpoints clave |
|---|---|
| **Auth/cuenta** | `POST /register`, `/login`, `/forgot-password`, `/reset-password`, `/logout`; `GET/PUT /me`, `PUT /me/password` |
| **Asistente IA** | `POST /ai/chat`, `/ai/drafts/{id}/confirm|discard`; `GET /insights`, `POST /insights/{type}/refresh`; `/ai/channels/whatsapp/*` (vínculo OTP); `/ai/message-packs/*` (paquetes de mensajes) |
| **Negocio/facturación** | `GET/PUT /business`, `/business/billing-profile`, `/business/notifications`, `/business/payment-methods`; `GET /payment-methods`, `/pse/financial-institutions` (proxy Payments Core); `/payment-sources`; `/subscription/*` |
| **Dashboard** | `GET /dashboard/summary`, `PUT /dashboard/shortcuts`, `/dashboard/whatsapp-onboarding` |
| **Auditoría/soporte** | `/audit-logs*`, `/support-tickets` |
| **Empleados** | CRUD `/employees`, `/employees/permission-catalog`, `/employees/{id}/permissions`, `/toggle` |
| **Productos/inventario** | `/products*`, `/product-categories`, `/ingredients*`, `/product-attributes` (variantes), `/stock-movement-reasons` |
| **Compras/proveedores** | `/suppliers*`, `/purchases*`, `/stock-movements` |
| **Gastos** | `/expenses*`, `/expense-types`, `/fixed-expense-templates*` |
| **Descuentos** | `/discounts*` |
| **Ventas/mesas** | `POST /sales`, `/sales/{id}/reverse`, `/receipt*`; `/tables*`, `/open-tabs*`; `/kitchen/tickets*` (comandera) |
| **Cuentas por cobrar** | `/receivables*`, `/reminders*`, `/layaways*` (apartados) |
| **Servicios/agenda** | `/service-orders*`, `/service-workflow`, `/appointments*` |
| **Reportes** | `/reports/sales/*`, `/reports/cash-closings*`, `/reports/inventory/*`, `/reports/suppliers*` |
| **Contabilidad** | `/accounting/monthly|annual|closings`, `POST /accounting/close-month` |
| **Caja** | `/cash-shifts*`, `/cash-closings*` |
| **SuperAdmin** (`/v1/superadmin/*`) | Negocios (activar, plan, feature flags, precio custom, impersonar), usuarios cross-tenant, anuncios, catálogo global de métodos de pago, workflows de servicio, dashboard de finanzas, comunicaciones, plantillas, auditoría global, tickets, cron jobs, guías de soporte |

> Para el listado exhaustivo endpoint-por-endpoint con método, permiso y
> feature flag requeridos, `routes/api.php`/`routes/superadmin.php` son la
> fuente de verdad — este doc resume por módulo para no quedar
> desactualizado en cada PR.

## Catálogo de herramientas de IA (`App\Capabilities`)

Ver [`../integrations/ia-core-tools.md`](../integrations/ia-core-tools.md)
para el contrato completo. Resumen: `Registry::MAP` mapea nombre-de-tool en
español → clase `Capability`. Tools de lectura hoy: `ventas_resumen`,
`ventas_por_dia`, `estado_caja`, `inventario`, `stock_producto`. Tools de
escritura (generan `AiDraft` en `nexolu-ia-core`, nunca ejecutan solas):
`crear_gasto`, `crear_producto`, `crear_cliente`.

## Base de datos

No corre migraciones Laravel desde cero — el esquema (91 tablas,
`database/legacy-schema/schema.sql`) se carga **una sola vez** por entorno.
`php artisan migrate:baseline` adopta ese estado como si fuera el batch 0
de Laravel; de ahí en más, todo cambio de esquema nuevo es una migración
Laravel real. Detalle completo en [`../data-model.md`](../data-model.md).

## Comandos artisan custom (los que importan para operar)

| Comando | Uso |
|---|---|
| `migrate:baseline` | Adopta el esquema legacy como punto de partida de Laravel migrations |
| `permissions:sync` | Sincroniza `PermissionCatalog` → BD |
| `legacy:normalize-payment-methods`, `payment-methods:migrate-catalog`, `clients:backfill-links` | Los 3 parches post-migración de un negocio (los mismos que corre `run-migration-patches`) |
| `exchange-rate:fetch` | TRM del día |
| `inventory:send-low-stock-alerts`, `notifications:send-daily-whatsapp-summary`, `reminders:send-whatsapp-notifications`, `appointments:send-*-reminders` | Notificaciones programadas (WhatsApp/email) |
| `audit:prune` | Purga `log_actions` más viejos que la retención (default 45 días) |

## Docs internos del repo (`nexolu-pos-api/docs/`)

| Archivo | Qué cubre |
|---|---|
| `CUTOVER_TODO.md` | Deuda técnica sobre tablas compartidas con el legacy, solo pagable al retirarlo |
| `MIGRATION_BACKLOG.md` | Backlog de jobs/módulos de `pos-saas-legacy` aún sin migrar |
| `CUTOVER_PER_BUSINESS.md` | Diseño del cutover gradual negocio-por-negocio (sin dual-write, sin vuelta atrás) |
| `CUTOVER_PILOT_LOG.md` | Bitácora viva del piloto de migración gradual en producción real |
| `PRODUCTION_CUTOVER.md` | Runbook de despliegue a producción |
| `PLAN_METODOS_PAGO_ALTERNOS.md` | Plan de Nequi/PSE/Botón Bancolombia vía Payments Core |
| `LOCAL_DATA_IMPORT.md` | Cómo cargar un snapshot de datos reales de SG en local |
| `WHATSAPP_TEMPLATES_PENDING.md` | Plantillas de WhatsApp que el código ya usa pero faltan aprobar en Meta |

Leer siempre el `CLAUDE.md` de ese repo antes de tocar código — convenciones
de PHP/Pint/PHPUnit específicas que este doc no repite.
