# Topología de infraestructura (producción + SG)

> **Uso interno / equipo de ingeniería.** Este documento tiene IPs reales,
> nombres de droplets y estructura de red. **No lo subas a Drive/NotebookLLM
> ni lo uses como fuente para presentaciones externas** — para eso están los
> docs de [`../company/`](../company/overview.md), que no tienen esta
> información. Datos verificados en vivo contra la API de DigitalOcean el
> 2026-08-28 (no solo inferidos del código) — si algo no cuadra con lo que
> ves en el dashboard de DO, ese es el que manda.

## Cuenta y proyecto

Todo corre en una sola cuenta de DigitalOcean, región **`nyc1`** (New York),
en la VPC por defecto:

- **VPC**: `default-nyc1` (`ffddc1dc-4fd5-4aea-9f0a-f003ca6d7834`), rango
  `10.116.0.0/20`. Todos los droplets de Nexolú están en esta VPC — se
  hablan entre sí por su IP **privada** (`10.116.x.x`), nunca por la
  pública, cuando cruzan droplets (ver caso de MySQL abajo).

## Droplets de Nexolú (4)

| Nombre (DO) | IP pública | IP privada (VPC) | Tamaño | Rol | Tags |
|---|---|---|---|---|---|
| **`nexolu-core`** | `134.122.19.243` | `10.116.0.5` | `s-1vcpu-2gb` (2GB RAM, 50GB disco) | `ia-core`, `comms-api`, `payments-core` | `nexolu`, `core`, `production` |
| **`nexolu-pos-prod`** | `174.138.42.118` | `10.116.0.6` | `s-1vcpu-2gb` (2GB RAM, 50GB disco) | `pos-api`, `pos-front`, **MySQL + Redis compartidos** | `nexolu`, `pos`, `production` |
| **`nexolu`** | `134.122.116.201` (+ IP reservada `174.138.110.88`, sin uso activo en DNS hoy) | `10.116.0.3` | `s-1vcpu-2gb` (2GB RAM, 50GB disco) | Monolito legacy `pos-saas` + panel `nexolu-admin`/`nexolu-admin-front` | *(sin tags)* |
| **`nexolu-pos-sg`** | `167.71.31.140` (efímera) / **reservada `134.209.129.58`** (la que usa DNS) | `10.116.0.4` | `s-1vcpu-2gb` (2GB RAM, 50GB disco) | Staging/SG: todo el stack nuevo junto | `nexolu`, `pos-sg`, `migration` |

Ambos `nexolu-core` y `nexolu-pos-prod` fueron creados el 2026-08-26 (Ubuntu
24.04 LTS limpio, con `monitoring` habilitado). `nexolu` (el droplet
legacy/admin) es el más viejo del grupo (2023-09-20, imagen "Laravel 10.16.1
on Ubuntu 22.04" ya retirada — sigue funcionando, pero no es una imagen
reproducible si hay que recrearlo desde cero).

**`nexolu-pos-sg` usa IP reservada a propósito**: es el único droplet que se
destruye y recrea (nunca se apaga/enciende) — el flujo de "apagar SG" del
panel admin toma snapshot + destruye el droplet, y "encender SG" restaura el
snapshot como droplet nuevo y **reasigna la misma IP reservada**
(`134.209.129.58`). Los dominios `*-sg.nexolu.co` apuntan a esa IP
reservada, no a la efímera — así no hay que tocar DNS en cada ciclo.

### Droplets NO relacionados con Nexolú (mismo cuenta DO, para no confundir)

Hay un quinto droplet en la cuenta, **`sga-app`** (`104.248.230.120`, IP
reservada `146.190.186.24`), sin tags, imagen Laravel 10.0 retirada, creado
en 2023-04. No aparece en ningún repo de Nexolú ni en `nexolu-infra` —
parece un proyecto viejo/no relacionado (posible candidato a revisar si
sigue en uso, o darlo de baja si no).

## Dominios y DNS

**`nexolu.co` (y todos sus subdominios) NO está gestionado en esta cuenta de
DigitalOcean** — el `domain-list` de la cuenta solo trae dominios de otros
proyectos (`easytickets.com.co`, `luxurynails.com.co`, `gbsibate.com`,
`cafe.chaparro.dev`). El DNS real de `nexolu.co` vive en otro proveedor
(registrador o Cloudflare) que no verifiqué en esta pasada — **pendiente de
documentar dónde exactamente** (avisar si hace falta que lo busque).

Igual, según el código de cada repo (`nginx/*.conf`, `.env.example`,
`docs/PRODUCTION_SETUP.md`), estos son los subdominios reales en uso y a qué
apuntan:

| Dominio | Apunta a (droplet) | Servicio |
|---|---|---|
| `pos.nexolu.co` / `pos.chaparro.dev` | `nexolu` (`134.122.116.201`) | Monolito legacy `pos-saas` (Laravel + Inertia) — **producción real de clientes hoy** |
| `admin.nexolu.co` | `nexolu` (`134.122.116.201`) | `nexolu-admin-front` (SPA del panel) |
| `api-admin.nexolu.co` | `nexolu` (`134.122.116.201`) | `nexolu-admin` (BFF del panel), puerto interno `127.0.0.1:8001` |
| `pos-backend.nexolu.co` | `nexolu-pos-prod` (`174.138.42.118`) | `nexolu-pos-api` (Laravel nuevo), puerto interno `127.0.0.1:8001` |
| `new-pos.nexolu.co` | `nexolu-pos-prod` (`174.138.42.118`) | `nexolu-pos-front` (SPA nueva), estático servido por nginx del host desde `dist/` |
| `ia.nexolu.co` | `nexolu-core` (`134.122.19.243`) | `nexolu-ia-core`, puerto interno `127.0.0.1:8000` |
| `comms.nexolu.co` | `nexolu-core` (`134.122.19.243`) | `nexolu-comms-api`, puerto interno `127.0.0.1:8010` |
| `payments.nexolu.co` | `nexolu-core` (`134.122.19.243`) | `nexolu-payments-core`, puerto interno `127.0.0.1:8020` |
| `api-sg.nexolu.co`, `ia-sg.nexolu.co`, `comms-sg.nexolu.co`, `payments-sg.nexolu.co`, `new-pos-sg.nexolu.co` | `nexolu-pos-sg` (IP reservada `134.209.129.58`) | Mismo stack que producción, todo junto en un solo droplet, para staging/pruebas |

Dominios asociados a productos futuros/en incubación, **registrados pero
sin confirmar si tienen app real corriendo**: `easytickets.com.co` y
`luxurynails.com.co` apuntan ambos a `134.122.116.201` (el mismo droplet
`nexolu`/legacy) — coincide con `apps/tickets` y el perfil "salón de
belleza" que ya existen como bundles en `nexolu-ia-core` (ver
[`../apis/ia-core.md`](../apis/ia-core.md)), pero no verifiqué contenido
real detrás de esos dominios en esta pasada.

`easytickets.com.co`/`luxurynails.com.co`/`gbsibate.com`/`cafe.chaparro.dev`
sí están en la cuenta de DO (`domain-list`), a diferencia de `nexolu.co`.
`gbsibate.com` y `cafe.chaparro.dev` no tienen relación aparente con Nexolú
(otro cliente/proyecto en la misma cuenta) — mencionados acá solo para que
no se confundan si aparecen al mirar el dashboard de DO.

## Qué corre en cada droplet, en detalle

### `nexolu-core` (`134.122.19.243`)

Stack Python puro, orquestado por `nexolu-infra/docker-compose.yml`:
`ia-core` (`127.0.0.1:8000`), `comms-api` (`127.0.0.1:8010`),
`payments-core` (`127.0.0.1:8020`). Nginx del host hace `proxy_pass` a esos
tres puertos según el `Host` de cada request. **No tiene su propio MySQL
local en producción** — le habla a la base de `nexolu-pos-prod` cruzando la
VPC (ver siguiente sección). Este es el único droplet donde `docker compose
up -d mysql redis` de `deploy-menu.sh` sería redundante/conflictivo si se
corre tal cual — ver nota de riesgo en
[`deploy.md`](deploy.md#advertencia-mysql-en-nexolu-core).

### `nexolu-pos-prod` (`174.138.42.118`)

`nexolu-pos-api` (Laravel, `127.0.0.1:8001`), `nexolu-pos-front` (build
estático servido por nginx del host, sin contenedor), y el **MySQL +
Redis compartidos de todo el stack nuevo** (`pos-web`/`pos-queue`/
`pos-scheduler` + `mysql` + `redis`, vía `docker-compose.yml` de
`nexolu-infra`). El puerto de MySQL está publicado **solo en la IP privada
de VPC** (`10.116.0.6:3306`), justamente para que `nexolu-core` (y
cualquier herramienta de migración) pueda conectarse cruzando droplets sin
exponer la base a internet.

### `nexolu` (`134.122.116.201`) — el droplet "viejo"

Corre **tres cosas que no tienen nada que ver con `nexolu-infra`** (ese
repo no lo toca en absoluto):

1. **`pos-saas`** (el monolito legacy, Laravel + Inertia) — sigue siendo la
   producción real de los negocios que todavía no migraron. Fuente de
   verdad de `pos.nexolu.co`.
2. **`nexolu-admin`** (BFF del panel superadmin) — contenedor Docker suelto
   sin compose, `127.0.0.1:8001`, deploy 100% manual vía SSH + `deploy.sh`
   propio del repo (`ssh root@pos.chaparro.dev 'cd /opt/nexolu-admin &&
   bash deploy.sh'`).
3. **`nexolu-admin-front`** (SPA del panel) — build local + `rsync` de
   `dist/` a `/var/www/admin.nexolu.co/`.

Deliberadamente en un droplet **aparte** de los dos anteriores: si SG se
rompe o si `nexolu-pos-prod`/`nexolu-core` tienen un incidente, el panel que
se usa para operarlos sigue vivo.

### `nexolu-pos-sg` (efímera `167.71.31.140` / reservada `134.209.129.58`)

Staging de ventas ("SG"): los 5 servicios del stack nuevo (`pos-api`,
`ia-core`, `comms-api`, `payments-core`, `pos-front`) **todos juntos en un
solo droplet**, con un `docker-compose.override.yml` local (no commiteado)
que agrega límites de memoria más chicos para MySQL y un servicio
`frontend` (Vite dev server en contenedor, sin build). Pensado para
destruirse/recrearse seguido — no guardar nada ahí que no esté en un
snapshot reciente o en el repo.

## Ver también

- [`deploy.md`](deploy.md) — cómo se despliega cada servicio en cada
  droplet (`deploy-menu.sh`, el panel admin, diferencias por ambiente).
- [`../apis/admin-bff.md`](../apis/admin-bff.md) — cómo el panel modela
  estos mismos droplets como `DropletSettings` para poder operarlos sin
  tocar el dashboard de DO a mano.
- Memoria de sesión `project_prod_infra_topology` (si estás usando Claude
  Code con memoria persistente) para el historial de cómo se llegó a esta
  topología.
