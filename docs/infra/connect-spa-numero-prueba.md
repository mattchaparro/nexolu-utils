# Probar Connect + Spa + IA con el número de prueba de Meta

Objetivo: escribirle por WhatsApp de verdad al sistema completo — flujos de
Connect para lo estructurado, el bot (ia-core) para el texto libre — sin
tocar el número real del local (sigue en ManyChat).

## Ya está hecho y verificado en producción (2026-09-17)

- **Código desplegado**: comms-api (coordinación flujo/bot, bandeja Chat,
  salientes API en el hilo), spa-api (relevo `flow_notify`,
  `GET /api/connect/disponibilidad`), spa-front (notas internas ámbar).
- **App `spa` registrada** en comms.nexolu.co y en ia.nexolu.co
  (`base_url=https://agenda-backend.nexolu.co`, catálogo de tools refrescado).
- **`.env` del spa en prod cableado** (respaldo `.env.bak-*` en el servidor):
  `COMMS_CORE_BASE_URL/API_KEY/TOOLS_KEY`, `IA_CORE_BASE_URL/API_KEY`.
  `COMMS_CORE_WEBHOOK_SECRET` ya existía.
- Probado con curl desde prod: spa→comms 200, spa→ia-core 200,
  ia-core→spa (catálogo de tools) 200, disponibilidad con llave → catálogo
  real de Luxury.
- Circuito completo verificado en local con IA real (Gemini): "menu" →
  responde el flujo y el bot calla; texto libre → responde el bot con la
  tool de disponibilidad; todo el hilo visible en la bandeja de Connect.

## Lo único que falta (es de Meta, solo tú puedes)

1. **Número de prueba**: developers.facebook.com → tu app → WhatsApp → API
   Setup. Anota el `phone_number_id` y el token temporal (dura 24h). Agrega
   tu celular como destinatario verificado.
2. **Credencial en Connect** (connect.nexolu.co → Apps y credenciales →
   spa → WhatsApp): `phone_number_id`, `access_token`, `meta_app_secret`
   (App Secret del dashboard) y un `webhook_verify_token` que inventes.
   **Deja callback URL/secret en blanco y avísale a Claude**: los sincroniza
   con el secreto que ya tiene el spa (`callback_url` =
   `https://agenda-backend.nexolu.co/api/webhooks/nexolu-comms/whatsapp`).
3. **Webhook en Meta**: WhatsApp → Configuration → callback
   `https://comms.nexolu.co/webhooks/whatsapp/spa`, el verify token del
   paso 2, suscribir el campo `messages`.
4. **Asignar el número al negocio de pruebas** — "Luxury Nails (PRUEBAS)",
   id 2 — (Claude puede hacerlo con el `phone_number_id`):
   `businesses.whatsapp_phone_number_id = <phone_number_id>` (forceFill a
   propósito, no hay formulario).

## Qué probar desde tu celular

- **"menu"** → responde el FLUJO de Connect (crear `menu_servicios` en el
  builder con keyword `menu`: lista de categorías + "Hablar con alguien").
  El bot no dice nada.
- **Texto libre** ("¿tienen agenda mañana para semipermanente?") → responde
  el BOT y agenda de verdad en 2-3 mensajes (el negocio tiene varias sedes:
  te va a preguntar cuál).
- **"Hablar con alguien"** en la lista (nodo Acciones con `notify_app`) →
  bot en pausa + nota ámbar en la bandeja del spa, y correo si el nodo
  lleva `emails`.
- **connect.nexolu.co/chat** → todo el hilo (tú, flujo, bot) y responder
  desde ahí.

## Flujo con disponibilidad en vivo (opcional)

Nodo Acciones → Solicitud externa:
`GET https://agenda-backend.nexolu.co/api/connect/disponibilidad?negocio=2&servicio={{contact.fields.servicio}}&fecha=manana&sede=<sede>`
con header `Authorization: Bearer <COMMS_CORE_TOOLS_KEY del .env del spa>` y
`save: {"horarios": "resumen"}`; el siguiente mensaje muestra
`{{contact.fields.horarios}}`. Siempre responde 200 con `resumen` en
español (errores incluidos: "No existe el servicio X. Los que hay: …").

## Gotchas

- Token de prueba caduca en 24h: si todo deja de enviar con
  `Authentication Error`, es eso.
- El bot piensa en la cola: el contenedor `nexolu-spa-worker` debe estar
  arriba (lo está).
- Cambios de `.env` del spa: `bash deploy.sh recrear` (no `docker restart`).
- comms en prod: migraciones con `docker compose exec comms-api alembic
  upgrade head` (el build no las corre).
- La suite de spa-api tiene 49 fallos PREEXISTENTES por una fecha fija
  vencida en `SchedulingScenario::wednesday()` — no son de esta integración.
