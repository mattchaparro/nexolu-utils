#!/usr/bin/env bash
#
# Levanta todo el stack local de Nexolu POS:
#   - nexolu-pos-api      (Laravel Sail: mysql + redis + api en :8000)
#   - nexolu-ia-core      (uvicorn, :8001)
#   - nexolu-comms-api    (uvicorn, :8002)
#   - nexolu-payments-core (uvicorn, :8003) - pasarela de pagos unificada
#     (Wompi hoy). nexolu-pos-api la alcanza via host.docker.internal, no
#     localhost, porque corre en un contenedor Sail - ver PAYMENTS_CORE_BASE_URL
#     en su .env. La primera vez que corre este script, si nexolu-pos-api/.env
#     todavia no tiene PAYMENTS_CORE_API_KEY, tambien da de alta el Merchant +
#     Integration + credencial Wompi sandbox (ver seccion 4 mas abajo).
#   - nexolu-pos-front    (Vite en contenedor node:20, :5173)
#   - 3 tuneles cloudflared (API + frontend + Payments Core), para abrir el
#     frontend desde el celular apuntando la SPA al tunel de la API (no a
#     localhost, que desde el celular no significa nada), y para poder
#     pegar el tunel de Payments Core como webhook URL en el dashboard
#     sandbox de Wompi (Wompi corre afuera, no le puede pegar a localhost).
#
# Uso:
#   bash start_local_pos.sh              Pull + rebuild de los 5 repos, y
#                                        tuneles relanzados y verificados.
#   bash start_local_pos.sh --no-tunnel  Lo mismo (pull + rebuild) pero sin
#                                        tocar los tuneles cloudflared ya
#                                        corriendo - misma URL de siempre.
#
# SIEMPRE, con o sin flag, en cada uno de los 5 repos: `git pull origin
# main` (con stash/pop automatico si hay cambios locales sin commitear, para
# no perderlos) + rebuild real:
#   - nexolu-pos-api: docker compose up -d --build
#   - nexolu-ia-core / nexolu-comms-api: pip install -e ".[dev]" de nuevo +
#     reinicia el proceso uvicorn
#   - nexolu-pos-front: recrea el contenedor (npm install limpio)
#
# La UNICA diferencia de --no-tunnel es la seccion 5 (tuneles): sin la flag,
# cada corrida mata cualquier cloudflared viejo (propio o huerfano) y
# levanta tuneles nuevos, sin darlos por buenos hasta confirmar con un curl
# real que responden - un tunel rapido de trycloudflare.com puede quedar
# "vivo" pero colgado despues de muchas horas (visto en vivo el 2026-08-11 -
# "control stream encountered a failure", loop de reconexion fallida), asi
# que nunca se reutiliza uno sin verificarlo. Con --no-tunnel esa seccion se
# salta por completo: las URLs publicas quedan exactamente como estaban.
#
# Asume que los 5 repos ya estan clonados como hermanos en este mismo
# directorio, en main, y ya pasaron por el setup inicial (composer install,
# .env con WWWUSER/WWWGROUP/APP_PORT, schema.sql cargado, venvs de los tres
# servicios Python con su .env propio - incluido PAYMENTS_MASTER_KEY y
# PROVISIONING_KEY en nexolu-payments-core/.env). Este script NO hace ese
# setup de una sola vez, salvo el provisioning del Merchant/Integration de
# Payments Core (seccion 4), que si automatiza.

set -u

NO_TUNNEL=0
for arg in "$@"; do
    case "$arg" in
        --no-tunnel) NO_TUNNEL=1 ;;
        -h|--help)
            echo "Uso: $0 [--no-tunnel]"
            echo "  Sin flags:    pull + rebuild de los 5 repos, tuneles relanzados y verificados."
            echo "  --no-tunnel:  lo mismo, pero sin tocar los tuneles cloudflared ya corriendo."
            exit 0
            ;;
        *)
            echo "Argumento desconocido: $arg (uso: $0 [--no-tunnel])" >&2
            exit 1
            ;;
    esac
done

# RAIZ es el directorio padre donde estan clonados como hermanos los 6 repos
# (nexolu-pos-api, nexolu-ia-core, nexolu-comms-api, nexolu-payments-core,
# nexolu-pos-front, nexolu-utils) - NO necesariamente el directorio de este
# archivo: este script vive en nexolu-utils/build/, dos niveles por debajo de ese padre.
# Se busca hacia arriba (hasta 3 niveles) el primero que tenga una carpeta
# nexolu-pos-api adentro, para que funcione igual si alguien lo copia o lo
# corre desde otro lado.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ=""
buscar="$SCRIPT_DIR"
for _ in 1 2 3; do
    if [ -d "$buscar/nexolu-pos-api" ]; then
        RAIZ="$buscar"
        break
    fi
    buscar="$(dirname "$buscar")"
done
if [ -z "$RAIZ" ]; then
    echo "[start-local-pos] ERROR: no encontre nexolu-pos-api cerca de $SCRIPT_DIR." >&2
    echo "[start-local-pos] Cloná los 6 repos (nexolu-pos-api, nexolu-ia-core, nexolu-comms-api, nexolu-payments-core, nexolu-pos-front, nexolu-utils) como hermanos en el mismo directorio padre - ver nexolu-utils/README.md." >&2
    exit 1
fi

RUNTIME_DIR="$RAIZ/.local-pos"
mkdir -p "$RUNTIME_DIR"

API_DIR="$RAIZ/nexolu-pos-api"
IA_CORE_DIR="$RAIZ/nexolu-ia-core"
COMMS_DIR="$RAIZ/nexolu-comms-api"
PAYMENTS_DIR="$RAIZ/nexolu-payments-core"
FRONT_DIR="$RAIZ/nexolu-pos-front"

log() { echo "[start-local-pos] $*"; }
diag() { echo "[start-local-pos] $*" >&2; }

# git pull con stash/pop automatico - no queremos que un cambio local sin
# commitear (p.ej. vite.config.ts con allowedHosts:true) bloquee el pull ni
# se pierda. Si el pop despues no puede reaplicarse solo (conflicto real),
# avisa y deja el stash guardado en vez de resolverlo el solo.
pull_repo() {
    local dir="$1" nombre="$2"
    if [ ! -d "$dir/.git" ]; then
        diag "    AVISO: $nombre no es un repo git en $dir, salto el pull."
        return
    fi
    local hizo_stash=0
    if [ -n "$(cd "$dir" && git status --short --untracked-files=no)" ]; then
        (cd "$dir" && git stash push -u -m "start_local_pos.sh autobackup") >/dev/null 2>&1
        hizo_stash=1
    fi
    local antes despues
    antes="$(cd "$dir" && git rev-parse --short HEAD 2>/dev/null)"
    if ! (cd "$dir" && git pull origin main); then
        diag "    ERROR: git pull fallo en $nombre - revisar a mano."
    fi
    despues="$(cd "$dir" && git rev-parse --short HEAD 2>/dev/null)"
    if [ "$hizo_stash" = "1" ]; then
        if ! (cd "$dir" && git stash pop) >/dev/null 2>&1; then
            diag "    AVISO: $nombre tenia cambios locales que no se pudieron reaplicar solos tras el pull (quedaron en 'git stash list' - revisar a mano)."
        fi
    fi
    if [ "$antes" != "$despues" ]; then
        log "    $nombre actualizado: $antes -> $despues"
    else
        log "    $nombre ya estaba al dia ($antes)."
    fi
}

# ---------------------------------------------------------------------------
# 1. nexolu-pos-api (Laravel Sail: mysql + redis + laravel.test en 8000)
# ---------------------------------------------------------------------------
if [ ! -d "$API_DIR" ]; then
    log "ERROR: no existe $API_DIR - clonalo primero (nexolu-pos-api, rama main)."
    exit 1
fi
if [ ! -f "$API_DIR/.env" ]; then
    log "ERROR: falta $API_DIR/.env - falta el setup inicial (ver docs/LOCAL_DATA_IMPORT.md y el historial de este chat)."
    exit 1
fi

log "1/5 nexolu-pos-api (Sail)..."
pull_repo "$API_DIR" "nexolu-pos-api"
(cd "$API_DIR" && docker compose up -d --build) || { log "ERROR: docker compose up --build fallo en nexolu-pos-api."; exit 1; }

log "    Esperando a que MySQL este healthy..."
st=""
for i in $(seq 1 30); do
    st="$(docker inspect -f '{{.State.Health.Status}}' nexolu-pos-api-mysql-1 2>/dev/null)"
    [ "$st" = "healthy" ] && break
    sleep 2
done
[ "$st" = "healthy" ] && log "    MySQL healthy." || log "    AVISO: MySQL no reporto healthy a tiempo, sigo igual."

# Los datos de MySQL viven en el volumen con nombre nexolu-pos-api_sail-mysql,
# no en el contenedor - sobreviven a docker compose stop/restart/up/--build
# (todo lo que hace este script). Este chequeo es solo por si alguna vez el
# volumen aparece vacio de verdad (docker system prune --volumes, disco
# nuevo, etc.) - avisa en vez de dejar un login roto en silencio, y de paso
# re-asegura que el usuario demo apunte al negocio 5 (Restaurante de
# prueba, con todos los feature_flags activos - ver
# docs/LOCAL_DATA_IMPORT.md) por si algo lo hubiera dejado apuntando a otro
# lado.
DB_PASSWORD_LOCAL="$(grep -E '^DB_PASSWORD=' "$API_DIR/.env" | cut -d= -f2-)"
NEGOCIOS="$(docker exec nexolu-pos-api-mysql-1 mysql -uroot -p"$DB_PASSWORD_LOCAL" -N -e 'SELECT COUNT(*) FROM businesses;' pos_saas 2>/dev/null)"
if [ -z "$NEGOCIOS" ] || [ "$NEGOCIOS" = "0" ]; then
    log "    AVISO: pos_saas no tiene datos (schema vacio o sin cargar)."
    log "    Correr: mysql -uroot -p... pos_saas < database/legacy-schema/schema.sql"
    log "    y luego: bash $API_DIR/scripts/import-sg-data.sh"
else
    RESULTADO="$(cd "$API_DIR" && docker compose exec -T laravel.test php artisan tinker --execute='
        $u = \App\Models\User::where("email", "demo@nexolu.test")->first();
        if (! $u) {
            echo "sin-usuario";
        } elseif ((int) $u->business_id !== 5) {
            $u->update(["business_id" => 5]);
            $u->syncRoles(["admin"]);
            echo "corregido";
        } else {
            echo "ok";
        }
    ' 2>/dev/null)"
    case "$RESULTADO" in
        *sin-usuario*) log "    AVISO: no existe demo@nexolu.test - correr scripts/import-sg-data.sh." ;;
        *corregido*)   log "    Usuario demo apuntaba a otro negocio - corregido a business_id=5." ;;
        *ok*)          log "    Usuario demo OK (business_id=5)." ;;
        *)             log "    AVISO: no se pudo verificar el usuario demo (revisar Sail manualmente)." ;;
    esac
fi

# ---------------------------------------------------------------------------
# 2. nexolu-ia-core (uvicorn, puerto 8001)
# ---------------------------------------------------------------------------
log "2/5 nexolu-ia-core (puerto 8001)..."
pull_repo "$IA_CORE_DIR" "nexolu-ia-core"
if [ -d "$IA_CORE_DIR/.venv" ]; then
    (cd "$IA_CORE_DIR" && .venv/bin/pip install -q -e ".[dev]")
    pkill -f "uvicorn nexolu_ia_core.main:app" 2>/dev/null
    sleep 1
    (cd "$IA_CORE_DIR" && nohup .venv/bin/uvicorn nexolu_ia_core.main:app --host 0.0.0.0 --port 8001 > "$RUNTIME_DIR/ia-core.log" 2>&1 &)
    sleep 2
    log "    Reconstruido y reiniciado, log en $RUNTIME_DIR/ia-core.log"
else
    log "    AVISO: no existe $IA_CORE_DIR/.venv - saltado (ver README de ese repo)."
fi

# ---------------------------------------------------------------------------
# 3. nexolu-comms-api (uvicorn, puerto 8002)
# ---------------------------------------------------------------------------
log "3/5 nexolu-comms-api (puerto 8002)..."
pull_repo "$COMMS_DIR" "nexolu-comms-api"
if [ -d "$COMMS_DIR/.venv" ]; then
    (cd "$COMMS_DIR" && .venv/bin/pip install -q -e ".[dev]")
    pkill -f "uvicorn nexolu_comms_api.main:app" 2>/dev/null
    sleep 1
    (cd "$COMMS_DIR" && nohup .venv/bin/uvicorn nexolu_comms_api.main:app --host 0.0.0.0 --port 8002 > "$RUNTIME_DIR/comms-api.log" 2>&1 &)
    sleep 2
    log "    Reconstruido y reiniciado, log en $RUNTIME_DIR/comms-api.log"
else
    log "    AVISO: no existe $COMMS_DIR/.venv - saltado (ver README de ese repo)."
fi

# ---------------------------------------------------------------------------
# 4. nexolu-payments-core (uvicorn, puerto 8003) - pasarela de pagos
#    unificada (Wompi hoy). Corre en el host igual que ia-core/comms-api;
#    nexolu-pos-api la alcanza via host.docker.internal (esta en un
#    contenedor Sail), no localhost - ver PAYMENTS_CORE_BASE_URL en su .env.
# ---------------------------------------------------------------------------
log "4/5 nexolu-payments-core (puerto 8003)..."
if [ ! -d "$PAYMENTS_DIR" ]; then
    log "ERROR: no existe $PAYMENTS_DIR - clonalo primero (nexolu-payments-core, rama main)."
    exit 1
fi
pull_repo "$PAYMENTS_DIR" "nexolu-payments-core"
if [ ! -d "$PAYMENTS_DIR/.venv" ]; then
    log "    AVISO: no existe $PAYMENTS_DIR/.venv - saltado (setup inicial: python3 -m venv .venv && .venv/bin/pip install -e '.[dev]', cp .env.example .env con PAYMENTS_MASTER_KEY y PROVISIONING_KEY generados - ver README de ese repo)."
else
    (cd "$PAYMENTS_DIR" && .venv/bin/pip install -q -e ".[dev]")
    pkill -f "uvicorn nexolu_payments_core.main:app" 2>/dev/null
    sleep 1
    (cd "$PAYMENTS_DIR" && nohup .venv/bin/uvicorn nexolu_payments_core.main:app --host 0.0.0.0 --port 8003 > "$RUNTIME_DIR/payments-core.log" 2>&1 &)
    sleep 2
    log "    Reconstruido y reiniciado, log en $RUNTIME_DIR/payments-core.log"

    # Provisioning automatico del Merchant + Integration + credencial Wompi
    # sandbox - SOLO la primera vez: el Core devuelve api_key/webhook_secret
    # una unica vez, al crear la Integration (no hay forma de volver a
    # pedirlos despues), asi que si nexolu-pos-api/.env ya tiene
    # PAYMENTS_CORE_API_KEY se asume que esto ya se hizo y no se toca nada.
    PAYMENTS_CORE_API_KEY_ACTUAL="$(grep -E '^PAYMENTS_CORE_API_KEY=' "$API_DIR/.env" 2>/dev/null | cut -d= -f2-)"
    if [ -n "$PAYMENTS_CORE_API_KEY_ACTUAL" ]; then
        log "    Merchant/Integration ya configurados (PAYMENTS_CORE_API_KEY presente en nexolu-pos-api/.env)."
    else
        log "    PAYMENTS_CORE_API_KEY vacio en nexolu-pos-api/.env - provisionando Merchant/Integration/Wompi en el Core..."
        WOMPI_ENV_FILE="$RUNTIME_DIR/wompi-sandbox.env"
        PROVISIONING_KEY="$(grep -E '^PROVISIONING_KEY=' "$PAYMENTS_DIR/.env" 2>/dev/null | cut -d= -f2-)"
        if [ ! -f "$WOMPI_ENV_FILE" ]; then
            diag "    AVISO: falta $WOMPI_ENV_FILE (WOMPI_PUBLIC_KEY/WOMPI_PRIVATE_KEY/WOMPI_INTEGRITY_SECRET/WOMPI_EVENTS_SECRET del comercio sandbox de Wompi) - salto el provisioning."
        elif [ -z "$PROVISIONING_KEY" ]; then
            diag "    AVISO: falta PROVISIONING_KEY en $PAYMENTS_DIR/.env - salto el provisioning."
        else
            # shellcheck disable=SC1090
            source "$WOMPI_ENV_FILE"
            json_get() { "$PAYMENTS_DIR/.venv/bin/python" -c "import json,sys; print(json.load(sys.stdin).get(\"$1\",\"\"))"; }

            MERCHANT_RESP="$(curl -s -w '\n%{http_code}' -X POST "http://localhost:8003/v1/admin/merchants" \
                -H "X-Payments-Provisioning-Key: $PROVISIONING_KEY" -H "Content-Type: application/json" \
                -d '{"name":"Nexolu POS","slug":"nexolu-pos"}')"
            MERCHANT_CODE="$(echo "$MERCHANT_RESP" | tail -1)"
            MERCHANT_BODY="$(echo "$MERCHANT_RESP" | sed '$d')"
            MERCHANT_ID=""

            if [ "$MERCHANT_CODE" = "201" ]; then
                MERCHANT_ID="$(echo "$MERCHANT_BODY" | json_get id)"
            else
                diag "    ERROR: no se pudo crear el Merchant en Payments Core (http_code=$MERCHANT_CODE, body=$MERCHANT_BODY)."
                diag "    Si ya existia de una corrida anterior incompleta, borra $PAYMENTS_DIR/nexolu_payments_core.db y volve a correr este script."
            fi

            if [ -n "$MERCHANT_ID" ]; then
                INTEGRATION_RESP="$(curl -s -w '\n%{http_code}' -X POST "http://localhost:8003/v1/admin/merchants/$MERCHANT_ID/integrations" \
                    -H "X-Payments-Provisioning-Key: $PROVISIONING_KEY" -H "Content-Type: application/json" \
                    -d '{"name":"Nexolu POS","slug":"nexolu-pos","environment":"sandbox","webhook_url":"http://localhost:8000/api/webhooks/payments-core"}')"
                INTEGRATION_CODE="$(echo "$INTEGRATION_RESP" | tail -1)"
                INTEGRATION_BODY="$(echo "$INTEGRATION_RESP" | sed '$d')"

                WOMPI_RESP="$(curl -s -w '\n%{http_code}' -X POST "http://localhost:8003/v1/admin/merchants/$MERCHANT_ID/providers/wompi" \
                    -H "X-Payments-Provisioning-Key: $PROVISIONING_KEY" -H "Content-Type: application/json" \
                    -d "{\"environment\":\"sandbox\",\"public_key\":\"$WOMPI_PUBLIC_KEY\",\"private_key\":\"$WOMPI_PRIVATE_KEY\",\"integrity_secret\":\"$WOMPI_INTEGRITY_SECRET\",\"events_secret\":\"$WOMPI_EVENTS_SECRET\"}")"
                WOMPI_CODE="$(echo "$WOMPI_RESP" | tail -1)"

                if [ "$INTEGRATION_CODE" = "201" ] && [ "$WOMPI_CODE" = "201" ]; then
                    NEW_API_KEY="$(echo "$INTEGRATION_BODY" | json_get api_key)"
                    NEW_WEBHOOK_SECRET="$(echo "$INTEGRATION_BODY" | json_get webhook_secret)"
                    sed -i "s#^PAYMENTS_CORE_API_KEY=.*#PAYMENTS_CORE_API_KEY=${NEW_API_KEY}#" "$API_DIR/.env"
                    sed -i "s#^PAYMENTS_CORE_WEBHOOK_SECRET=.*#PAYMENTS_CORE_WEBHOOK_SECRET=${NEW_WEBHOOK_SECRET}#" "$API_DIR/.env"
                    log "    Merchant 'nexolu-pos' + Integration + credencial Wompi sandbox creados. PAYMENTS_CORE_API_KEY/WEBHOOK_SECRET guardados en nexolu-pos-api/.env."
                else
                    diag "    ERROR: Merchant creado (id=$MERCHANT_ID) pero fallo la Integration (http_code=$INTEGRATION_CODE) o la credencial Wompi (http_code=$WOMPI_CODE) - revisar a mano."
                fi
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 5. nexolu-pos-front (Vite dentro de un contenedor node:20, puerto 5173)
# ---------------------------------------------------------------------------
log "5/5 nexolu-pos-front (puerto 5173)..."
if [ ! -d "$FRONT_DIR" ]; then
    log "ERROR: no existe $FRONT_DIR - clonalo primero (nexolu-pos-front, rama main)."
    exit 1
fi
if [ ! -f "$FRONT_DIR/.env" ] && [ -f "$FRONT_DIR/.env.example" ]; then
    cp "$FRONT_DIR/.env.example" "$FRONT_DIR/.env"
    log "    .env creado desde .env.example."
fi

pull_repo "$FRONT_DIR" "nexolu-pos-front"

if ! grep -q "allowedHosts" "$FRONT_DIR/vite.config.ts" 2>/dev/null; then
    log "    AVISO: vite.config.ts no tiene allowedHosts:true - el tunel del frontend puede dar 'Blocked request'."
    log "    Agregar 'server: { allowedHosts: true }' dentro de defineConfig({...}) y volver a correr este script."
fi

docker rm -f nexolu-pos-front >/dev/null 2>&1
docker run -d --name nexolu-pos-front -p 5173:5173 \
    -v "$FRONT_DIR:/app" -w /app \
    node:20 sh -c "npm install && npm run dev -- --host 0.0.0.0" >/dev/null
log "    Contenedor recreado, esperando a Vite..."
for i in $(seq 1 30); do
    docker logs nexolu-pos-front 2>&1 | grep -q "ready in" && break
    sleep 2
done

# ---------------------------------------------------------------------------
# 6. Tuneles cloudflared (API + frontend + Payments Core) - se salta por
#    completo con --no-tunnel: las URLs publicas quedan exactamente como
#    estaban. El tunel de Payments Core es el que hay que pegar en el
#    dashboard sandbox de Wompi como webhook URL (Wompi corre afuera, no
#    puede pegarle a localhost:8003) - ver el resumen final de URLs.
# ---------------------------------------------------------------------------
API_URL=""
FRONT_URL=""
PAYMENTS_URL=""
TUNELES_OK=1

if [ "$NO_TUNNEL" = "1" ]; then
    log "6/6 Tuneles cloudflared: salteados (--no-tunnel). URLs publicas sin cambios."
    API_URL="$(grep -oE '^VITE_API_BASE_URL=https://[a-zA-Z0-9.-]*' "$FRONT_DIR/.env" 2>/dev/null | sed 's/^VITE_API_BASE_URL=//')"
    FRONT_URL="$(grep -oE 'https://[a-zA-Z0-9.-]*trycloudflare\.com' "$RUNTIME_DIR/tunnel-front.log" 2>/dev/null | tail -1)"
    PAYMENTS_URL="$(grep -oE 'https://[a-zA-Z0-9.-]*trycloudflare\.com' "$RUNTIME_DIR/tunnel-payments.log" 2>/dev/null | tail -1)"
    if [ -n "$API_URL" ]; then
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$API_URL" 2>/dev/null)"
        case "$code" in
            000|5*) diag "    AVISO: el tunel de la API que ya tenias configurado no responde bien ahora mismo (http_code=$code). Correr sin --no-tunnel para renovarlo."; TUNELES_OK=0 ;;
        esac
    fi
    if [ -n "$FRONT_URL" ]; then
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$FRONT_URL" 2>/dev/null)"
        case "$code" in
            000|5*) diag "    AVISO: el tunel del frontend que ya tenias configurado no responde bien ahora mismo (http_code=$code). Correr sin --no-tunnel para renovarlo."; TUNELES_OK=0 ;;
        esac
    fi
    if [ -n "$PAYMENTS_URL" ]; then
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$PAYMENTS_URL/health" 2>/dev/null)"
        case "$code" in
            000|5*) diag "    AVISO: el tunel de Payments Core que ya tenias configurado no responde bien ahora mismo (http_code=$code). Correr sin --no-tunnel para renovarlo."; TUNELES_OK=0 ;;
        esac
    fi
else
    # Los tuneles rapidos de trycloudflare.com se cuelgan solos despues de un
    # rato largo corriendo (quedan "vivos" en el proceso pero atascados en un
    # loop de reconexion fallida contra el borde de Cloudflare - "control
    # stream encountered a failure", visto en vivo el 2026-08-11). Por eso
    # este paso no reutiliza nada: en cada corrida mata cualquier cloudflared
    # viejo (el que haya lanzado un run anterior de este script, y tambien
    # cualquier huerfano suelto) y levanta tuneles nuevos, y no los da por
    # buenos hasta confirmar con un curl real que responden.
    matar_tunel_viejo() {
        local puerto="$1"
        pkill -f "cloudflared tunnel --url http://localhost:$puerto" 2>/dev/null
        sleep 1
        pkill -9 -f "cloudflared tunnel --url http://localhost:$puerto" 2>/dev/null
    }

    lanzar_tunel_verificado() {
        local puerto="$1" logfile="$2" pidfile="$3" nombre="$4"

        matar_tunel_viejo "$puerto"
        rm -f "$pidfile"
        : > "$logfile"

        nohup cloudflared tunnel --url "http://localhost:$puerto" > "$logfile" 2>&1 &
        echo $! > "$pidfile"

        local url=""
        for i in $(seq 1 15); do
            url="$(grep -oE 'https://[a-zA-Z0-9.-]*trycloudflare\.com' "$logfile" 2>/dev/null | head -1)"
            [ -n "$url" ] && break
            sleep 1
        done

        if [ -z "$url" ]; then
            diag "    ERROR: $nombre no genero URL (revisar $logfile)."
            return 1
        fi

        # No alcanza con que cloudflared haya impreso la URL: confirmar que
        # responde de verdad antes de dar el tunel por bueno. Justo despues
        # de arrancar, el borde de Cloudflare puede devolver 000 (sin
        # conexion todavia) o un 5xx propio del edge (tunel registrado pero
        # sin propagar aun, visto en vivo: 530) - ninguno de los dos cuenta
        # como listo, solo un codigo que vino de la app real (2xx/3xx/4xx).
        local code="000"
        for i in $(seq 1 15); do
            code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null)"
            case "$code" in
                000|5*) sleep 2 ;;
                *) break ;;
            esac
        done

        case "$code" in
            000|5*)
                diag "    ERROR: $nombre levanto ($url) pero no responde bien (http_code=$code) - revisar $logfile."
                return 1
                ;;
        esac

        diag "    $nombre OK: $url (http_code=$code)"
        echo "$url"
        return 0
    }

    if ! command -v cloudflared >/dev/null 2>&1; then
        log "AVISO: cloudflared no esta instalado - salto los tuneles (frontend/API solo disponibles en localhost)."
    else
        log "6/6 Tuneles cloudflared (matando procesos viejos y verificando los nuevos)..."
        API_URL="$(lanzar_tunel_verificado 8000 "$RUNTIME_DIR/tunnel-api.log" "$RUNTIME_DIR/tunnel-api.pid" "Tunel API")" || TUNELES_OK=0
        FRONT_URL="$(lanzar_tunel_verificado 5173 "$RUNTIME_DIR/tunnel-front.log" "$RUNTIME_DIR/tunnel-front.pid" "Tunel frontend")" || TUNELES_OK=0
        PAYMENTS_URL="$(lanzar_tunel_verificado 8003 "$RUNTIME_DIR/tunnel-payments.log" "$RUNTIME_DIR/tunnel-payments.pid" "Tunel Payments Core")" || TUNELES_OK=0

        if [ -n "$API_URL" ]; then
            log "    Apuntando VITE_API_BASE_URL al tunel de la API y reiniciando el front..."
            sed -i "s#^VITE_API_BASE_URL=.*#VITE_API_BASE_URL=${API_URL}/api/v1#" "$FRONT_DIR/.env"
            docker restart nexolu-pos-front >/dev/null
            for i in $(seq 1 30); do
                docker logs nexolu-pos-front 2>&1 | tail -5 | grep -q "ready in" && break
                sleep 2
            done
            # El restart tira abajo el tunel del frontend por un instante
            # (Vite deja de responder mientras reinicia) - re-verificarlo.
            code="000"
            for i in $(seq 1 15); do
                code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$FRONT_URL" 2>/dev/null)"
                case "$code" in
                    000|5*) sleep 2 ;;
                    *) break ;;
                esac
            done
            case "$code" in
                000|5*)
                    diag "    ERROR: tunel del frontend no quedo respondiendo bien tras el restart (http_code=$code)."
                    TUNELES_OK=0
                    ;;
            esac
        fi
    fi
fi

# ---------------------------------------------------------------------------
echo
if [ "$TUNELES_OK" = "1" ]; then
    log "Listo."
else
    log "TERMINO CON ERRORES: revisar los AVISO/ERROR de arriba (tuneles)."
fi
echo "  API local:         http://localhost:8000"
echo "  IA Core local:     http://localhost:8001"
echo "  Comms API local:   http://localhost:8002"
echo "  Payments Core local: http://localhost:8003"
echo "  Frontend local:    http://localhost:5173"
[ -n "$API_URL" ]      && echo "  API tunel:          $API_URL"
[ -n "$FRONT_URL" ]    && echo "  Frontend tunel:     $FRONT_URL   <- abrir esto desde el celular"
[ -n "$PAYMENTS_URL" ] && echo "  Payments Core tunel: $PAYMENTS_URL"
[ -n "$PAYMENTS_URL" ] && echo "  Webhook Wompi:      ${PAYMENTS_URL}/v1/webhooks/wompi   <- pegar en el dashboard sandbox de Wompi"
echo "  Login demo:        demo@nexolu.test / password123"

[ "$TUNELES_OK" = "1" ] || exit 1
