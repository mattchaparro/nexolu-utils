# Asistentes conversacionales de agendamiento por WhatsApp con LLMs — estado del arte 2026

Investigación de septiembre de 2026. El objetivo es contrastar lo que hace hoy la industria con lo
que tenemos montado en `nexolu-ia-core`, `nexolu-spa-api` y `nexolu-comms-api`, y decidir qué vale
la pena mover.

El problema que dispara esta investigación es concreto: el evaluador `php artisan ia:evaluar` da
23, 24, 25 o 26 de 28 sin que cambie una línea de código, y añadir reglas al prompt del agente ya
no mejora nada — a veces empeora. Resulta que ese es un problema conocido, medido y con nombre
propio en la literatura de 2026. Buena parte del informe gira alrededor de eso.

## Lo que ya se hizo con esto (19 de septiembre, madrugada)

Antes de leer las recomendaciones, lo que ya está aplicado y desplegado, para no volver a hacerlo:

- **3.2, temperatura.** Estaba sin fijar y corría con el ~1.0 del proveedor. Ahora `ChatRequest`
  la lleva en 0 por defecto y viaja en el payload (`nexolu_ia_core/core/schemas.py`,
  `providers/openai_compatible.py`). El efecto fue el que anticipa el informe: la evaluación pasó
  de oscilar entre 23 y 26 a dar **26 de 28 con los 26 pasando las tres repeticiones**. Lo que
  falla ahora, falla siempre, que es lo que se puede arreglar.
- **3.1, a medias.** `ia:evaluar --repetir=N` corre cada caso N veces y muestra `(bien/veces)` al
  lado, que es lo que separa un caso roto (0/3) de uno inestable (2/3). Falta lo importante del
  punto: **persistir** la serie para tener histórico y reportar `pass^k` en el tiempo.
- Aparte del informe, esa misma noche se destapó que la evaluación mantenía una transacción abierta
  mientras el Core llamaba de vuelta por HTTP. No protegía de nada — es otro proceso, otra conexión
  — y en cambio dejaba trancada la fila de la conversación: `hablar_con_persona` esperaba 45
  segundos por el candado y el Core lo daba por caído. La evaluación reportaba que el bot no
  escalaba los reclamos a una persona, y el bot sí los escalaba.

Sigue pendiente todo lo demás, y el orden del informe sigue siendo el bueno.

---

## 1. Qué hace hoy la industria

### 1.1 Workflow contra agente: la distinción que ordena todo lo demás

Anthropic separa **workflows** (orquestación predefinida en código) de **agentes** (el LLM dirige
dinámicamente su propio proceso) y cataloga cinco patrones de workflow — prompt chaining, routing,
parallelization, orchestrator-workers, evaluator-optimizer — antes de llegar al agente autónomo.
La recomendación central es explícita y va contra la moda: evitar frameworks complejos, empezar con
la API directa y añadir complejidad solo cuando mejora resultados de forma demostrable
([Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)).

Un asistente de agendamiento es, en esta taxonomía, un **agente de un solo bucle con herramientas**,
no un sistema multiagente. El bucle es corto (entender → consultar disponibilidad → agendar) y el
espacio de acciones es cerrado. Nada en la literatura de 2026 sugiere que partirlo en varios agentes
mejore nada a esta escala; lo que sí aparece repetidamente es que **partir un agente único en varios
hace el debugging exponencialmente más difícil** y que un fallo en una capacidad rompe todo el
sistema, argumento que solo aplica cuando el agente ya es grande
([O'Reilly Radar, The AI Agents Stack 2026](https://www.oreilly.com/radar/the-ai-agents-stack-2026-edition/)).

### 1.2 Grafos y máquinas de estado: LangGraph, OpenAI Agents SDK

LangGraph modela el flujo como un grafo dirigido con estado tipado: nodos que son funciones o
agentes, aristas condicionales, y un objeto de estado compartido. Su rasgo diferencial es el
**checkpointing**: cada transición se persiste, lo que habilita depuración con viaje en el tiempo,
aprobaciones humanas a mitad de ejecución y recuperación tras fallo.

OpenAI archivó Swarm y lo reemplazó por el Agents SDK de producción, cuyas primitivas son
*handoffs* (un agente cede a otro como si fuera una llamada a herramienta), *guardrails* (validación
paralela de entrada que aborta al fallar), *sessions* y *tracing* integrado.

La comparación que hacen los análisis de 2026 es útil: LangGraph responde a "¿qué forma tiene esta
computación?" y conviene cuando el estado explícito, la recuperación de ejecuciones largas y la
intervención humana definen el problema; el Agents SDK conviene cuando quieres un bucle gestionado
con pocas primitivas
([Cipher Projects](https://www.cipherprojects.com/blog/posts/openai-agents-sdk-vs-langgraph-2026/),
[LangChain, AI agent frameworks](https://www.langchain.com/resources/ai-agent-frameworks)).

Ninguno de los dos criterios describe agendar una cita en un salón de uñas.

### 1.3 El patrón que sí describe nuestro caso: CALM / "lógica de negocio en código"

Rasa CALM (*Conversational AI with Language Models*) es la formulación más limpia del patrón. El LLM
no gestiona el diálogo: genera **comandos** a partir de la conversación (`CommandGenerator`), y un
motor determinista ejecuta flujos definidos en código. La frase que resume la arquitectura es que
los LLMs mantienen la conversación fluida pero **no adivinan tu lógica de negocio**
([Rasa, CALM](https://rasa.com/docs/learn/concepts/calm/),
[LLM Command Generators](https://rasa.com/docs/reference/config/components/llm-command-generators/)).

Esto es exactamente lo que nosotros hacemos con `app/Ai/Capabilities/`: la herramienta es el comando,
la capacidad es el flujo determinista. La diferencia es que en CALM el modelo emite comandos contra
un esquema cerrado y validado, mientras nosotros usamos function calling clásico sin `tool_choice`
ni structured outputs.

El mismo principio aparece formulado como regla operativa en los análisis de agendamiento: el modelo
**no debe poder "agendar"** — debe interpretar intención, recolectar contexto y llamar a herramientas
deterministas que son dueñas de la verdad sobre los cupos; depender del LLM para la disponibilidad
de calendario produce alucinaciones y promesas de cupos que no existen
([Mintec, AI agents for appointment scheduling](https://mintec.co/blog/ai-agents-appointment-scheduling-booking/)).

### 1.4 Diseño de herramientas: donde de verdad se gana precisión

Anthropic publicó el material más accionable que existe sobre esto. Los puntos que importan aquí:

- **Las descripciones son prompt.** "Pequeños refinamientos en las descripciones pueden producir
  mejoras dramáticas". Describir la herramienta como a un empleado nuevo, haciendo explícito el
  contexto implícito. Nombres de parámetros inequívocos (`user_id`, no `user`).
- **Consolidar en vez de multiplicar.** El ejemplo literal que usan es `schedule_event` en lugar de
  `list_users` + `list_events` + `create_event`.
- **Namespacing** con prefijos comunes mejora la selección correcta entre herramientas parecidas.
- **Los errores son instrucciones.** Un código de error opaco desperdicia el turno; un mensaje que
  dice qué hacer a continuación reconduce al agente.
- **Devolver contexto significativo**: nombres naturales antes que UUIDs, campos que informen la
  acción siguiente, nada de `mime_type` ni identificadores técnicos.
- **Evaluación dirigida por métricas**: tareas realistas que exijan varias llamadas, midiendo
  exactitud, tiempo, número de llamadas, tokens y errores, con un conjunto retenido para no
  sobreajustar.

([Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents))

### 1.5 Structured outputs y decodificación restringida

A principios de 2026 OpenAI, Anthropic y Google soportan salida estructurada nativa. El modo `strict`
de OpenAI garantiza conformidad de formato; Anthropic no garantiza conformidad en tool use y su
parámetro `strict` se ignora, por lo que hace falta validación propia. En servidores abiertos,
XGrammar es el backend por defecto de vLLM, SGLang y TensorRT-LLM desde marzo de 2026, con menos de
40 µs por token
([BetterLink](https://eastondev.com/blog/en/posts/ai/20260506-llm-structured-output/),
[Aidan Cooper, constrained decoding](https://www.aidancooper.co.uk/constrained-decoding/)).

La advertencia que repiten todas las fuentes serias: **la decodificación restringida garantiza
sintaxis y conformidad de esquema, no corrección factual**. La validación de dominio y el reintento
siguen siendo obligatorios.

Para nosotros la parte relevante es más mundana:

- **OpenRouter soporta `response_format` con `json_schema` y `strict: true`**, y permite
  `require_parameters: true` en las preferencias de proveedor para que solo enrute a endpoints que
  respeten los parámetros enviados
  ([OpenRouter, Structured Outputs](https://openrouter.ai/docs/features/structured-outputs)).
- **Gemini soporta modos de function calling**: `auto`, `any` (obliga a llamar una función), `none`,
  y `allowed_function_names` para restringir el conjunto permitido en un turno dado. También soporta
  llamadas paralelas y encadenadas
  ([Gemini API, Function calling](https://ai.google.dev/gemini-api/docs/function-calling)).

Es decir: hay una palanca de determinismo disponible que hoy no estamos usando.

### 1.6 Evaluación de agentes: lo que hacen los equipos serios

**La brecha eval/observabilidad.** La encuesta *State of Agent Engineering* de LangChain (1.340
respuestas, noviembre–diciembre de 2025) es el dato duro más citado de 2026:

| Métrica | Valor |
|---|---|
| Con agentes en producción | 57,3 % |
| Con observabilidad de algún tipo | 89 % (94 % entre los que están en producción) |
| Con trazado detallado paso a paso | 62 % |
| Con **evals offline** | 52,4 % |
| Con **evals online** | 37,3 % |
| Método de evaluación: revisión humana | 59,8 % |
| Método de evaluación: LLM-as-judge | 53,3 % |
| Barrera principal: **calidad** (consistencia, precisión, alucinaciones) | 33 % |
| Barrera secundaria: latencia | 20 % |
| Usa varios modelos en producción/desarrollo | 75 %+ |
| No hace fine-tuning (prefiere prompting + RAG) | 57 % |

([LangChain, State of Agent Engineering](https://www.langchain.com/state-of-agent-engineering);
resumen en [KDnuggets](https://www.kdnuggets.com/the-state-of-agent-engineering-report-overview))

La lectura que hacen los comentaristas es que esos 37 puntos de diferencia entre observabilidad y
evals son donde muere la calidad: la observabilidad te deja inspeccionar una ejecución mala, pero no
cierra el bucle convirtiendo el fallo en cobertura de regresión
([NoCode.Tech](https://www.nocode.tech/article/langchain-report-quality-not-cost-killing-ai-agents)).

**pass@k contra pass^k.** Esta es la métrica que nos falta y que explica nuestro 23–26 de 28.

- `pass@1`: acierta en un intento.
- `pass@k`: acierta **al menos una** de k veces.
- `pass^k`: acierta **las k veces**.

Con 75 % de acierto por intento: `pass@3 = 1 − 0,25³ = 98,4 %`, pero `pass^3 = 0,75³ = 42,2 %`. Con
90 % de acierto, `pass^8 ≈ 43 %`. La recomendación es usar `pass@1` como métrica más cercana a la
experiencia real, `pass@k` solo si el reintento existe de verdad en el flujo, y **`pass^k` para
agentes de cara al cliente donde la consistencia es lo crítico**
([Bharadwaj P, Measuring agent reliability](https://bharad.dev/blog/measuring-agent-reliability)).

τ-bench introdujo `pass^k` precisamente para agentes de atención al cliente con políticas explícitas
y uso de herramientas; τ²-Bench extiende el entorno a estado compartido entre agente y usuario, con
dominios airline, retail, telecom y banking_knowledge
([sierra-research/tau2-bench](https://github.com/sierra-research/tau2-bench)). No pude verificar en
la documentación pública del repo los conteos exactos por dominio ni si reporta varianza entre
corridas; el paper de referencia es arXiv 2506.07982.

**Golden datasets y trayectorias.** La práctica documentada es: conjunto ancla de 50–100 casos
escritos a mano por expertos con trayectoria esperada validada, creciendo hacia ≥500 casos minados
de tráfico real antes de confiar en métricas agregadas; evaluación **de trayectoria** (la secuencia
de pasos), no solo del resultado final; juez LLM calibrado a 85–90 % de acuerdo con un conjunto
anotado por humanos; y regresión por debajo de la línea base que **bloquea el merge**
([Galtea, guía completa de LLM evaluation 2026](https://galtea.ai/blog/llm-evaluation-complete-guide),
[Medium, Agent Evaluation chapter 8](https://medium.com/@vinodkrane/chapter-8-agent-evaluation-for-llms-how-to-test-tools-trajectories-and-llm-as-judge-788f6f3e0d52)).
Estas cifras vienen de blogs técnicos, no de un estándar; tómalas como orden de magnitud.

**Cómo se maneja el no-determinismo.** Dos hallazgos:

1. **Temperature 0 no es determinista, y la causa está identificada.** Thinking Machines Lab
   demostró que muestrear 1.000 completaciones de Qwen3-235B a temperatura 0 produce 80 salidas
   distintas. La causa no es el muestreo: es que los kernels de matmul, RMSNorm y atención cambian
   el resultado numérico de una muestra **según el tamaño del lote** en el que caiga en el servidor.
   Haciendo tres kernels invariantes al batch obtuvieron 1.000 de 1.000 corridas idénticas bit a bit
   ([Thinking Machines Lab](https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/)).

   La consecuencia práctica para nosotros: **no podemos eliminar la varianza desde el cliente**. La
   carga del servidor de Google/OpenRouter es un parámetro oculto de nuestro evaluador. Lo único que
   queda es medirla.

2. **Una corrida es una muestra de tamaño uno.** La recomendación uniforme es ejecutar cada caso N
   veces y reportar intervalos de confianza o bootstrap, porque un 90 % sobre 10 corridas y un 90 %
   sobre 1.000 son evidencias muy distintas; un agente que pasa el 70 % de las veces produce
   ejecuciones verdes suficientemente a menudo como para parecer fiable hasta que el tráfico real
   revela la tasa real
   ([Label Studio](https://labelstud.io/learning-center/how-to-handle-non-determinism-in-agent-evaluation/),
   [Arize, agent evaluation](https://arize.com/guides/ai-agent-handbook/agent-evaluation/)).

### 1.7 Observabilidad: OpenTelemetry GenAI es el estándar de portabilidad

Las convenciones semánticas GenAI de OpenTelemetry definen tres operaciones:

- `invoke_agent` — span raíz que envuelve la interacción completa del agente
- `chat` — un span por llamada al modelo
- `execute_tool` — un span por invocación de herramienta

Atributos clave: `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`,
`gen_ai.response.finish_reasons`, y opcionalmente `gen_ai.system_instructions`,
`gen_ai.input.messages`, `gen_ai.output.messages`. Métricas:
`gen_ai.client.operation.duration` y `gen_ai.client.token.usage`
([OpenTelemetry blog, Inside the LLM Call](https://opentelemetry.io/blog/2026/genai-observability/),
[semantic-conventions/gen-ai-spans.md](https://github.com/open-telemetry/semantic-conventions/blob/main/docs/gen-ai/gen-ai-spans.md)).

La mayoría de estas convenciones sigue en estado experimental en 2026, con
`OTEL_SEMCONV_STABILITY_OPT_IN` para emisión dual durante las transiciones. Datadog empezó soporte
nativo en OTel v1.37. El coste de instrumentar es despreciable: el procesamiento es asíncrono por
lotes y las llamadas al LLM ya tardan segundos
([Dash0](https://www.dash0.com/knowledge/opentelemetry-genai-semantic-conventions-explained),
[Greptime](https://greptime.com/blogs/2026-05-09-opentelemetry-genai-semantic-conventions)).

Sobre plataformas: Langfuse es la línea base open source y la mejor opción autoalojada para
requisitos de residencia de datos; LangSmith es óptimo si estás sobre LangChain/LangGraph; Braintrust
apunta a rigor en evaluación con gates de CI y releases controlados. El consejo transversal es hacer
del soporte de OTel un requisito duro de compra, para no quedar atrapado
([MarkTechPost, comparativa 2026](https://www.marktechpost.com/2026/08/09/top-llm-observability-and-evaluation-platforms-in-2026-langfuse-langsmith-braintrust-arize-and-more-compared/),
[Latitude, comparativa](https://latitude.so/blog/ai-agent-observability-tools-compared-latitude-vs-langfuse-langsmith-braintrust)).

### 1.8 Contexto y memoria

Anthropic publicó la guía más concreta. Las ideas que aplican aquí:

- **La "zona Goldilocks" del system prompt.** Demasiado específico (lógica if-else hardcodeada en el
  prompt) produce fragilidad y coste de mantenimiento creciente; demasiado vago no da señal. La cita
  literal sobre el fallo que nosotros estamos viviendo: *"hardcoding complex, brittle logic in their
  prompts to elicit exact agentic behavior... creates fragility and increases maintenance complexity
  over time"*.
- **Estructurar el prompt en secciones** con etiquetas XML o encabezados Markdown
  (`<background_information>`, `<instructions>`, `## Tool guidance`, `## Output description`).
- **Método de construcción**: empezar con un prompt mínimo en el mejor modelo disponible y añadir
  instrucciones **a partir de fallos observados**, no por anticipación.
- **Regla de oro para herramientas**: si un ingeniero no puede decir con certeza cuál herramienta
  usar en una situación, el agente tampoco podrá.
- **Ejemplos**: pocos y canónicos, no una lista de casos borde.
- **Compaction** (resumir la conversación conservando decisiones y pendientes, descartando salidas
  redundantes), **structured note-taking** (memoria persistente fuera de la ventana) y
  **subagentes** (contextos limpios que devuelven resúmenes de 1.000–2.000 tokens). La forma más
  segura y ligera de compaction es el **borrado de resultados de herramientas antiguos**.
- **Just-in-time retrieval**: guardar identificadores ligeros y cargar en runtime, en lugar de
  precargar todo.

([Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents),
[Claude Cookbook, context engineering](https://platform.claude.com/cookbook/tool-use-context-engineering-context-engineering-tools))

Sobre "evitar que el modelo cite datos viejos": el mecanismo estándar es exactamente el borrado de
resultados de herramientas antiguos, más re-consultar antes de afirmar. No encontré una técnica
distinta o más sofisticada que sea consenso en 2026.

### 1.9 WhatsApp: reglas específicas del canal

**Cambio de política de Meta, enero de 2026.** Meta actualizó los términos del WhatsApp Business
Solution el **15 de enero de 2026** para bloquear **asistentes de IA de propósito general** en la
plataforma; los usuarios nuevos de la API registrados desde el 15 de octubre de 2025 quedaron sujetos
de inmediato. ChatGPT, Copilot y Perplexity dejaron de poder operar por la Business API. **Lo que
sigue permitido y explícitamente fomentado son bots de IA para tareas de negocio estructuradas:
servicio al cliente, consultas de pedidos y gestión de citas**
([respond.io](https://respond.io/blog/whatsapp-general-purpose-chatbots-ban),
[TechCrunch, octubre de 2025](https://techcrunch.com/2025/10/18/whatssapp-changes-its-terms-to-bar-general-purpose-chatbots-from-its-platform/)).

Nosotros estamos del lado permitido, pero conviene que el prompt y el producto sigan haciendo
evidente que el asistente está acotado a agendar y atender: el criterio que citan los análisis es
"propósito definido, puntos de entrada estructurados, nodos de validación y criterios explícitos de
finalización", es decir, un flujo que **no puede derivar en conversación abierta**
([Alibaba Cloud, guía de política 2026](https://www.alibabacloud.com/help/en/chatapp/use-cases/whatsapp-ai-policy-2026-guide)).

**Mensajes interactivos.** Las listas admiten hasta 10 secciones con **10 filas en total** entre
todas las secciones, más encabezado y pie opcionales. Los botones de respuesta rápida admiten un
máximo de **3**
([Interactive list messages](https://developers.facebook.com/docs/whatsapp/cloud-api/messages/interactive-list-messages/),
[Interactive reply buttons](https://developers.facebook.com/docs/whatsapp/cloud-api/messages/interactive-reply-buttons-messages/)).

**Indicador de escritura.** Se envía como `POST /{PHONE_NUMBER_ID}/messages` con
`status: "read"`, el `message_id` del mensaje entrante y `typing_indicator: {"type": "text"}`. Se
descarta al responder **o a los 25 segundos**, lo que ocurra primero. Meta advierte que solo debe
mostrarse si de verdad vas a responder, y requiere haber recibido antes un webhook de mensaje
([Typing indicators, Meta](https://developers.facebook.com/docs/whatsapp/cloud-api/typing-indicators)).

Esto importa más de lo que parece: un estudio con 209 participantes citado en la literatura de
latencia conversacional encontró que **2,3 segundos de retraso con indicador de escritura dio
satisfacción estadísticamente indistinguible de una respuesta instantánea**, y que sin el indicador
la satisfacción caía significativamente con el mismo retraso
([Orvera, latency optimization](https://orvera.ai/blogs/optimize-latency-conversational-ai)). No
pude rastrear el estudio primario; trátalo como indicativo, no como cifra dura.

**Debounce.** El patrón documentado es *trailing-edge debounce*: al llegar cada mensaje se programa
un trabajo diferido (~3 s) y al dispararse comprueba si llegaron mensajes más nuevos; si sí, se
retira. La ventana es un compromiso: corta parte los mensajes, larga se siente lenta
([DEV, routing de WhatsApp a N agentes](https://dev.to/seryllns_/how-we-route-whatsapp-messages-to-n-agents-with-a-single-llm-call-5d22)).

**Ventana de 24 h y precios.** Desde el **1 de julio de 2025** el cobro es por mensaje, no por
conversación. Las respuestas no-plantilla dentro de la ventana de servicio abierta siguen siendo
gratuitas, **pero desde el 1 de octubre de 2026 Meta empezará a cobrar por mensaje de negocio,
incluidas las respuestas de servicio y las plantillas de utilidad dentro de la ventana de 24 horas**
([Blueticks, pricing 2026](https://blueticks.co/blog/whatsapp-business-api-pricing-2026),
[WhatsApp Business Platform pricing](https://whatsappbusiness.com/products/platform-pricing/)).
Esta última fecha es de fuente secundaria y conviene verificarla con Meta directamente, porque
cambia la economía de fragmentar respuestas en varios mensajes.

### 1.10 Coste y latencia

**Prompt caching.** A junio de 2026 los tres grandes proveedores descuentan el input cacheado en un
90 %: OpenAI en la familia GPT-5.x, Anthropic en todos los modelos Claude actuales, Google en Gemini
2.5 y posteriores. Anthropic cobra un recargo de escritura (1,25× para TTL de 5 minutos, 2× para
1 hora); el caching explícito de Gemini añade una tarifa de almacenamiento por hora. La latencia cae
entre 40 % y 80 % en prompts mayoritariamente cacheados
([LeanLM, comparativa de prompt caching](https://leanlm.ai/blog/prompt-caching),
[PromptHub](https://www.prompthub.us/blog/prompt-caching-with-openai-anthropic-and-google-models)).

La implicación de diseño es directa: **todo lo estable va al principio del prompt y lo variable al
final**. Ponerle la fecha de hoy al comienzo del system prompt invalida el caché en cada turno.

**Routing y cascadas.** El routing decide de una vez a qué modelo va la consulta; la cascada empieza
barata y escala si la confianza es baja. Las cifras reportadas van de 45 % a 85 % de ahorro
manteniendo ~95 % de la calidad; RouteLLM reportó más de 85 % de reducción de coste en MT-Bench
enviando solo el 14 % de las consultas al modelo fuerte
([TrueFoundry](https://www.truefoundry.com/blog/llm-routing-cost-quality-aware-model-selection),
[NeuralTrust](https://neuraltrust.ai/blog/llm-model-routing)). Para un salón con volumen bajo esto
es irrelevante como ahorro; puede ser relevante como **cascada de calidad** (escalar a un modelo
mejor cuando el caso es ambiguo), que es otro problema.

**Llamadas por turno.** No encontré un número canónico. Lo que sí es consenso es que cada llamada
extra suma latencia completa del modelo y que los agentes de atención al cliente en producción
apuntan a primera respuesta por debajo de 30 segundos
([008agent, guía WhatsApp 2026](https://www.008agent.ai/blog/ai-agents-whatsapp-business-guide)).
Nuestro tope de 6 iteraciones está en el rango razonable; lo que no tenemos es la distribución real.

---

## 2. Qué tenemos ya que está bien

Esto no es cortesía. Varias decisiones del repo coinciden con lo que las fuentes de 2026 recomiendan,
y algunas van por delante de lo que hace la mayoría.

**La lógica de negocio está en código, no en el prompt.** `C:\Nexolu\nexolu-spa-api\app\Ai\Capabilities\`
(9 archivos, 1.590 líneas) es un `CommandGenerator` de CALM sin saberlo. `AvailabilityCapability.php`
(381 líneas) resuelve "el lunes" a fecha real, filtra franja, encadena multi-servicio y multi-persona,
recorta a 4 opciones y envía los botones él mismo. El modelo nunca decide si hay cupo. Esto es
literalmente la recomendación de la industria y es la razón por la que el sistema funciona a pesar
de la varianza del modelo.

**Las descripciones de herramientas están escritas como prompt.** `nexolu-ia-core\nexolu_ia_core\apps\spa\tools.py`
tiene descripciones de 40–100 palabras con justificación de negocio y antipatrones dentro, no
one-liners. Esa es exactamente la palanca que Anthropic identifica como la de mayor retorno, y
coincide con lo que ustedes ya observaron empíricamente ("lo que sí mejoró fue mover decisiones al
código y a las descripciones de las herramientas").

**Las herramientas están consolidadas, no atomizadas.** 9 herramientas, con ausencias deliberadas y
documentadas (`clientes`, `empleados`). `crear_cita` es un `schedule_event`, no tres llamadas. Coincide
con el ejemplo textual de Anthropic.

**Los errores de dominio viajan como datos, no como HTTP.** `AiToolInvokeController.php` convierte
`AiArgumentException` en un 200 con `falta_informacion` + `instruccion: "Pregúntale eso a la clienta
y vuelve a intentarlo. No es un fallo del sistema."` Esto es el patrón de "errores accionables" de
Anthropic, implementado bien.

**El `context` se trata como afirmación, no como credencial.** Todo se re-resuelve contra BD;
`MyAppointmentsCapability` no acepta ningún argumento que identifique a un cliente; `Cancel` devuelve
lo mismo para cita ajena e inexistente. Es la clase de guardrail que el Agents SDK vende como
característica.

**Ya hay compaction de resultados de herramientas.** `orchestrator.py::_compact_tool_result()`
(líneas 556-589) reemplaza resultados de herramientas antiguos por una nota de descarte. Eso es la
forma "más segura y ligera de compaction" que Anthropic describe, y es el mecanismo correcto contra
el problema de "el modelo cita datos viejos". Ya está hecho.

**El prompt está diseñado para ser cacheable.** `_build_turns()` inyecta el contexto temporal pegado
al último turno de usuario, no al system prompt, explícitamente para mantener estable el prefijo. Y
`openai_compatible.py:113` envía `usage: {include: true}` para leer `cached_tokens`, con una propiedad
`cache_ratio` en `core\schemas.py:92`. La instrumentación de caché existe.

**El evaluador mide trayectoria, no texto.** `EvaluarAgente.php` verifica `espera` / `prohibido`
contra `tools_used`. Eso es evaluación de trayectoria, que es lo que la literatura de 2026 pide, y
está por encima de lo que hace la media (recordar: solo 52,4 % de los equipos hace evals offline de
cualquier tipo). Que `prohibido` sea falla dura y `espera` sea aviso es una distinción sensata.
Que los mensajes del caso se unan con `\n` "como los junta el debounce en producción" es fidelidad
real al entorno.

**Flow first, LLM fallback ya está implementado, y bien.** El motor de flujos marca
`event.flow_handled`, `forwarder.py:88` lo traduce a `X-Nexolu-Flow-Handled`, y
`CommsWebhookController.php:136` calla al agente si vale `1`. Sin header el LLM sigue funcionando
(degradación segura). Además hay un segundo mute por `agentIsPaused()` para el relevo humano. La
industria describe este patrón; ustedes lo tienen.

**Debounce y typing indicator existen.** 8 s de debounce en `AnswerWhatsappMessageJob`, con
desempate por ID de mensaje (no timestamp), idempotencia por `wamid` en caché 6 h, y
`markAsReadWithTyping()` invocado sin bloquear el 200. Tres detalles que la mayoría se salta.

**Ventana de 24 h correctamente modelada.** `last_inbound_at` separado de `last_message_at` porque
"la ventana la abre EL MENSAJE DE ELLA". Ese es el bug clásico y aquí no está.

**Se mide latencia, tokens y coste por turno.** `Message` guarda `latency_ms`, `input_tokens`,
`output_tokens`; `usage_daily` acumula con `cost_micros` del proveedor. Los datos existen; lo que
falta es el consumo de esos datos (ver §3.4).

---

## 3. Qué nos falta, ordenado por valor/esfuerzo

| # | Qué | Valor | Esfuerzo | Repo |
|---|---|---|---|---|
| 1 | Persistir resultados del evaluador y reportar `pass^k` con N repeticiones por defecto | Muy alto | Bajo | `nexolu-spa-api` |
| 2 | Fijar `temperature: 0` (y `seed` si el proveedor lo acepta) | Alto | Muy bajo | `nexolu-ia-core` |
| 3 | `tool_choice` / `allowed_function_names` por fase de conversación | Alto | Bajo-medio | `nexolu-ia-core` |
| 4 | Ampliar el golden set de 28 a ~100 casos, con holdout | Alto | Medio | `nexolu-spa-api` |
| 5 | Trazas OpenTelemetry GenAI (`invoke_agent` / `chat` / `execute_tool`) | Alto | Medio | `nexolu-ia-core` |
| 6 | Adelgazar el prompt del agente moviendo reglas a herramientas y código | Medio-alto | Medio | ambos |
| 7 | Consumir el `cache_ratio` que ya medimos; alertar si cae | Medio | Bajo | `nexolu-ia-core` |
| 8 | Memoria por contacto resumida en vez de ventana fija de 20 | Medio | Medio | `nexolu-ia-core` |
| 9 | Troceo de respuestas largas y más uso de listas interactivas | Medio | Bajo-medio | `nexolu-spa-api` |
| 10 | Unificar `send_message` / `send_message_stream` | Medio | Bajo | `nexolu-ia-core` |

### 3.1 Persistir los resultados del evaluador y reportar `pass^k` — el punto número uno

**Qué es.** Hoy `ia:evaluar` imprime a stdout y no guarda nada: no hay serie histórica, no hay
intervalo de confianza, y el exit code solo mira las fallas duras. Con `--repetir=N` ya acumulas
`(bien/veces)` por caso, pero el número se pierde al cerrar la terminal.

Lo que falta es pequeño: escribir cada corrida a un JSON o a una tabla (`caso`, `commit`, `modelo`,
`prompt_hash`, `intento`, `tools_used`, `veredicto`, `latencia_ms`, `tokens`), y que el resumen
reporte `pass@1` (media sobre N·28) y **`pass^k` por caso** (cuántos casos pasaron las N veces).

**Por qué importa aquí.** El 23/24/25/26 de 28 no es ruido de medición: es la métrica que tienen.
Con N=1 no se puede distinguir "cambié el prompt y mejoró" de "esta vez tuve suerte". Y el hallazgo
de Thinking Machines dice que **no van a poder eliminar esa varianza desde el cliente** — la carga
del servidor de inferencia es un parámetro que no controlan. La única salida es medirla: con N=5 y
28 casos son 140 conversaciones, perfectamente asumible en una corrida nocturna.

Un ejemplo de lo que aparecería de inmediato: si 25 casos pasan siempre y 3 pasan la mitad de las
veces, `pass^5` da 25/28 estable y sabes exactamente qué 3 casos arreglar. Hoy el ruido está
repartido y parece que todo se mueve.

**Qué tocar.** `C:\Nexolu\nexolu-spa-api\app\Console\Commands\EvaluarAgente.php`: cambiar el default
de `--repetir` a 3 o 5, añadir `--json=ruta` y el cálculo de `pass^k`. Opcionalmente una migración
para una tabla `ia_evaluaciones`. El umbral de CI pasa a ser sobre `pass^k`, no sobre una corrida.

### 3.2 Fijar temperatura y semilla

**Qué es.** Hoy no se envía `temperature` en ninguna parte de `nexolu-ia-core` (grep vacío): se usa
el default del proveedor, que para Gemini vía OpenRouter suele ser 1.0. Para un agente que elige
herramientas de un conjunto de 9, eso es varianza regalada.

**Por qué importa.** No elimina el no-determinismo — Thinking Machines es claro en que
`temperature=0` es "necesario pero salvajemente insuficiente" — pero elimina la capa de varianza que
sí está bajo nuestro control. Es la mitad del problema, resuelta con una línea.

**Qué tocar.** `C:\Nexolu\nexolu-ia-core\nexolu_ia_core\providers\openai_compatible.py`, en el
payload junto a `max_tokens`. Exponerlo como setting por agente. Hacerlo **antes** de tocar nada más,
porque cambia la línea base de todas las mediciones siguientes.

### 3.3 `tool_choice` y `allowed_function_names`

**Qué es.** Gemini soporta modo `any` (obliga a llamar alguna función) y `allowed_function_names`
(restringe el conjunto en ese turno). OpenRouter deja pasar los parámetros y permite
`require_parameters: true` para enrutar solo a proveedores que los respeten.

**Por qué importa para un salón.** Buena parte de los fallos de un agente de agendamiento son "no
llamó a la herramienta que debía" o "respondió de memoria en vez de consultar". Ese es precisamente
el tipo de decisión que no debería estar en el prompt. Casos concretos donde restringir el conjunto
es trivialmente correcto:

- Si la clienta acaba de recibir opciones de horario y responde con una, el conjunto permitido es
  `{crear_cita}` (y `hablar_con_persona`). No hay razón para que `servicios` esté disponible.
- Si aún no hay contacto guardado y es el primer turno, `guardar_contacto` puede forzarse.
- Cuando el turno anterior fue `disponibilidad`, prohibir volver a llamar `disponibilidad` con los
  mismos argumentos corta un bucle observable.

Esto es mover decisiones al código, que es exactamente lo que ya vieron que funciona, pero en la capa
del protocolo en vez de la del prompt.

**Qué tocar.** `openai_compatible.py` para pasar el parámetro, y `orchestrator.py` para calcular el
conjunto permitido a partir del estado del turno anterior. Ojo: esto empieza a ser una máquina de
estados ligera. No hace falta LangGraph — hace falta un `dict` de estado en el orquestador.

### 3.4 Ampliar el golden set

**Qué es.** 28 casos escritos a mano es un buen ancla (la práctica documentada habla de 50–100 a
mano), pero está por debajo, y no hay conjunto retenido: cada regla nueva del prompt se ajusta contra
los mismos 28, que es la definición de sobreajuste.

**Por qué importa.** `CasosReales.php` ya tiene la estructura correcta (bloques temáticos, `espera`,
`prohibido`, `nota` pedagógica). Lo que falta es volumen y procedencia: casos minados de
conversaciones reales de WhatsApp, no inventados. Un salón genera decenas de conversaciones al día;
en un mes hay material para 200 casos con trayectoria conocida.

Y falta la división: un set de desarrollo contra el que iterar y un **holdout** que solo se corre
antes de desplegar. Si no, cada ajuste del prompt es memorización.

**Qué tocar.** `C:\Nexolu\nexolu-spa-api\app\Services\Ia\Evaluacion\CasosReales.php` (añadir un campo
`conjunto: 'dev'|'holdout'`) y un comando que extraiga candidatos de `whatsapp_conversations` +
`tool_invocation_logs` para revisarlos a mano. No hace falta LLM-as-judge: la trayectoria es
verificable con `assert` sobre `tools_used`, que es más barato y más estable que un juez. Un juez
solo aportaría en las 2-3 dimensiones de texto (tono, no prometer lo que no hay), y ahí sí sería
justificable — pero después, no antes.

### 3.5 Trazas OpenTelemetry

**Qué es.** No hay OTel, Langfuse ni Sentry en ninguno de los tres repos. Hay `logging` estándar y
una auditoría propia (`ToolInvocationLog` con `arguments`, `status`, `result_summary[:500]`) que es
buena pero es una tabla, no una traza: no encadena el turno completo ni deja ver dónde se fue el
tiempo.

**Por qué importa.** El dato de la encuesta de LangChain es que 89 % tiene observabilidad y 52 %
tiene evals; nosotros estamos en el cuadrante raro — tenemos evals y no tenemos trazas. Cuando una
clienta se queja de que el bot "se enredó", hoy hay que reconstruirlo leyendo filas de tres tablas.
Con `invoke_agent` → `chat` → `execute_tool` se ve el turno entero, con latencias por span, y se
responde en segundos a "¿fue el modelo o fue la consulta de disponibilidad?".

La instrumentación es barata porque los datos ya se recogen: `latency_ms`, `input_tokens`,
`output_tokens`, `model`, `tool_name` están todos en `Message` y `ToolInvocationLog`. Es cuestión de
emitirlos como spans con nombres estándar.

**Qué tocar.** `C:\Nexolu\nexolu-ia-core\nexolu_ia_core\core\telemetry\logging.py` (45 líneas) es el
lugar natural; instrumentar `orchestrator.py` (span raíz por turno, hijo por llamada al proveedor,
hijo por herramienta) y `core\tools\` (span por ejecución). Añadir `opentelemetry-sdk` +
`opentelemetry-exporter-otlp` a `pyproject.toml`. Destino: Langfuse autoalojado es la opción sensata
(open source, acepta OTLP, datos en nuestro droplet). Si se hace bien, `nexolu-comms-api` y
`nexolu-spa-api` pueden propagar el mismo trace-id y verse el turno desde el webhook de Meta.

**Cuidado con la privacidad.** `gen_ai.input.messages` y `gen_ai.output.messages` llevan el contenido
literal de la conversación de una clienta. Eso se activa por configuración explícita, no por defecto.

### 3.6 Adelgazar el prompt del agente

**Qué es.** `agents.py::INSTRUCCIONES` son 8.612 caracteres / 1.581 palabras, y el bloque dominante
es "Reglas que no puedes romper" con ~20 bullets. Esto es precisamente lo que Anthropic describe como
*brittle logic hardcoded in prompts*, con la consecuencia que ustedes ya observan: añadir reglas deja
de mejorar y a veces empeora.

**Por qué importa.** Cada regla nueva compite por atención con las anteriores. La guía recomienda el
camino inverso: empezar mínimo y añadir solo a partir de fallos observados, con secciones
delimitadas (`<instructions>`, `## Tool guidance`), ejemplos canónicos pocos y diversos en lugar de
una lista de casos borde.

**Qué tocar.** Para cada bullet de "Reglas que no puedes romper", preguntar en orden:

1. ¿Puede ser una validación en `app/Ai/Capabilities/`? → va a `nexolu-spa-api`.
2. ¿Puede ser parte de la descripción de una herramienta? → va a `tools.py`.
3. ¿Puede ser un `allowed_function_names` según el estado? → va a `orchestrator.py`.
4. Si no es ninguna, entonces sí es prompt.

Mi expectativa, mirando la lista de capacidades que ya existen, es que la mayoría cae en 1 o 2. Y
esto **hay que hacerlo con el evaluador arreglado primero** (§3.1), porque si no, no habrá forma de
saber si quitar una regla rompió algo o fue la varianza.

También: aplicar encabezados Markdown/XML a las secciones existentes de `INSTRUCCIONES` es un cambio
de media hora con retorno medible.

### 3.7 Consumir el `cache_ratio`

**Qué es.** Ya se pide `usage: {include: true}` y ya existe `ChatResult.cache_ratio`, pero no encontré
que se consuma en ningún sitio. Un prompt de ~2,2k tokens de instrucciones más el business_profile
más 20 mensajes de historial es exactamente el perfil donde el caché implícito de Gemini paga.

**Por qué importa.** Menos por coste (el volumen de un salón es bajo) que por **latencia**: 40–80 %
menos en prompts mayoritariamente cacheados. En WhatsApp la latencia percibida es el producto.

Y sirve como canario: si el `cache_ratio` se desploma después de un cambio, es que alguien metió algo
variable al principio del prompt. Hoy no nos enteraríamos.

**Qué tocar.** Guardar `cached_tokens` en `Message` junto a `input_tokens`, agregarlo en
`usage_daily`, y sacarlo por el mismo sitio que el resto de métricas de admin.

### 3.8 Memoria por contacto

**Qué es.** Hoy la memoria es una ventana fija de 20 mensajes (`Settings.ai_history_turns`) más la
compactación de resultados de herramientas. No hay resumen ni perfil persistente de la clienta.

**Por qué importa para un salón.** Una clienta que vuelve cada tres semanas arranca con la ventana
llena de la conversación de hace un mes o vacía, según el ritmo. Lo que debería persistir es poco y
estructurado: nombre y cómo prefiere que la llamen, servicios que suele pedir, con qué empleada, si
prefiere mañana o tarde, si alguna vez hubo un problema. Eso es *structured note-taking*: un
documento pequeño por contacto, escrito por código a partir de las citas reales (no por el modelo),
inyectado al prompt.

Ojo con la diferencia: **no debe ser el modelo quien escriba la memoria**. Las citas ya están en la
BD del Spa; el perfil se deriva de ahí. Si el modelo escribe la memoria, las alucinaciones se vuelven
permanentes.

**Qué tocar.** El `user_profile` que `SystemPromptBuilder.build()` ya inyecta es el hueco donde va.
Lo que falta es que `nexolu-spa-api` lo calcule desde el historial de citas y lo exponga. Beneficio
lateral: sustituye parte de la ventana de 20 mensajes, lo que ahorra tokens y mejora el caché.

### 3.9 Troceo de respuestas y más listas interactivas

**Qué es.** No hay troceo de salida en ninguno de los dos repos; el control de longitud es indirecto
(`max_tokens=1500` más instrucciones de estilo). El nodo `blocks` del motor de flujos sí trocea con
esperas de 1-15 s entre mensajes, pero el agente no tiene equivalente.

**Por qué importa.** Un párrafo de 1.500 tokens en WhatsApp es ilegible. Y el canal ya tiene la
solución nativa: `interactive.list` admite 10 filas en total y los botones 3. `OfferOptionsCapability`
y `AvailabilityCapability` ya los usan bien; el patrón podría extenderse a la selección de servicio
y de empleada, que hoy probablemente se resuelven por texto libre.

**Aviso económico**: si se confirma que desde el 1 de octubre de 2026 Meta cobra por cada mensaje de
negocio incluso dentro de la ventana de 24 h, trocear una respuesta en tres mensajes triplica el
coste de ese turno. Eso convierte el troceo de una mejora de UX gratis en un compromiso. **Verificar
esa fecha con Meta antes de implementar troceo agresivo.**

**Qué tocar.** `C:\Nexolu\nexolu-spa-api\app\Jobs\AnswerWhatsappMessageJob.php` para el troceo por
párrafos; las capacidades del catálogo para convertir más preguntas en listas.

### 3.10 Unificar los dos caminos del orquestador

`send_message()` (líneas 71-244) y `send_message_stream()` (246-439) duplican ~120 líneas idénticas
de persistencia y ejecución de herramientas, y el backoff está reimplementado a mano en el camino de
streaming. Es riesgo de divergencia puro: todo lo que se añada arriba (temperatura, `tool_choice`,
spans OTel) hay que añadirlo dos veces o se pierde en uno de los dos.

No es estado del arte, es higiene, pero conviene hacerlo **antes** de §3.2, §3.3 y §3.5 para no pagar
el trabajo dos veces.

---

## 4. Lo que NO deberíamos hacer

**No migrar a LangGraph, CrewAI, AutoGen ni al OpenAI Agents SDK.** El criterio para LangGraph en
2026 es "cuando el estado explícito, la recuperación de ejecuciones largas y la intervención humana
definen el problema". Agendar una cita es un bucle de 1-3 llamadas a herramientas contra una API
propia; no hay ejecución larga que recuperar ni grafo que inspeccionar. La recomendación de Anthropic
sigue siendo empezar con la API directa y añadir framework solo si mejora resultados de forma
demostrable. Además, el orquestador actual son 675 líneas que el equipo entiende, con guard de
herramientas, compactación y fallback por `models` de OpenRouter ya resueltos; migrar significa
reimplementar eso dentro de las abstracciones de otro. El coste es real y el beneficio, hipotético.

**No partir el agente en varios agentes.** Un `recepcionista` con 9 herramientas está muy lejos del
punto donde la descomposición paga. Los subagentes de Anthropic existen para aislar contextos de
investigación larga y devolver resúmenes de 1.000-2.000 tokens; aquí no hay nada que aislar. Partirlo
añadiría latencia (un turno extra de modelo por handoff) y un modo de fallo nuevo (el enrutador se
equivoca). El docstring de `agents.py` ya justifica el agente único correctamente.

**No añadir más reglas al prompt esperando que mejore.** Ya está medido en el repo y explicado en la
literatura: la lógica frágil hardcodeada en el prompt crea fragilidad y coste de mantenimiento
creciente. La tasa de retorno de esa palanca es negativa a partir de cierto punto y ya lo pasamos.
Si aparece un fallo nuevo, la pregunta es "¿en qué capacidad o en qué descripción de herramienta
vive esto?", no "¿qué bullet añado?".

**No perseguir el determinismo bit a bit.** Es tentador leer el artículo de Thinking Machines y
pensar en autoalojar un modelo con kernels invariantes al batch. Para 28 casos de un salón de uñas
eso es desproporcionado: significa abandonar Gemini 2.5 Flash, montar inferencia propia y mantenerla.
La respuesta correcta es aceptar la varianza y **medirla con `pass^k`**, que cuesta una tarde.

**No meter LLM-as-judge todavía.** El 53,3 % de los equipos lo usa, pero nuestro evaluador ya mide
trayectorias con asserts deterministas, que es más barato, más rápido y no tiene varianza propia.
Un juez calibrado exige su propio conjunto anotado por humanos (85-90 % de acuerdo) y se convierte en
un segundo sistema que mantener y evaluar. Solo tiene sentido después de que el golden set esté
ampliado y persistido, y solo para las dimensiones de texto que los asserts no pueden cubrir.

**No usar el LLM para calcular disponibilidad, precios ni fechas.** Ya no lo hacemos —
`AvailabilityCapability` resuelve todo, `ServicesCapability` devuelve el precio ya formateado como
texto porque un `180000.0` hizo que el modelo escribiera "$180.00". Dejar constancia de por qué:
ese tipo de decisión vuelve a proponerse cada vez que alguien quiere "simplificar" quitando código.

**No abrir el agente a conversación de propósito general.** Además de ser mala idea de producto, desde
el 15 de enero de 2026 los términos del WhatsApp Business Solution bloquean asistentes de IA de
propósito general en la plataforma. Lo permitido son bots acotados a tareas de negocio estructuradas
— gestión de citas está explícitamente entre ellas. Cualquier propuesta de "que también responda
preguntas generales" es un riesgo regulatorio sobre el número de WhatsApp del cliente, no solo una
decisión de diseño.

**No mover el contexto temporal al principio del system prompt.** Parece más limpio y rompe el caché
de prefijo en cada turno. La decisión actual de pegarlo al último turno de usuario está bien y está
documentada; conviene que quede escrita también aquí.

**No subir el debounce por encima de ~10 s ni bajarlo de ~5.** Los 8 s actuales están en el rango
razonable. Más corto parte los mensajes de quien escribe en ráfaga (que es como escribe la gente en
WhatsApp); más largo se siente muerto. Si se quiere mejorar la percepción, la palanca es el indicador
de escritura, que ya está implementado y dura hasta 25 segundos.

---

## Notas sobre las fuentes

Las fuentes primarias usadas aquí son: Anthropic Engineering (tres artículos), la documentación de
Meta para WhatsApp Cloud API, la documentación de Rasa, la de Gemini API, la de OpenRouter, el blog
y las convenciones semánticas de OpenTelemetry, el blog de Thinking Machines Lab y el informe *State
of Agent Engineering* de LangChain. Esas se pueden citar sin reservas.

Lo que viene de blogs técnicos secundarios y conviene verificar antes de apoyarse en ello:

- Las cifras de tamaño de golden dataset (50-100 a mano, ≥500 para agregados) y el umbral de
  calibración de jueces (85-90 % de acuerdo) circulan en varias guías de 2026 pero no tienen un
  origen normativo.
- El estudio de 209 participantes sobre indicador de escritura y 2,3 s de retraso: no encontré el
  paper original.
- La fecha del **1 de octubre de 2026** para el cobro de mensajes de servicio dentro de la ventana de
  24 h viene de análisis de terceros. Es un dato con consecuencias económicas directas para §3.9 y
  hay que confirmarlo en la documentación de precios de Meta.
- Los conteos de tareas por dominio de τ²-Bench (airline 50, retail 114, telecom 114) aparecen en
  fuentes secundarias; no los pude confirmar en el README del repositorio.

No encontré, y lo digo explícitamente: un número canónico de "llamadas a herramientas por turno
razonables" para agentes conversacionales, ni benchmarks públicos de agentes de agendamiento en
español, ni evidencia de que algún producto grande de agendamiento por WhatsApp publique su
arquitectura con detalle. Lo que hay son guías de proveedores y posts de ingeniería sueltos.
