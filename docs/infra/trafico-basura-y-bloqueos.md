# Tráfico basura, bloqueo de IPs y diagnóstico de "el POS está lento"

Runbook operativo del droplet `nexolu-pos-prod` (`174.138.42.118`). Nació del
incidente del **2026-09-07**, donde el negocio reportó "el POS no carga / está
lentísimo" y el diagnóstico encontró dos cosas distintas: una caída real de
segundos por un despliegue, y un bot que ocupaba el **97% del tráfico**.

> Todos los comandos de diagnóstico son de **solo lectura**. Los de bloqueo
> cambian la red de producción y están marcados como tales.

## 1. "El POS no carga": los tres primeros comandos

Antes de suponer nada, medir. Casi siempre alcanza con esto:

```bash
for u in https://new-pos.nexolu.co https://pos-backend.nexolu.co/up https://pos.nexolu.co; do
  curl -s -o /dev/null -m 15 -w "$u -> HTTP %{http_code} en %{time_total}s\n" "$u"
done
```

Sano = los tres en `200` por debajo de ~1s. Si responden bien, **no está
caído**: el problema fue transitorio (ver §2) o es del lado del cliente.

Recursos del droplet:

```bash
ssh -i ~/Personal/ssh_keys/id_ed25519 root@174.138.42.118 'uptime; free -h | head -3; df -h / | tail -1; docker ps --format "{{.Names}}\t{{.Status}}"'
```

Señales de alarma: `load average` sostenido > 2 (es 1 core), `available` de
memoria < 200 Mi, disco > 85%, o algún contenedor que no diga `Up`.

**`Up X minutes` en los contenedores de la app es un dato clave**: si son
pocos minutos, hubo un despliegue reciente y probablemente esa fue la causa.

## 2. Confirmar si fue un despliegue

Un despliegue reinicia los contenedores y el POS queda inaccesible unos
segundos. Se ve así en el log de errores de nginx:

```bash
ssh -i ~/Personal/ssh_keys/id_ed25519 root@174.138.42.118 'tail -20 /var/log/nginx/error.log'
```

```
connect() failed (111: Connection refused) while connecting to upstream ...
upstream prematurely closed connection while reading response header ...
```

Para acotar la ventana exacta (errores por minuto):

```bash
ssh -i ~/Personal/ssh_keys/id_ed25519 root@174.138.42.118 \
  'grep -oE "^[0-9/]+ [0-9]{2}:[0-9]{2}" /var/log/nginx/error.log | sort | uniq -c | tail -10'
```

Si todos los errores caen en **un solo minuto** y coinciden con el despliegue,
el caso está cerrado: no fue una caída del servicio, fue la ventana del deploy.

> **Regla operativa**: con negocios operando en vivo, desplegar antes de que
> abran o después de cerrar. Hoy el despliegue no es sin corte.

## 3. Medir el tráfico basura

El log de acceso se llena de peticiones de bots. Para ver cuánto del tráfico
es real:

```bash
ssh -i ~/Personal/ssh_keys/id_ed25519 root@174.138.42.118 '
TOTAL=$(wc -l < /var/log/nginx/access.log)
BOT=$(grep -c "/machine-" /var/log/nginx/access.log)
echo "total=$TOTAL bot=$BOT ($((BOT*100/TOTAL))%)"
grep "/machine-" /var/log/nginx/access.log | awk "{print \$1}" | sort | uniq -c | sort -rn | head -5'
```

Las IPs que más repiten son las candidatas a bloquear.

Peticiones por minuto ahora mismo (ritmo real):

```bash
ssh -i ~/Personal/ssh_keys/id_ed25519 root@174.138.42.118 \
  'M=$(date -d "1 minute ago" +"%d/%b/%Y:%H:%M"); echo "$M -> $(grep -c "$M" /var/log/nginx/access.log)"'
```

### Identificar qué es el bot antes de bloquear

Nunca bloquear a ciegas: puede ser un cliente real mal configurado. Dos
comprobaciones:

**A. Ver la línea cruda** (User-Agent y ruta completa):

```bash
ssh -i ~/Personal/ssh_keys/id_ed25519 root@174.138.42.118 'grep "/machine-" /var/log/nginx/access.log | tail -2'
```

**B. Decodificar el payload**, si trae hex (el de `?ping=` lo trae):

```bash
python3 -c "
import re, sys
h = sys.argv[1]
print(*[t.decode() for t in re.findall(rb'[ -~]{3,}', bytes.fromhex(h))], sep='\n')
" 0B04034DCB70...   # el valor de ?ping=
```

### El caso identificado (2026-09-07)

| Dato | Valor |
|---|---|
| Payload decodificado | `SSuite-5-2-20210112-085246`, `SG_-<id>`, `5.2` |
| Ruta | `/machine-<timestamp>?ping=<hex>/lossyproc?rand=<aleatorio>` |
| User-Agent | `Mozilla/15.0 ... AppleWebKit/1537.36 ... Safari/1537.36` (**falso**: los reales son `5.0` y `537.36`) |
| vhost | cae en `default`, **no** en `new-pos` ni `pos-backend` |
| IPs | `38.122.174.106`, `108.53.236.186`, `24.191.195.6` |
| Volumen | 217.856 peticiones en un día (97% del total), ~214/min |

Es el beacon de telemetría de un software llamado "SSuite". **No es un
ataque**: piden rutas que no existen y reciben 404. La hipótesis más probable
es que la IP del droplet perteneció antes a otro cliente de DigitalOcean y
esos equipos siguen reportándose a ciegas.

Que **caiga en el vhost `default`** es la prueba de que no busca a Nexolú: no
pide ninguno de nuestros dominios, entra por la IP cruda.

## 4. Bloquear IPs — ⚠️ cambia producción

**El firewall de DigitalOcean NO sirve para esto**: es lista blanca, no admite
reglas de denegación. El bloqueo va a nivel de host con `iptables`.

```bash
# ⚠️ PRODUCCIÓN
ssh -i ~/Personal/ssh_keys/id_ed25519 root@174.138.42.118 '
for ip in 38.122.174.106 108.53.236.186 24.191.195.6; do
  iptables -C INPUT -s $ip -j DROP 2>/dev/null || iptables -I INPUT -s $ip -j DROP
done
iptables -S INPUT'
```

`-C` antes de insertar hace el comando repetible sin duplicar reglas. La
política por defecto queda en `ACCEPT`: **no hay riesgo de quedarse sin SSH**.

Verificar que sirvió:

```bash
ssh -i ~/Personal/ssh_keys/id_ed25519 root@174.138.42.118 '
A=$(grep -c "/machine-" /var/log/nginx/access.log); sleep 20
B=$(grep -c "/machine-" /var/log/nginx/access.log)
echo "nuevas en 20s: $((B-A))"
iptables -L INPUT -n -v | grep DROP'
```

### Persistencia: `nexolu-block-bots.service`

Las reglas de `iptables` se pierden al reiniciar. Están persistidas con una
unidad systemd propia:

```bash
systemctl status nexolu-block-bots       # ver estado
systemctl restart nexolu-block-bots      # re-aplicar a mano
cat /etc/systemd/system/nexolu-block-bots.service
```

> ⚠️ **NO usar `iptables-persistent` en este droplet.** Se probó y se
> descartó: al guardar se lleva también las reglas que genera Docker (cadenas
> `DOCKER`, IPs de contenedores como `172.18.0.x`). Al reiniciar, restaurarlas
> puede pisar la red de los contenedores y dejar la API sin base de datos. La
> unidad systemd corre `After=docker.service` y solo toca las 3 reglas de
> `INPUT`, así que no puede romper Docker.

Para agregar una IP: editar el `for` de la unidad y `systemctl daemon-reload &&
systemctl restart nexolu-block-bots`. Para revertir todo:

```bash
# ⚠️ PRODUCCIÓN
systemctl disable --now nexolu-block-bots
for ip in 38.122.174.106 108.53.236.186 24.191.195.6; do iptables -D INPUT -s $ip -j DROP; done
```

## 5. Los despliegues no borran el bloqueo

Verificado el 2026-09-07: ni el panel (`nexolu-admin`), ni `deploy-menu.sh`,
ni los `deploy.sh` de cada servicio tocan `iptables`, `ufw` ni el firewall.
Tampoco hay `docker compose down -v` ni `docker system prune`, que sí borrarían
redes.

Los despliegues **recrean contenedores**, y Docker administra únicamente sus
propias cadenas (`DOCKER`, `FORWARD`, `nat`) — nunca las reglas de usuario en
`INPUT`, que es donde vive el bloqueo. Sobrevive a despliegues y a reinicios.

Si aun así se quisiera confirmar tras un despliegue:

```bash
ssh -i ~/Personal/ssh_keys/id_ed25519 root@174.138.42.118 'iptables -S INPUT | grep DROP'
```

## 6. Qué defensas hay y cuáles faltan

Estado al 2026-09-07:

| Defensa | Estado |
|---|---|
| Throttle en `/login`, `/register`, `/forgot-password`, `/reset-password` | ✅ desde 2026-09-07 (ver `AppServiceProvider::registerAuthRateLimiters`) |
| Bloqueo de las 3 IPs del beacon | ✅ `nexolu-block-bots.service` |
| `limit_req` / `limit_conn` en nginx | ❌ no configurado |
| fail2ban | ❌ no instalado |
| ufw | ❌ inactivo (política `ACCEPT`) |
| CDN / WAF adelante | ❌ no hay |

**Sigue siendo susceptible a un DoS**: un solo droplet de 1 core, sin nada
adelante. Lo que se cerró es el vector más barato de explotar (fuerza bruta
contra el login, que además quema CPU en bcrypt por intento). Los siguientes
pasos naturales son `limit_req` en nginx para `/api/` y fail2ban.

## 7. El droplet legacy

`nexolu` (`134.122.116.201`, donde vive `pos.nexolu.co`) **no tiene este
ruido**: 0 beacons, ~15k líneas de log. No hace falta bloquear nada ahí, pero
el diagnóstico de §1–§3 aplica igual cambiando la IP.
