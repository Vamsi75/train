# Day 28 — Tricky Interview Master Set, Mock & Capstone

> The questions that actually separate candidates, plus a timed mock and a capstone that proves the whole stack.

## A. The "gotcha" greatest hits (answer before reading)

**Q1. `@Transactional` on a method, called from another method in the same class — does it work?**
No — **self-invocation bypasses the AOP proxy**, so no transaction is started. (Day 5/15.) Same for `@Cacheable`, `@Async`, `@Retryable`.

**Q2. Default rollback behavior of `@Transactional`?**
Rolls back on **unchecked** exceptions/`Error` only — **not** checked exceptions, which **commit** unless you set `rollbackFor`. (Day 15.)

**Q3. You inject a prototype bean into a singleton. Fresh instance each call?**
No — injected once at singleton creation. Use `ObjectProvider`/`@Lookup`/scoped proxy. (Day 2.)

**Q4. Constructor vs field injection — why prefer constructor?**
Immutability (`final`), explicit mandatory deps, testable without Spring, surfaces "too many deps" smell, no reflection needed. (Day 3.)

**Q5. `@SpringBootApplication` = ?**
`@Configuration` + `@EnableAutoConfiguration` + `@ComponentScan`. (Day 7.)

**Q6. How does auto-configuration decide what to configure?**
Conditional beans (`@ConditionalOnClass/Property/MissingBean`) listed in `AutoConfiguration.imports`, evaluated against classpath/beans/properties. (Day 7.)

**Q7. Why does `@ConditionalOnMissingBean` matter?**
It lets your bean **override** Boot's default — "user wins." (Day 4/7.)

**Q8. JDK dynamic proxy vs CGLIB?**
Interface → JDK proxy; no interface → CGLIB subclass (can't proxy `final`). Boot defaults to CGLIB. (Day 5.)

**Q9. N+1 problem and three fixes?**
1 + N lazy queries; fix with `JOIN FETCH`, `@EntityGraph`, batch fetching, or DTO projection. (Day 14.)

**Q10. `LazyInitializationException` — cause and right fix?**
Lazy association accessed after session closed; fix by fetching in the transaction / DTOs — **not** by enabling `open-in-view`. (Day 14/27.)

**Q11. Enum in JPA — `STRING` or `ORDINAL`?**
`STRING` — `ORDINAL` corrupts data if enum order changes. (Day 14.)

**Q12. Is a JWT encrypted?**
No — **signed**, not encrypted; payload is readable. Never put secrets in it. (Day 18.)

**Q13. How do you revoke a stateless JWT before expiry?**
You can't purely; use short TTL + revocable refresh tokens, a `jti` denylist, or token versioning. (Day 18.)

**Q14. Circuit breaker states?**
CLOSED → (failures) → OPEN (fail fast) → (wait) → HALF_OPEN (trial) → CLOSED/OPEN. (Day 21.)

**Q15. RabbitMQ vs Kafka?**
Smart broker w/ routing, message removed on ack vs distributed replayable log, ordering per partition. (Day 22.)

**Q16. At-least-once delivery → what must consumers be?**
**Idempotent** (dedupe), because duplicates/redelivery happen. (Day 22.)

**Q17. `@WebMvcTest` vs `@SpringBootTest`?**
Web slice only (fast, mocked services) vs full context (slow). (Day 23.)

**Q18. Why Testcontainers over H2?**
Tests run against the **real DB engine** → catches dialect/behavior bugs H2 hides. (Day 23.)

**Q19. Reactive: why does "nothing happen until subscribe"?**
`Mono`/`Flux` are lazy blueprints; the framework subscribes when writing the response. Ignoring the result = no-op. (Day 24.)

**Q20. Spring AI: `ChatModel` vs `ChatClient`?**
Low-level port vs high-level fluent API (the one you use). (Day 25.)

**Q21. What is RAG?**
Retrieve relevant chunks via embeddings, inject into the prompt → grounded, less hallucination. (Day 26.)

**Q22. What is MCP?**
Open protocol standardizing AI ↔ tools/data via MCP servers; Spring AI has client+server support. (Day 26.)

**Q23. `bootstrap.yml` still needed?**
Largely no — use `spring.config.import: configserver:` (Boot 2.4+). (Day 8/19.)

**Q24. open-in-view default and why it's bad?**
Default **true**; holds a DB connection for the whole request → pool starvation, hides N+1. Set false. (Day 27.)

**Q25. `fixedRate` vs `fixedDelay`?**
Fixed cadence (can overlap) vs gap after completion (no overlap). (Day 16.)

---

## B. "Explain end-to-end" questions (whiteboard)

**Q26. Trace an HTTP POST from socket to DB and back.**
Filter chain (security, MDC) → DispatcherServlet → HandlerMapping → HandlerAdapter → argument resolvers (`@RequestBody` via Jackson `HttpMessageConverter`, `@Valid` validation) → controller → `@Transactional` service (proxy starts tx) → repository (Spring Data → Hibernate → JDBC → connection from Hikari) → dirty-checking flush + commit → return DTO → `HttpMessageConverter` serializes to JSON → response back through interceptors/filters. (Days 5, 11, 13, 14, 15.)

**Q27. Design a resilient call from Service A to Service B.**
Discover B by name (discovery/LoadBalancer) → declarative client (`@HttpExchange`/Feign) → **connect+read timeouts** → `@CircuitBreaker` + `@Retry`(idempotent only, backoff+jitter) + `@Bulkhead` → **fallback** for graceful degradation → propagate the bearer token + trace id → emit metrics. (Days 18, 20, 21.)

**Q28. Walk through a RAG request in a Spring AI app.**
User question → `ChatClient.prompt()` with a `QuestionAnswerAdvisor` → advisor embeds the question (`EmbeddingModel`) → similarity search in `VectorStore` (filtered by tenant) → top-k chunks injected as context into the prompt → `ChatModel` generates a grounded answer → optional structured output mapping → metrics/trace recorded. (Day 25/26.)

---

## C. Timed mock interview (45 min)
**Round 1 — Core (10 min):** Q1, Q3, Q4, Q8, plus "bean lifecycle order and where proxies are created."
**Round 2 — Boot/Web/Data (15 min):** auto-config mechanics; `@Transactional` propagation+rollback; N+1 with a live fix; `@ControllerAdvice`/`ProblemDetail`; open-in-view.
**Round 3 — Distributed (10 min):** config server + refresh; circuit breaker states; RabbitMQ vs Kafka + idempotency; JWT validation + revocation.
**Round 4 — Spring AI (10 min):** ChatClient vs ChatModel; structured output; RAG end-to-end; tool-calling guardrails; MCP.

Grade: confident + correct on 80%+ across all rounds = ready for a 4-year-level Spring role.

---

## D. CAPSTONE — build "Cent Copilot" (portfolio-grade)
A microservice that ties the **entire** guide together. Build it for real; the README explaining your decisions is what wins offers.

**Service: `support-copilot-service`** (Spring Boot 3.2+, Java 21)
1. **REST API** (`@RestController`, DTOs, `ProblemDetail` errors, validation) — Days 11–13.
2. **Persistence** — JPA entities for tickets, `@EntityGraph` to avoid N+1, Flyway migrations, `@Version` optimistic locking — Days 14–15.
3. **Security** — OAuth2 resource server (JWT), `@PreAuthorize` on the revoke action, method security — Days 17–18.
4. **Config** — `@ConfigurationProperties`, profiles, fetch from a Config Server, `@RefreshScope` a feature flag — Days 8, 19.
5. **Resilience** — call a downstream `cert-service` via a declarative client with timeouts + circuit breaker + fallback — Days 20–21.
6. **Messaging** — publish a `TicketTriaged` event to RabbitMQ; an idempotent consumer + DLQ — Day 22.
7. **Spring AI** — a `/copilot` endpoint: **RAG** over your docs (`VectorStore` + `QuestionAnswerAdvisor`), **conversation memory** (`MessageChatMemoryAdvisor`), **structured output** for triage (`TicketTriage` record), and a **read-only `@Tool`** for live cert status (guarded) — Days 25–26.
8. **Observability** — Actuator, Micrometer metrics (incl. AI token usage), trace ids in logs, custom health indicator — Days 9–10.
9. **Tests** — unit (Mockito), `@WebMvcTest` (incl. security), `@DataJpaTest` + Testcontainers, one `@SpringBootTest` happy path — Day 23.
10. **Production** — graceful shutdown, `MaxRAMPercentage`, layered Docker image, README documenting trade-offs — Days 10, 27.

**Stretch:** expose the cert-status tool via an **MCP server** so any MCP client can use it (Day 26).

---

## Final self-assessment — you're ready when, without notes, you can:
- [ ] Explain IoC/DI and defend constructor injection.
- [ ] Describe the bean lifecycle and where AOP proxies are created.
- [ ] Explain why `@Transactional`/`@Cacheable` silently fail on self-invocation.
- [ ] Explain auto-configuration mechanics and debug it with the condition report.
- [ ] Diagnose and fix N+1, `LazyInitializationException`, and connection-pool exhaustion.
- [ ] Configure a stateless JWT resource server and reason about revocation.
- [ ] Design a resilient inter-service call (discovery, timeout, breaker, bulkhead, fallback).
- [ ] Choose RabbitMQ vs Kafka and make a consumer idempotent.
- [ ] Build a RAG + tool-calling endpoint with Spring AI and explain its guardrails.
- [ ] Walk an interviewer through a production incident from symptom to root cause.

Revisit any unchecked box's day. Then go get the offer. 🚀

⬅ Back to [README](README.md) · See also [Annotations Cheatsheet](_cheatsheets/annotations-cheatsheet.md) & [Rapid-fire 100](_cheatsheets/interview-rapidfire.md)
