# Day 25 — Spring AI Fundamentals (ChatClient, Prompts, Structured Output)

> **Spring AI 1.0 (GA, 2025)** brings Spring-idiomatic AI: portable abstractions over LLM providers, auto-configuration, and the patterns you already know (starters, `@ConfigurationProperties`, fluent builders). This is the hottest topic in Spring interviews right now.

## THEORY

### 1. What Spring AI is (and the core idea)
Spring AI is an application framework for building AI-powered apps that **brings Spring portability and DI to AI**. Its central idea: **abstract over models and vector stores** so you can swap OpenAI ↔ Anthropic ↔ Azure ↔ Ollama (local) ↔ Bedrock ↔ Vertex without rewriting your app — just change a starter + properties. It's the "Spring Data of AI."

### 2. Key abstractions
| Abstraction | Purpose |
|-------------|---------|
| **`ChatModel`** | Low-level interface to a chat LLM (`call(Prompt) -> ChatResponse`). |
| **`ChatClient`** | **Fluent, high-level** API (the one you'll use) — like `RestClient`/`WebClient` for LLMs. |
| **`EmbeddingModel`** | Turns text into vectors (Day 26). |
| **`Prompt` / `Message`** | The input: a list of `SystemMessage`, `UserMessage`, `AssistantMessage`. |
| **`PromptTemplate`** | Templated prompts with `{placeholders}`. |
| **`Advisor`** | Interceptors around chat calls (memory, RAG, logging) — like AOP for prompts. |
| **`VectorStore`** | Store/search embeddings (Day 26). |
| **Tool / Function calling** | Let the model invoke your Java methods (Day 26). |

### 3. Starters & configuration (Spring AI 1.0 naming)
Add a **model starter** (1.0 renamed them to `spring-ai-starter-model-<provider>`):
```xml
<!-- pick ONE provider; swapping providers = swap this + properties -->
<dependency>
  <groupId>org.springframework.ai</groupId>
  <artifactId>spring-ai-starter-model-anthropic</artifactId>
</dependency>
<!-- or spring-ai-starter-model-openai, -azure-openai, -ollama, -bedrock-converse, -vertex-ai-gemini -->
```
```yaml
spring:
  ai:
    anthropic:
      api-key: ${ANTHROPIC_API_KEY}        # secret via env var, never committed (Day 8)
      chat:
        options:
          model: claude-sonnet-4-5          # provider-specific model id
          temperature: 0.7
          max-tokens: 1024
```
Auto-configuration provides a `ChatModel` and a `ChatClient.Builder` bean ready to inject.

### 4. The `ChatClient` fluent API (your bread and butter)
```java
@Service
public class AssistantService {
    private final ChatClient chat;
    public AssistantService(ChatClient.Builder builder) {     // injected, constructor DI
        this.chat = builder
            .defaultSystem("You are a concise support assistant for the Cent platform.")
            .build();
    }
    public String ask(String question) {
        return chat.prompt()
            .user(question)
            .call()                 // synchronous
            .content();             // String response
    }
    public Flux<String> askStreaming(String question) {
        return chat.prompt().user(question).stream().content();   // token streaming
    }
}
```

### 5. Prompts, roles & templates
- **System message** — sets behavior/persona/rules (high priority instructions).
- **User message** — the actual query.
- **Assistant message** — prior model replies (for multi-turn context).
- **`PromptTemplate`** — inject variables safely:
```java
String answer = chat.prompt()
    .user(u -> u.text("Summarize the incident for {audience} in {n} bullet points: {log}")
                .param("audience", "executives").param("n", 3).param("log", logText))
    .call().content();
```

### 6. Structured output — map LLM responses to Java objects (huge for real apps)
Instead of parsing free text, have the model return data mapped to a record/POJO via `BeanOutputConverter` (Spring AI injects format instructions and parses the JSON for you):
```java
public record IncidentSummary(String severity, List<String> rootCauses, String recommendation) {}

IncidentSummary summary = chat.prompt()
    .user("Analyze this log and summarize the incident:\n" + logText)
    .call()
    .entity(IncidentSummary.class);     // returns a typed object, not a String
```
This is what makes LLMs usable in a typed backend — you get a `record`, not a blob of prose.

### 7. Options per call & cost/latency awareness
Override model options per request (`ChatOptions`): temperature (creativity), maxTokens (cost/length cap), model. Be **token- and latency-aware**: LLM calls are slow (seconds) and metered (cost per token). Cache where possible, stream for UX, set timeouts and limits, and never put PII/secrets in prompts you don't control.

### 8. Observability
Spring AI integrates with **Micrometer** (Day 9): metrics and traces for model calls (latency, token usage). Critical in production to watch cost and performance of AI calls.

---

## PRACTICE

```java
// A "smart endpoint" — classify a support ticket into a typed result
public record TicketTriage(
    String category,          // e.g., AUTHENTICATION, CERTIFICATE, BILLING
    String priority,          // LOW / MEDIUM / HIGH / URGENT
    boolean needsHumanReview,
    String suggestedReply) {}

@Service
public class TriageService {
    private final ChatClient chat;
    public TriageService(ChatClient.Builder b) {
        this.chat = b.defaultSystem(
            "You triage Cent support tickets. Be precise and conservative; " +
            "set needsHumanReview=true if unsure or if it involves security/revocation.").build();
    }
    public TicketTriage triage(String ticketText) {
        return chat.prompt()
            .user(u -> u.text("Triage this ticket:\n{t}").param("t", ticketText))
            .options(ChatOptionsBuilder.builder().temperature(0.2).build())  // low = deterministic
            .call()
            .entity(TicketTriage.class);     // structured output → typed record
    }
}

@RestController
@RequestMapping("/ai")
class TriageController {
    private final TriageService service;
    TriageController(TriageService s) { this.service = s; }
    @PostMapping("/triage")
    public TicketTriage triage(@RequestBody String ticket) { return service.triage(ticket); }
    @GetMapping(value="/chat", produces=MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<String> chat(@RequestParam String q) { return service.streamAnswer(q); }
}
```

**Exercises:**
1. Inject `ChatClient.Builder`, set a `defaultSystem`, and build a `/ask` endpoint returning the model's text.
2. Add a streaming endpoint (`.stream().content()`) returning a `Flux<String>` as SSE.
3. Use `.entity(SomeRecord.class)` to get **structured** output; verify you receive a typed object.
4. Swap the provider (e.g., Anthropic → Ollama local) by changing only the starter + properties; confirm the code is unchanged.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. What's the point of Spring AI's abstraction layer — why not call the provider SDK directly?**
**Portability and Spring integration.** Spring AI's `ChatModel`/`ChatClient`/`EmbeddingModel`/`VectorStore` abstractions let you **swap LLM and vector-store providers by changing a starter + properties**, with no application-code changes — avoiding vendor lock-in and easing testing (use a local Ollama in dev, a hosted model in prod). You also get Spring idioms for free: auto-configuration, `@ConfigurationProperties`, DI of a ready `ChatClient.Builder`, Micrometer observability, and consistent retry/error handling.

**Q2. `ChatModel` vs `ChatClient` — when do you use each?**
`ChatModel` is the **low-level** port (`call(Prompt)`), provider-implemented — use it for fine-grained control or when building infrastructure. `ChatClient` is the **high-level fluent API** built on top (analogous to `RestClient` over raw HTTP) — the **recommended** way to build apps: fluent `prompt().system().user().call().entity()`, with advisors, default prompts, streaming, and structured output. Most application code uses `ChatClient`.

**Q3. What is "structured output" and why is it important for backend apps?**
Structured output makes the model return data **mapped to a Java type** (record/POJO) rather than free text. Spring AI's `BeanOutputConverter` appends format instructions to the prompt and parses the model's JSON into your type via `.entity(MyRecord.class)`. It's essential because a typed backend can't reliably act on prose — you need `TicketTriage{category, priority}` to drive logic, not a paragraph. It turns an LLM into a typed function.

**Q4. What do System, User, and Assistant messages mean?**
A prompt is a list of role-tagged messages. **System** sets the model's persona, rules, and constraints (highest-priority instructions, e.g., "be conservative, flag security issues"). **User** is the human's actual input/query. **Assistant** messages are the model's prior responses, included to give **multi-turn conversational context**. The model conditions its next response on all of them; good system prompts are how you control behavior and guardrails.

**Q5. Why must you be careful about temperature, tokens, latency, and secrets with LLM calls?**
**Temperature** controls randomness — low (≈0.2) for deterministic/classification tasks, higher for creative ones; wrong settings give inconsistent or bland results. **Tokens** = cost and context limits — you pay per token and the context window is finite, so cap `maxTokens` and trim inputs. **Latency** — LLM calls take seconds, so use streaming for UX, timeouts, async, and caching. **Secrets/PII** — prompts are sent to a third party (unless self-hosted); never include credentials or sensitive data you're not allowed to share, and store the API key via env/secret manager (Day 8).

**Q6. How would you keep AI calls observable and cost-controlled in production?**
Use Spring AI's **Micrometer** integration to track **token usage, latency, and error rates** per model/endpoint (Day 9 dashboards/alerts), set **timeouts and retries with backoff** (Day 21) since model endpoints are flaky/slow, **cap `maxTokens`** and trim prompt size, **cache** deterministic responses, and consider routing simple tasks to **cheaper/smaller or local models**. Treat the model like any external dependency: bulkhead it, circuit-break it, and budget it.

**Q7. How do you test code that calls an LLM (which is non-deterministic and external)?**
**Mock the `ChatModel`/`ChatClient`** in unit tests (return canned `ChatResponse`s) so tests are deterministic and free — you test *your* logic (prompt assembly, structured-output mapping, error handling), not the model. For integration confidence, use a **local model (Ollama)** or recorded responses, and assert on **structure/contracts** (the record parses, required fields present) rather than exact wording. Evaluate model *quality* separately with eval datasets, not in unit tests.

➡ Next: [Day 26 — Spring AI Advanced: RAG, Tools & MCP](day-26-spring-ai-rag-tools-mcp.md)
