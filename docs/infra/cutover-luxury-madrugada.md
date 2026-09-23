# Cambio ManyChat → Nexolú en Luxury Nails (la madrugada)

**Por qué de madrugada y de un solo golpe:** ManyChat y Nexolú no pueden
convivir en el mismo número: si las dos apps están suscritas, las dos
contestan cada mensaje. La "ventana de convivencia" del runbook general
se reduce a minutos, con el menor tráfico posible (1–4 am).

**Qué NO cambia:** el número, el nombre visible, la calidad y los
límites (misma WABA, ruta A de la sección M). **Qué SÍ se pierde:** el
historial de chats de ManyChat. Ninguna herramienta lo transfiere.

> ⚠️ **LA SIM DEL NÚMERO YA NO EXISTE (Pillofón salió de Colombia).**
> Por eso hay tres cosas que NO se hacen, porque exigen un código SMS o de
> llamada al número, y ese código no tendríamos cómo recibirlo:
>
> 1. **NUNCA borrar el número** de WhatsApp Manager (ícono de papelera).
>    La ayuda de ManyChat dice que, después de desconectar, se borre el
>    número del Business Manager: **ese paso se ignora**. Borrarlo y
>    volverlo a agregar exige verificar el número por SMS.
> 2. **No mover el número a otra WABA** (ruta B). La migración
>    programática de Meta exige código SMS o de llamada.
> 3. **No desactivar ni reemplazar la cuenta de WhatsApp Business** de Luxury.
>
> Lo que SÍ se puede sin SIM (verificado en la documentación de Meta):
> - Que otra app use la misma WABA (ruta A). El número sigue registrado.
> - Registrar de nuevo el número, si ManyChat lo desregistró: solo pide
>   el **PIN** de verificación en dos pasos, no un SMS. Desregistrar no
>   borra el número.
> - Cambiar el PIN desde WhatsApp Manager, como administrador.
>
> Seguro recomendado: recuperar la línea con el operador que absorbió a
> Pillofón. Solo sirve por si Meta algún día pide verificar el número
> de nuevo.

> **Qué hay que tener creado ANTES en la WABA productiva** (plantillas,
> Flow, y en qué archivo entra cada id): [waba-productiva-que-crear.md](waba-productiva-que-crear.md).
> Casi todo eso se puede hacer con luz, sin desconectar ManyChat.

**Día sugerido:** madrugada de miércoles a jueves o de jueves a viernes.
Evitar la del viernes: el fin de semana es cuando más se agenda y no
queremos estrenar ahí.

---

## A. El día antes (con luz, sin prisa) — ~1 hora

- [ ] **Confirmar la WABA real de Luxury** en su Business Manager
      (WhatsApp Manager → Cuentas). Anotar `WABA_ID` y el
      `PHONE_NUMBER_ID` del número real.
- [ ] **¿El Flow de confirmación está en ESA WABA?** Los Flows viven
      dentro de una WABA. Si lo creaste en la de prueba, créalo de nuevo
      en la real (mismo JSON: `nexolu-spa-api/docs/whatsapp-flows/`),
      publícalo y anota el nuevo Flow ID.
- [ ] **PIN de verificación en dos pasos del número:** WhatsApp Manager →
      Números → el número → Verificación en dos pasos. Si ManyChat puso
      uno que no conoces, cámbialo ahí y anótalo. Sin él no se puede
      registrar el número en nuestra app.
- [ ] **Token de sistema** en el Business Manager de Luxury: Usuarios del
      sistema → crear uno (admin) → asignarle la WABA y la app Meta de
      Nexolú → generar un token permanente con
      `whatsapp_business_messaging` + `whatsapp_business_management`.
      *(Si la app es del mismo portafolio que la WABA, basta el acceso
      estándar: no hace falta la revisión de Tech Provider.)*
- [ ] **Plantillas:** que las de recordatorio y confirmación estén
      aprobadas en esa WABA. Después del cambio se sincronizan desde
      Connect → Plantillas → Sincronizar.
- [ ] **Exportar contactos de ManyChat** (CSV desde la interfaz) e
      importarlos a Connect (script del Bloque 6.1 del runbook general).
- [ ] **Anotar qué hace hoy ManyChat** que el bot nuevo no hace (palabras
      clave, difusiones programadas, secuencias). Lo que falte se
      decide antes, no a las 2 am.
- [ ] **Avisar al equipo del salón:** desde el día siguiente las
      conversaciones se ven en la bandeja del spa/Connect, no en ManyChat.
- [ ] **Pasarme los datos** (`WABA_ID`, `PHONE_NUMBER_ID`, Flow ID). El
      token y el PIN los pones tú directamente en el `.env`/panel; no
      pasan por el chat.

## B. La madrugada — ~45 minutos

| Min | Paso | Quién |
|---|---|---|
| 0 | Mandarle un mensaje al número real desde tu teléfono: confirmar que ManyChat contesta (es el "antes") | Alejandro |
| 5 | Cargar en Connect el canal propio de Luxury: `PHONE_NUMBER_ID`, `WABA_ID`, token | Alejandro (panel) / yo reviso |
| 10 | Suscribir nuestra app a la WABA: `POST /{WABA_ID}/subscribed_apps` con el token | yo |
| 12 | **Desconectar WhatsApp en ManyChat** (Configuración → WhatsApp → Desconectar). Desde aquí contesta solo Nexolú. ⚠️ **NO borrar el número de WhatsApp Manager después**, aunque ManyChat lo sugiera (ver advertencia arriba) | Alejandro |
| 15 | Registrar el número en nuestra app: `POST /{PHONE_NUMBER_ID}/register` con el PIN. Por si ManyChat lo desregistró al desconectarse | yo |
| 18 | spa `.env`: `whatsapp_phone_number_id` de Luxury = el real; `WHATSAPP_BOOKING_FLOW_ID` = el de la WABA real → redeploy | yo |
| 25 | **Validación** (sección C) | los dos |
| 40 | Si todo pasa: sincronizar plantillas en Connect y dejar corriendo el vigilante | yo |

## C. Validación (no se cierra la madrugada sin esto)

Desde **dos teléfonos distintos** (el tuyo y otro que no esté en ninguna
lista de prueba; ese es justo el caso de María):

- [ ] "Hola" → llega el iniciador (Agendar por aquí / en la web / Otra consulta)
- [ ] Por aquí → servicio → día → hora → formulario → confirmar → llega "¡Listo! Quedó agendada"
- [ ] La cita aparece en la agenda del spa
- [ ] "Quiero cambiar mi cita" → horas → «Sí, muévela» → una sola cita, movida
- [ ] La conversación se ve en la bandeja
- [ ] ManyChat NO contestó nada en ninguna de las pruebas
- [ ] Cancelar las citas de prueba

## D. Volver atrás (si algo falla y no se arregla en 15 minutos)

1. Reconectar WhatsApp en ManyChat (sus flujos siguen ahí: **no borres
   nada de ManyChat hasta una semana después**).
2. Quitar nuestra suscripción: `DELETE /{WABA_ID}/subscribed_apps` con
   nuestro token.
3. Mensaje de prueba: vuelve a contestar ManyChat.

Tiempo estimado de vuelta atrás: ~10 minutos. Las citas que se hayan
agendado mientras tanto ya están en la agenda del spa: no se pierden.

## E. La semana siguiente

- Revisar cada mañana el reporte del vigilante (conversaciones sin
  respuesta, mensajes fallidos, citas sin confirmación).
- Después de 7 días estables: cerrar la cuenta de ManyChat.
