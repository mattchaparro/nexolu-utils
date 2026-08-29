# Onboarding para desarrolladores nuevos

Ruta recomendada para alguien que se une al equipo de ingeniería de
Nexolú. Objetivo: en menos de un día, tener el ambiente local corriendo y
entender qué repo hace qué antes de tocar código.

## 1. Pedir acceso (día 0, antes de que llegue el desarrollador si es posible)

| Acceso | Para qué | Quién lo otorga |
|---|---|---|
| GitHub — los 8 repos `nexolu-*` (ver [tabla de repos](../README.md#mapa-de-repos)) | Clonar y contribuir | Admin del org de GitHub |
| GitLab (`gitlab.com:mattchaparrof/pos-saas`) | Solo si va a tocar el monolito legacy o consultar su código como referencia | Admin de GitLab |
| Cuenta de DigitalOcean (si el rol incluye infra/deploy) | Ver droplets, métricas, snapshots | Owner de la cuenta DO |
| Panel SuperAdmin (`admin.nexolu.co`) | Operar deploys, ver merchants/apps/credenciales sin acceso SSH directo | Owner del panel (login único, ver [`apis/admin-bff.md`](apis/admin-bff.md)) |
| Credenciales de sandbox de Wompi/Meta/OpenRouter/Brevo (si va a tocar integraciones) | Probar sin usar credenciales de producción | Quien mantiene esas cuentas |

## 2. Leer, en este orden

1. **[README raíz de `nexolu-utils`](../README.md)** — de punta a punta.
   Es el mapa mental de todo el ecosistema: qué migración está en curso,
   por qué, y cómo se comunican los servicios.
2. **Este `docs/`** completo, en el orden que prefieras — está pensado
   para consultarse como referencia, no para memorizar de una sentada:
   - [`apis/`](apis/) — un doc por servicio, con su inventario de
     endpoints.
   - [`integrations/`](integrations/) — cómo se conectan los servicios
     entre sí (los tres flujos que cruzan repos: IA, WhatsApp, pagos).
   - [`data-model.md`](data-model.md) — el esquema compartido con el
     legacy, multi-tenant, feature flags.
   - [`frontends.md`](frontends.md) — las dos SPAs.
   - [`infra/`](infra/) — topología real (droplets/IPs/dominios) y cómo
     se despliega. **Uso interno**, no para compartir fuera del equipo.
3. **El `CLAUDE.md` del repo puntual** donde vas a trabajar — cada repo
   tiene el suyo con convenciones específicas (estilo de código, qué no
   romper, cómo correr sus tests). Este `docs/` da el contexto de
   conjunto, no reemplaza esas reglas.

## 3. Levantar el ambiente local

Seguir [`../build/README.md`](../build/README.md) — un solo script
(`build/start_local_pos.sh`) levanta los 4 servicios (Laravel Sail + 2
FastAPI + Vite) y expone API y frontend por túneles de Cloudflare.

Antes de la primera corrida, el setup inicial en `nexolu-pos-api`
(`composer install`, `.env`, cargar el schema legacy, importar datos de
prueba) está detallado en ese mismo README — no lo repetimos acá para no
desincronizarlo.

Login de prueba una vez levantado todo: `demo@nexolu.test` / `password123`
— admin del negocio "Restaurante de prueba", con **todos** los feature
flags activos, para poder probar cualquier módulo sin toparse con una
feature apagada.

## 4. Antes de migrar un módulo del monolito

Si la tarea es migrar un módulo de `pos-saas` (legacy) a `nexolu-pos-api`:

1. Revisar `nexolu-pos-api/docs/MIGRATION_BACKLOG.md` — si el módulo ya
   está listado, seguir el estado ahí.
2. Revisar `nexolu-pos-api/docs/CUTOVER_TODO.md` — si tu módulo toca una
   tabla compartida con el legacy, leer eso antes de "arreglar" un dato
   que parece inconsistente (probablemente es deuda conocida, no un bug
   nuevo).
3. Revisar `nexolu-pos-front/docs/BACKEND_READINESS.md` antes de empezar
   un módulo de frontend — para no construir pantallas contra endpoints
   que todavía no existen.

## 5. Convenciones que cruzan todos los repos

Ver la sección ["Convenciones que cruzan todos los
repos"](../README.md#convenciones-que-cruzan-todos-los-repos) del README
raíz — idioma (código en inglés, UI en español), `business_id` como
unidad de aislamiento, y dónde vive cada doc de referencia.

## 6. Si usás un agente de IA (Claude Code u otro) para trabajar en estos repos

Dale el contexto del [README raíz](../README.md) primero (o pedile que lo
lea) antes de pedirle que implemente algo — así entiende qué repo migra
qué, y por qué ciertas cosas (compartir la base de datos con el monolito,
no correr migraciones en `nexolu-pos-api`, no "arreglar" datos de
`CUTOVER_TODO.md`) son decisiones deliberadas y no bugs a corregir.
