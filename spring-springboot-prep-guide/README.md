# Spring & Spring Boot Preparation Guide — Zero to 4 Years Experience

A complete, day-wise Spring Framework + Spring Boot learning + interview-prep track, ending with **Spring AI**. Same rhythm every day:

> **Theory** → **Production-grounded Practice** → **Tricky Interview Questions & Answers**

Examples are **production-style**, many modeled on patterns from a real microservices platform (referred to as *Centurion* / *cent* throughout): Spring Cloud Config, AMQP-driven services, constructor-injected `@RestController`s, multi-module Maven with a BOM, schedulers, and service factories.

> **Stack assumed:** Spring Boot **3.2+** (Spring Framework **6.x**), **Java 17/21**, Jakarta EE namespace (`jakarta.*`, not `javax.*`), Maven. Spring AI **1.0 GA**. Where something changed from Spring Boot 2.x / Java 8, it's called out — interviewers love the migration questions.

---

## How to use this guide
1. **Build along.** Generate a project at [start.spring.io](https://start.spring.io) (see `_setup/setup.md`) and run every snippet. Spring is learned by wiring beans, not reading about them.
2. **Answer interview questions out loud first.** The "tricky" ones are exactly what separates a 2-year dev from a 4-year dev.
3. **Connect concepts to the cent examples** — being able to say *"in our microservices we did X because Y"* is what wins interviews.
4. **Pace:** ~2–3 hrs/day → 5–6 weeks part-time, ~3 weeks full-time.

---

## Curriculum

### Phase 1 — Spring Core Foundations (Days 1–6)
| Day | Topic |
|-----|-------|
| [Day 01](day-01-spring-overview-ioc-di.md) | What Spring is, IoC & DI, the container, ApplicationContext |
| [Day 02](day-02-beans-scopes-lifecycle.md) | Beans: definition, scopes, lifecycle callbacks |
| [Day 03](day-03-dependency-injection-deep.md) | DI deep: constructor vs field vs setter, `@Qualifier`, `@Primary`, circular deps |
| [Day 04](day-04-configuration-profiles-spel.md) | `@Configuration`, component scanning, profiles, properties, SpEL |
| [Day 05](day-05-aop-proxies.md) | AOP: aspects/advice/pointcuts, JDK vs CGLIB proxies, the self-invocation trap |
| [Day 06](day-06-events-resources-validation.md) | Application events, `@EventListener`, resources, bean validation |

### Phase 2 — Spring Boot Fundamentals (Days 7–11)
| Day | Topic |
|-----|-------|
| [Day 07](day-07-springboot-autoconfig-starters.md) | Auto-configuration, starters, `@SpringBootApplication`, how Boot bootstraps |
| [Day 08](day-08-config-properties-profiles.md) | Externalized config, `@ConfigurationProperties`, profiles, config precedence |
| [Day 09](day-09-actuator-observability.md) | Actuator, health, metrics, Micrometer, tracing |
| [Day 10](day-10-logging-devtools-packaging.md) | Logging, DevTools, packaging, fat jars, layered images, native |
| [Day 11](day-11-rest-controllers-mvc.md) | Spring MVC: controllers, request/response, the DispatcherServlet flow |

### Phase 3 — Web & Data (Days 12–16)
| Day | Topic |
|-----|-------|
| [Day 12](day-12-rest-advanced.md) | REST advanced: `ResponseEntity`, content negotiation, versioning, `RestClient` |
| [Day 13](day-13-validation-exception-handling.md) | Validation, `@ControllerAdvice`, `ProblemDetail` (RFC 7807) |
| [Day 14](day-14-spring-data-jpa.md) | Spring Data JPA: repositories, queries, paging, N+1, projections |
| [Day 15](day-15-transactions.md) | `@Transactional`: propagation, isolation, the proxy pitfalls |
| [Day 16](day-16-caching-scheduling-async.md) | Caching, `@Scheduled`, `@Async`, `@Retryable` |

### Phase 4 — Security (Days 17–18)
| Day | Topic |
|-----|-------|
| [Day 17](day-17-spring-security-fundamentals.md) | Security filter chain, authn/authz, password encoding, CSRF/CORS |
| [Day 18](day-18-jwt-oauth2-resource-server.md) | JWT, OAuth2 resource server, method security (cent's OAuth providers) |

### Phase 5 — Microservices & Spring Cloud (Days 19–22)
| Day | Topic |
|-----|-------|
| [Day 19](day-19-microservices-config-server.md) | Microservices principles, Spring Cloud Config (cent's config-server) |
| [Day 20](day-20-discovery-gateway.md) | Service discovery, API Gateway, client-side load balancing |
| [Day 21](day-21-resilience-feign.md) | Resilience4j (circuit breaker/retry/bulkhead), OpenFeign |
| [Day 22](day-22-messaging-amqp-kafka.md) | Messaging: Spring AMQP/RabbitMQ & Kafka, event-driven (cent's AMQP) |

### Phase 6 — Testing & Reactive (Days 23–24)
| Day | Topic |
|-----|-------|
| [Day 23](day-23-testing.md) | Unit/slice/integration tests, MockMvc, Mockito, Testcontainers |
| [Day 24](day-24-reactive-webflux.md) | Reactive: WebFlux, `Mono`/`Flux`, backpressure, when (not) to use |

### Phase 7 — Spring AI & Production (Days 25–28)
| Day | Topic |
|-----|-------|
| [Day 25](day-25-spring-ai-fundamentals.md) | **Spring AI:** `ChatClient`, models, prompts, structured output |
| [Day 26](day-26-spring-ai-rag-tools-mcp.md) | **Spring AI advanced:** RAG, embeddings, vector stores, tool calling, advisors, MCP |
| [Day 27](day-27-production-readiness-issues.md) | **Production readiness & real-time issue playbook** |
| [Day 28](day-28-tricky-interview-capstone.md) | **Tricky interview master set + mock + capstone** |

---

## Supporting files
- [`_setup/setup.md`](_setup/setup.md) — generate a project, project layout, run/debug
- [`_cheatsheets/annotations-cheatsheet.md`](_cheatsheets/annotations-cheatsheet.md) — every annotation you'll be asked about
- [`_cheatsheets/interview-rapidfire.md`](_cheatsheets/interview-rapidfire.md) — 100 rapid-fire Q&A for the night before

---

## What "4 years of Spring" means to an interviewer
By the end you should, **without notes**, be able to:
- Explain IoC/DI and *why* constructor injection is preferred.
- Describe what auto-configuration actually does and how to debug it.
- Explain why `@Transactional` on a private method or self-invoked method silently does nothing.
- Diagnose the N+1 query problem and fix it three ways.
- Design a microservice with config server, discovery, gateway, and a circuit breaker — and explain the failure modes.
- Build a RAG pipeline and a tool-calling chat endpoint with Spring AI.
- Walk through a production incident (memory leak, thread-pool exhaustion, connection-pool starvation).

Start with [`_setup/setup.md`](_setup/setup.md), then [Day 01](day-01-spring-overview-ioc-di.md).
