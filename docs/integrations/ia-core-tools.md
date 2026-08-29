# Integración POS ↔ IA Core: chat, tools y drafts

Cómo el Asistente de IA del POS consulta datos reales y ejecuta acciones,
sin que `nexolu-ia-core` toque nunca una base de datos de negocio. Es una
relación en dos sentidos, no una llamada simple.

## El principio de diseño

`nexolu-ia-core` es reutilizable por **cualquier** producto Nexolú (POS,
Spa, EasyTickets) porque no sabe nada de negocio — cada app le expone su
propio catálogo de herramientas. El Core "decide todo" (proveedor de LLM,
loop de tool-calling, persistencia de conversación) pero **ejecutar** algo
real es siempre responsabilidad de la app dueña del dato.

## Paso 1 — POS → Core: iniciar el chat

```
POST {IA_CORE_BASE_URL}/v1/chat
Authorization: Bearer <IA_CORE_API_KEY>   # API key de la app "pos"
{ agent, message, context, conversation_id }
```

El Core resuelve qué `AgentDefinition` usar (personalidad + subset de
tools), arma el prompt del sistema, y corre el loop de tool-calling (hasta
6 iteraciones por mensaje) contra el proveedor de LLM resuelto por
`ModelRouter`.

## Paso 2 — Core → POS: ejecutar una tool de lectura

Cuando el modelo pide una tool, el Core **nunca la ejecuta él mismo** — le
pega de vuelta a la app:

```
POST {base_url}/api/ai/tools/invoke      # base_url = de la AppRegistration
Authorization: Bearer <api_key de la app>
{ "tool": "ventas_resumen", "arguments": {...}, "context": {business_id, user_id, permissions, features, is_admin} }
```

Del lado del POS, `AiToolInvokeController` (`nexolu-pos-api`) es el único
despachador — **re-valida `business_id`/`user_id` contra la BD**, nunca
confía a ciegas en el `context` que mandó el Core. `App\Capabilities\Registry`
mapea el nombre de la tool (en español — contrato compartido entre ambos
repos, aunque las clases que las implementan estén en inglés) a una clase
`Capability` que reusa los mismos `Service` que los controladores HTTP
normales (nunca Eloquent directo).

Respuesta esperada: `{"data": {...}}` (200) o `{"error": "..."}` (4xx/5xx).
Un fallo de dispatch no tumba la conversación — se degrada a un mensaje de
error que el modelo recibe como resultado de la tool y sigue conversando.

### Catálogo de tools hoy (`nexolu-pos-api`)

| Tool | Tipo | Permiso requerido | Feature |
|---|---|---|---|
| `ventas_resumen` | lectura | `reports.sales` | — |
| `ventas_por_dia` | lectura | `reports.sales` | — |
| `estado_caja` | lectura | `cash_shift.manage` | — |
| `inventario` | lectura | `inventory.view` | — |
| `stock_producto` | lectura | `inventory.view` | — |
| `crear_gasto` | **escritura** | `expenses.create` | `expenses` |
| `crear_producto` | **escritura** | `inventory.add` | — |
| `crear_cliente` | **escritura** | `clients.manage` | `clients` |

`GET /api/ai/tools/catalog` expone este mapeo tool→permiso/feature; el Core
lo cachea ~24h (`RemoteToolCatalog`, `POST
/v1/admin/apps/{id}/tool-catalog/refresh` para invalidar antes).

## Paso 3 — Escrituras: nunca sin confirmación humana

Una tool de **escritura** (`WriteTool`) nunca llama `tools/invoke` de
inmediato. El Core arma un `Draft` en BD propia (estado `pending`) y le
muestra al usuario una tarjeta de confirmación en el chat (o por WhatsApp
Flow). Solo cuando el usuario confirma:

```
POST {IA_CORE_BASE_URL}/v1/drafts/{draft_id}/confirm
Authorization: Bearer <api_key de la app>
```

recién ahí el Core llama `tools/invoke` de verdad con los `arguments` del
draft (editables antes de confirmar). `POST .../discard` cancela sin
ejecutar nada.

## Reintento manual de una tool fallida

`POST /v1/admin/tool-logs/{log_id}/retry` (🔑Plataforma, vía panel admin):
relee la `AppRegistration` **vigente** (respeta una rotación de API key
posterior al fallo), reconstruye el `TenantContext` desde el `context` JSON
guardado en el log original, y reintenta. Escribe un log **nuevo**, nunca
muta el original — mismo patrón que usa `nexolu-payments-core` para
reintentos de webhook.

## Alta de una app nueva en el Core

Dos pasos independientes, ambos necesarios:

1. **Código** (`nexolu-ia-core/nexolu_ia_core/apps/<nombre>/`): `tools.py`
   (metadata `Tool`/`WriteTool`, mismos nombres que la app real va a
   implementar) + `agents.py` (`AgentDefinition` por personalidad) +
   agregar la rama en `apps/registry.py::get_app_bundle()`.
2. **Datos** (runtime, sin redeploy): `POST /v1/admin/apps` —
   `app_id`, `base_url` (adonde el Core le pega para tools/invoke y
   tools/catalog), y opcionalmente `provider`/`model`/`provider_api_key`/
   `provider_preferences`/`budget_limit_usd`.

Hoy existen 3 bundles de código ya armados aunque solo `pos` tiene tráfico
real: `spa` (citas/clientes/disponibilidad/empleados) y `tickets`
(eventos/tickets/QR) — pensados explícitamente para demostrar que el mismo
Core sirve a un producto distinto sin cambiar una línea del motor.

## Referencia

- Guía completa del lado del Core:
  `nexolu-ia-core/docs/APP_INTEGRATION.md` (+ spec OpenAPI formal en
  `docs/openapi/app-contract.json`).
- Contrato del lado del POS: `App\Capabilities\*` en `nexolu-pos-api`.
