# Un chatbot para muchos negocios, no uno para un spa — cómo se estructura y qué mover al núcleo

Investigación de septiembre de 2026. Continúa el informe
[chatbot-estado-del-arte.md](./chatbot-estado-del-arte.md), que ya cubrió frameworks, evaluación,
observabilidad, caché y reglas del canal WhatsApp. Nada de eso se repite aquí; cuando hace falta se
cita.

La frase que dispara esta segunda parte es del dueño del producto: **"no vamos a poder crear un
chatbot solamente para un spa"**. Hoy buena parte de lo que hace que la conversación funcione —
traducir "las manitos" al catálogo, paginar listas, elegir el servicio más probable cuando piden
varios, no mandar la misma lista dos veces, pasar a una persona, no repetir preguntas — vive en PHP
dentro de `nexolu-spa-api`. Un POS que tome pedidos o un colegio que atienda a padres por WhatsApp
necesitarían exactamente lo mismo, y hoy habría que escribirlo otra vez.

La pregunta es, entonces: **¿qué es núcleo y qué es conocimiento del negocio?** Y la respuesta que
da la industria es sorprendentemente uniforme.

---

## 1. Cómo lo hacen los demás

### 1.1 La misma partición en tres capas, con distintos nombres

Todas las plataformas que sirven a muchos verticales — Rasa, Sierra, Decagon, Intercom, Zendesk,
Google, Botpress, Voiceflow, ManyChat — terminan separando lo mismo:

| Capa | Qué contiene | Cómo la llama cada uno |
|---|---|---|
| **Núcleo conversacional** (una vez, para todos) | Entender el mensaje en contexto, reparar la conversación cuando se desvía (corrección, cancelación, ambigüedad, "no entendí", relevo a humano, sesión), renderizar en el canal, medir | Rasa: *dialogue understanding* + *conversation patterns*; Intercom: motor Fin (Refine → Generate → Validate); Google: el LLM de intención + *event handlers*; Sierra/Decagon: la plataforma |
| **Lógica de negocio** (por cliente o por vertical) | Los pasos de cada tarea: qué datos hacen falta, qué API se llama, qué se valida antes de escribir | Rasa: *flows*; Intercom: *Procedures* / *Tasks*; Zendesk: *procedures* + *dialogues*; Google: *playbooks* + *flows*; Sierra: *journeys* / *skills*; Decagon: *AOPs* |
| **Conocimiento del dominio** (por cliente) | Vocabulario y sinónimos, catálogo, base de conocimiento, tono y marca | Google: *entity types* con sinónimos; Botpress/Voiceflow: *knowledge base*; Sierra: colores, logos, saludo, tono |

Rasa CALM lo formula con más claridad que nadie. El modelo de lenguaje interpreta el mensaje y emite
**comandos** de un vocabulario cerrado e independiente del dominio — `start flow`, `set slot`,
`disambiguate flows`, `cancel flow`, `repeat message`, `search and reply` — y el prompt que los
genera se rellena en tiempo de ejecución con los flujos y slots del cliente, de modo que "el mismo
componente funciona universalmente sin reentrenar"
([Rasa, LLM command generators](https://rasa.com/docs/reference/config/components/llm-command-generators/)).
La lógica de negocio "se define en flows", que escribe el desarrollador por asistente; el resto es
plataforma ([Rasa, CALM](https://rasa.com/docs/learn/concepts/calm/)).

Lo que Rasa llama **conversation patterns** es la pieza que a nosotros nos falta como concepto:
"flujos de sistema reutilizables que provee CALM" para "interacciones no lineales", pensados para
que el desarrollador "se concentre en los recorridos de usuario y la lógica de negocio en vez de
contemplar cada desvío posible"
([Rasa, Conversation patterns](https://rasa.com/docs/learn/concepts/conversation-patterns/)). Son
quince, con nombre propio, y cada uno se puede sobreescribir por proyecto creando un flujo con el
mismo nombre ([Rasa, Patterns](https://rasa.com/docs/reference/primitives/patterns/)):

| Patrón | Cuándo salta | Qué hace por defecto |
|---|---|---|
| `pattern_collect_information` | Falta un dato de un `collect` | Lo pregunta (con la `description` del slot como guía para el LLM) |
| `pattern_clarification` | El mensaje encaja en varios flujos | Ofrece opciones; `max_clarification_options` = 3 |
| `pattern_correction` | El usuario corrige algo que ya dijo | Actualiza el slot; opcionalmente pide confirmación |
| `pattern_cancel_flow` | Cancela a mitad | Detiene el flujo y lo dice |
| `pattern_skip_question` | Salta una pregunta obligatoria | Insiste en completarla |
| `pattern_continue_interrupted` | Cambió de tema y vuelve | Pregunta si retoma lo interrumpido |
| `pattern_completed` | El flujo terminó | "¿Algo más?" |
| `pattern_cannot_handle` | No se pudo generar comando | Pide reformular |
| `pattern_chitchat` | Fuera de tema | "No estoy entrenado para eso" (o respuesta libre si se habilita) |
| `pattern_human_handoff` | Excede al asistente | Por defecto informa; se sobreescribe con el relevo real |
| `pattern_internal_error` | Falló una herramienta | Mensaje genérico; `context.info` trae `tool_name`, `error_message` |
| `pattern_validate_slot` | Validación en tiempo real de un dato | Aplica validaciones antes de la lógica de negocio |
| `pattern_session_start` | Empieza la sesión | Recibe metadatos del canal |
| `pattern_repeat_bot_messages` | "¿Qué dijiste?" | Repite |
| `pattern_customer_satisfaction` | Al terminar | Encuesta |

El ejemplo público de Rasa muestra la parametrización por dominio: en el demo bancario,
`pattern_clarification` lleva un contador y **escala a humano si la aclaración falla dos veces**, y
`pattern_cancel_flow` avisa antes de cancelar solo cuando el flujo es "transferir dinero"
([rasa-calm-demo, patterns.yml](https://github.com/RasaHQ/rasa-calm-demo/blob/main/data/flows/patterns.yml)).
El patrón es del núcleo; el umbral y la excepción son del cliente.

### 1.2 Lenguaje natural para los pasos, código para lo que no puede fallar

Decagon, Intercom, Zendesk, Sierra y Google convergen en un segundo principio: **los pasos de la
tarea se escriben en lenguaje natural y las validaciones críticas en código**.

- Decagon: los *Agent Operating Procedures* "combinan instrucciones conversacionales con lógica en
  código", con "salvaguardas integradas — ejecutando pasos clave de validación en código — para que
  acciones sensibles se manejen de forma segura". Los árboles de decisión fallaron porque "las
  consultas de los clientes rara vez siguen esas rutas predefinidas" y se volvían "enormes e
  inmanejables" ([Decagon, Why we built AOP](https://decagon.ai/blog/why-we-built-aop)).
- Intercom: las *Procedures* se escriben "como entrenarías a un compañero"; "usa código para
  precisión" cuando un paso lo necesita; Fin "escala si detecta que la conversación no avanza, está
  en un bucle, o el cliente pide explícitamente un humano"
  ([Intercom, Fin Procedures explained](https://www.intercom.com/help/en/articles/12495167-fin-procedures-explained)).
  En las guías de buenas prácticas: usar if/else en cada paso para "garantizar que siempre puedas
  tomar una decisión … o tener una salida"; declarar qué datos hacen falta y de dónde salen; y para
  los conectores de datos "Fin le pedirá automáticamente al cliente los que falten"
  ([Intercom, Best practices for Fin Tasks](https://www.intercom.com/help/en/articles/10539969-best-practices-for-fin-tasks)).
- Sierra: el Agent SDK compone "skills — como triage, respond, confirm — en workflows complejos", y
  permite "definir el grado de flexibilidad que el agente debe exhibir para cada workflow, con
  niveles variables de creatividad y determinismo"
  ([Sierra, Agent SDK](https://sierra.ai/product/agent-sdk)). Los *Journeys* del Agent Studio son
  lo mismo en lenguaje natural: "pasos como referenciar artículos, llamar APIs externas o recoger
  información del cliente"; lo que se configura por marca son "colores, logos, saludos y tono"
  ([Sierra, Meet Agent Studio](https://sierra.ai/uk/blog/meet-agent-studio)).
- Google: un *playbook* es "el bloque básico de los agentes generativos", con objetivo,
  instrucciones paso a paso que referencian herramientas, **ejemplos** ("conversaciones de muestra
  que son efectivamente few-shot prompts") y parámetros; los *routine playbooks* "leen parámetros de
  sesión al entrar y los escriben al salir", y pueden transferir a otro playbook o a un *flow*
  determinista en el mismo turno
  ([Dialogflow CX, Playbooks](https://docs.cloud.google.com/dialogflow/cx/docs/concept/playbook)).

Ninguno de ellos publica su arquitectura interna con detalle; lo anterior sale de documentación de
producto y de sus blogs. Lo que sí es verificable es el **patrón de producto**: un motor único, y
por cliente un paquete de (instrucciones en lenguaje natural + herramientas + conocimiento +
umbrales).

### 1.3 El vocabulario del cliente es dato, no código

La traducción de "las manitos" a "Manicure" tiene un nombre estándar: **entidades con sinónimos**.
En Dialogflow CX cada *entity type* se define por agente con un valor de referencia y sus
sinónimos ("green onion" y "scallion" → un mismo valor), con *fuzzy matching* para errores de
escritura, y con generación automática de sinónimos a partir de la descripción de la entidad
([Dialogflow CX, Entities](https://docs.cloud.google.com/dialogflow/cx/docs/concept/entity)). El
mecanismo (normalizar, comparar, resolver ambigüedad) es del núcleo; la tabla es del cliente. Rasa
hace lo mismo con la `description` de cada slot en el `collect`
([Rasa, Writing flows](https://rasa.com/docs/pro/build/writing-flows/)).

### 1.4 La frontera entre flujo determinista y lenguaje libre

Aquí también hay consenso, y es un consenso **híbrido**, no un bando:

- Google lo pone como un espectro: *fully generative* (playbooks), *partly generative* (flows con
  *generative fallback* cuando la entrada no coincide con nada esperado) y *deterministic* ("los
  flows usan modelos de lenguaje para entender la intención … pero una vez establecida, tienes
  control total sobre el flujo y las respuestas"). El criterio: determinismo cuando "requieres
  control sobre la conversación y todas las respuestas", a cambio de más tiempo de diseño
  ([Dialogflow CX, Generative vs deterministic](https://docs.cloud.google.com/dialogflow/cx/docs/generative-deterministic),
  [Generative fallback](https://docs.cloud.google.com/dialogflow/cx/docs/concept/generative-fallback)).
- Botpress: el *Autonomous Node* "usa IA para decidir qué decir y qué herramientas usar", itera hasta
  cumplir condiciones de salida, y entonces "el control vuelve al workflow determinista"; por defecto
  no ve variables, hay que darle acceso explícito
  ([Botpress, Autonomous Node](https://botpress.com/docs/studio/concepts/nodes/autonomous-node)).
- Voiceflow: el *Agent step* decide el enrutamiento y "el transcript muestra el path inline" hacia
  playbooks o workflows especializados
  ([Voiceflow, Agent step](https://www.voiceflow.com/docs/changelog/agent-step.md)).
- Zendesk: "flujos híbridos que combinan respuestas generativas con flujos guionados", con
  *procedures* en lenguaje natural y *dialogues* con ramas
  ([Zendesk, Dialogue builder](https://support.zendesk.com/hc/en-us/articles/9066753203738-Managing-conversation-flows-in-the-dialogue-builder-for-advanced-AI-agents)).
  La página de *agentic AI* exige login; no la pude leer.
- ManyChat: el *AI Step* es "la única IA real en un flujo por defecto"; si la base de conocimiento no
  responde, cae a "Perdón, no entendí — elige del menú" y el control vuelve a los botones. La
  fuente es un análisis de terceros; el artículo oficial devolvió 403
  ([setsmart, ManyChat automation](https://setsmart.io/blog/manychat-automation);
  [ManyChat AI Step, oficial](https://help.manychat.com/hc/en-us/articles/14281187288860-Manychat-AI-Step)).

La lectura común: **el LLM interpreta la entrada libre y maneja los desvíos; lo determinista es
dueño de los menús de entrada, de la recolección estructurada, de la confirmación y de la
escritura**. Es exactamente nuestro `X-Nexolu-Flow-Handled` + agente, pero ellos lo tienen en las
dos direcciones (el LLM también puede devolver el control al flujo) y nosotros solo en una.

Para WhatsApp en particular hay una tercera opción entre botones y texto libre: **WhatsApp Flows**,
formularios nativos de varias pantallas con selectores de fecha, listas desplegables y radios, cuyo
resultado vuelve al negocio por webhook. Meta los promociona para citas (Farmacias del Ahorro,
"2,6 veces más citas")
([WhatsApp Business, Flows](https://whatsappbusiness.com/es-la/products/whatsapp-flows/)). Un
integrador publica cifras de completitud (65–85 % contra 35–55 % de un enlace tipo Calendly) y
recomienda 2–4 pantallas, **pero sin citar fuente**; tómalo como anécdota de proveedor
([wa.expert](https://wa.expert/pages/whatsapp-flows-appointment-booking)). La documentación oficial
está en [developers.facebook.com/docs/whatsapp/flows](https://developers.facebook.com/docs/whatsapp/flows);
la página de entrada no tiene contenido legible por herramienta y no pude verificar la lista de
componentes desde ahí.

Sobre "hazlo en la web": Meta recomienda el botón **CTA URL** precisamente porque "los usuarios
pueden dudar en tocar URLs crudas con cadenas largas u oscuras"; el botón admite 20 caracteres y el
cuerpo 1.024
([Meta, Interactive CTA URL messages](https://developers.facebook.com/docs/whatsapp/cloud-api/messages/interactive-cta-url-messages)).
Nuestro motor de flujos ya tiene el nodo `cta_url`; lo que no existe es la **regla de cuándo
ofrecerlo**. En la literatura no encontré un umbral canónico. Lo que sí aparece son criterios
operativos: Rasa escala tras dos aclaraciones fallidas; Intercom cuando "no avanza o está en un
bucle"; los análisis de relevo hablan de 15–30 % de handoff como rango sano y de que un handoff
bajo con clientes frustrados significa gente "atrapada en bucles de automatización"
([Bluetweak, AI-to-human handoff](https://www.bluetweak.com/blog/ai-to-human-handoff), fuente
secundaria). Aplicado a citas por WhatsApp, los casos donde la web gana al chat son los que ya
salen en `CasosReales.php`: tres personas a la vez, dos profesionales distintas a horas distintas,
un catálogo que no cabe en dos listas, o cualquier cosa que exija pago (que en Colombia no se puede
cobrar dentro de WhatsApp, ver la memoria de Connect).

### 1.5 Cómo prueban conversaciones completas

Todos los grandes hacen lo mismo y lo llaman parecido:

- **Sierra**: cada conversación anotada por el equipo de CX "puede convertirse en un test de
  conversación — un snapshot que se simula contra APIs mock para reproducir el problema"; los
  releases son inmutables (código, prompts, versión de modelo y conocimiento)
  ([Sierra, Agent Development Life Cycle](https://sierra.ai/blog/agent-development-life-cycle)).
- **Decagon**: previews en tiempo real, unit tests de respuesta, tests de integración ("dispara las
  herramientas correctas"), y "simulaciones que modelan conversaciones completas … programadas para
  correr automáticamente, detectando regresiones o deriva sutil"
  ([Decagon, test-driven](https://decagon.ai/resources/the-future-of-ai-agents-is-test-driven)).
- **Parloa**: "miles de conversaciones simuladas a través de escenarios, idiomas, canales y casos
  borde", mezclando "transcripciones históricas con tests sintéticos", puntuadas con "evaluaciones
  basadas en LLM y criterios basados en reglas" sobre "éxito de la tarea, tono, exactitud y
  comportamiento de API" ([Parloa, Test](https://www.parloa.com/platform/test/)). Un modelo hace de
  cliente y otro corre el agente ([OpenAI, Parloa](https://openai.com/index/parloa/)).
- **Intercom**: "correr simulaciones antes de poner una Procedure en vivo es la forma recomendada de
  asegurar comportamiento fiable a escala"
  ([Intercom, Fin Procedures explained](https://www.intercom.com/help/en/articles/12495167-fin-procedures-explained)).

Del lado académico, τ-bench es la referencia: "conversaciones dinámicas entre un usuario (simulado
por modelos de lenguaje) y un agente con herramientas de API y políticas"; el éxito se juzga
"comparando el estado de la base de datos al final con el estado objetivo anotado", y la
fiabilidad con `pass^k`. GPT-4o resolvía "<50 % de las tareas" con "pass^8 <25 % en retail"
([τ-bench, arXiv 2406.12045](https://arxiv.org/abs/2406.12045)).

Y tres hallazgos de 2026 sobre **el simulador mismo**, que importan porque cambian el diseño:

1. **Los simuladores son demasiado cooperativos.** Heredan del modelo un carácter "cooperativo y
   homogéneo", y por eso agentes que van bien en simulación fallan con usuarios reales "poco claros,
   impacientes o reticentes a dar información". Generando *persona policies* (código de generador
   evolucionado por LLM) los anotadores humanos los tomaron por humanos el 80,4 % de las veces contra
   ~40 % del baseline, y los agentes entrenados con ellos mejoraron +17 % relativo fuera de
   distribución ([arXiv 2605.12894](https://arxiv.org/abs/2605.12894)).
2. **Los simuladores pierden el objetivo en conversaciones largas.** UGST (*User Goal State
   Tracking*) hace que el simulador lleve un estado explícito de su meta y razone sobre él antes de
   responder; mejora en MultiWOZ y τ-bench ([arXiv 2507.20152](https://arxiv.org/abs/2507.20152)).
3. **No capturan la fricción real.** Con 1.000 diálogos reales de 16 dominios, los simulados "no
   logran capturar las fricciones de comunicación que los usuarios reales introducen", y la calidad
   varía por dominio, lo que sugiere simuladores específicos por dominio
   ([realsim, arXiv 2605.02624](https://arxiv.org/abs/2605.02624)).

Una guía práctica lo resume en cuatro piezas — persona sembrada "de clusters de tráfico real, no de
la imaginación", meta que "el agente no conoce: debe elicitarla", **presupuesto de paciencia** que
se expresa como "respuestas más cortas, repetirse, amenazar con irse", y **umbral de abandono**
calibrado con datos — y añade dos advertencias: puntuar la conversación, no el promedio de turnos;
y que "la métrica más importante no es el éxito contra el simulador sino la divergencia
simulador-versus-producción", porque cambiar el modelo que hace de usuario movió el éxito del agente
hasta nueve puntos ([tianpan.co](https://tianpan.co/blog/2026/04/27/synthetic-users-multi-turn-agent-eval),
blog técnico). Otra guía separa *personas* (quién habla), *escenarios* (qué quiere, turno a turno) y
*veredictos ligados a evals* que fijan "cada fallo al turno exacto en que ocurrió"
([Future AGI, simulation guide](https://futureagi.com/blog/ai-agent-simulation-practical-guide-2026/)).

**Métricas.** Las que usa la industria para atención al cliente: *containment rate* (sesiones
resueltas sin humano ÷ sesiones), *escalation rate* (la inversa), *task completion rate*, turnos
hasta completar, y la advertencia de que un bot puede "contener" dando una respuesta genérica que
no resuelve nada
([Decagon, containment rate](https://decagon.ai/glossary/what-is-chatbot-containment-rate);
[Bookbag, benchmarks](https://bookbag.ai/blog/chatbot-containment-rate-benchmarks), secundaria).
Los benchmarks que circulan (70–85 % de contención para agentes que ejecutan acciones, 40–60 % para
asistentes estándar) son de proveedores, no de un estándar.

**Casos a partir de fallos reales.** El flujo documentado es: capturar trazas de producción, añadir
las que fallaron a un dataset "con un clic", escribir el evaluador que reproduce la falla, validar el
arreglo offline y volver a desplegar — "un fallo que viste una vez se vuelve un test que corres
siempre" ([LangSmith, Evaluation](https://docs.langchain.com/langsmith/evaluation)). Sierra lo hace
con anotación humana diaria de muestras; Parloa con transcripciones históricas.

### 1.6 Sesión, contexto y "empezar de cero"

Dialogflow CX guarda la sesión 30 minutos por defecto, ampliable hasta 24 horas
([Dialogflow CX, Sessions](https://docs.cloud.google.com/dialogflow/cx/docs/concept/session)). Rasa
usa 60 minutos (`session_expiration_time`), con `carry_over_slots_to_new_session` para decidir qué
datos sobreviven al reinicio
([Rasa, Session timer](https://rasa.com/docs/reference/config/session-management/session-timer/)).
Ambos separan **el historial** (se reinicia) de **los datos del usuario** (se conservan por
elección). Ninguno de los dos está pensado para WhatsApp, donde una conversación de citas se
extiende por horas con silencios largos; el valor concreto tendrá que ser nuestro, pero la
distinción sí aplica.

---

## 2. Qué de lo nuestro ya es reutilizable y qué está pegado al spa

Miré `C:\Nexolu\nexolu-spa-api\app\Ai\` completo, las dos piezas del canal
(`CommsWebhookController.php`, `AnswerWhatsappMessageJob.php`), el orquestador del Core y el motor de
flujos de Connect. Lo clasifico con la partición de §1.1.

### 2.1 Lo que ya es núcleo (y está donde debe)

- **`nexolu-ia-core/core/chat/orchestrator.py`** no importa nada de `apps.*`: recibe el registro de
  herramientas, el agente y el cliente de despacho de la app. Es la separación correcta y está
  documentada en su docstring.
- **`core/chat/system_prompt.py`** arma el prompt en capas (persona base → instrucciones del agente
  → perfil del negocio → con quién habla → disciplina de herramientas). El *tenant context* ya viaja
  como datos rotulados, no como órdenes.
- **`core/agents/base.py`**: un agente = instrucciones + subconjunto de herramientas + modelo. Es la
  unidad "por vertical" que Google llama playbook y Sierra journey, en su forma mínima.
- **Compactación de resultados viejos** (`_compact_tool_result`) y **ventana de historial**
  (`ai_history_turns`): son genéricos y ya sirven a POS, hogar y spa.
- **El protocolo de errores accionables**: `AiToolInvokeController` devuelve `falta_informacion` +
  `instruccion` como 200. Es genérico aunque hoy solo lo emite el spa.
- **`nexolu-comms-api/core/flows/engine.py`**: nodos `buttons`, `list` (10 filas), `capture`,
  `cta_url`, `condition`, `actions.notify_app`, sesiones con TTL de 24 h. Es un motor determinista
  multi-app, y el header `X-Nexolu-Flow-Handled` ya resuelve la mitad de la frontera de §1.4.
- **`Capability.php`** (la interfaz): permisos, feature flags, `allowsCustomers()`, revalidación de
  argumentos. El contrato es genérico; se puede copiar tal cual al POS y al SGA.

### 2.2 Lo que es genérico pero vive en el spa, en PHP

Esto es el corazón del problema. Cada archivo resuelve un **patrón de conversación** de la tabla de
§1.1, y ninguno sabe nada de uñas salvo por las tablas que contiene:

| Archivo | Patrón que implementa | Qué tiene de genérico | Qué tiene de spa |
|---|---|---|---|
| `app/Ai/Resolves.php` (`pickByName`, `resolveServiceIn`) | `pattern_clarification`: exacto → contenido → pegado → ambiguo con opciones | El algoritmo de resolución por nombre con normalización y la excepción con `opciones` | Que busca en `Service`, `Resource`, `Location` |
| `app/Ai/ComoLoPide.php` | Entidades con sinónimos (§1.3) | El matcher por categoría y por pedazo de nombre; `elMasProbable` | Las cuatro tablas de palabras (`manitos`, `pieses`, `semi`…) |
| `app/Ai/LoQueMasPiden.php` | Orden de candidatos por frecuencia | La idea (respetar `sort_order` del negocio, si no, popularidad) | La consulta a `appointment_items` |
| `app/Ai/ServiciosPendientes.php` | Paginación de una lista de 10 | Todo: TTL 15 min, fila "Muéstrame más", detección de "ver más" con holgura | Solo el nombre |
| `app/Ai/OpcionesEnviadas.php` | "Una herramienta ya respondió; que el modelo se calle" | Todo | Nada; está indexado por teléfono porque no hay otro identificador de turno |
| `app/Ai/FechaDicha.php` | Resolución de fechas relativas en español | Todo ("el lunes", "en ocho", "pasado mañana") | Nada |
| `app/Ai/HoraLegible.php` | Formato de hora como habla la gente | Todo | Nada |
| `app/Ai/EsUnaPrueba.php` | Modo evaluación ("no mandes de verdad") | El concepto | Que sea una caché por teléfono en vez de un flag del contexto |
| `app/Ai/Capabilities/OfferOptionsCapability.php` | Renderizar opciones tocables + guardar en el hilo | Todo el contrato (mensaje, ≤10 opciones de ≤24 caracteres, botón) | Que escriba en `Message`/`WhatsappConversation` del spa |
| `app/Ai/Capabilities/HandoffCapability.php` | `pattern_human_handoff` | Pausar al agente, dejar nota, reabrir como no leída, instrucción de cierre | La nota en la bandeja del spa |
| `app/Ai/Capabilities/AvailabilityCapability.php` (`queEligaServicio`, `siguienteTanda`, `repartidas`, `mostrar`) | Disambiguación por lista con paginación; "4 opciones repartidas, no 4 seguidas"; enviar opciones y callar al modelo | Esas cuatro rutinas, ~200 de las 520 líneas | La disponibilidad en sí (`AvailabilityService`, `slotsForChain`, `CitasSimultaneas`) |
| `app/Http/Controllers/Api/CommsWebhookController.php` | Canal: firma, dedupe por `wamid`, botón→texto, ventana 24 h, mute por flujo o por humano | Todo | Que resuelva la conversación en tablas del spa |
| `app/Jobs/AnswerWhatsappMessageJob.php` | Canal: debounce 8 s, juntar pedazos, trailing-edge por ID | Todo | Que lea `Message` del spa |
| `apps/spa/agents.py::INSTRUCCIONES` (Core) | Los patrones que **no** tienen código: no repetir preguntas, confirmar antes de escribir, cuándo escalar, no inventar catálogo | Unas 12 de las ~20 reglas son de cualquier vertical | Las de servicio, sede, "juntas", `hora`/`hora_24` |

Dos observaciones sobre lo que el enunciado daba por hecho:

- **"Pasar a un humano cuando alguien se frustra"** no tiene detección: es una instrucción del
  prompt (`agents.py`, "si vienen molestas o reclamando") más la capacidad que pausa. No hay
  contador de turnos sin avance ni nada parecido al "no avanza o está en bucle" de Intercom.
- **"Resetear el contexto después de horas"** no lo encontré en PHP. `ia_conversation_id` se escribe
  en `AnswerWhatsappMessageJob.php:111` y solo lo anula `Evaluacion/Banco.php`. Lo que hay es la
  ventana fija de N turnos del Core, la compactación, y los TTL de caché (15 min pendientes, 3 min
  opciones enviadas, 24 h sesiones de flujo en Connect). Es decir: hoy una clienta que vuelve a los
  tres días arranca con la cola de la conversación anterior, recortada por cantidad y no por tiempo.
  Es un hueco, no una pieza que haya que mover.

### 2.3 Lo que sí es del spa y debe quedarse

`AvailabilityService`, `slotsForChain`, `CitasSimultaneas`, `BookingService` y su índice único
anti-solape, `is_bookable_online`, el filtro de franja horaria, `supuse` (qué se eligió por ella),
`para_quien`, la nota en la bandeja, los permisos por rol. Nada de eso tiene análogo en un POS ni
en un colegio, y el informe anterior ya dejó escrito por qué el LLM no puede calcular disponibilidad
ni precios.

---

## 3. Propuesta: qué mover al núcleo y qué dejar en cada app

El criterio es el de §1.1: **el núcleo es dueño de los patrones de conversación y del canal; cada
app es dueña de la verdad de su negocio y de su vocabulario, y lo expresa como datos y como
herramientas**. Nada se reescribe: se extrae pieza por pieza con `ia:evaluar` como red (el
informe anterior insiste en arreglar primero el evaluador, §3.1; sigue vigente).

Ordenado por valor sobre esfuerzo:

| # | Qué | A dónde | Valor | Esfuerzo | Qué desaparece del spa |
|---|---|---|---|---|---|
| 1 | **Contrato de resultado de herramienta** con campos estándar: `falta_informacion`, `opciones` (ambigüedad), `respondio_al_usuario`, `instruccion`, `supuse` | `ia-core/core/tools/` | Muy alto | Bajo | `OpcionesEnviadas.php` |
| 2 | **`ofrecer_opciones` como herramienta del núcleo**, con paginación ("ver más") | `ia-core` (declara) + `comms-api` (envía y recuerda la página) | Muy alto | Medio | `ServiciosPendientes.php`, `OfferOptionsCapability.php`, `queEligaServicio`/`siguienteTanda`/`mostrar` |
| 3 | **Resolutores de argumentos del núcleo**: fecha relativa, franja, hora legible | `ia-core` (tipos de parámetro declarados en el schema) | Alto | Bajo | `FechaDicha.php`, `HoraLegible.php`, `deLaFranja` |
| 4 | **`hablar_con_persona` del núcleo** con pausa en Connect | `ia-core` + `comms-api` | Alto | Medio | La mitad de `HandoffCapability.php`; `agentIsPaused()` pasa a leerse de Connect |
| 5 | **Estado ligero por conversación** en el orquestador: qué se ofreció, qué falta, turnos sin avance, `allowed_tools`, expiración por inactividad | `ia-core/core/chat/` | Alto | Medio | Media docena de reglas del prompt; añade lo que hoy no existe (bucle → handoff, reset por horas) |
| 6 | **Vocabulario por tenant como datos** + matcher genérico | matcher en librería compartida; tablas en cada app (seed por vertical) | Alto | Medio | Las constantes de `ComoLoPide.php`; el algoritmo de `Resolves::pickByName` se vuelve paquete |
| 7 | **Confirmación antes de escribir** como gate del núcleo en canal WhatsApp | `ia-core` (reutiliza el concepto de borrador/`WriteTool` que ya tiene para el panel) | Alto | Medio-alto | La regla del prompt "repite y espera"; el riesgo de agendar sin confirmar deja de depender del modelo |
| 8 | **Modo prueba como flag del contexto** | `ia-core` (`context.modo_prueba`) → `comms-api` no envía | Medio | Bajo | `EsUnaPrueba.php` |
| 9 | **Canal a Connect**: debounce, typing, dedupe `wamid`, botón→texto, ventana 24 h | `comms-api` | Alto | Alto | La mitad de `CommsWebhookController.php` y de `AnswerWhatsappMessageJob.php` |
| 10 | **Simulador de clientes por perfil** (§4) | `ia-core` (motor) + cada app (metas y verificador de estado) | Muy alto | Medio-alto | `EvaluarAgente.php` se queda como el verificador del spa |

### 3.1 El contrato de resultado (número uno porque desbloquea el resto)

Hoy `OpcionesEnviadas` existe porque una herramienta no tiene forma de decirle al orquestador "ya
le contesté yo". Lo resuelve con una caché por teléfono que el job lee al final, y que el evaluador
tiene que limpiar entre casos. Es el síntoma de que falta un campo en el protocolo.

La propuesta es que el Core reconozca un pequeño vocabulario en cualquier resultado de herramienta,
de cualquier app:

- `respondio_al_usuario: true` — el Core no manda el texto del modelo por el canal (o lo devuelve
  vacío con una marca `handled_by_tool` para que la app lo sepa). La regla "una sola lista por turno"
  se aplica en el Core, no en cada capacidad.
- `falta_informacion` + `instruccion` — ya existe; se formaliza y se documenta en `core/tools/base.py`.
- `opciones: [...]` — "esto es ambiguo, estas son las alternativas"; el Core puede decidir por
  política de canal si las manda como lista (punto 2) o se las deja al modelo.
- `supuse: [...]` — "esto lo elegí yo"; el Core lo inyecta en la instrucción de confirmación.

Es una tarde de trabajo en `core/tools/` y `orchestrator.py`, y borra un archivo del spa y un
`Cache::pull` del job.

### 3.2 `ofrecer_opciones` y la paginación, en el núcleo

Es la pieza con más código genérico atrapado en el spa (`OfferOptionsCapability` entera, más las
cuatro rutinas de `AvailabilityCapability`). Y Connect ya sabe mandar listas de 10 filas, esperar la
respuesta y guardar sesiones: el nodo `list` del motor hace exactamente eso.

Diseño: el Core declara `ofrecer_opciones` para toda app cuyo canal sea WhatsApp; su ejecución no
va a la app sino a Connect (`POST /v1/messages/options` o el equivalente), que envía la lista,
recuerda las filas que no cupieron con el mismo TTL de 15 minutos, y traduce el toque de vuelta al
Core como `{eleccion: <id>, titulo: <texto>}` en vez de solo el título. Con eso el POS ofrece
productos y el SGA ofrece sedes o grados con el mismo código, y el "Muéstrame más servicios" deja
de ser una frase mágica que el modelo tiene que reenviar con las mismas palabras.

Lo que se queda en el spa: **qué** opciones y en **qué orden** (`LoQueMasPiden`, la descripción
"45 min · 60.000 COP", `TituloCorto`). La app devuelve la lista completa en `opciones`; el núcleo la
pagina.

### 3.3 Resolutores de argumentos

`FechaDicha` no tiene una línea de spa. El Core puede declarar tipos de parámetro
(`"format": "nexolu/fecha-dicha"`, `"nexolu/franja"`) y resolverlos **antes** de despachar a la
app: la herramienta recibe `fecha: "2026-09-22"` y además `fecha_dicha: "el lunes"` y
`dia: "lunes 22 de septiembre"` para escribirle a la persona. Si no se entiende, el Core devuelve
él mismo el `falta_informacion` sin gastar una llamada a la app. El POS ("para mañana"), el SGA
("la reunión del jueves") y el hogar lo usan sin tocar nada.

### 3.4 Handoff y pausa

`HandoffCapability` hace tres cosas: pausar, dejar nota, marcar no leída. La primera es genérica y
Connect ya recibe `human_reply` y emite `flow_notify`; la pausa debería vivir ahí (un contacto "en
manos de humano hasta T") y el Core consultarla antes de responder, para que `agentIsPaused()` no
tenga que reimplementarse en cada app. La nota en la bandeja sigue siendo un evento que cada app
recibe (`flow_notify`, que el spa ya atiende) y pinta como quiera.

Lo que falta y ninguna app tiene: **detección de bucle**. Con el estado del punto 5 es trivial —
misma herramienta con los mismos argumentos dos veces, o N turnos sin que cambie el conjunto de
datos recogidos — y es el criterio literal de Intercom. El umbral (2, como el demo de Rasa; 3) es
configuración por app.

### 3.5 Estado ligero, no máquina de estados

El informe anterior (§3.3) ya proponía un `dict` de estado en el orquestador para `allowed_tools`.
Aquí se le suman cuatro campos: `ofrecido` (las últimas opciones), `recogido` (qué datos ya se
tienen, derivados de los argumentos que las herramientas aceptaron), `turnos_sin_avance`, y
`ultimo_mensaje_at` para expirar. Con eso:

- "Nunca preguntes algo que ya te dijeron" deja de ser un bullet y pasa a ser contexto inyectado
  ("ya sabes: servicio X, día Y") — la forma de `pattern_collect_information`.
- El reset por inactividad se hace como Rasa: el historial se corta pasadas N horas (para WhatsApp,
  algo entre 6 y 24; hay que medirlo), pero `recogido` y el `user_profile` se conservan.
- El bucle dispara `hablar_con_persona` sin pasar por el modelo.

No es LangGraph ni una máquina de estados formal: son cuatro claves en un diccionario que ya
existe implícitamente en `turns`.

### 3.6 Vocabulario como datos

`ComoLoPide` es Dialogflow *entities* escrito a mano. El algoritmo (normalizar, categoría segura →
probable → tipo en el nombre → exacto) se puede publicar como paquete PHP compartido o como servicio
del Core; las tablas pasan a una tabla `ai_vocabulario(business_id, palabra, apunta_a, tipo)` con un
seed por vertical (uñas, pero también "una gaseosa" → categoría Bebidas en el POS, "el boletín" →
Certificados en el SGA). El negocio podrá completarla desde el panel, como hace Dialogflow con la
generación asistida de sinónimos. Lo que no se mueve es la **decisión** de que el vocabulario se
resuelva en código y no en el modelo: el docstring de `ComoLoPide` lo argumenta y las fuentes de
§1.3 lo confirman.

### 3.7 Lo que se queda en cada app, para dejarlo escrito

Herramientas de negocio y su verdad (disponibilidad, precios, inventario, notas); permisos y
feature flags (`Capability.php`); el orden y la presentación de las opciones; el perfil del
negocio y del cliente que se inyecta al prompt; el verificador de estado final para el simulador
(§4); las **instrucciones del agente**, que son por vertical como los playbooks de Google — pero
adelgazadas a lo que de verdad es del vertical, porque los patrones pasan al núcleo.

---

## 4. Cómo debería ser el simulador de clientes por perfil

Hoy `ia:evaluar` (`app/Console/Commands/EvaluarAgente.php`, `Services/Ia/Evaluacion/CasosReales.php`,
`Banco.php`) manda **guiones fijos** de 1 a 4 mensajes y verifica la trayectoria (`espera` /
`prohibido`). Es evaluación de un turno compuesto, no de una conversación: nadie responde a la lista
que el bot manda, nadie toca una hora, nadie dice "no está el mío" ni "mejor el jueves". Y es lo que
piden todos los productos de §1.5 y los tres papers.

### 4.1 Dónde vive

El motor del simulador en `nexolu-ia-core` (un módulo `evals/` con acceso a los proveedores y al
orquestador), porque el simulador es independiente del vertical. Cada app aporta tres cosas:

1. Un **fixture** de negocio (el spa ya lo tiene en `Banco.php`: negocio, cliente, teléfono de
   prueba).
2. El **modo prueba** (punto 8 de §3): nada sale por Meta; las listas y botones se capturan y se
   devuelven al simulador como si la persona los viera.
3. Un **verificador de estado final**: "¿quedó una cita para estos servicios ese día en esa franja
   para dos personas?" — la comparación de estado de BD contra estado objetivo de τ-bench. Para el
   POS es un pedido; para el SGA una solicitud o un pago registrado. El spa ya sabe borrar lo que
   creó (`EsUnaPrueba::SELLO`).

### 4.2 Perfiles, sembrados de tráfico real

Los arquetipos ya están escritos en `CasosReales.php`: la señora mayor que saluda en tres líneas sin
signos, quien escribe "ola bnas kiero", el mensaje de voz transcrito de corrido, las tres amigas,
la que agenda para el esposo con dos profesionales distintas. Eso es exactamente "personas sembradas
de clusters de tráfico real". Lo que falta es convertir cada uno en un **perfil con dimensiones**
que el simulador pueda combinar:

| Dimensión | Valores de ejemplo | Por qué importa |
|---|---|---|
| Registro y ortografía | correcta / sin tildes ni signos / abreviaturas / transcripción de voz | Lo que rompe el matching de nombres |
| Cuánto sabe del catálogo | dice el nombre real / dice "las manitos" / no sabe qué quiere | Decide si `ComoLoPide` entra en juego |
| Fragmentación | una idea en un mensaje / en tres / con correcciones ("peor a las 10") | Prueba el debounce y el "no repitas preguntas" |
| Cooperación | responde lo que le preguntan / contesta otra cosa / ignora la pregunta | El hallazgo central de arXiv 2605.12894 |
| Interacción con botones | toca / escribe el título / escribe otra cosa parecida / dice "no está el mío" | Prueba la paginación y la traducción botón→texto |
| Corrige a mitad | nunca / cambia el día después de ver horas / cambia de servicio | `pattern_correction` |
| Paciencia | turnos que tolera sin avance antes de quejarse | Detona la frustración |
| Umbral de abandono | turnos totales que aguanta | Da la tasa de abandono, que hoy no se mide |
| Para quién | ella / la hija / dos personas / un grupo | El caso que más plata mueve |

Un perfil es una combinación; el banco de casos es el producto cartesiano recortado a lo que se ve
en producción. La librería de perfiles es **compartida entre verticales** (así escribe la gente por
WhatsApp en Colombia, sea a un salón o a un colegio); lo que cambia por app es la meta.

### 4.3 La meta, oculta y con estado

Cada caso lleva una meta estructurada que el agente no ve: `{servicios: ["semi manos", "pedicure"],
dia: "sábado", franja: "tarde", personas: 2, para_quien: "hija", acepta: {hora_min: "14:00"}}`, y un
**desenlace esperado**: cita creada con esos datos, o relevo a humano, o ninguna cita (cuando lo
correcto es no agendar). El simulador mantiene un estado de meta al estilo UGST — qué ya dijo, qué
le preguntaron, si la opción ofrecida cumple — y decide en cada turno: aceptar, rechazar con
motivo, corregir, insistir o irse. Sin ese estado, el simulador acepta la primera hora que le ofrecen
y la evaluación sale verde por cooperación, que es el fallo documentado.

### 4.4 Qué se mide

Primero lo determinista, que ya existe y no tiene varianza: estado final de BD contra meta;
`espera`/`prohibido` sobre `tools_used`; que ninguna escritura ocurra sin un turno de confirmación
previo (visible en el historial). Encima, por conversación:

- **Tarea completada** (sí/no) y **turnos hasta completar**.
- **Preguntas repetidas** (misma pregunta dos veces; una heurística sobre el texto del bot alcanza
  para empezar, un juez LLM después si hace falta).
- **Listas enviadas** contra **horas escritas en texto** (la métrica de "lo que se toca no se
  escribe").
- **Escalación** (a humano) y **abandono** (el simulador se fue): las dos tasas de §1.5.
- **Latencia y costo** por conversación (ya se guardan por turno).
- **`pass^k`** por caso con N repeticiones, y su histórico — el punto 1 del informe anterior, que
  sigue sin hacerse.

Y la que recomienda tianpan.co: **divergencia simulador–producción**. Con las conversaciones reales
de `whatsapp_conversations` se calculan las mismas distribuciones (turnos, abandono, tasa de
handoff, proporción de botones tocados) y se comparan con las del simulador. Si el simulador
completa en 3 turnos lo que en producción toma 7, el simulador es demasiado amable y hay que
endurecer los perfiles, no celebrar.

### 4.5 Casos desde conversaciones reales que fallaron

El minado propuesto en el informe anterior (§3.4) se concreta así: un comando que recorre
`whatsapp_conversations` + `messages` + `tool_invocation_logs` y marca como candidatas las que
cumplen cualquiera de estas señales — hubo `hablar_con_persona` o `human_reply`; más de N turnos sin
`crear_cita`; la misma herramienta con los mismos argumentos dos veces; la clienta dejó de contestar
después de una pregunta del bot; el bot escribió horas en texto. Cada candidata se anota a mano en
dos campos: **perfil** (de la tabla de §4.2) y **meta** (§4.3), y pasa a ser un caso del banco con
la conversación original guardada como referencia. Es el "cada conversación anotada se vuelve un
test" de Sierra, con nuestras tablas.

### 4.6 Dos cautelas

Usar **otro modelo** para el simulador que para el agente (el efecto "sala de espejos" y los nueve
puntos de variación por cambiar el modelo usuario). Y correr el simulador **contra el modo prueba,
nunca contra Meta**: `EsUnaPrueba` existe porque una corrida mandó listas reales al teléfono de
Alejandro; con perfiles que tocan botones y abandonan, una corrida son cientos de mensajes.

---

## 5. Lo que no deberíamos hacer

Se mantienen íntegras las ocho prohibiciones del informe anterior (§4): ni LangGraph ni Agents SDK,
ni partir el agente, ni más reglas al prompt, ni determinismo bit a bit, ni juez LLM todavía, ni
LLM para disponibilidad, ni propósito general, ni tocar el prefijo del prompt. A eso se suma, por lo
visto aquí:

**No adoptar Rasa, Botpress ni Voiceflow para "tener patrones".** Rasa CALM es la referencia
conceptual de este informe y no su recomendación de compra: traer su runtime significa reescribir
las nueve capacidades como flows YAML, aprender su `CommandGenerator`, y perder el orquestador que
el equipo ya entiende. Lo que vale de Rasa es la **lista de quince patrones con nombre**, que sirve
de checklist para saber qué tiene el núcleo y qué no. Botpress y Voiceflow son builders visuales
para gente sin código; nosotros ya tenemos el builder (Connect) y el código.

**No inventar un DSL de "procedimientos" propio.** Decagon, Intercom y Sierra venden que el
negocio escriba sus pasos en lenguaje natural porque su cliente es un equipo de CX sin ingenieros.
Nuestro cliente es un salón, una tienda, un colegio: nadie ahí va a escribir un AOP. El equivalente
nuestro son las instrucciones del agente en `agents.py` más las herramientas en código, y ya está.

**No mover lógica de negocio al núcleo por comodidad.** La tentación aparecerá con `LoQueMasPiden`
("es solo ordenar por frecuencia") y con `deLaFranja` ("es solo un rango"). La primera consulta
citas del spa; la segunda depende de qué llama "tarde" cada negocio. La prueba para cada pieza es la
de la tabla de §2.2: si para explicarla hay que nombrar una tabla de la app, es de la app.

**No construir un segundo motor de flujos en ia-core.** Connect ya tiene uno con quince tipos de
nodo, sesiones y `notify_app`. Si el núcleo necesita mandar una lista o pausar un contacto, le pide a
Connect; si Connect necesita entender texto libre, le pregunta al Core. La frontera de §1.4 se
implementa en las dos direcciones **entre los dos servicios que ya existen**, no dentro de uno.

**No hacer la extracción de golpe ni sin el evaluador.** Cada punto de §3 borra código del spa. Si
se hacen todos juntos y `ia:evaluar` sigue en N=1 sin histórico, no habrá forma de saber cuál de
los diez movimientos rompió el caso que antes pasaba. El orden es: evaluador persistido con `pass^k`
→ contrato de resultado (§3.1) → una pieza a la vez, con la evaluación en verde entre cada dos.

**No prometer WhatsApp Flows todavía.** Las cifras de completitud son de proveedores sin fuente, y
la política de Meta desde enero de 2026 (informe anterior, §1.9) hace que cualquier superficie nueva
en el número del cliente merezca leerse dos veces. El `cta_url` hacia la agenda web ya existe y
cubre el "hazlo en la web" de hoy; Flows es una opción a evaluar con datos propios cuando el
simulador diga cuántas conversaciones terminan en la web.

---

## Notas sobre las fuentes

Primarias y citables sin reservas: la documentación de Rasa (patterns, CALM, command generators,
writing flows, session timer) y su demo público; la de Dialogflow CX (generative vs deterministic,
playbooks, parameters, entities, sessions); la de Meta (CTA URL); los artículos de ayuda de Intercom
(Fin Procedures, best practices for Fin Tasks); los papers τ-bench (2406.12045), Persona Policies
(2605.12894), UGST (2507.20152) y realsim (2605.02624); las páginas de producto de Sierra, Decagon,
Parloa, Botpress y Voiceflow, con la salvedad de que son páginas de producto y no describen
implementación.

No pude leer, y lo digo: el artículo de Zendesk sobre *agentic AI* (pide login) y la página de OpenAI
sobre Zendesk (403); el artículo oficial del *AI Step* de ManyChat (403), sustituido por un análisis
de terceros; la página de entrada de WhatsApp Flows en developers.facebook.com (sin contenido
legible); la página de referencia de Rasa sobre *dialogue understanding* (404 en la URL que probé;
la lista de comandos salió de la página de *command generators*).

Secundarias, para tomar como orden de magnitud: las cifras de completitud de WhatsApp Flows
(wa.expert, sin fuente); los rangos de contención y de handoff (Bookbag, Bluetweak); los blogs de
tianpan.co y Future AGI sobre simuladores, que son buenos pero son blogs.

No encontré, y lo digo explícitamente: ninguna plataforma que publique **cómo** implementa
internamente la separación núcleo/vertical (todas la venden, ninguna la describe); un umbral canónico
de cuándo mandar al usuario a la web; ni un estudio de simuladores de usuario en español
colombiano o para agendamiento por WhatsApp. Lo más cercano a nuestro caso sigue siendo la
combinación de los patrones de Rasa (qué es genérico) con el diseño de τ-bench (cómo se juzga una
conversación).
