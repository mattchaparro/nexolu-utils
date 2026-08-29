# `nexolu-admin` (BFF) + `nexolu-admin-front` — panel SuperAdmin

Panel de administración **interno de Nexolú** (equipo, no clientes) para
operar infraestructura y administrar la plataforma a nivel de negocio.
Repos: [`nexolu-admin`](https://github.com/mattchaparro/nexolu-admin) (BFF,
FastAPI) + [`nexolu-admin-front`](https://github.com/mattchaparro/nexolu-admin-front)
(SPA, Vue 3). Producción: `admin.nexolu.co` (SPA) / `api-admin.nexolu.co`
(BFF) — ver [`../infra/topology.md`](../infra/topology.md).

**Sin base de datos propia.** Todo el estado real vive en los servicios que
orquesta (`nexolu-payments-core`, `nexolu-ia-core`, `nexolu-comms-api`,
droplets vía DigitalOcean/SSH). El único estado propio son los JWT de
sesión (sin persistir) y los "jobs" de infraestructura (en memoria de
proceso — se pierden si el contenedor reinicia, pero la operación en el
droplet sigue su curso).

## Arquitectura

```
nexolu-admin/app/
├── auth/          # JWT propio, un solo operador (superadmin)
├── core/           # Settings: DropletSettings, EnvironmentSettings
├── clients/         # httpx wrapper por servicio: payments_core.py, ia_core.py, comms_core.py
├── payments/          # router proxy → nexolu-payments-core
├── ia_core/             # router proxy → nexolu-ia-core
├── comms/                # router proxy → nexolu-comms-api
└── infra/
    ├── router.py           # deploy/snapshot/power-off/power-on/env-files
    ├── do_client.py          # DigitalOceanClient (API v2)
    ├── ssh_runner.py           # comandos remotos por SSH, streaming
    └── jobs.py                  # JobStore en memoria
```

Los 3 proxies (payments/ia_core/comms) siguen el mismo patrón: excepción
tipada por servicio → reenvía 4xx tal cual, aplana 5xx/timeout a 502.

## Autenticación del panel

**Un solo operador**, sin tabla de usuarios ni roles reales — deliberado:
si el login dependiera de `nexolu-pos-api` de algún ambiente, apagar ese
ambiente dejaría sin forma de volver a entrar al panel que se necesita para
encenderlo.

- Credenciales en env vars del propio BFF: `ADMIN_EMAIL` +
  `ADMIN_PASSWORD_HASH` (bcrypt). Vacío por defecto = login siempre falla.
- `POST /auth/login` → JWT propio (HS256, `JWT_SECRET_KEY`, TTL
  `JWT_TTL_HOURS`, default 24h). Verificación 100% local, sin llamar a
  ningún otro servicio.
- `UserOut.roles` siempre `["superadmin"]` fijo (compat de shape con
  `UserResource` de `nexolu-pos-api`, no un sistema de roles real).

## Modelo de "ambientes" y droplets

```python
class DropletSettings(BaseModel):
    droplet_name, region, size, ssh_key_ids, vpc_uuid,
    reserved_ip, tags, ssh_host, ssh_user, ssh_key_path

class EnvironmentSettings(BaseModel):
    payments_core_base_url, payments_core_provisioning_key,
    ia_core_base_url, ia_core_platform_api_key,
    comms_core_base_url, comms_core_platform_api_key,
    droplets: dict[str, DropletSettings]   # rol lógico -> droplet
```

| Ambiente | `droplets` | Mapea a (ver [`../infra/topology.md`](../infra/topology.md)) |
|---|---|---|
| `sg` | `{"default": ...}` | `nexolu-pos-sg` (un solo droplet) |
| `prod` | `{"core": ..., "pos": ...}` | `nexolu-core` + `nexolu-pos-prod` |

`SERVICE_DROPLET_ROLE` (fijo en código) mapea servicio → rol: `pos-api`/
`pos-front` → `"pos"`; `ia-core`/`comms-api`/`payments-core` → `"core"`.

**Barreras de seguridad en código, no solo config**: un ambiente sin
`droplets` → 404 antes de tocar DigitalOcean; el cliente nunca elige un
`droplet_id` real, solo un rol lógico; `_NEVER_POWER_CYCLE = {"prod"}`
bloquea apagar/encender producción en código.

Credenciales SSH: una key ed25519 **dedicada por droplet**, nunca
compartida entre ambientes, montada como archivo en el contenedor del BFF.

## Endpoints

### Auth (`/auth`)

`POST /login`, `POST /logout`, `GET /me`.

### Payments (`/v1/admin/payments/{env}`) — proxy a `nexolu-payments-core`

Merchants, integrations (crear/actualizar/rotar secreto/soft-delete),
credenciales Wompi (configurar/estado/revelar), transacciones (listar,
reenviar webhook). Ver [`payments-core.md`](payments-core.md) — mismo
shape, con `{env}` resuelto por el BFF.

### IA Core (`/v1/admin/ia-core/{env}`) — proxy a `nexolu-ia-core`

Apps (crear/actualizar/rotar key/refresh de catálogo de tools), uso/costo
(`platform`, `daily`), tool logs (listar/retry), drafts (listar/purge). Ver
[`ia-core.md`](ia-core.md).

### Comms (`/v1/admin/comms/{env}`) — proxy a `nexolu-comms-api`

Apps (crear/actualizar/rotar key), credenciales Meta WhatsApp / Brevo
(configurar/estado/revelar), notificaciones (log de envíos). Ver
[`comms-api.md`](comms-api.md).

### Infra (`/v1/admin/infra/{env}`)

| Método | Path | Qué hace |
|---|---|---|
| GET | `/status` | Estado de todos los droplets del ambiente |
| GET | `/branches` | Rama git + commits atrás de `origin/main` de cada repo, por droplet |
| GET | `/metrics` | CPU/memoria/load/ancho de banda (DO Monitoring API) |
| DELETE | `/{droplet}/snapshots/{id}` | Borra un snapshot |
| GET | `/jobs/{job_id}` | Consulta estado/steps/output de un job (polling) |
| POST | `/{droplet}/jobs/snapshot` | Job: snapshot del droplet |
| POST | `/{droplet}/jobs/power-off` | Job: prune + snapshot + destruir (bloqueado en `prod`) |
| POST | `/{droplet}/jobs/power-on` | Job: recrear desde snapshot + reasignar IP reservada + health-check de 5 servicios |
| POST | `/jobs/deploy/{service}` | Job: `deploy-menu.sh {service}` remoto — ver [`../infra/deploy.md`](../infra/deploy.md) |
| GET | `/env-files/{service}` | Lee `.env` remoto (marca qué es secreto) |
| POST | `/jobs/env-files/{service}` | Job: edita `.env` remoto, backup con timestamp, `force-recreate` de los contenedores afectados |

Los jobs de deploy transmiten stdout/stderr **línea por línea** al frontend
vía polling (`GET /jobs/{job_id}` cada 1.2s) — no es un spinner ciego.

## Gestión de credenciales de apps — es proxy puro, sin BD propia

El panel **nunca** guarda estas credenciales — cada acción es un `POST`
autenticado hacia el admin-API real de cada servicio (`PROVISIONING_KEY`
para payments-core, `Bearer <platform_api_key>` para ia-core/comms-api). El
secreto de plataforma correspondiente **nunca llega al frontend**. Patrón
repetido en los 3: el valor en claro solo se devuelve una vez (creación o
regeneración); ver de nuevo requiere un endpoint `.../secrets` explícito.

## `nexolu-admin-front`

Vue 3.5 + Vite + Pinia + TanStack Query + PrimeVue 5 (mismo preset
`nexoluPreset.ts` que `nexolu-pos-front`) + Tailwind v4 + VeeValidate/Zod.

Rutas clave (`/:env(sg|prod)/...`, con el ambiente **en la URL** a
propósito):

| Path | Vista |
|---|---|
| `/iniciar-sesion` | Login |
| `/` | Dashboard (placeholder — módulos se migrarán acá desde `nexolu-pos-front`) |
| `/:env/pagos/comercios` | Merchants, integrations, Wompi, transacciones |
| `/:env/infraestructura` | Status/métricas/branches/deploy/env-files por droplet |
| `/:env/comunicaciones` | Apps, Meta WhatsApp, Brevo, logs |
| `/:env/ia-core` | Apps, uso/costo, tool logs, drafts |

Auth: JWT en `localStorage`, interceptor Axios, 401 limpia sesión y
redirige. Cambiar de ambiente (`sg`↔`prod`) hace **reload completo de
página** a propósito — para no arrastrar cache de TanStack Query de un
ambiente a otro en una acción sensible.

## Docs internos

`nexolu-admin/docs/PRODUCTION_SETUP.md` — el más importante: diseño y
runbook de cómo el panel pasó de administrar solo SG a SG + producción real
(dos droplets). Fuente primaria de la topología documentada en
[`../infra/topology.md`](../infra/topology.md).
