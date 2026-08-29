# La estrategia "Core": infraestructura compartida entre productos

> Apto para exportar a Drive / NotebookLLM — arquitectura conceptual, sin
> IPs, credenciales ni detalles operativos.

## El problema que resuelve

Cada producto de software para negocios termina necesitando las mismas
tres cosas: una forma de asistir al usuario con IA, una forma de
comunicarse con sus clientes (WhatsApp, correo), y una forma de cobrar. Si
cada producto nuevo de Nexolú construyera esto desde cero, cada lanzamiento
sería más lento que el anterior — y el conocimiento (qué proveedor de LLM
rinde mejor, cómo se factura WhatsApp, cómo se maneja un webhook de pago
firmado) quedaría atrapado dentro de un solo producto.

La respuesta de Nexolú es extraer esas tres capacidades en **servicios
independientes, sin lógica de negocio propia**, consumidos por API por
cualquier producto de la compañía.

## Los tres servicios Core

### IA Core — el motor de asistente conversacional

Recibe mensajes de un usuario final (dueño o empleado de un negocio),
decide qué modelo de lenguaje usar, mantiene el historial de la
conversación, y — cuando hace falta un dato real del negocio o ejecutar
una acción — se lo pide de vuelta al producto dueño de ese dato. IA Core
nunca toca la base de datos de ningún producto: solo orquesta la
conversación y aplica una regla no negociable — **ninguna escritura ocurre
sin que un humano la confirme explícitamente**. Cada producto (POS, y a
futuro otros) define su propio catálogo de "lo que el asistente puede
hacer" — IA Core no sabe qué es una "venta" o una "cita", solo sabe cómo
tener una conversación y cuándo pedirle a la app correspondiente que
ejecute algo.

Esto significa que agregar el asistente de IA a un producto nuevo no
requiere construir un chatbot desde cero — se conecta al mismo motor, con
su propio vocabulario de acciones.

### Comms Core — comunicación con el cliente final

Centraliza el envío de WhatsApp y correo electrónico para todos los
productos, con reporting de costo unificado. Cada producto tiene sus
propias credenciales de proveedor (su propio número de WhatsApp Business,
su propia identidad de remitente de correo), pero la lógica de "cómo se
manda un mensaje, cómo se verifica que llegó, cuánto costó" vive en un
solo lugar.

### Payments Core — cobros

Pasarela de pago centralizada, diseñada desde el inicio para **múltiples
comercios**: cada empresa cliente de Nexolú (o la propia Nexolú como
agregador) puede tener su propia cuenta de la pasarela de pago, y cada
producto que cobra algo (hoy, suscripciones del POS) se integra una sola
vez contra un contrato estable, sin acoplarse a los detalles de la
pasarela de pago subyacente.

## Por qué esto importa para el negocio, no solo para ingeniería

- **Velocidad de lanzamiento**: un producto nuevo de Nexolú (por ejemplo,
  un sistema de agenda para salones de belleza, o venta de entradas para
  eventos) no necesita re-resolver IA, mensajería o cobros — se conecta a
  infraestructura que ya funciona en producción.
- **Consistencia de marca y costo**: los tres servicios reportan uso y
  costo de forma unificada, así que la compañía tiene una sola fuente de
  verdad de cuánto cuesta operar IA o mensajería, sin importar cuántos
  productos la usen.
- **El POS es el primer cliente, no el dueño**: aunque hoy todo el tráfico
  real viene del POS, ningún servicio Core tiene una sola línea de código
  específica del POS en su motor — la prueba de que la arquitectura
  funciona es que ya existen catálogos de capacidades preparados para
  otros productos, listos para activarse el día que ese producto exista.

## Estado de adopción (a nivel conceptual)

| Servicio | Adopción hoy |
|---|---|
| IA Core | Integrado y en uso activo por el POS (chat del asistente, insights del panel) |
| Payments Core | Integrado y en uso activo (checkout de suscripción del POS) |
| Comms Core | Desplegado en producción; el corte del tráfico real de mensajería está en preparación |

Para el detalle técnico de cada servicio, ver los documentos en
[`../apis/`](../apis/) (uso interno de ingeniería, no para exportar).
