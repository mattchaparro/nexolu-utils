# Agendar por WhatsApp: barrido completo, lo que falla y qué hacer

21 de septiembre de 2026. Este documento recoge tres cosas que se hicieron el mismo día, en este
orden: (1) leer todas las conversaciones reales que hay y catalogar cada falla con su causa; (2)
construir un simulador de clientas por perfil que conversa con el bot de producción hasta agendar
o irse, y correrlo antes y después de arreglar lo que encontró; (3) juntar eso con los dos
informes de investigación (`chatbot-estado-del-arte.md`, `chatbot-multivertical.md`) en un plan
por prioridad.

La conclusión corta va primero, porque cambia cómo hay que leer el resto.

---

## 0. La conclusión

**La evaluación que teníamos decía 29 de 30 y el bot no le agendaba una cita a nadie.** Las dos
cosas eran verdad al mismo tiempo. `ia:evaluar` mide un turno: "dado este mensaje, ¿llamó la
herramienta correcta?". Las conversaciones reales se rompen *entre* turnos: la clienta toca un
servicio de la lista y el modelo olvida el día que ella dijo tres mensajes antes; toca una hora y
el modelo llama a la agenda sin decir qué servicio; pide "el viernes" y el modelo cambia el
servicio. Ninguna prueba de un turno puede ver eso. Por eso "el dataset no servía de mucho":
medía la unidad equivocada.

El simulador de perfiles sí lo ve. En su primera corrida, **ocho clientas simuladas, cero
citas**. Y lo importante no es el cero sino que las ocho se cayeron en el mismo sitio: el modelo
no es un buen lugar para guardar lo que ya se dijo ni para interpretar un botón tocado. Eso se
arregla en código, no en el prompt, y se arregló ese mismo día en tres vueltas: **0 → 3 → 7 de 8,
las siete con la cita en la agenda** (§3.3–3.4). Por el camino apareció un bug de producción que
nadie había visto: la reserva tomaba a la primera profesional del servicio y no a la que estaba
libre a esa hora, así que tocar una hora ofrecida "con Anyi" no agendaba nada.

Lo estructural, para más adelante: casi todo lo que tuvimos que construir en PHP para que el bot
del salón funcione --traducir "las manitos", paginar listas, recordar el pedido, silenciar al
modelo cuando una herramienta ya respondió, pasar a una persona-- no tiene una línea de uñas.
Es lo que la industria llama *patrones de conversación*, y es lo que habría que reescribir para
un POS o un colegio. El informe multivertical dice qué mover al núcleo y en qué orden; acá se
resume en §6.

---

## 1. Cómo funciona hoy: las tres puertas

Una clienta que escribe al WhatsApp del salón entra por una de tres puertas, y hasta hoy solo dos
estaban conectadas entre sí.

**Puerta 1, el menú.** Si escribe una palabra clave (`menu`, `servicios`, `precios`, `info`,
`catálogo`), Connect responde con un flujo determinista: una lista de categorías (Manicure,
Pedicure, Pestañas, Cejas), al tocar una categoría la lista de sus servicios con precio y
duración, al tocar un servicio "¿para qué día?" --y ahí el flujo se retira y le pasa la palabra
al bot. El menú se genera desde el catálogo real (`php artisan connect:menu`), así que un
servicio que se esconde en el panel desaparece del menú. Connect marca el mensaje como atendido
(`X-Nexolu-Flow-Handled`) para que el bot no conteste encima.

**Puerta 2, la conversación.** Cualquier otro mensaje llega al Spa, que lo deduplica, espera ocho
segundos por si vienen más pedazos (la gente escribe en tres mensajes lo que es una idea), y si
nadie del local tiene la conversación en sus manos, se lo pasa al Core. El Core arma el prompt
(instrucciones del agente + perfil del negocio + con quién habla + fecha de hoy) y deja que el
modelo decida qué herramienta llamar de nueve: catálogo, disponibilidad, mis citas, crear,
cancelar, mover, guardar contacto, ofrecer opciones, hablar con una persona. Las herramientas
viven en el Spa y son las que saben la verdad: qué servicios hay, qué horas quedan, quién puede.
Varias de ellas **responden solas** --la disponibilidad manda las horas como botones-- y le
dicen al modelo que se calle.

**Puerta 3, la web.** `agenda.nexolu.co/reservar/luxury-nails` es la reserva pública: calendario
completo, sin conversación, sin tokens. Funciona y no tenía ninguna conexión con el chat: el bot
ni la conocía, y a una clienta simulada que pidió el enlace dos veces le respondió que "no
tenemos un link para agendar". Desde hoy el enlace está en el perfil que lee el bot (§3.3).

Lo que hay que retener del dibujo: el modelo elige herramientas; el código decide qué es verdad
y qué se le muestra a la clienta. Cada vez que una decisión se ha movido del prompt al código
(fechas, horas, botones, paginación, sinónimos, ahora la memoria del pedido), el bot ha mejorado
de forma estable. Cada vez que se ha intentado con una regla más en el prompt, ha mejorado un
caso y empeorado otro.

---

## 2. Lo que pasó de verdad: las conversaciones reales

Hay una sola conversación real larga --la de Alejandro, 136 mensajes entre el 18 y el 21 de
septiembre-- y una corta de otra persona (6 mensajes, ninguna respuesta le llegó). Todo lo demás
en la bandeja son corridas de la evaluación con números inventados. Es poco, pero es exactamente
el material que tiene un producto antes de salir: lo que el dueño probó a mano.

Cada fila es una falla observada, con su causa verificada (no supuesta: se leyeron los registros
de llamadas a herramientas del Core y los datos del Spa) y su estado a hoy.

### 2.1 En el canal

| Qué pasó | Causa | Estado |
|---|---|---|
| "Menú" recibió la lista del flujo **y** un párrafo del bot, los dos | El bot contestaba aunque el flujo ya hubiera atendido | Arreglado el 19 (`X-Nexolu-Flow-Handled`) |
| "servicios" no abrió el menú: el bot volcó los 41 servicios en texto | Había una sesión de flujo abierta y la palabra clave se trató como respuesta a la lista anterior | Arreglado el 19 (una palabra clave interrumpe la sesión) |
| Una clienta escribió tres veces y "nadie le contestó" | El bot sí contestó; Meta rechazó las tres respuestas (número de prueba, teléfono fuera de la lista permitida). La bandeja las mostraba como entregadas y la alerta contaba la conversación como atendida | Arreglado hoy: un envío fallido no cuenta como respuesta, la bandeja lo pinta en rojo con el motivo, y entra en la alerta |
| "Hola, quiero agendar una cita" (sábado 17:49) sin respuesta | La evaluación, que conversa con el número del dueño, dejó su conversación real en pausa | Arreglado hoy (`Banco` restaura con UPDATE directo) |
| Una respuesta tardó 90 segundos | Sin causa verificada; probablemente varias llamadas al modelo en un turno | Abierto: medir latencia por turno |
| Nada le llega a nadie fuera de la lista de Meta | Seguimos en el número de prueba | Operativo: conectar el número real de Luxury |

### 2.2 En las herramientas y el estado

| Qué pasó | Causa | Estado |
|---|---|---|
| "¿Se puede cancelar? Sí" → "no encuentro esa cita" | El modelo inventó el id | Arreglado el 19: con una sola cita próxima, se cancela esa |
| "Necesito que sean por separado… es por el sistema" | Las cadenas de servicios no existían en la herramienta | Arreglado el 19 (`slotsForChain`) |
| Horas escritas como texto, en 24h, consecutivas (10:00, 10:15, 10:30…) | El modelo escribía lo que la herramienta devolvía | Arreglado el 19: la herramienta manda 4 horas repartidas como botones y le dice al modelo que calle |
| La misma lista de horas dos veces seguidas | Herramienta + `ofrecer_opciones` en el mismo turno | Arreglado el 19 (`OpcionesEnviadas`) |
| "El lunes" buscó el martes | El modelo calculaba la fecha | Arreglado el 19: la fecha va como se dijo y la resuelve el código |
| "en la sede Principal" con un solo local | La herramienta nombraba la sede siempre | Arreglado el 19 |
| "Semi permanente" (con espacio) → "no lo encuentro" | Comparación sin quitar espacios | Arreglado el 19 |
| "Manos y pies en semi" → lista de manos, los pies perdidos → "no sirves" | El código solo resolvía UN servicio ambiguo a la vez | Arreglado hoy: con varios servicios se toma el más probable por parte y se deja a la vista |
| "Semi con rubber" → lista de diez para elegir lo ya dicho | La búsqueda por tipo era "cualquiera de los dos" | Arreglado hoy: primero el que tiene todos los tipos dichos |
| Tocar un servicio de la lista → "hoy no tengo horas" habiendo pedido mañana | El modelo mandaba `fecha: hoy` en el turno del toque | Arreglado hoy: `UltimoPedido` pisa el día con el que ella dijo |
| Tocar una hora → "no pude consultar la agenda" | El modelo llamaba sin servicio; la validación rechazaba; el modelo traducía el rechazo como falla | Arreglado hoy: `servicio` y `fecha` opcionales, se completan con lo último pedido |
| Un título de opción de 26 letras → "no pude consultar la agenda" | Validación `max:24` como error | Arreglado hoy: se recorta con puntos suspensivos |
| "Quiero ver únicamente con Alejandra" → la misma lista, con Anyi y Marcela | En cadenas de servicios la profesional preferida es una preferencia blanda, no un filtro | **Abierto** (§6.1) |
| "Me mandas el link de la página?" → "no tenemos un link" | El bot no sabía que existe | Arreglado hoy: va en el perfil del negocio |

### 2.3 En el modelo

Estas no tienen un arreglo de código directo. Se listan porque el simulador las vigila y porque
el plan estructural (§6.3) las ataca por otro lado: quitándole al modelo la decisión.

| Qué pasó | Estado |
|---|---|
| Inventó "Manicura y Pedicura 70.000 / Manicura 35.000 / Pedicura 40.000": tres servicios que no existen, con precio | Mitigado el 19 (los resultados viejos se descartan explícitamente); el simulador lo detecta por negrillas que no están en el catálogo |
| Dijo que Semipermanente dura 45 minutos; dura 60 | Misma clase |
| Parafraseó mal el horario (sábado 9 am; abre a las 10) | El horario real está en el perfil; el modelo lo redondeó. Abierto menor: darlo como texto literal |
| "Buenos días" tres horas después → siguió el hilo viejo ("¿para qué día tu cita de manos y pies?") | Abierto: no hay corte de contexto por inactividad, solo por cantidad (20 mensajes) |
| "?" → llamó a mis citas y contestó "no tienes citas próximas" | Abierto: a un "?" se repite la pregunta o se ofrecen opciones |
| Repitió la misma frase de apertura tres veces a quien ya le había contestado | Mitigado hoy (`UltimoPedido`); falta un detector de bucle que pase a persona |
| Saluda con "¡Hola, X!" en cada turno | Abierto (prompt) |
| "Para mañana" → mandó la fecha ISO de hoy | Abierto: resolver fechas relativas en el Core, antes del modelo |
| Cambió solo el servicio ("semipermanente" → buscó Tradicional) | Abierto (modelo) |
| Precio total de dos personas como "$90.000" | Abierto menor: la herramienta devuelve el número suelto; darlo formateado |

### 2.4 En los datos y la prueba

| Qué pasó | Estado |
|---|---|
| 41 servicios con `sort_order` en cero: la lista salía alfabética y Tradicional y Semipermanente (mil citas) quedaban fuera de las diez filas | Arreglado el 19: orden por lo que más se pide (98 % de las citas caben en las diez) |
| Nombres cortados a lo bruto ("Recubrimiento Acrigel + ") | Arreglado el 20 |
| La evaluación decía 28/28 mientras nadie lograba agendar | Arreglado hoy: `ia:simular` (§3) |
| La evaluación dejó 75 citas de prueba en la agenda y una conversación en pausa | Arreglado el 19 y hoy |
| Las citas 6722/6723 aparecieron canceladas | Las canceló el propio dueño desde el panel (usuario 1, 3:57 am); ni el bot ni la evaluación |

---

## 3. Las clientas simuladas

### 3.1 Qué es y por qué

`php artisan ia:simular` hace que el modelo interprete a una persona concreta --con su forma de
escribir, lo que sabe y lo que quiere-- y la pone a conversar con el bot **de producción**: el
mismo Core, las mismas herramientas, el catálogo y la agenda reales de Luxury. Conversa hasta
lograr su meta, rendirse o agotar los turnos. Lo que se mide es lo que le importa al negocio:

- si consiguió lo que venía a buscar;
- si quedó agendado **lo que quería** (se compara con la agenda real, no con lo que el bot dijo);
- en cuántos mensajes;
- y qué dijo el bot que no debía: horas en 24h, listas escritas a mano, la misma respuesta dos
  veces, un servicio que no existe en el catálogo, "¿a qué hora te gustaría?".

Conversa con el número del dueño (`IA_EVAL_PHONE`) y **nada sale**: el canal corta los envíos y
los deja registrados para que la clienta simulada pueda "tocar" las listas igual que una persona.
Lo que el bot cree, la pausa por relevo humano, la limpieza al terminar: todo imita a producción
(cuando no lo hacía, midió cosas falsas; §3.5).

### 3.2 Los ocho perfiles

Salen de la clientela real del salón y de las quejas que ya llegaron. Cada uno tiene una meta y
lo que debería quedar en la agenda.

| Perfil | Cómo escribe | Qué quiere |
|---|---|---|
| **Gloria, 68** | Largo, sin signos, "mi niña", "las manitos", no conoce nombres del catálogo | Manicure tradicional mañana en la mañana |
| **Valentina, 24** | Minúsculas, abreviaturas, impaciente, toca botones de una | Semi con rubber hoy después de las 5 |
| **Camila, 31** | Cortés y directa; no quiere chatear con un bot | El enlace de la página para agendar sola |
| **Patricia, 45** | Normal; viene con su hija | Semipermanente para las dos, sábado en la tarde, al mismo tiempo |
| **Andrea, 35** | Pregunta precios y diferencias, cambia de opinión | Terminar en Semipermanente el viernes en la tarde |
| **Laura, 29** | Directa; ya tiene cita mañana a las 10 | Moverla a la tarde |
| **Andrés, 38** | Corto, con pena; nunca ha ido | Manos y pies de hombre, lo sencillo, el domingo |
| **Diana, 41** | Molesta desde el primer mensaje; se le levantó el esmalte | Que una persona la contacte; que no le vendan una cita |

### 3.3 Primera corrida: cero de ocho

| Perfil | Turnos | Qué pasó |
|---|---|---|
| Gloria | 6, se fue | Dijo "mañana en la mañana"; el bot le preguntó la franja; tocó Tradicional y el bot buscó **hoy** ("Hoy no tengo horas"); volvió a preguntar la franja; misma lista; mismo error. Dos veces la misma respuesta |
| Valentina | 5, se fue | El bot resolvió Semi + Rubber y mostró 4 horas (bien). Tocó "6 pm" → "No pude consultar la disponibilidad para hoy". Preguntó por qué → la pasaron a una persona. Pidió mañana → "No pude consultar la agenda para mañana" |
| Camila | 2, se fue | "Por ahora no tenemos un link para agendar directamente" |
| Patricia | 4, se fue | Primer turno: "Tuve un problema al consultar la agenda". Dijo sábado dos veces; tocó Semipermanente → "No tengo horas para Semipermanente **hoy lunes**" |
| Andrea | 8, se fue | Preguntó precios y diferencias (bien, con el catálogo). Pidió el viernes → el bot buscó **Tradicional**, que nunca mencionó. Corrigió; le mostró horas; tocó "4:45 pm" → "No pude consultar la disponibilidad para hoy" |
| Laura | 8, agotó | El bot encontró su cita (a las "5 am": la cita de prueba estaba en UTC, §3.5). "Sí, porfa" → "¿Qué servicio te gustaría agendar y para qué día?" tres veces. Al final mostró horas de la tarde; tocó "3:15 pm" → "No pude consultar la disponibilidad para hoy" |
| Andrés | 5, se fue | "Semi hombre, manos y pies" → el bot armó **tres** servicios (Tradicional, Pedi Jellyspa, Semipermanente Hombre). Tocó "10 am" → "necesito saber qué día y qué servicio" |
| Diana | 5, agotó | Turno 1: pasó a una persona (bien). Turnos 2–5: el bot siguió contestando lo mismo ("ya le avisé a alguien") cuatro veces --esto no pasa en producción, donde el bot queda en pausa; error del simulador, corregido (§3.5) |

Lo que estas ocho conversaciones tienen en común no es un problema de "inteligencia". Es que **el
modelo pierde lo que ya se dijo en cuanto la conversación pasa de dos turnos**, y que cuando una
herramienta le rechaza una llamada por un dato que falta, él se lo cuenta a la clienta como una
falla del sistema. Los registros del Core lo muestran con exactitud:

- Después de tocar un servicio, seis de seis llamadas a la agenda llevaban `fecha: "hoy"`,
  aunque la clienta había dicho mañana, sábado o viernes.
- Después de tocar una hora, cinco de cinco llamadas iban **sin servicio** y la herramienta las
  rechazaba ("el servicio es obligatorio"). Eso es lo que la clienta leía como "no pude consultar
  la agenda".
- Una llamada a `ofrecer_opciones` con "6 pm con Anyi Ruiz" (26 letras) fue rechazada por dos
  letras de más.

Lo que se arregló ese mismo día, todo en código del Spa:

1. **`UltimoPedido`**: cada vez que una herramienta entiende un pedido --qué servicios, qué día,
   qué franja, para cuántas-- lo guarda media hora. La siguiente llamada completa lo que el
   modelo olvidó. Y cuando lo que llega es un **toque** sobre algo que se ofreció, lo guardado
   pisa lo que el modelo diga: el día lo dijo ella; el "hoy" se lo inventó él.
2. `servicio` y `fecha` dejan de ser obligatorios en la agenda y en la reserva. Faltar un dato
   es una pregunta ("¿qué se quiere hacer?"), no un error.
3. Los títulos largos se recortan en vez de rechazarse.
4. El enlace de la agenda web va en el perfil del negocio, con la instrucción de mandarlo a quien
   lo pida o prefiera agendar sola.
5. "Semi hombre" acota a los servicios de hombre; "semi con rubber" es Semi + Rubber con todas
   las letras y no una lista de diez.

Todo con pruebas de PHPUnit que fallan si vuelve a pasar (190 en verde).

### 3.4 Las corridas siguientes: de 0 a 7 en tres iteraciones

El ciclo fue siempre el mismo: correr los ocho perfiles, leer las transcripciones y los registros
de llamadas a herramientas, encontrar la causa mecánica, arreglarla en código con su prueba, volver
a correr. Cada vuelta tardó una hora.

| Corrida | Lograron su meta | Qué se arregló antes |
|---|---|---|
| 1 | 0 de 8 | -- |
| 2 | 3 de 8 | `UltimoPedido` (memoria del pedido), servicio/fecha opcionales, títulos recortados, enlace web en el perfil, "semi con rubber" |
| 3 | 7 de 8 (dos de ellas con la cita **sin quedar**) | `Toques`: los botones tocados se atienden en código, sin modelo |
| 4 | 7 de 8, las siete **con la cita en la agenda** | La reserva usa a quien está libre a esa hora; si no puede, lo dice |

**Corrida 2** (3 de 8). Camila recibió el enlace de la web en el primer mensaje. Patricia agendó
las dos citas simultáneas --después de que el bot le preguntara el servicio que ya había dicho.
Diana fue pasada a una persona en el primer mensaje y el bot se calló. Las otras cinco se cayeron
todas en el mismo sitio, y era nuevo: **tocaban una hora** ("6:15 pm") y el modelo no sabía qué
hacer con dos palabras sueltas. Valentina recibió la misma lista de horas tres veces seguidas;
Andrea y Patricia recibieron "¿qué servicio y qué día?" después de tocar; Laura, "ya no tenemos
horas hoy" para una hora que acababa de ver. El modelo volvía a consultar la agenda con los mismos
datos (ahora completos gracias a `UltimoPedido`) y la herramienta, obediente, volvía a mandar la
misma lista.

Un botón tocado es un dato estructurado: sabemos exactamente qué se le ofreció y qué eligió. Pedirle
al modelo que lo interprete es pedirle que adivine algo que ya sabemos. `Toques` atiende en código,
antes del Core, la cadena completa que sigue a una lista: tocó un servicio → las horas del día que
ya dijo; tocó una hora → "Te confirmo: X el D a las H con P. ¿Lo agendo?" con botones *Sí, agendar*
/ *Otra hora*; tocó Sí → se agenda y se le dice; tocó *Otra hora* → las horas que **no** había
visto, sin volver a consultar. Es la frontera que todas las plataformas híbridas ponen igual: los
botones los atiende el flujo, el texto libre el modelo.

**Corrida 3** (7 de 8). Valentina agendó en tres mensajes: "hola, tienen turno hoy pa semi con
rubber?" → cuatro horas → tocó una → confirmación → *Sí, agendar*. Andrés, que en la primera
corrida había recibido tres servicios inventados, agendó *Semipermanente Hombre + Pedi - Hombre -
Tradicional* el domingo a las 10. Laura movió su cita a la tarde (aunque a mitad de camino el bot
dijo "no tengo horas para *Tradicional*", un servicio que nadie mencionó). Patricia, Andrea y
Camila también.

Pero dos de las siete --Valentina y Andrea-- terminaron con un mensaje **vacío** después de *Sí,
agendar*, y la agenda quedó sin su cita. La clienta simulada lo dio por logrado porque nadie le
dijo lo contrario; una de verdad habría llegado al salón sin cita. La causa era un bug de
producción que existía desde antes del simulador: la agenda ofrecía "2:30 pm **con Anyi**", pero la
reserva, cuando nadie decía con quién, tomaba a la *primera* profesional del servicio --Alejandra,
que a esa hora no trabaja-- y fallaba con "Alejandra no atiende en ese horario". Cualquier clienta
que tocara una hora ofrecida con Anyi o con Marcela no podía agendar. Arreglado: la reserva le
pregunta a la misma agenda quién tiene libre esa hora, el toque le pasa con quién se le ofreció, y
si aun así no se puede, se dice y se reofrecen horas --callarse después de un "sí" es dejarla
creyendo que agendó.

La que sigue fallando siempre es **Gloria**, y por una razón distinta a todas las demás: el modelo
no llama a ninguna herramienta. Ella dice "mañana en la mañana… las manitos… lo normalito" en
mensajes largos y sin signos, y el bot le pregunta el servicio, después el día, después la franja,
después el día otra vez. Ella se lo repitió cuatro veces. No hay nada que completar en `UltimoPedido`
porque el modelo nunca pasó por una herramienta; es comprensión de texto libre, que es lo único
que le pedimos al modelo y lo que peor hace con este perfil. El arreglo estructural es el que
proponen los dos informes: extraer día, franja y servicio del mensaje en código (o en el Core),
antes de que el modelo decida qué preguntar. Mientras eso no exista, la señora mayor es quien más
necesita que la alerta le llegue a una persona rápido --y hoy le llega, porque el bot la pasó a
alguien en el octavo turno.

**Corrida 4** (7 de 8, todas con cita real). Gloria agendó por primera vez: "hola mi niña… cupo
para mañana arreglarme las uñitas" → franja → lista → Tradicional → "10 am" → confirmación → *Sí,
agendar* → *Tradicional el martes 22 a las 10 am con Anyi Ruiz*, en cinco mensajes. Valentina en
tres (escribió "si, agendar" en minúscula y sin tilde, y el toque igual se reconoció). Andrés en
cuatro. Laura movió su cita a las 3:15 pm --pero la de las 10 am **siguió en la agenda**: el
camino de toques agenda, no mueve; §6.1. Andrea pidió "Semipermanente, sin rubber" y el bot buscó
primero Semi + Rubber; ella corrigió, la lista la salvó y agendó. Diana, a una persona en el primer
mensaje. Camila, el enlace.

La que falló fue Patricia, y es la misma falla de Gloria en la corrida anterior con otra cara: el
bot le preguntó **el servicio y el día alternadamente diez veces**, sin llamar a ninguna
herramienta, mientras ella se los repetía ("No sé por qué me preguntas de nuevo el servicio"). En
las corridas 2 y 3 el mismo perfil había agendado a la primera. Es variación del modelo en la
comprensión del texto libre, y no hay memoria que la arregle porque nunca pasó por una herramienta.
Lo que sí la habría cortado es lo que no existe todavía: un detector de bucle --la misma pregunta
dos veces-- que pase a una persona o mande el enlace de la web sin preguntarle al modelo. Es el
punto 3 y 4 de §6.1 y ahora tiene una transcripción que lo justifica.

Lo que las cuatro corridas enseñan, además del número: **cada falla que se arregló en código no
volvió**. Las que quedan son todas del mismo tipo --el modelo decide preguntar en vez de mirar-- y
ese tipo se ataca quitándole la decisión, no explicándosela mejor.

### 3.5 Lo que el simulador no ve todavía, y lo que midió mal

Tres cosas midió mal en la primera corrida y se corrigieron antes de la segunda: mostraba el
texto del modelo aunque una herramienta ya hubiera mandado botones (en producción el job lo
descarta); la clienta simulada copiaba la descripción de la fila al "tocarla" (de una fila
tocada solo llega el título); y seguía preguntándole al bot cuando el bot estaba en pausa por
relevo humano (en producción no responde). Cuando un simulador no imita al canal, mide fallas que
no existen y esconde las que sí.

Lo que sigue sin ver:

- **La calidad de la redacción.** Mide hechos contables (repitió, inventó, escribió una hora en
  24h), no si el tono es el de la recepción. Un juez con modelo se puede agregar después; el
  informe anterior recomienda no hacerlo aún.
- **Una corrida por perfil.** La clienta simulada va a temperatura alta a propósito, así que cada
  corrida es distinta. Un perfil que falla una vez es una pista; uno que falla tres es un bug. Hay
  que correr `--veces=3` antes de creerle a un cambio, como con `ia:evaluar --repetir=3`.
- **La gente real es menos cooperativa.** Las personas simuladas contestan lo que se les
  pregunta. Las de verdad mandan un audio, tres mensajes cortados, o desaparecen y vuelven al día
  siguiente.
- **El canal.** Habla con el Core directo: no pasa por el debounce de ocho segundos, ni por la
  ventana de 24 horas, ni por el menú de palabras clave. Esas capas se prueban aparte.

---

## 4. Tres niveles de prueba, y qué mide cada uno

"Creé un dataset y no sirvió de mucho" es una lectura justa de lo que había. Lo que hay ahora son
tres niveles, y la regla de cuál usar:

| Nivel | Qué mide | Cuesta | Cuándo |
|---|---|---|---|
| **PHPUnit** (`tests/Feature/Ai`) | Lo que es código: traducir "las manitos", paginar, esconder servicios, recortar títulos, recordar el pedido | Nada | Siempre. Cada falla que se arregla en código deja una prueba acá |
| **`ia:evaluar --repetir=3`** | Un turno: dado este mensaje, ¿qué herramienta llamó? 30 casos | Tokens; ~20 min | Al tocar el prompt o la descripción de una herramienta |
| **`ia:simular --veces=3`** | Una conversación completa: ¿logró su meta, agendó lo que quería, en cuántos turnos, qué dijo que no debía? 8 perfiles | Tokens; ~45 min | Antes de dar por bueno un cambio de comportamiento; y con cada conversación real que salga mal, convertida en perfil o en caso |

La lección de esta semana es de orden: lo primero es reproducir la falla en el nivel más bajo
que la vea. Si es de código (casi siempre lo es), PHPUnit. Si es de decisión del modelo en un
turno, un caso en `CasosReales`. Si solo aparece en la conversación, un perfil. Y la evaluación de
turnos tiene que estar en verde **antes** de correr la de conversaciones, porque la segunda tarda
más y falla por más razones.

Dos hechos que hay que tener presentes al leer números:

- **El modelo no es determinista aunque se le fije la temperatura en cero.** Antes de fijarla
  (el 19), la misma evaluación daba 23, 24, 25 o 26 de 28 sin tocar código. Con cero está mucho
  más quieto, pero el informe de estado del arte explica por qué nunca va a ser exacto.
- **Un cambio que sube un caso puede bajar otro.** Pasó varias veces esta semana con el prompt.
  Por eso los cambios de prompt van de a uno, con `--repetir=3` antes y después.

---

## 5. Lo que cada perfil necesita del sistema

Leer las ocho conversaciones desde la clienta, no desde el bot, deja requisitos concretos. Los que
ya se cumplen van marcados.

**Gloria (mayor, escribe largo).** Que entiendan sus palabras ("las manitos") sin pedirle el
nombre del catálogo ✓. Listas cortas y una decisión por vez: le va bien con botones, mal con
diez filas. Que no le repitan una pregunta que ya contestó (dijo "en la mañana" y le preguntaron
la franja). Que le confirmen en una frase, con el nombre de la persona que la va a atender.
Paciencia: sus mensajes llegan en pedazos y tardan.

**Valentina (joven, con afán).** Cero preguntas redundantes: si dijo "hoy después de las 5",
las horas van filtradas y ya ✓ (la franja se completa sola). Botones siempre. Que tocar una hora
sea el último paso, no el principio de otra ronda ✓. Que un tropiezo del sistema no le llegue
como "no pude": si algo falla, alternativa u hora nueva, nunca la explicación técnica.

**Camila (prefiere la web).** El enlace, de una, en el primer mensaje que lo pida ✓. Es la
salida más barata que hay: cero tokens, cero turnos, cero riesgo de agendar mal. También debería
ofrecerse solo, sin que lo pidan, cuando la conversación no avanza (§6.1).

**Patricia (viene con su hija).** Que "las dos al mismo tiempo" se entienda como dos citas
simultáneas y no como una cadena ✓. Que se diga con quién queda cada una y el total. Que si a esa
hora solo cabe una, se diga claro y se ofrezca otra hora, nunca agendar una y dejar a la otra
fuera ✓ (todo o nada).

**Andrea (compara, cambia de opinión).** Precios y diferencias sacados del catálogo, con las
descripciones que ya existen (la de rubber es buena) y nunca inventados. Que cambiar de servicio a
mitad de camino conserve el día y la franja ✓. Que "el viernes" no cambie el servicio.

**Laura (mover su cita).** Que "tengo cita mañana, pásala a la tarde" sea una sola gestión: mis
citas → horas de la tarde → mover. El sistema ya sabe qué servicio era; preguntárselo tres veces
es lo que la agotó. `reagendar_cita` existe y no se llamó ni una vez; §6.1.

**Andrés (hombre, primera vez).** "¿Atienden hombres?" responde con los tres servicios de
hombre y sus precios ✓. "Semi hombre" filtra a hombre ✓. Menos preguntas que a nadie: le da pena.

**Diana (molesta).** Pasar a una persona en el primer mensaje ✓ y **callarse** ✓ (así es en
producción). Jamás ofrecer una cita nueva. Lo que falta es del lado humano: que la alerta le
llegue al dueño de inmediato y que en la bandeja se vea con quién está molesta y por qué.

---

## 6. Plan de mejoras, por prioridad

### 6.1 Ahora, en el Spa (días)

1. **Profesional preferida como filtro duro en cadenas.** "Solo con Alejandra" tiene que devolver
   solo horas con Alejandra o decir que no hay. Hoy `fitChain` la trata como preferencia y cae a
   otras. Es un `if` en `AvailabilityService`.
2. **Mover una cita en una gestión, y que sea mover.** `reagendar_cita` existe y no se llamó en
   ninguna de las cuatro corridas. En la cuarta, Laura "movió" su cita y quedó con dos: la de las
   10 am y la nueva de las 3:15 pm, porque el camino de toques agenda, no mueve. Dos cosas: que
   `mis_citas` alimente `UltimoPedido` con el servicio de la cita (para no volver a preguntarlo), y
   que `Toques` sepa que hay una cita que se está moviendo y confirme "¿La paso de las 10 am a las
   3:15 pm?" llamando a `reagendar_cita`, no a `crear_cita`.
3. **Ofrecer la web cuando no avanza.** Regla contable, sin modelo: si en dos turnos seguidos el
   bot repite una pregunta o una herramienta devuelve "falta información" dos veces, el siguiente
   mensaje lleva el enlace de la agenda ("si prefieres, acá lo ves completo"). Y una fila
   "Agendar en la web" en el menú de palabras clave (`cta_url`, que Connect ya tiene).
4. **Detector de bucle → persona.** La misma respuesta del bot dos veces, o tres turnos sin que
   cambie lo recogido, pasa a `hablar_con_persona` sin preguntarle al modelo. Es el criterio
   literal de Intercom y del demo de Rasa (dos aclaraciones fallidas → humano).
5. **Corte de contexto por inactividad.** Un "Buenos días" tres horas después de la última
   conversación no puede continuar el hilo viejo. Corte del historial pasadas N horas (empezar con
   6), conservando la ficha de la clienta. Es un cambio en el Core (`_build_turns`), pequeño.
6. **Nombre corregible.** Hoy `guardar_contacto` no pisa un nombre existente. Si la persona dice
   "soy Valentina, no Mateo", tiene que poder. Teléfonos compartidos existen.
7. **Horario y precio total como texto ya formateado**, no como datos que el modelo redacte.
   Cada número que el modelo escribe es un número que puede escribir mal.
8. **Saludar una vez.** "¡Hola, X!" en cada turno es una regla del prompt que el modelo ignora.
   Camino determinista: si el turno anterior fue del bot hace menos de 10 minutos, quitar el
   saludo de la respuesta en el job. Es cosmético pero se nota en cada conversación.

### 6.2 En la operación (Alejandro)

- Conectar el número real de Luxury. Mientras se esté en el número de prueba, ninguna clienta
  real recibe nada, y la bandeja ya lo dice en rojo.
- Revisar la bandeja de Connect a diario y, cada falla real, convertirla en perfil o en caso. El
  simulador solo es tan bueno como las historias que se le den.
- Antes de anunciar el chat a las clientas: una semana de `ia:simular --veces=3` en verde.

### 6.3 Lo estructural: un núcleo para todos los negocios (semanas)

El informe `chatbot-multivertical.md` lo desarrolla con fuentes; acá el resumen de lo que aplica.
Todas las plataformas que sirven a muchos verticales separan lo mismo en tres capas: un **núcleo
conversacional** (entender, reparar la conversación, canal, medir), la **lógica de negocio** por
cliente (los pasos de cada tarea) y el **conocimiento del dominio** como datos (vocabulario,
catálogo, tono). Rasa lo llama *conversation patterns* y tiene quince con nombre: aclarar entre
opciones, corregir un dato, cancelar a mitad, pasar a humano, "no entendí", sesión nueva. Nosotros
tenemos la mayoría escritos en PHP dentro del salón.

Lo que hoy es del salón y no debería serlo, en orden de valor sobre esfuerzo:

| # | Qué | A dónde | Qué desaparece del Spa |
|---|---|---|---|
| 1 | **Contrato de resultado de herramienta**: `respondio_al_usuario`, `falta_informacion`, `opciones`, `supuse` como campos que el Core entiende | `ia-core` | `OpcionesEnviadas` y el `Cache::pull` del job |
| 2 | **`ofrecer_opciones` con paginación como herramienta del núcleo**, enviada por Connect, que recuerda la página y devuelve el id tocado (no solo el título) | `ia-core` + `comms-api` | `ServiciosPendientes`, `OfferOptionsCapability`, 200 líneas de `AvailabilityCapability` |
| 3 | **Resolutores de argumentos**: fecha relativa, franja, hora legible, declarados en el schema y resueltos antes de llamar a la app | `ia-core` | `FechaDicha`, `HoraLegible`, `deLaFranja` |
| 4 | **Handoff y pausa en Connect**, consultados por el Core | `comms-api` | Media `HandoffCapability` y `agentIsPaused()` por app |
| 5 | **Estado ligero por conversación**: qué se ofreció, qué se recogió, turnos sin avance, última actividad. `UltimoPedido` es el prototipo de esto en el Spa; generalizarlo | `ia-core` | Media docena de reglas del prompt; habilita bucle→humano y reset por horas |
| 6 | **Vocabulario como datos por negocio** + el matcher como paquete | tabla por app; algoritmo compartido | Las tablas de `ComoLoPide`; el negocio las completa desde el panel |
| 7 | **Confirmación antes de escribir** como puerta del Core, no como regla del prompt | `ia-core` | El riesgo de agendar sin confirmar deja de depender del modelo |
| 8 | **Simulador de perfiles en el Core**, con cada app aportando metas y verificador de estado final | `ia-core` + apps | `ia:simular` se queda como verificador del Spa |

Y lo que se queda en cada app, para dejarlo escrito: la verdad del negocio (disponibilidad,
precios, reserva con su índice anti-solape), permisos y banderas, el orden y la presentación de
las opciones, el perfil del negocio y de la clienta, y las instrucciones del agente --adelgazadas
a lo que de verdad es del vertical.

Orden: evaluador con histórico y `pass^k` → contrato de resultado → una pieza a la vez, con las
tres pruebas en verde entre cada dos. Nunca todo junto.

---

## 7. Lo que no hay que hacer

Está argumentado con fuentes en los dos informes; acá la lista para no volver a discutirlo:

- **No más reglas al prompt.** Pasa de 8.600 caracteres; cada regla nueva diluye las otras y esta
  semana varias empeoraron un caso mientras arreglaban otro. Una decisión que se puede tomar en
  código se toma en código.
- **No adoptar Rasa, Botpress ni Voiceflow.** Su lista de patrones sirve de checklist; su runtime
  significaría reescribir lo que ya funciona.
- **No un segundo motor de flujos en el Core.** Connect ya tiene uno; el Core le pide.
- **No mover lógica de negocio al núcleo por comodidad** (`LoQueMasPiden` consulta citas del
  spa; `deLaFranja` depende de qué llama "tarde" cada negocio).
- **No un juez con modelo para la calidad todavía.** Primero lo que se cuenta.
- **No WhatsApp Flows aún.** El `cta_url` a la web ya cubre "hazlo tú"; Flows se evalúa con datos
  propios cuando el simulador diga cuántas terminan en la web.
- **No propósito general.** Los términos de Meta desde enero de 2026 permiten gestión de citas y
  bloquean asistentes generales; cada superficie nueva en el número del cliente se lee dos veces.

---

## 8. Dónde está cada cosa

- Simulador: `nexolu-spa-api/app/Console/Commands/SimularClientas.php`, perfiles en
  `app/Services/Ia/Evaluacion/Perfiles.php`, banco compartido en `Banco.php`. Transcripciones en
  `storage/app/simulaciones/` con `--guardar`.
- Evaluación por turnos: `EvaluarAgente.php` + `CasosReales.php` (30 casos).
- Memoria del pedido: `app/Ai/UltimoPedido.php`. Traducción de vocabulario: `ComoLoPide.php`.
  Paginación: `ServiciosPendientes.php`. Orden por demanda: `LoQueMasPiden.php`.
- Investigación: `chatbot-estado-del-arte.md` (evaluación, determinismo, observabilidad) y
  `chatbot-multivertical.md` (arquitectura por capas, qué mover al núcleo, cómo debe ser el
  simulador).
