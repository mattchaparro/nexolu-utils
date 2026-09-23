# Qué crear en la WABA productiva de Luxury (y dónde va cada id)

> Complemento de [cutover-luxury-madrugada.md](cutover-luxury-madrugada.md):
> ese dice **cuándo** y **cómo** se hace el cambio; este dice **qué hay que
> tener creado antes** y **en qué archivo o pantalla entra cada dato**.

**La idea que ahorra la mitad del trabajo:** casi todo esto se puede crear
**hoy, con luz, sin desconectar ManyChat**. Crear plantillas y publicar un
Flow no le quita el número a nadie ni cambia quién contesta; solo deja las
piezas listas en la WABA. Lo único que de verdad es de madrugada es
desconectar ManyChat y suscribir nuestra app.

---

## 1. Plantillas: **no hay ids que pasarme**

El código las llama **por nombre e idioma**, no por id. Si las creas con
estos nombres exactos, no hay nada que actualizar de mi lado.

| Nombre | Categoría | Idioma | Variables | Botones | Quién la manda |
|---|---|---|---|---|---|
| `confirmacion_cita` | utility | `es` | 6 | 3 | El panel, al confirmar una cita |
| `recordatorio_cita` | utility | `es` | 4 | — | El cron, 24h antes |
| `retoque_recordatorio` | marketing | `es` | 3 | 3 | El cron de retoques |

Los cuerpos exactos, el orden de las variables y los textos de los botones
están en **`nexolu-spa-api/docs/plantillas-whatsapp.md`**.

Tres cosas que fallan en silencio si se descuidan:

- **El nombre.** Una letra distinta (`confirmacion-cita`, `confirmacionCita`)
  y el envío falla. Meta no avisa "no existe esa plantilla" de forma visible:
  queda el motivo en la bandeja.
- **El orden de las variables.** Meta no recibe nombres, recibe una lista
  posicional. Cambiar `{{3}}` por `{{4}}` manda "tu cita en miércoles 3 a las
  Luxury Nails" sin que nada falle.
- **El texto de los botones.** Son la interfaz: el bot compara contra
  constantes del código. Cambiar «Agendar retoque» por «Agendar mi retoque»
  en Meta deja el botón muerto — la clienta toca y no pasa nada.

**Antes de crear `confirmacion_cita`:** escribir garantías, recomendaciones y
cancelaciones en «Enséñale al bot» (Configuración → Bot). Sus tres botones
salen de ahí, y en una plantilla los botones son fijos: aparecen aunque no
haya nada escrito.

**Después de que Meta las apruebe:** Connect → Plantillas → **Sincronizar**.
No es cosmético: el espejo hace que, si una plantilla queda pausada o
rechazada, Connect corte el envío ANTES de llamar a Meta y deje el motivo a
la vista, en vez de fallar mensaje por mensaje gastando límite.

### Las difusiones son aparte

Las campañas usan **la plantilla que elija el negocio**, no una nuestra. Si
en ManyChat tienes difusiones que quieres conservar, cada una necesita su
propia plantilla aprobada en esta WABA. Esas sí las eliges desde el panel al
crear la difusión; no van en el código.

---

## 2. Flows: **estos sí son ids, y sí te los voy a pedir**

| Archivo (JSON listo) | Para qué | Variable | Estado |
|---|---|---|---|
| `nexolu-spa-api/docs/whatsapp-flows/elegir-fecha.json` | El calendario nativo al tocar «Otro día» | `WHATSAPP_DATE_FLOW_ID` | **hay que publicarlo** |
| `nexolu-spa-api/docs/whatsapp-flows/confirmar-cita.json` | Confirmar la cita en un formulario | `WHATSAPP_BOOKING_FLOW_ID` | **apagado a propósito** — dejar la variable vacía |

> **Los Flows viven DENTRO de una WABA.** El que publicaste en la de pruebas
> no existe en la productiva: hay que crearlo allá otra vez con el mismo
> JSON, publicarlo, y pasarme el id nuevo.

**Dónde lo actualizo yo:** `.env` de `nexolu-spa-api` en el droplet
(134.122.116.201) + redeploy. Un dato, un redeploy de dos minutos.

*Limitación conocida, por si entra otro negocio:* esas dos variables son
**globales del spa**, no por negocio. Hoy da igual porque solo Luxury tiene
número propio; el día que entre un segundo negocio con su propia WABA hay
que volverlas un campo por negocio. Está anotado, no es para esta noche.

---

## 3. El número y la WABA: no se crean, se conectan

No hay nada que *crear* acá — el número ya existe y se queda donde está. Lo
que hay que hacer es decirle a cada sistema cuál es:

| Dato | Dónde entra | Quién |
|---|---|---|
| `WABA_ID` + `PHONE_NUMBER_ID` + token | Connect → canal del negocio | Tú (el token no pasa por el chat) |
| `PHONE_NUMBER_ID` | `businesses.whatsapp_phone_number_id` en la BD del spa | Yo, con el dato |
| Webhook de Meta | Apuntando a Connect | Yo |

**El segundo de la tabla es el que se olvida y el que más duele.** Es lo que
enruta los mensajes ENTRANTES al negocio correcto: sin él, la clienta escribe
y el bot no sabe de qué spa es. Hoy **no hay pantalla** para ese campo — se
escribe en la base —, así que cuando tengas el `PHONE_NUMBER_ID` real me lo
pasas y lo dejo puesto.

---

## 4. Lo que NO hay que crear (y ManyChat obligaba)

- **Contactos.** La Cloud API manda a un número de teléfono, no a un
  contacto. No hay que "registrar" a la clienta antes de escribirle: ese paso
  desaparece.
- **Flujos.** Los reemplaza la entrada guiada del bot, que ya está en
  producción.
- **Palabras clave.** Igual: el bot las entiende o las atiende el equipo.

Y lo que **no se puede tocar**, porque la SIM del número ya no existe
(Pillofón salió de Colombia): no borrar el número, no migrarlo a otra WABA,
no desactivar la cuenta. El detalle está en el runbook de la madrugada.

---

## 5. Orden sugerido

**Ahora, sin tocar nada de ManyChat:**

1. Escribir garantías, recomendaciones y cancelaciones en «Enséñale al bot».
2. Crear las 3 plantillas en la WABA productiva y esperar la aprobación
   (suele tardar minutos, pero puede tardar horas: por eso va primero).
3. Publicar `elegir-fecha.json` en la WABA productiva y anotar el Flow ID.
4. Poner el Instagram en la página pública y el monto de multa por
   cancelación tardía (hoy las multas se registran en $0).

**La madrugada del cambio** (todo lo demás, en el runbook): canal en Connect,
suscribir la app, desconectar ManyChat, registrar el número, `.env` +
redeploy, validar desde dos teléfonos.

---

## 6. Lo que necesito de ti, en una lista

- [ ] `WABA_ID` de Luxury
- [ ] `PHONE_NUMBER_ID` del número real
- [ ] Flow ID de `elegir-fecha` **publicado en esa WABA**
- [ ] Aviso de que las 3 plantillas quedaron **aprobadas** (o cuál no, y por qué)

El **token** y el **PIN** no me los mandes por chat: van directo al panel y
al `.env`.

---

## 7. Mientras tanto, en la WABA de pruebas

Sirve para validar **el comportamiento**: que cada botón haga lo suyo, que
los textos se lean bien en un teléfono de verdad, que el calendario bloquee
los días cerrados.

Lo que **no** se puede llevar de allá para acá: las plantillas y los Flows no
se copian entre WABAs. Se crean de nuevo. Por eso conviene que los textos
queden decididos en pruebas antes de crearlos en la productiva — cambiar el
cuerpo de una plantilla aprobada significa volver a pasar por revisión.
