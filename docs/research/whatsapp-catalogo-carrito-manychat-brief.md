# Nexolú + WhatsApp Business Platform: Catálogo, Carrito, Pedidos e Integración POS

> Brief de investigación escrito por Alejandro (2026-09-14). Se guarda tal
> cual lo redactó, para que la conversación que lo trabaje lo lea completo.
> El contexto que el brief NO tiene (lo que ya existe en el ecosistema) está
> al final, en "Anexo: lo que ya existe".

## Objetivo

Quiero investigar y diseñar la integración entre **Nexolú POS** y **WhatsApp Business Platform / WhatsApp Cloud API de Meta**, con especial foco en:

1. Catálogos de productos de WhatsApp.
2. Creación y administración del catálogo directamente desde Nexolú POS.
3. Sincronización de productos, precios, imágenes, disponibilidad y demás información entre Nexolú y Meta.
4. Productos individuales y múltiples productos enviados por WhatsApp.
5. Carrito de WhatsApp.
6. Recepción de carritos/pedidos en Nexolú.
7. Conversión automática de una conversación de WhatsApp en un pedido/venta del POS.
8. Integración con **Nexolú IA** para que la IA pueda consultar catálogo, inventario, precios y preparar pedidos.
9. Arquitectura multiempresa/multitenant.
10. Migración de números de WhatsApp que actualmente están conectados a **ManyChat** hacia el Core de Nexolú.
11. Caso real inicial: **Luxury Nails Spa & Boutique**, cuyo número de WhatsApp actualmente está conectado a ManyChat y eventualmente debería pasar a la infraestructura de WhatsApp de Nexolú.

> **IMPORTANTE:** No asumir que una capacidad existe. Investigar la documentación oficial y vigente de Meta antes de definir endpoints, permisos o arquitectura. Priorizar documentación oficial de Meta/WhatsApp Business Platform.

---

# 1. Contexto de Nexolú

Nexolú es una plataforma que busca evolucionar hacia una suite de: POS, Restaurantes, Eventos, Software empresarial, Automatización, IA, WhatsApp.

Stack actual/principal: Laravel, Vue 3, Tailwind, MySQL; API propia en proceso de separación/migración; Core de IA separado, inicialmente basado en OpenRouter/LLM; Jobs/queues para procesos asíncronos.

La visión es que WhatsApp sea una extensión real del negocio:

```text
                    NEXOLÚ
                       |
          +------------+------------+
          |            |            |
         POS       Nexolú IA     WhatsApp
          |            |            |
          +------------+------------+
                       |
                    Cliente
```

La idea no es construir simplemente un chatbot. La idea es: Nexolú POS + Inventario + Catálogo + WhatsApp + IA + Pedidos.

# 2. Idea principal

```text
Nexolú POS
    | productos, precios, imágenes, inventario, disponibilidad
    v
Nexolú WhatsApp Integration
    v
Meta / WhatsApp Business Platform
    v
Catálogo de WhatsApp
    v
Cliente: explora productos, agrega productos, crea carrito
    v
WhatsApp
    v
Webhook de Nexolú
    v
Nexolú
    +--> validar productos
    +--> validar precios
    +--> validar inventario
    +--> calcular total
    +--> aplicar promociones
    +--> crear pedido
    +--> reservar/descontar inventario
    +--> enviar confirmación
    +--> imprimir/enviar a cocina
```

La fuente de verdad debe ser Nexolú, no el catálogo de Meta. Meta/WhatsApp debe funcionar principalmente como canal de presentación e interacción.

# 3. Catálogo de productos

Investigar exactamente qué permite actualmente WhatsApp Business Platform / Cloud API.

## 3.1 ¿Puede Nexolú crear un catálogo?

Desde mi propio backend, ¿puedo: crear un catálogo; asociarlo a una cuenta de WhatsApp Business; crear, actualizar, eliminar/desactivar productos; actualizar precio, descripción, imágenes, URL, categoría; definir `retailer_id`; consultar productos y catálogos; sincronizar inventario/disponibilidad si Meta lo permite; administrar variantes; administrar productos con opciones/modificadores?

Distinguir claramente entre: lo que se puede hacer por API; lo que sólo se puede hacer desde Commerce Manager / WhatsApp Manager; lo que requiere permisos especiales; lo que depende del tipo de cuenta; lo que Meta ya no permite; lo que está limitado por región/cuenta.

# 4. Modelo de producto de Nexolú

```text
Product: id, business_id, name, description, price, image, sku / retailer_id,
         category_id, active, stock, track_inventory, available_on_whatsapp

whatsapp_catalog_products: id, business_id, product_id, catalog_id,
         meta_product_id, retailer_id, sync_status, last_synced_at,
         last_error, created_at, updated_at
```

Investigar si esta estructura es suficiente o si debería incluir más campos.

# 5. Sincronización

Nexolú es la fuente de verdad. Ejemplo: el administrador cambia "Granizado de Mango $8.000 → $9.000" y Nexolú dispara `ProductUpdated → Queue → WhatsAppCatalogSyncJob → Meta`.

Investigar: endpoint de Meta; identificadores necesarios; si la actualización es inmediata; rate limits; qué pasa si Meta falla; retry; idempotencia; detección de productos desincronizados; sincronización inicial masiva; reconciliación periódica.

# 6. ¿Puede Nexolú crear el catálogo desde el POS?

MUY importante. La experiencia deseada: `POS → Configuración → WhatsApp → Conectar WhatsApp → Crear catálogo → Sincronizar productos → Sincronización automática ON`. El usuario del POS NO debería tener que entrar a Meta cada vez que cree un producto. Si no es 100% posible, definir exactamente qué pasos manuales quedan.

# 7. Productos enviados por WhatsApp

Formatos actuales para enviar: producto individual; múltiples productos; lista/productos agrupados; catálogo completo; carrito; mensajes interactivos de producto. Ejemplos reales de payloads actuales de Cloud API. **NO inventar payloads.**

# 8. Carrito de WhatsApp

1. ¿El cliente puede agregar productos del catálogo al carrito?
2. ¿El carrito llega a nuestro webhook?
3. ¿Qué información recibe Nexolú?
4. ¿Llega `retailer_id`? 5. ¿Cantidad? 6. ¿Precio? 7. ¿Catálogo? 8. ¿Variantes?
9. ¿Soporte para notas?
10. ¿Se puede modificar el carrito desde la API?
11. ¿Se puede confirmar automáticamente?
12. ¿Existe un concepto oficial de "order"?
13. ¿WhatsApp procesa el pago o sólo genera el carrito/pedido?
14. ¿Limitaciones?

Mostrar un ejemplo real del webhook/documentación.

# 9. Pedido en Nexolú

`Cliente → WhatsApp → Webhook → Parsear carrito → Mapear retailer_id → Producto Nexolú → Validar (activo, precio, inventario, sede) → Crear Order`.

```text
Order: id, business_id, customer_id, source=whatsapp, whatsapp_message_id,
       whatsapp_phone, status, subtotal, discount, tax, total
OrderItem: order_id, product_id, quantity, unit_price, discount, total
```

# 10. WhatsApp + Nexolú IA

Nexolú IA como capa conversacional sobre el POS. Ejemplo: "Quiero algo para 4 personas, máximo 60 mil" → la IA consulta productos, inventario, precios, promociones; recomienda; muestra productos reales del catálogo; prepara un pedido; **pide confirmación antes de una acción irreversible**; al confirmar llama `create_order()`.

# 11. IA y herramientas

Extender el patrón existente (`preparar_gasto()`, `preparar_entrada_inventario()`) a: `buscar_productos`, `consultar_producto`, `consultar_stock`, `consultar_precios`, `consultar_promociones`, `preparar_pedido`, `agregar_producto_pedido`, `calcular_pedido`, `confirmar_pedido`, `cancelar_pedido`. Separación explícita entre **read tools** y **write tools**; las de escritura requieren confirmación.

# 12. WhatsApp como frontend de Nexolú IA

WhatsApp no debería tener la lógica de negocio. La lógica vive en Nexolú/Core.

# 13. Multiempresa / SaaS

Cada negocio (Restaurante XYZ, Estación Polar, Luxury Nails) con su propia WABA y su propio catálogo. Investigar: Business Manager, Meta Business Account, WABA, Phone Number, Catalog, System User, Access Token, Embedded Signup, BSP, Tech Provider, Embedded Signup for Tech Providers, App Review, Permissions. Determinar el modelo adecuado para Nexolú.

# 14. Punto CRÍTICO: ManyChat

Luxury Nails Spa & Boutique: el número está conectado a ManyChat. Al migrar el spa a Nexolú, ese mismo número debe quedar administrado por la infraestructura de WhatsApp de Nexolú.

¿Cómo migrar el número sin perderlo ni, idealmente, la continuidad del negocio? Investigar: cómo se conecta ManyChat + WhatsApp; si ManyChat usa Cloud API, BSP o configuración propia; qué pasa con la WABA y con el número; si el número puede pasar a otra app/proveedor; proceso de migración; si hay que desvincular ManyChat primero; historial, contactos, plantillas, catálogos, display name; downtime; re-verificación del negocio; costos; restricciones; coexistence; mantener ManyChat temporalmente; webhooks; automatizaciones existentes.

**No asumir que "migrar el número" es cambiar un token.** Entender qué entidad de Meta controla hoy el número y qué tendría que cambiar.

# 15. Arquitectura deseada para migración

```text
ANTES:   Cliente → WhatsApp → ManyChat → Luxury Nails
DESPUÉS: Cliente → WhatsApp → Meta Cloud API → Nexolú WhatsApp Core
                                                 +--> Nexolú IA
                                                 +--> Nexolú API
                                                 +--> Luxury Nails (Spa)
```

# 16. ¿Nexolú debería convertirse en BSP?

No asumirlo. Diferenciar: Cloud API directo; usar un BSP; ser Tech Provider; ser Solution Partner/BSP; Embedded Signup; gestionar múltiples WABAs de clientes. Cuál es la arquitectura más realista para Nexolú **hoy**, evitando complejidad innecesaria.

# 17. Embedded Signup

`Nexolú → "Conectar WhatsApp" → Meta Embedded Signup → Login, Business, WABA, número → Nexolú recibe IDs/tokens`. Determinar: requisitos, permisos, App Review, verificación de negocio, qué credenciales almacenar y cuáles nunca, seguridad, expiración/refresh, desconectar, reconectar, rotar.

# 18. Seguridad

Almacenamiento seguro de access tokens, WABA ID, Phone Number ID, Business ID, Catalog ID, credenciales de la Meta App. Buenas prácticas actuales de Meta.

# 19. Webhooks

Eventos relevantes: mensajes entrantes, estados, interactivos, carritos, pedidos, errores, cambios de catálogo si existen, cambios de cuenta/número, plantillas. Arquitectura: `Meta → Webhook Nexolú → verificar firma → persistir evento crudo → Job → {Message,Cart,Order,Status}Processor`. Idempotentes.

# 20. Jobs / Queues

`SyncWhatsAppProductJob, SyncWhatsAppCatalogJob, ProcessWhatsAppMessageJob, ProcessWhatsAppCartJob, ProcessWhatsAppOrderJob, SendWhatsAppMessageJob, SendWhatsAppProductJob, SendWhatsAppTemplateJob`. Qué debe ser síncrono y qué asíncrono.

# 21. Modelo de datos recomendado

Como mínimo: `businesses, whatsapp_accounts, whatsapp_phone_numbers, whatsapp_catalogs, whatsapp_catalog_products, whatsapp_messages, whatsapp_conversations, whatsapp_webhook_events, whatsapp_templates, customers, products, categories, inventory, orders, order_items`. Relaciones: `Business → WhatsAppAccount → {PhoneNumber, Catalog → CatalogProducts}`.

# 22. Customer matching

Número de WhatsApp → Cliente de Nexolú. Reutilizar si existe; crear si no. Qué datos da WhatsApp y cuáles no.

# 23. Inventario

El catálogo de WhatsApp no debe vender lo que Nexolú sabe que está agotado. ¿Se puede ocultar/desactivar por API? ¿Modificar disponibilidad? ¿Meta tiene inventario propio? ¿Sincronizar stock o validar al crear el pedido? Comparar.

# 24. Precio

El precio de WhatsApp puede quedar desactualizado. Nexolú es la autoridad final: si no coincide, pedir confirmación al cliente.

# 25. Promociones

¿El catálogo de Meta soporta promociones/precios especiales? El cálculo definitivo lo hace Nexolú.

# 26. Variantes / modificadores

Fundamental para restaurante (pan, proteína, adiciones). ¿WhatsApp Catalog soporta variantes, opciones, modificadores, customization, cantidades? Si no, proponer IA/mensajes interactivos y luego `OrderItem` con modifiers en Nexolú.

# 27. Estación Polar (caso de prueba)

Granizados (mango, fresa, maracuyá, mora, lulo), helados, onces; eventualmente "arma tu granizado". ¿El catálogo representa esto o conviene producto base → flujo IA/interactivo → personalización → pedido?

# 28. Luxury Nails (caso distinto)

Servicios: Semi, Semi Rubber, Retoque Acrigel, Press On, Pedicure, Cejas, Pestañas. No hay "inventario de productos" (aunque sí vende algunos productos). Flujo: catálogo → servicios → cliente → **agendar cita**. ¿El catálogo de WhatsApp sirve para servicios o es mejor mensajes interactivos? El número está en ManyChat. **Primer caso real de migración.**

# 29. Costos

Conversaciones/mensajes por categoría (marketing, utility, authentication, service), plantillas, iniciados por usuario vs negocio, catálogo, Cloud API, BSP si aplica. **Precios vigentes, no antiguos.**

# 30. Límites

Rate limits, mensajes, catálogo, productos, llamadas API, webhooks, por WABA, por número, templates, envío.

# 31. Observabilidad

Métricas (`whatsapp_messages_received/sent, whatsapp_api_errors, whatsapp_webhook_errors, catalog_sync_*, orders_created/failed_from_whatsapp, ai_conversations, ai_orders`) y trazabilidad por `business_id, phone_number_id, conversation_id, message_id, order_id`.

# 32–34. Arquitectura y separación de responsabilidades

Evitar un "WhatsApp service" gigante. Módulos: `WhatsAppAccountService, WhatsAppCatalogService, WhatsAppMessagingService, WhatsAppWebhookService, WhatsAppConversationService, WhatsAppOrderService, WhatsAppTemplateService, WhatsAppCustomerService`, sobre un `MetaGraphApiClient` de bajo nivel (`request/get/post/delete`). Nada de llamadas a Graph API dispersas.

# 35–38. Flujos

- **Conexión**: admin → configuración → WhatsApp → Embedded Signup → OAuth → WABA + número → guardar → webhook activo.
- **Catálogo**: crear producto → `available_on_whatsapp` → Sync Job → Meta → publicado; actualizar nombre/descripción/precio/imagen/estado/disponibilidad automáticamente si Meta lo permite.
- **Pedido**: cliente → catálogo → carrito → webhook → Nexolú (customer, product, inventory, price) → Order → POS.
- **IA**: cliente → webhook → Nexolú IA (search_products, check_stock, check_prices, prepare_order) → confirmación → create_order.

# 39. Migración ManyChat → Nexolú: plan operativo

- **Fase A — Preparación**: Meta Business, Meta App, Cloud API, webhooks, WABA actual, propietario del número, cómo está conectado ManyChat, templates, automatizaciones.
- **Fase B — Nexolú listo**: backend, webhook, tokens, Phone Number ID, WABA, testing, templates, IA, catálogo.
- **Fase C — Migración**: qué hacer exactamente en Meta/ManyChat.
- **Fase D — Validación**: entrante, saliente, template, respuesta automática, multimedia, catálogo, pedido, webhook, IA.
- **Fase E — Producción**.

# 40. Pregunta crítica sobre historial

Si un número se mueve de ManyChat a Nexolú, ¿qué pasa con el historial? Diferenciar: historial en el teléfono, de WhatsApp, en ManyChat, contactos de ManyChat, datos en Meta, datos que Nexolú tendría que importar. **No asumir que se transfiere.**

# 41. Pregunta crítica sobre coexistencia

¿Se puede mantener temporalmente ManyChat + Nexolú con el mismo número? Si existe WhatsApp Coexistence: qué es, requisitos, limitaciones, si sirve para ManyChat, para Cloud API, si es recomendable, si duplica respuestas/webhooks.

# 42. Resultado esperado

A. Resumen ejecutivo (10–15 puntos). B. Qué SÍ puede hacer Nexolú. C. Qué NO. D. Arquitectura recomendada con diagrama. E. Modelo de datos. F. Endpoints Meta necesarios con documentación oficial. G. Permisos Meta. H. Payloads confirmados por documentación oficial. I. Flujo Embedded Signup. J. Flujo catálogo. K. Flujo carrito/pedido. L. Flujo IA. M. Migración ManyChat → Nexolú paso a paso. N. Riesgos. O. Plan: **MVP** (conectar un negocio), **V2** (catálogo + carrito + pedidos), **V3** (IA + automatización + multi-tenant).

# 43. Fuentes

Prioridad absoluta: documentación oficial de Meta, WhatsApp Business Platform, Graph API, y ManyChat. Secundarias sólo para complementar. Para cada capacidad importante: `Capacidad / Estado (Sí/No/Condicionado) / Fuente oficial / Requisitos / Permisos / Limitaciones`.

# 44. Pregunta final

¿Puedo construir en Nexolú un módulo de WhatsApp donde un negocio conecte su número, cree y gestione su catálogo desde Nexolú, sincronice automáticamente productos/precios/disponibilidad, reciba carritos/pedidos y permita que Nexolú IA atienda y convierta la conversación en una venta?

¿Puedo tomar el número de Luxury Nails que hoy usa ManyChat y migrarlo a Nexolú conservando el número, y qué pasos exactos debo seguir?

Si la respuesta es "sí, pero…", explicar exactamente el "pero". Si algo no es posible, la alternativa técnicamente más cercana.

# 45. Principio de diseño

WhatsApp es un canal de Nexolú, no el centro. Nexolú es la fuente de verdad. El catálogo de Meta es una superficie comercial del catálogo de Nexolú. El pedido, el inventario y la lógica terminan en Nexolú. La IA usa herramientas de Nexolú. Para el cliente del POS debe ser tan sencillo como "Conecta tu WhatsApp".

---

# Anexo: lo que ya existe (añadido por la sesión del Spa, 2026-09-14)

Esto no estaba en el brief y cambia varias respuestas. **Verificar en código antes de dar nada por hecho.**

- **Alcance ampliado por Alejandro**: la integración debe servir para **todas** las apps de Nexolú — POS (`nexolu-pos-api`), Spa (`nexolu-spa-api`, el reemplazo de la app de Luxury Nails, ya en producción en `agenda.nexolu.co`) y el colegio (`sga-api`). Diseñarla por **capacidad** (mensajería, plantillas, identidad de número, catálogo, comercio), no por app.
- **`nexolu-comms-api` ya existe y está en producción** (`comms.nexolu.co`, FastAPI): envío multicanal (`POST /v1/notifications/send`), credenciales de proveedor por app cifradas con Fernet, webhooks de Meta recibidos en `/webhooks/whatsapp/{app_id}` y reenviados con HMAC a cada app. Sin tráfico de negocio aún: el POS sigue con `MESSAGING_DRIVER=whatsapp_direct`. Docs: `nexolu-utils/docs/apis/comms-api.md` y `nexolu-utils/docs/integrations/whatsapp-comms.md`. Es el candidato natural a "Nexolú WhatsApp Core"; lo que le falta es catálogo, comercio y Embedded Signup.
- **`manychat-mcp` ya existe** (`C:\Nexolu\manychat-mcp`, 18 herramientas sobre la API de ManyChat: suscriptores, tags, custom fields, flows, envío). Sirve para (a) que el Spa dispare los flows de ManyChat mientras el número siga allá, sin tocar el legacy, y (b) exportar contactos y tags antes de migrar el número.
- **Nexolú IA** ya tiene el patrón de herramientas: `nexolu-utils/docs/integrations/ia-core-tools.md` y el repo `nexolu-ia-core`.
- **Necesidades reales por app**:
  - POS: el brief completo (catálogo, carrito, pedidos, variantes).
  - Spa: servicios + agendamiento público (`agenda.nexolu.co/<slug>`), encuestas al completar, difusiones segmentadas (`app/Services/Messaging/BroadcastService.php`, `app/Support/Clients/Segmento.php`), fidelización. Ya tiene productos con inventario. El número de Luxury Nails está en ManyChat y hoy el nuevo sistema sólo **lee** del legacy (`LecturaSolamente`).
  - SGA (colegio): notificaciones utility a familias. 6 de cada 10 familias sin teléfono ni correo en el dump real — el cuello es el dato, no el canal.
- **Restricciones vigentes de Alejandro**: no tocar `pos-saas` ni `spa_app` en producción; los empleados del spa no pueden ver datos de clientes; el droplet legacy (`134.122.116.201`, 1 vCPU) comparte MySQL y php-fpm con producción.
