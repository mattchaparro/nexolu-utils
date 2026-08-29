# `nexolu-ia-core` — API reference

Servicio Python/FastAPI (async, SQLAlchemy + Alembic) que actúa como motor
de IA compartido por todos los productos Nexolú (POS, y a futuro Spa,
EasyTickets). Repo:
[`nexolu-ia-core`](https://github.com/mattchaparro/nexolu-ia-core). No toca
ninguna base de datos de negocio — solo persiste memoria conversacional,
auditoría de tools, uso/costo y borradores de escritura. Contrato completo
de integración en [`../integrations/ia-core-tools.md`](../integrations/ia-core-tools.md).

## Arquitectura interna

```
nexolu_ia_core/
├── api/v1/          # routers FastAPI, capa fina
├── core/
│   ├── agents/        # AgentDefinition/AgentRegistry (personalidad + subset de tools)
│   ├── auth/           # AppIdentity, resolución de API key
│   ├── chat/            # ChatOrchestrator, SystemPromptBuilder
│   ├── memory/            # modelos SQLAlchemy, repository, db
│   ├── models/             # ModelRouter (selección proveedor/modelo)
│   ├── security/            # hashing API keys, cifrado Fernet
│   └── tools/                 # Tool/WriteTool, ToolRegistry, ToolGuard, AppToolClient
├── providers/        # OpenRouter, OpenAI, DeepSeek, Anthropic, null (tests)
└── apps/             # ÚNICO lugar que sabe que "pos"/"spa"/"tickets" existen
```

`core/` nunca importa nada de `apps/` — agregar una app nueva (ver
[integrations](../integrations/ia-core-tools.md#alta-de-una-app-nueva)) no
toca el motor.

## Autenticación — dos niveles

| Nivel | Cómo | Protege |
|---|---|---|
| **App** (`get_current_app`) | `Authorization: Bearer <api_key>`, hash SHA-256 contra `app_registrations.api_key_hash` (`hmac.compare_digest`) | `/v1/chat`, `/v1/completions`, `/v1/conversations/*`, `/v1/drafts/*`, `/v1/usage/*` |
| **Plataforma** (`require_platform_access`) | `NEXOLU_PLATFORM_API_KEY` fija, comparada en tiempo constante | Todo `/v1/admin/*` y los endpoints cross-app de `/v1/platform/*` |

API key con prefijo `iac_`, generada y rotable vía
`/v1/admin/apps/{app_id}/regenerate-key` — nunca vuelve a mostrarse en
claro después de creada/rotada.

## Endpoints

### Chat / completions / conversaciones

| Método | Path | Auth | Qué hace |
|---|---|---|---|
| POST | `/v1/chat` | App | Envía un mensaje; corre el loop de tool-calling completo |
| POST | `/v1/chat/stream` | App | Igual, como SSE (`text/event-stream`) |
| POST | `/v1/completions` | App | Redacción de una sola pasada, sin conversación ni tools (para insights ya calculados) |
| GET | `/v1/conversations/{id}` | App | Historial completo (filtrado por app+business_id+user_id) |

### Drafts

| Método | Path | Auth | Qué hace |
|---|---|---|---|
| POST | `/v1/drafts/{id}/confirm` | App | Confirma un borrador; recién ahí se llama `tools/invoke` de verdad |
| POST | `/v1/drafts/{id}/discard` | App | Descarta el borrador |

### Uso/costo

| Método | Path | Auth |
|---|---|---|
| GET | `/v1/usage/summary`, `/v1/usage/daily` | App (su propio gasto) |
| GET | `/v1/admin/usage/daily`, `/v1/platform/usage` | Plataforma (todas las apps) |

### Admin (`/v1/admin/*`, todo 🔑Plataforma)

| Recurso | Endpoints |
|---|---|
| **Apps** | `GET/POST /apps`, `PATCH /apps/{id}`, `POST /apps/{id}/regenerate-key`, `POST /apps/{id}/tool-catalog/refresh` |
| **Drafts** | `GET /drafts`, `POST /drafts/{id}/purge` (discard forzado, sin scope de tenant — para soporte) |
| **Tool logs** | `GET /tool-logs`, `POST /tool-logs/{id}/retry` (reintenta con la `AppRegistration` vigente, escribe un log nuevo sin mutar el original) |

## Modelo de datos

| Tabla | Rol |
|---|---|
| `app_registrations` | Identidad de apps cliente: `api_key` (cifrada Fernet) + `api_key_hash`, `base_url`, `provider`/`model` override, `provider_preferences` (ruteo OpenRouter), `budget_limit_usd` (informativo, sin enforcement) |
| `conversations` | Hilo de chat: `app_id`+`business_id`+`user_id`, `agent`, `title` |
| `messages` | Cada turno: `role`, `tool_calls`, `provider`/`model`, tokens, `latency_ms`, `error` |
| `tool_invocation_logs` | Auditoría de cada tool real: `status`, `arguments`, `context` (para poder reintentar fielmente) |
| `usage_daily` | Consumo agregado: `message_count`, tokens, `cost_micros` |
| `drafts` | Borrador de escritura: `status` (pending/confirmed/discarded/expired), `payload`, `expires_at` |

## Routing de modelos (OpenRouter + fallbacks)

Proveedor primario: **OpenRouter** (default `google/gemini-2.5-flash`).
También: OpenAI, DeepSeek, Anthropic nativo, `null` (tests). Precedencia de
selección (`ModelRouter.resolve()`): override de **agente** > override de
**app** > default global. Fallback de modelos (`openrouter_fallback_models`)
y reintentos con backoff exponencial (`tenacity`, solo 429/5xx) vía
`OpenAICompatibleProvider`.

## Streaming (SSE)

`POST /v1/chat/stream` — eventos `data: {json}\n\n` con `delta`/`done`, y en
el evento final `conversation_id`+`text`+`tools_used`+`drafts`. Las tool
calls dentro de un turno streameado se ejecutan de forma síncrona (no tiene
sentido streamear JSON intermedio); solo el texto se streamea.

## Sistema de budget

`AppRegistration.budget_limit_usd` es **puramente informativo** — alimenta
alertas del panel admin, pero el Core no bloquea requests al superarlo. Sin
enforcement implementado.

## Docs internos del repo

| Archivo | Qué cubre |
|---|---|
| `docs/APP_INTEGRATION.md` | Guía completa para conectar una app nueva: contrato, `TenantContext`, flujo de confirmación de escrituras, checklist de 6 pasos |
| `docs/openapi/app-contract.json` | Spec OpenAPI del contrato que cada app cliente debe implementar (`/api/ai/tools/invoke`, `/api/ai/tools/catalog`), servida en `/docs/app-contract` |
