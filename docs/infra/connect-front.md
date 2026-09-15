# Alta de `connect.nexolu.co` (Nexolú Connect) en `nexolu-core`

Runbook del primer despliegue del panel de Connect (`nexolu-comms-front`).
El patrón es el mismo de `tienda.nexolu.co` ([DEPLOY_STORE_FRONT.md](../../../nexolu-infra/docs/DEPLOY_STORE_FRONT.md)):
build estático con releases atómicas, servido por el nginx del host. Los
pasos 1, 2 y 6 los ejecuta Alejandro (DNS, deploy key, secretos); el resto
está automatizado en `nexolu-comms-front/deploy.sh` y `deploy-menu.sh`.

Droplet: **`nexolu-core` (134.122.19.243)** — el mismo de `comms.nexolu.co`,
a propósito: es el panel de esa API y caen/se levantan juntos. El legacy de
1 vCPU quedó descartado (comparte MySQL/php-fpm con `pos.nexolu.co`).

## 1. DNS (Hostinger)

Registro **A**: `connect` → `134.122.19.243`. Verificar propagación antes
de seguir (certbot valida por HTTP-01 y falla sin el A publicado):

```bash
nslookup connect.nexolu.co 8.8.8.8
```

## 2. Deploy key + clone en el droplet

En `nexolu-core`, igual que store-front (receta completa en
`nexolu-infra/docs/DEPLOY_STORE_FRONT.md` §"Alta en un droplet nuevo"):

```bash
ssh root@134.122.19.243
ssh-keygen -t ed25519 -f ~/.ssh/deploy_nexolu-comms-front -N "" -C "deploy nexolu-comms-front"
cat >> ~/.ssh/config <<'EOF'
Host github.com-nexolu-comms-front
    HostName github.com
    IdentityFile ~/.ssh/deploy_nexolu-comms-front
    IdentitiesOnly yes
EOF
cat ~/.ssh/deploy_nexolu-comms-front.pub   # -> GitHub repo nexolu-comms-front > Settings > Deploy keys (solo lectura)
git clone git@github.com-nexolu-comms-front:mattchaparro/nexolu-comms-front.git /opt/nexolu/nexolu-comms-front-src
mkdir -p /opt/nexolu/nexolu-comms-front/releases
```

## 3. `.env` de build (en `/opt/nexolu/nexolu-comms-front-src/.env`)

```bash
VITE_API_BASE_URL=https://comms.nexolu.co
VITE_AUTH_BASE_URL=https://auth.nexolu.co
VITE_PRIMEVUE_LICENSE_KEY=<la misma key community de nexolu-pos-front>
```

`deploy.sh` valida las tres **antes** de compilar (la lección del
2026-09-07: sin `VITE_AUTH_BASE_URL` la app compila y sale sin el botón de
SSO, sin ningún error visible).

## 4. Primer deploy

Desde cualquier máquina con SSH al droplet (o desde el droplet vía
`deploy-menu.sh comms-front`):

```bash
cd nexolu-comms-front && bash deploy.sh
```

Compila en el servidor (`node:22-alpine`, topes de memoria/CPU, nice/ionice)
y publica en `/opt/nexolu/nexolu-comms-front/releases/<ts>/` con swap
atómico de `current`. El aviso de "no hay release anterior" en el primer
deploy es esperable.

## 5. nginx + certbot

```bash
cp /opt/nexolu/nexolu-infra/nginx/connect.nexolu.co.conf /etc/nginx/sites-available/connect.nexolu.co
ln -s /etc/nginx/sites-available/connect.nexolu.co /etc/nginx/sites-enabled/
certbot --nginx -d connect.nexolu.co
nginx -t && systemctl reload nginx
```

(El `.conf` ya trae las líneas SSL; certbot las completa/valida igual.)

## 6. comms-api: panel + CORS (en `/opt/nexolu/nexolu-comms-api/.env`)

```bash
PANEL_CORS_ORIGINS=https://connect.nexolu.co
PANEL_EMAIL=<correo del operador>
PANEL_PASSWORD_HASH=<bcrypt>   # python -c "import bcrypt; print(bcrypt.hashpw(b'...', bcrypt.gensalt()).decode())"
PANEL_JWT_SECRET=<aleatorio largo>
# SSO (cuando nexolu-auth tenga registrado el producto nexolu-connect):
# NEXOLU_AUTH_PUBLIC_KEYS={"<kid>":"<PEM en base64>"}
```

Y aplicar — **nunca `restart`** (no relee `env_file:`):

```bash
cd /opt/nexolu/nexolu-comms-api && bash deploy.sh
# (o solo recrear si no hay código nuevo:)
cd /opt/nexolu/nexolu-infra && docker compose up -d --force-recreate comms-api
```

El deploy de comms-api ya corre `alembic upgrade head` en contenedor
efímero — trae 5 migraciones nuevas de Connect (webhooks/canales/usuarios/
plantillas/flujos/catálogo). ⚠️ Antes del primer deploy en core, verificar
el asunto del MySQL local de `levantar_infra` (deploy.md §problema
conocido).

## 7. Verificación

```bash
curl -I https://connect.nexolu.co/          # 200, Cache-Control: no-store en index
```

En el navegador: login local del operador → dashboard con uso → `Salir`.
Rollback si algo sale mal: `bash deploy.sh rollback`.
