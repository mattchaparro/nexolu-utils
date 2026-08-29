# Cómo se despliega cada cosa

Ver primero [`topology.md`](topology.md) para saber qué droplet es cuál.
Este doc es sobre **cómo** se sube código nuevo a cada uno.

## Regla de oro

**Nunca `git pull`/build a mano saltándose `deploy-menu.sh`** (salvo los dos
casos fuera de ese repo, ver más abajo). Cada repo de servicio trae su
propio `deploy.sh` (`git pull` + build/migrate específico de ese stack);
`nexolu-infra/deploy-menu.sh <servicio>` es el orquestador que los invoca en
el orden correcto y verifica que el commit que quedó corriendo sea el que
se esperaba.

## `nexolu-infra/deploy-menu.sh`

```bash
./deploy-menu.sh              # menú interactivo
./deploy-menu.sh <servicio>   # directo, sin menú
```

`<servicio>` ∈ `pos-api`, `ia-core`, `comms-api`, `payments-core`,
`pos-front`, `all`, `infra`.

Se corre **en el droplet correspondiente** (por SSH manual, o disparado por
el panel admin — ver abajo). No detecta el ambiente por hostname ni por
variables — reacciona a lo que ya existe en el filesystem/Docker de esa
máquina:

1. **`levantar_infra()`** (se corre siempre antes de `pos-api`/los 3
   servicios Python): `docker compose up -d mysql redis`, espera hasta
   60s a que `nexolu-mysql-1` esté `healthy`. Si `pos_saas` no tiene
   tablas, pregunta interactivamente si cargar el schema legacy.
2. **Aviso de `.env` incompleto**: no bloqueante, solo loguea si falta una
   var clave (`PAYMENTS_CORE_API_KEY`, `WHATSAPP_ACCESS_TOKEN`,
   `OPENROUTER_API_KEY`, `BREVO_API_KEY`, según el servicio).
3. Corre `../<repo>/deploy.sh` del servicio.
4. **Health check** contra `/up` o `/health` — informativo, nunca hace
   fallar el deploy completo.

### `pos-front`: detecta el patrón solo, no hace falta decirle cuál

```bash
if docker compose config --services | grep -qx frontend; then
    # patrón SG: dev server de Vite en contenedor con bind mount
elif [ -x ../nexolu-pos-front/deploy.sh ]; then
    # patrón producción: git pull && npm install && npm run build,
    # nginx del host sirve dist/ directo, sin contenedor
fi
```

Si el `docker-compose.yml` mezclado con el override local de ESE droplet
define un servicio llamado `frontend`, es SG. Si no, pero hay un
`deploy.sh` ejecutable en `../nexolu-pos-front/`, es producción.

### Advertencia: MySQL en `nexolu-core`

`levantar_infra()` siempre intenta `docker compose up -d mysql redis`, pero
en `nexolu-core` (producción) **no debería haber un MySQL propio** — la base
real vive en `nexolu-pos-prod` y se accede cruzando la VPC (ver
[`topology.md`](topology.md#nexolu-pos-prod-174138421-18)). Esto no está
resuelto de forma explícita en el repo (probablemente hay un
`docker-compose.override.yml` local no commiteado en `nexolu-core` que
quita `mysql`/`redis` del compose, pero no está documentado). **Antes de
correr `deploy-menu.sh ia-core|comms-api|payments-core` a mano en
`nexolu-core`, confirmar que no se está por levantar un MySQL local
duplicado.**

## El panel admin dispara lo mismo por SSH

`POST /v1/admin/infra/{env}/jobs/deploy/{service}` en `nexolu-admin` (ver
[`../apis/admin-bff.md`](../apis/admin-bff.md#infra)) hace exactamente
`cd /opt/nexolu/nexolu-infra && ./deploy-menu.sh {service}` por SSH en el
droplet resuelto para ese servicio+ambiente, transmitiendo el output línea
por línea a un job que el frontend consulta por polling. Es la forma
recomendada de desplegar sin tener que abrir una terminal SSH — pero es
literalmente el mismo script, no un camino distinto.

## Los dos casos que NO pasan por `nexolu-infra`

`nexolu-admin` y `nexolu-admin-front` corren en el droplet `nexolu`
(legacy), **fuera del `docker-compose.yml` de `nexolu-infra` y fuera de
`deploy-menu.sh`** — cada uno tiene su propio `deploy.sh`, invocado a mano:

- **`nexolu-admin`**: `ssh root@pos.chaparro.dev 'cd /opt/nexolu-admin &&
  bash deploy.sh'` — contenedor Docker suelto, sin compose,
  `127.0.0.1:8001`.
- **`nexolu-admin-front`**: build local (`npm run build`) + `rsync` de
  `dist/` a `/var/www/admin.nexolu.co/` en el droplet, permisos
  `larasail:larasail`.

Esto es intencional: el panel que enciende/apaga los demás droplets no
puede depender de sí mismo para desplegarse.

## Provisioning inicial de un droplet nuevo (`bootstrap.sh`)

Solo para un droplet **nuevo**, una vez (no para deploys posteriores — eso
es `deploy-menu.sh`). Corre en Ubuntu 24.04 limpio:

1. Instala Docker Engine + Compose plugin, `nginx`, `certbot` +
   `python3-certbot-nginx`.
2. Clona los 4 repos de servicio como hermanos (`git@github.com:...`, SSH) —
   si un repo ya existe, lo salta.
3. Copia `nginx/*.conf` a `/etc/nginx/sites-available/`, symlinks a
   `sites-enabled/`, `nginx -t` + reload.
4. **Se detiene ahí** — el resto es manual: completar `.env` de infra y de
   cada servicio, `certbot --nginx -d <dominio>` por cada dominio (los 4
   DNS ya tienen que resolver), y recién ahí `docker compose up -d mysql
   redis` + cargar el schema + los 4 `deploy.sh`.

No es idempotente para TLS ni `.env` — a propósito, para no automatizar
secretos.

## Diferencias por ambiente

| | Local (tu laptop) | SG (staging) | Producción |
|---|---|---|---|
| Cómo se levanta | `nexolu-utils/build/start_local_pos.sh` (Sail + 2 uvicorn + Vite + túneles Cloudflare) | `deploy-menu.sh` en `nexolu-pos-sg` | `deploy-menu.sh` en `nexolu-core`/`nexolu-pos-prod` (o vía panel admin) |
| `pos-front` | Vite dev server directo | Vite dev server en contenedor (bind mount) | Build estático, nginx del host |
| MySQL | Sail (`pos_saas`, contenedor local) | `docker-compose.yml` + override local | `nexolu-pos-prod`, accedido cruzando VPC desde `nexolu-core` |
| Dominios | `localhost:*` + túneles `trycloudflare.com` efímeros | `*-sg.nexolu.co` | `*.nexolu.co` |
| Vhosts nginx | — (no aplica) | a mano en el droplet, no viven en ningún repo | committeados en `nexolu-infra/nginx/*.conf` |
| Ciclo de vida | efímero, tu máquina | se **destruye y recrea** (IP reservada), nunca se apaga/enciende in-place | droplet persistente |

## Secretos y `.env`

Sin vault — `.env` a mano en cada droplet, igual que en local. El panel
admin tiene un editor de `.env` remoto por SSH (`GET`/`POST
/v1/admin/infra/{env}/env-files/{service}`): lee el archivo, aplica el
patch, hace backup con timestamp, y `docker compose up -d
--force-recreate` de los contenedores afectados (nunca `restart`, porque
eso no relee `env_file:`). El `.env` de `infra` (passwords de MySQL/Redis)
queda **deliberadamente sin editor** en el panel — cambiarlas con el
volumen ya inicializado desincroniza todo.

## Backups

No hay nada automatizado todavía. `nexolu-infra/README.md` documenta el
comando manual (`mysqldump --all-databases`) y lo lista explícitamente como
pendiente: falta el cron + subida a almacenamiento externo. Si estás
armando el plan de disaster recovery del equipo, este es el primer hueco a
tapar.
