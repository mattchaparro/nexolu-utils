# start_local_pos.sh

Levanta **todo** el stack local de Nexolú de una sola corrida:

| Servicio | Cómo | Puerto |
|---|---|---|
| `nexolu-pos-api` | Laravel Sail (Docker): mysql + redis + api | `:8000` |
| `nexolu-ia-core` | uvicorn desde `.venv` | `:8001` |
| `nexolu-comms-api` | uvicorn desde `.venv` | `:8002` |
| `nexolu-pos-front` | Vite dentro de un contenedor `node:20` | `:5173` |
| 2 túneles cloudflared | exponen la API y el frontend a internet | URLs públicas |

Los túneles son para poder abrir el frontend **desde el celular** (o
compartirlo con alguien) sin desplegar nada - la SPA en el celular no puede
usar `localhost`, así que apunta al túnel de la API en vez de a
`localhost:8000`.

## Requisito: los 5 repos clonados como hermanos

Este script **no clona nada por vos**. Antes de correrlo, cloná los 5 repos
en el mismo directorio padre (ej. `~/dev/nexolu/`):

```bash
mkdir -p ~/dev/nexolu && cd ~/dev/nexolu
git clone git@github.com:mattchaparro/nexolu-pos-api.git
git clone git@github.com:mattchaparro/nexolu-ia-core.git
git clone git@github.com:mattchaparro/nexolu-comms-api.git
git clone git@github.com:mattchaparro/nexolu-pos-front.git
git clone git@github.com:mattchaparro/nexolu-utils.git
```

El script busca la carpeta `nexolu-pos-api` hacia arriba desde donde vive
(hasta 3 niveles), así que da igual si lo corrés como
`bash nexolu-utils/build/start_local_pos.sh` desde `~/dev/nexolu/`, con la
ruta absoluta, o con un symlink apuntando a él - siempre encuentra el
directorio padre correcto.

## Setup inicial (una sola vez, antes de la primera corrida)

Este script **levanta** lo que ya existe, no hace el setup de cero. Antes
de la primera corrida hace falta, en `nexolu-pos-api`:

1. `composer install` (vía un contenedor con PHP 8.4+, ver
   `nexolu-pos-api/CLAUDE.md` si el PHP local no alcanza).
2. `.env` con `APP_PORT=8000`, `VITE_PORT=5174` (no 5173 - ver por qué en
   "Puertos" abajo), `WWWUSER`/`WWWGROUP` = tu `id -u`/`id -g`.
3. Cargar el esquema legacy una sola vez:
   `mysql -uroot -p... pos_saas < database/legacy-schema/schema.sql`
   (nunca `php artisan migrate` - ver `nexolu-pos-api/CLAUDE.md`).
4. Datos reales para desarrollar contra algo que no está vacío:
   `bash nexolu-pos-api/scripts/import-sg-data.sh` (ver
   `nexolu-pos-api/docs/LOCAL_DATA_IMPORT.md`).

Y en `nexolu-ia-core` / `nexolu-comms-api`: `.venv` creado con las deps
instaladas (`pip install -e ".[dev]"`) y `.env` con `DATABASE_URL` apuntando
a una base MySQL propia con Alembic corrido - ver el README de cada repo.

## Uso

```bash
bash start_local_pos.sh              # pull + rebuild de los 4 repos,
                                      # túneles relanzados y verificados
bash start_local_pos.sh --no-tunnel  # lo mismo, pero SIN tocar los túneles
```

**Usá `--no-tunnel` si ya tenés el frontend abierto en el celular o
compartiste la URL con alguien** y solo querés traer código nuevo - la URL
pública no cambia. Sin la flag, el script mata los túneles viejos y levanta
unos nuevos (con URL distinta) SIEMPRE, así que evitá correrlo sin
`--no-tunnel` si no hace falta - especialmente muchas veces seguidas: los
túneles gratis de `trycloudflare.com` empiezan a devolver `530` (rate
limit del lado de Cloudflare) si creás demasiados en poco tiempo. Si te
pasa, esperá un par de minutos sin tocar nada y volvé a correr el script.

En **ambos** modos, siempre: hace `git pull origin main` en los 4 repos
(con stash/pop automático si tenés cambios locales sin commitear, para no
perderlos) y reconstruye de verdad - no solo reinicia lo que ya estaba
corriendo:

- `nexolu-pos-api`: `docker compose up -d --build`.
- `nexolu-ia-core` / `nexolu-comms-api`: `pip install -e ".[dev]"` de nuevo
  + reinicia el proceso `uvicorn`.
- `nexolu-pos-front`: recrea el contenedor (`npm install` limpio).

## Por qué los túneles se relanzan SIEMPRE (sin `--no-tunnel`)

Un túnel rápido de `trycloudflare.com` puede quedar **vivo en el proceso
pero colgado** después de muchas horas corriendo (se ve en el log como
`control stream encountered a failure`, reintentando en loop sin éxito
nunca). El script nunca confía en "el proceso sigue vivo": en cada corrida
mata cualquier `cloudflared` viejo (propio o huérfano) y no da un túnel
nuevo por bueno hasta confirmar con un `curl` real que responde 2xx/3xx/4xx
- ni `000` (sin conexión) ni un `5xx` del borde de Cloudflare (visto en
vivo: `530`, tunel registrado pero sin propagar todavía) cuentan como
listo. Si algo no queda respondiendo de verdad, el script termina con
código de salida distinto de cero y lo dice explícito arriba de las URLs
finales - no se queda callado.

## Qué imprime al final

```
API local:         http://localhost:8000
IA Core local:     http://localhost:8001
Comms API local:   http://localhost:8002
Frontend local:    http://localhost:5173
API tunel:          https://xxxx.trycloudflare.com
Frontend tunel:     https://yyyy.trycloudflare.com   <- abrir esto desde el celular
Login demo:        demo@nexolu.test / password123
```

El usuario demo (`demo@nexolu.test` / `password123`) es admin del negocio
**"Restaurante de prueba"** (id 5 en los datos de `sg`), elegido a propósito
porque tiene **todos** los `feature_flags` activos - es el único negocio
importado donde se puede probar cualquier módulo sin toparse con una
feature apagada. El script re-asegura esto en cada corrida (si algo movió
al usuario demo a otro negocio, lo corrige solo).

## Puertos

`nexolu-pos-api` corre con Laravel Sail, que trae su propio `compose.yaml`
con un puerto para Vite (`VITE_PORT`, pensado para el frontend legado
embebido en el monolito, que acá no se usa). Ese puerto **tiene que ser
distinto de 5173**, porque 5173 es el puerto real de `nexolu-pos-front`
(el SPA nuevo) - si coinciden, `docker compose up` falla al intentar
publicar el mismo puerto dos veces. Por eso el `.env` de `nexolu-pos-api`
debe tener `VITE_PORT=5174` (o cualquier otro que no sea 5173/8000/3306/6379).
