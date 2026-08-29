# Modelo de datos: esquema compartido, multi-tenant, feature flags

## La base MySQL compartida con el legacy

`nexolu-pos-api` **no corre migraciones Laravel tradicionales desde cero**.
El esquema (91 `CREATE TABLE`, `database/legacy-schema/schema.sql`, ~121KB)
se carga **una sola vez** por entorno (dev, testing, SG, producción)
directo vía `mysql`, nunca vía `php artisan migrate` para el esquema base.
Es el mismo esquema que usa `pos-saas` (el monolito legacy) — en
producción, **ambas apps leen/escriben la misma base MySQL real**
(físicamente en el droplet `nexolu-pos-prod`, ver
[`infra/topology.md`](infra/topology.md)).

### Baseline (desde 2026-08-20)

`database/migrations/0000_00_00_000000_baseline_legacy_schema.php` es una
migración no-op que representa "todo lo que `schema.sql` tenía hasta acá".
`php artisan migrate:baseline` marca esa migración como corrida (fila en
`migrations`, batch `0`) sin ejecutar su `up()` — idempotente, rechaza
correr contra una BD sin la tabla `businesses`.

**De ahí en adelante**, todo cambio de esquema genuinamente nuevo (tabla
nueva o `ALTER` sobre algo que `schema.sql` ya tenía) es una migración
Laravel real — el sistema viejo de parches SQL manuales
(`database/legacy-schema/patches/`) quedó congelado ese día, se conserva
solo como historial.

### El riesgo de tocar una tabla compartida

Antes de escribir una migración sobre una tabla que `pos-saas` **también**
lee/escribe, hay que confirmar que el cambio es aditivo/nullable y auditar
el código legacy contra `INSERT`/`SELECT *` posicionales — un cambio no
aditivo rompe el monolito en producción real, con negocios reales
operando. `nexolu-pos-api/docs/CUTOVER_TODO.md` acumula la deuda que solo
se puede pagar al **retirar** el monolito de una tabla (inconsistencias que
el legacy reintroduciría si se "arreglaran" antes de tiempo).

### Migración de negocios individuales

`nexolu-pos-api/docs/CUTOVER_PER_BUSINESS.md` documenta el enfoque
vigente: cutover **gradual, negocio por negocio**, sin dual-write y sin
vuelta atrás una vez migrado. `BusinessDataExporter` (del lado legacy)
**remapea IDs** al exportar un negocio — por eso cualquier endpoint que
cruce ambos sistemas para un negocio recién migrado debe resolver por
`slug`, nunca por `id` numérico (ver
`POST /api/admin/businesses/{business:slug}/run-migration-patches` en
[`apis/pos-api.md`](apis/pos-api.md)).

## Multi-tenant: `business_id`

Es la unidad de aislamiento en todo lo que toca al POS. Nunca viaja
explícito en un request — se resuelve 100% del usuario autenticado
(`App\Traits\BelongsToBusiness`):

- **Creación**: `business_id` se sobreescribe siempre con el del usuario
  autenticado, sin importar lo que venga en el payload — cierra la puerta
  a inyección de tenant.
- **Lectura**: global scope automático (`business_id = auth()->user()
  ->business_id`) en cualquier modelo que use el trait.
- **Fuera de contexto autenticado** (comandos de consola, jobs en cola,
  tests): el scope no aplica — hay que asignar `business_id` a mano o usar
  `->withoutGlobalScope('business')`.

Un mismo negocio puede combinar verticales (tienda + mesas + agenda) a la
vez — nunca asumir una sola vertical ni que un módulo está disponible sin
chequear feature flags.

## Feature flags

- **Dónde viven**: columna `feature_flags` (JSON) en `businesses`.
- **Resolución** (`Business::hasFeature()`), 3 pasos:
  1. `feature_flags` null/vacío (negocio muy antiguo) → todo habilitado.
  2. La clave existe explícita en `feature_flags` → se usa ese valor.
  3. La clave falta pero hay `subscription_plan` → se completa con el
     default de `BusinessFeaturePresets::fromPlan($plan)`.
- **`Business::resolvedFeatureFlags()`** expone el resultado final ya
  resuelto — es lo único que el frontend debe leer (vía
  `BusinessResource.resolved_features`), nunca reimplementar las 3 ramas a
  mano (bug real ya corregido en `nexolu-pos-front`: una rama quedaba mal
  resuelta y mostraba módulos no contratados a negocios del plan Básico).
- **Catálogo** (~21 flags): `open_tabs`, `inventory`, `inventory_advanced`,
  `ingredients`, `variants`, `expenses`, `managerial_accounting`,
  `cash_closing`, `shift_daily_close_required`, `receivables`,
  `kitchen_board`, `services`, `cash_receipts_pdf`,
  `permissions_management`, `low_stock_alert`, `audit_logs`, `clients`,
  `scheduling`, `layaway`, `discounts`, `charges`, `reminders`.
- **Presets por modo de setup** al registrar un negocio: `retail`,
  `food_service`, `minimal`, `spa`, `professional_services`, `custom`.
- Superadmin edita `feature_flags` de un negocio vía `PATCH
  /api/v1/superadmin/businesses/{business}/config`.

## Bases de datos de los servicios Python (no comparten nada con MySQL de negocio)

`nexolu-ia-core`, `nexolu-comms-api` y `nexolu-payments-core` tienen cada
uno su **propia** base (SQLite en dev, MySQL en producción — mismo motor
que el resto del stack, pero esquema aparte, gestionado con Alembic).
Ninguno de los tres tiene ni necesita acceso a las tablas de negocio del
POS — el aislamiento es deliberado, es lo que los hace reutilizables por
otros productos Nexolú. Detalle de entidades de cada uno en su doc de API
respectivo ([`apis/`](apis/)).
