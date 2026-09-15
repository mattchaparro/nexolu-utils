# Nexolú Connect — Runbook operativo de Alejandro

Todo lo que **solo tú** puedes ejecutar para llevar a producción lo construido
(fases 0–4 + iteraciones 1–3 del [tablero](../research/whatsapp-plan-implementacion.md)).
Ordenado por dependencias: cada bloque dice qué desbloquea. Los datos de Meta
salen del [análisis verificado](../research/whatsapp-capacidad-transversal.md)
(secciones B, G, I y M).

**Convención**: `[ ]` = pendiente tuyo · `(ya listo)` = el código/preparación ya existe.

---

## Bloque 1 — connect.nexolu.co en producción

*Desbloquea: operar Connect (apps, credenciales, webhooks, flujos, plantillas, catálogo) desde el navegador.*
*Detalle paso a paso: [connect-front.md](connect-front.md).*

- [ ] **DNS** (Hostinger): registro A `connect` → `134.122.19.243` (nexolu-core). *(Dijiste que lo ibas configurando — verificar con `nslookup connect.nexolu.co 8.8.8.8`.)*
- [ ] **Deploy key** del repo `nexolu-comms-front` (primero créale el remoto en GitHub y push):
  ```bash
  # en tu máquina, una vez creado el repo en GitHub:
  cd C:\Nexolu\nexolu-comms-front && git remote add origin git@github.com:mattchaparro/nexolu-comms-front.git && git push -u origin main
  ```
  Luego en el droplet: key ed25519 dedicada + alias `github.com-nexolu-comms-front` + clone a `/opt/nexolu/nexolu-comms-front-src` (receta literal en connect-front.md §2).
- [ ] **`.env` de build** en `/opt/nexolu/nexolu-comms-front-src/.env`:
  ```bash
  VITE_API_BASE_URL=https://comms.nexolu.co
  VITE_AUTH_BASE_URL=https://auth.nexolu.co
  VITE_PRIMEVUE_LICENSE_KEY=<la misma key community de nexolu-pos-front>
  ```
- [ ] Primer `bash deploy.sh` (ya listo) → nginx (`.conf` ya en nexolu-infra) → `certbot --nginx -d connect.nexolu.co`.
- [ ] **`.env` de comms-api en prod** (`/opt/nexolu/nexolu-comms-api/.env`) — el bloque del panel:
  ```bash
  PANEL_CORS_ORIGINS=https://connect.nexolu.co
  PANEL_EMAIL=<tu correo de operador>
  PANEL_PASSWORD_HASH=<bcrypt>   # python -c "import bcrypt; print(bcrypt.hashpw(b'TU_CLAVE', bcrypt.gensalt()).decode())"
  PANEL_JWT_SECRET=<aleatorio largo>   # python -c "import secrets; print(secrets.token_urlsafe(48))"
  ```
- [ ] Deploy de comms-api (`deploy-menu.sh comms-api` o su `deploy.sh`): aplica solo las **6 migraciones nuevas** (`a1c4e7f2b9d3` → `f3a7c9e254b8`: webhooks, canales, usuarios de panel, plantillas, flujos/contactos, catálogo). ⚠️ Antes verifica el asunto del MySQL local de `levantar_infra` en nexolu-core (deploy.md §problema conocido). Recuerda: `up -d --force-recreate`, nunca `restart`.
- [ ] **Prueba**: entrar a connect.nexolu.co con el login local → crear el usuario cliente de prueba si quieres → todo el panel funciona sin Meta todavía.

## Bloque 2 — SSO con auth.nexolu.co

*Desbloquea: "Entrar con Nexolú" en Connect (para ti y para clientes externos con cuenta). Sin esto el login local sigue funcionando — no es bloqueante del resto.*

- [ ] En el `.env` de **nexolu-auth** (nexolu-core): agregar el producto `nexolu-connect` a `AUTH_PRODUCTS_JSON`, con retorno a `https://connect.nexolu.co` (mismo formato que `nexolu-admin`; el fragmento de vuelta es `#auth_token=`).
- [ ] En el `.env` de **comms-api**: pegar la llave pública de auth:
  ```bash
  NEXOLU_AUTH_PUBLIC_KEYS={"<kid>":"<PEM en base64>"}   # el mismo valor que ya tiene nexolu-admin
  # (NEXOLU_AUTH_ISSUER y NEXOLU_AUTH_AUDIENCE ya tienen defaults correctos:
  #  https://auth.nexolu.co / nexolu-connect)
  ```
- [ ] Recrear comms-api y auth → probar el botón "Entrar con Nexolú".

## Bloque 3 — Meta: la App de plataforma y Tech Provider

*Desbloquea: Embedded Signup (números propios por negocio), el webhook de plataforma, y a futuro operar N clientes. Es el bloque más largo por los tiempos de revisión de Meta.*

### 3.1 Cuenta y verificación
- [ ] **Verificación de negocio de Nexolú** en Meta Business Manager (documento legal, dominio nexolu.co, teléfono). Requisito previo de todo lo demás.
- [ ] Firmar el **Tech Provider Amendment** (Meta lo presenta al declarar que onboardeas clientes). Hasta completar App Review: máximo **10 clientes onboardeados por ventana de 7 días** (luego 200).

### 3.2 La App Meta de plataforma (una sola para todo el ecosistema)
- [ ] Crear App tipo **Business** en developers.facebook.com → agregar producto **WhatsApp**.
- [ ] Anotar y poner en el `.env` de comms-api:
  ```bash
  META_PLATFORM_APP_ID=<app id>
  META_PLATFORM_APP_SECRET=<app secret>
  META_PLATFORM_WEBHOOK_VERIFY_TOKEN=<inventado por ti, aleatorio>
  ```
- [ ] Configurar el **webhook** de la app: URL `https://comms.nexolu.co/webhooks/whatsapp/platform`, verify token = el de arriba, suscrito a `messages`, `message_template_status_update`, `account_update`. *(El endpoint ya existe y exige firma — fallará cerrado hasta que META_PLATFORM_APP_SECRET esté puesto.)*
- [ ] **Facebook Login for Business**: crear la *configuración de login* para Embedded Signup (assets: WABA + phone number; versión de signup para Tech Providers) →
  ```bash
  META_LOGIN_CONFIG_ID=<config id>
  ```
- [ ] **Número de prueba** de WhatsApp (la app lo trae) para los videos del review y las primeras pruebas end-to-end.

### 3.3 App Review (acceso avanzado)
- [ ] Solicitar acceso avanzado a **`whatsapp_business_messaging`** y **`whatsapp_business_management`**. Requiere 2 screencasts: (1) enviar un mensaje, (2) crear una plantilla — ambos se pueden grabar contra el panel de Connect + número de prueba una vez el Bloque 1 esté vivo.
- [ ] Para catálogo: **`catalog_management`** y **`business_management`** (mismo proceso).
- Nota operativa por cliente (no tuya, del negocio): los **Términos de catálogo** se aceptan creando el *primer* catálogo vía Business Manager (paso manual único por negocio), y el método de pago de Meta se agrega en WhatsApp Manager del cliente.

## Bloque 4 — Credenciales de las apps en Connect

*Desbloquea: tráfico real por comms. Todo se hace desde el panel de Connect (Apps y credenciales) — o el panel admin.*

- [ ] **App `pos`**: pegar las credenciales que hoy viven en el `.env` del POS (`WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, + `waba_id`) en la credencial meta-whatsapp de la app pos, con:
  - `callback_url` = `https://pos-backend.nexolu.co/api/webhooks/nexolu-comms/whatsapp`
  - `callback_secret` = inventado por ti (el mismo va al `.env` del POS como `COMMS_CORE_WEBHOOK_SECRET`)
  - `meta_app_secret` = el de la app Meta actual del POS, y activar **"Exigir firma de Meta"**
- [ ] **App `spa`**: igual, con `callback_url` = `https://agenda-backend.nexolu.co/api/webhooks/nexolu-comms/whatsapp`. *El número del spa sigue en ManyChat: esta credencial queda lista pero sin tráfico hasta el Bloque 6.*
- [ ] **App `sga`**: crearla cuando llegue la iteración 4 (solo plantillas utility).
- [ ] Las **api_keys** que el panel te muestre al crear/rotar cada app van al `.env` de la app correspondiente como `COMMS_CORE_API_KEY`.

## Bloque 5 — Cutover del POS a comms

*Requiere: Bloques 1 y 4. Desbloquea: que el POS envíe y reciba vía Connect (y con ello: catálogo + pedidos del POS cuando quieras encenderlos).*

- [ ] `.env` del POS en prod:
  ```bash
  COMMS_CORE_BASE_URL=https://comms.nexolu.co
  COMMS_CORE_API_KEY=<la de la app pos>
  COMMS_CORE_WEBHOOK_SECRET=<el callback_secret del Bloque 4>
  MESSAGING_DRIVER=nexolu_comms
  ```
- [ ] Correr a mano las **3 migraciones nuevas** del POS (regla del repo: migrate no está en su deploy.sh):
  ```bash
  php artisan migrate:baseline   # solo si nunca corrió en ese ambiente
  php artisan migrate --force    # available_on_whatsapp, whatsapp_orders, índice clients
  ```
- [ ] En el dashboard de Meta de la app ACTUAL del POS: cambiar la URL del webhook a `https://comms.nexolu.co/webhooks/whatsapp/pos` (verify token = el `webhook_verify_token` que pusiste en la credencial de la app pos).
- [ ] Validar: mensaje entrante de prueba → aparece en Webhooks de Connect como `delivered` → llega al POS (IA responde). Envío saliente (recordatorio) → sale y queda en Notificaciones de Connect.

## Bloque 6 — Spa productivo con Connect + migración Luxury

*Requiere: Bloques 1, 3 (para número propio) y 4. Es la migración de la sección M del análisis — ruta preferida: **misma WABA, cambiar la app suscrita**.*

1. **Antes de tocar el número** *(se puede ya)*:
   - [ ] Exportar el CSV de suscriptores desde la UI de ManyChat (la API no lo permite).
   - [ ] Importarlo: `python scripts/import_manychat_contacts.py export.csv --app spa --business <id-del-negocio-luxury>` (en el droplet, dentro del contenedor de comms o con su .env).
   - [ ] Crear el flujo `post_agenda` en Connect (el panel trae el ejemplo precargado) y agregar la acción "Iniciar un flujo de WhatsApp" a la etapa *Confirmada* del workflow de Luxury (spa-front → superadmin → Workflows; el campo del flujo ya existe).
   - [ ] `.env` del spa: `COMMS_CORE_*` (Bloque 4).
2. **Fase A/B — preparación**: identificar en el Business Manager DE LUXURY la WABA que creó ManyChat (le pertenece al negocio, no a ManyChat) y confirmar acceso admin. Plantillas existentes: sincronizarlas luego desde Connect (pantalla Plantillas → Sincronizar).
3. **Fase C — el corte**:
   - [ ] Suscribir la app Meta de Nexolú a esa WABA (si el token del negocio: `POST /{waba_id}/subscribed_apps` — o vía Embedded Signup apuntando a la WABA existente, que además registra el canal propio en Connect automáticamente). **Ventana de convivencia**: ambas apps (ManyChat y Nexolú) reciben los webhooks — deliberado y corto.
   - [ ] Cuando Connect responda bien: desconectar el número en ManyChat (quitar su app de la WABA / desde ManyChat).
4. **Fase D — validación**: entrante, saliente, plantilla, flujo `post_agenda` real con una cita de prueba, difusión pequeña.
5. **Recordatorios duros del análisis**: el **historial de chats NO se transfiere** (nada lo hace); el PIN de 2 pasos lo fija Connect al registrar; display name/calidad/límites se conservan en la misma WABA.

## Bloque 7 — Referencia rápida de env vars nuevas

| Servicio | Variable | Qué es |
|---|---|---|
| comms-api | `PANEL_EMAIL` / `PANEL_PASSWORD_HASH` / `PANEL_JWT_SECRET` / `PANEL_CORS_ORIGINS` | Sesión del panel Connect (break-glass + CORS) |
| comms-api | `NEXOLU_AUTH_PUBLIC_KEYS` (+ issuer/audience con defaults) | SSO con auth.nexolu.co |
| comms-api | `META_PLATFORM_APP_ID` / `META_PLATFORM_APP_SECRET` / `META_PLATFORM_WEBHOOK_VERIFY_TOKEN` / `META_LOGIN_CONFIG_ID` | App Meta de plataforma (Embedded Signup + webhook de números propios) |
| comms-front (build) | `VITE_API_BASE_URL` / `VITE_AUTH_BASE_URL` / `VITE_PRIMEVUE_LICENSE_KEY` | Horneadas al compilar; deploy.sh las exige |
| pos-api | `MESSAGING_DRIVER=nexolu_comms` + `COMMS_CORE_BASE_URL/API_KEY/WEBHOOK_SECRET` | Cutover a Connect |
| spa-api | `COMMS_CORE_BASE_URL/API_KEY/WEBHOOK_SECRET` | Envío + flujos vía Connect |
| nexolu-auth | `AUTH_PRODUCTS_JSON` += `nexolu-connect` | Producto del SSO |

## Bloque 8 — Llaves SSH / deploy keys

Solo hay UNA nueva: la deploy key de **nexolu-comms-front** en nexolu-core (Bloque 1). Todo lo demás usa las que ya existen. Patrón: key ed25519 dedicada por repo, alias en `~/.ssh/config` del droplet, deploy key de **solo lectura** en GitHub.

## Orden sugerido

```
1 (panel en prod) ──► 2 (SSO)          ← independientes entre sí después del 1
      │
      ├──► 4 (credenciales apps) ──► 5 (cutover POS)
      │
      └──► 3 (Meta/Tech Provider) ──► 6 (Luxury)     ← 6.1 se puede hacer YA
```

Lo único con espera externa real es el Bloque 3 (revisiones de Meta: días a semanas) — por eso conviene arrancarlo en paralelo apenas exista el panel para grabar los videos.
