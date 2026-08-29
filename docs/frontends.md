# Frontends: `nexolu-pos-front` y `nexolu-admin-front`

## `nexolu-pos-front`

SPA nueva del POS (reemplaza gradualmente al frontend Inertia del legacy),
consume **solo** `nexolu-pos-api` por REST puro, sin SSR.

**Stack**: Vue 3.5 (Composition API), Vite, Vue Router 5, Pinia 4, TanStack
Query 5, Tailwind v4, PrimeVue 5 (modo **unstyled**, envuelto por `src/ui`
— ninguna pantalla importa PrimeVue directo), Axios, VeeValidate+Zod,
VueUse, Sentry.

### Autenticación

`POST /api/v1/login` (Sanctum) → token en `localStorage`
(`nexolu_auth_token`) vía `src/services/http/tokenStorage.ts` → adjuntado
como `Authorization: Bearer` en cada request (`src/services/http/
client.ts`). 401 → `clearSession()` (limpia token + user + cache de
TanStack Query) + redirect a login. Sanctum expira a las 4h — sin refresh
token, se re-pide credencial (aceptable para un POS por turnos). SSO desde
el legacy vía fragmento `#token=...` (nunca query string).

### Estructura (`src/`)

`modules/` (~35 módulos independientes, patrón `views/components/
composables/services` cada uno) — ventas, cuentas abiertas, catálogo,
clientes, proveedores, compras, apartados, órdenes de servicio, citas,
recordatorios, gastos, descuentos, cuentas por cobrar, comandera,
empleados, auditoría, reportes, contabilidad, turnos de caja, ajustes,
suscripción, más el panel `/superadmin` (negocios, comunicaciones, feature
catalog, métodos de pago, plantillas WhatsApp, workflows).

### Estado

Patrón fuerte: **Pinia solo para sesión** (`auth.store.ts`,
`flash.store.ts`) — todo estado de servidor (listados, mutaciones) vive en
**TanStack Query** vía composables por módulo. `queryClient.clear()` se
llama al cambiar de sesión/impersonación, para no arrastrar cache entre
negocios.

### Feature flags y permisos en el frontend

`src/utils/hasFeature.ts` lee directo `business.resolved_features` (nunca
reimplementa la lógica de 3 ramas del backend). `useNavItems.ts` cruza
feature flags + permisos + guards reales del router para armar el menú —
única fuente, para no desincronizar menú vs. rutas accesibles.

### Multi-tenant

Un usuario normal tiene un único `business_id`, sin selector — el backend
lo infiere del token. Los superadmin operan "como" otro negocio vía
**impersonación** (`/superadmin/negocios`), nunca hay multi-negocio real
por usuario.

### Build/deploy

Dev: `npm run dev` (Vite HMR). Producción: `npm run build`
(`vue-tsc -b && vite build`, type-check bloqueante) → `dist/` estático,
servido por nginx del host — ver [`infra/deploy.md`](infra/deploy.md). En
SG corre distinto: Vite dev server en contenedor con bind mount.

### Pendiente conocido

`docs/BACKEND_READINESS.md` (repo) trackea qué módulos del menú ya tienen
backend listo — consultar antes de arrancar un módulo de frontend nuevo.
No hay todavía una vista de chat del Asistente IA en el router (el backend
ya está listo).

## `nexolu-admin-front`

SPA del panel SuperAdmin — ver [`apis/admin-bff.md`](apis/admin-bff.md)
para el detalle completo (rutas, auth, stack). Mismo preset visual
(`nexoluPreset.ts`) que `nexolu-pos-front`, misma familia de librerías
(Vue 3.5, PrimeVue 5, TanStack Query, VeeValidate+Zod).

## Convenciones compartidas entre ambos frontends

- Rutas de la SPA en **español** (`/vender`, `/catalogo`,
  `/iniciar-sesion`), `name` interno en inglés.
- Ningún componente importa PrimeVue crudo — todo pasa por una capa `src/
  ui`/Nexolú UI propia, para desacoplar identidad visual de la librería.
- Texto de cara al usuario en español; identificadores de código en
  inglés (mismo criterio que el backend, ver
  [README raíz](../README.md#convenciones-que-cruzan-todos-los-repos)).
