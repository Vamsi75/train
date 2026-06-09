# 100 Rapid-Fire Spring/Boot Q&A — The Night Before

Cover the answer, recall, reveal. Aim for instant recall.

## Core / IoC / DI (1–18)
1. **IoC?** Container controls object creation/wiring, not your code.
2. **DI?** Container supplies dependencies from outside; an implementation of IoC.
3. **BeanFactory vs ApplicationContext?** Latter adds events, i18n, eager singletons, resource/env — always use it.
4. **Default bean scope?** Singleton (one per container, ≠ JVM singleton).
5. **Spring singleton thread-safe?** No — keep beans stateless.
6. **@Component vs @Service vs @Repository?** Semantic; @Repository adds exception translation.
7. **@RestController?** @Controller + @ResponseBody.
8. **Constructor vs field injection?** Constructor: final, explicit, testable, no reflection.
9. **Why field injection bad?** Hides deps, no final, hard to test, masks too-many-deps.
10. **Multiple beans same type, no qualifier?** NoUniqueBeanDefinitionException.
11. **Resolve ambiguity?** @Primary / @Qualifier / param name / inject List/Map.
12. **Inject all impls?** `List<T>` (ordered) or `Map<String,T>` — strategy pattern.
13. **Is @Autowired needed on a single constructor?** No (since 4.3).
14. **Circular dep with constructor injection?** Fails fast; refactor (or @Lazy/setter).
15. **Bean lifecycle order?** Construct → inject → aware → BPP-before → @PostConstruct → afterPropertiesSet → init → **BPP-after (proxy)** → destroy callbacks.
16. **Prototype destroyed by Spring?** No; no @PreDestroy for prototypes.
17. **Prototype into singleton fresh each call?** No; use ObjectProvider/@Lookup.
18. **ObjectProvider use?** Lazy/optional/multi, fresh prototype per getObject().

## Config / AOP / events (19–32)
19. **@Configuration vs @Component for @Bean?** @Configuration proxies inter-bean calls → same singleton.
20. **proxyBeanMethods=false?** Lite mode, no proxy, faster, @Bean calls create new objects.
21. **${} vs #{}?** Property placeholder vs SpEL.
22. **Profiles?** Env-specific beans/config; `@Profile`, `spring.profiles.active`.
23. **@ConditionalOnMissingBean?** Auto-config backs off if you defined your own — user wins.
24. **Property precedence top 3?** CLI args > SPRING_APPLICATION_JSON > sys props/env vars.
25. **Spring AOP weaving type?** Runtime, proxy-based.
26. **JDK vs CGLIB proxy?** Interface → JDK; none → CGLIB subclass (no final).
27. **Self-invocation problem?** Internal call bypasses proxy → @Transactional/@Cacheable no-op.
28. **Which methods can AOP advise?** Public, called via the proxy (not private/final/self).
29. **@Around forgot proceed()?** Target never runs.
30. **App events sync or async?** Sync by default; @Async to offload.
31. **@TransactionalEventListener AFTER_COMMIT?** Fire only if tx committed.
32. **Run once on startup?** ApplicationReadyEvent / ApplicationRunner.

## Spring Boot (33–46)
33. **@SpringBootApplication?** @Configuration+@EnableAutoConfiguration+@ComponentScan.
34. **Auto-config mechanism?** Conditional beans in AutoConfiguration.imports.
35. **Starter?** Versioned dependency bundle, no code.
36. **Override auto-config?** Define your own bean / set property / exclude.
37. **Debug auto-config?** `--debug` condition report / /actuator/conditions.
38. **@Value vs @ConfigurationProperties?** Latter: type-safe, nested, validated, grouped.
39. **Relaxed binding?** base-url=baseUrl=BASE_URL all map.
40. **Validate config at startup?** @Validated on @ConfigurationProperties.
41. **bootstrap.yml needed?** Mostly no — use spring.config.import.
42. **Actuator default exposed?** health (+info); expose others explicitly.
43. **Liveness vs readiness?** Restart-me vs route-traffic-to-me.
44. **Micrometer?** Vendor-neutral metrics facade.
45. **Change log level at runtime?** POST /actuator/loggers.
46. **Fat jar layout?** Nested jars (BOOT-INF) + JarLauncher, not shaded.

## Web / data (47–64)
47. **DispatcherServlet?** Front controller routing to handlers.
48. **Filter vs Interceptor?** Servlet-level/all requests vs MVC handler-aware.
49. **@PathVariable/@RequestParam/@RequestBody?** Path / query / body.
50. **Content negotiation?** Accept header → HttpMessageConverter.
51. **Why DTOs not entities?** Decouple contract, avoid lazy/serialization leaks.
52. **Idempotent HTTP methods?** GET/PUT/DELETE (not POST).
53. **RestTemplate vs RestClient vs WebClient?** Legacy sync / modern sync / reactive.
54. **ProblemDetail?** RFC 7807 standard error body (Spring 6).
55. **MethodArgumentNotValidException vs ConstraintViolationException?** @Valid body vs method/param validation.
56. **N+1 problem?** 1+N lazy queries.
57. **N+1 fixes?** JOIN FETCH / @EntityGraph / batch / DTO projection.
58. **LazyInitializationException fix?** Fetch in tx / DTO; not open-in-view.
59. **Enum mapping?** EnumType.STRING.
60. **Need save() on managed entity?** No — dirty checking flushes.
61. **getReferenceById vs findById?** Lazy proxy (no SELECT) vs SELECT+Optional.
62. **@Version?** Optimistic locking → OptimisticLockException.
63. **JOIN FETCH + pagination danger?** In-memory paging, OOM risk.
64. **open-in-view default?** true — set false (holds connection, hides N+1).

## Transactions (65–70)
65. **@Transactional default rollback?** Unchecked only; checked commits.
66. **rollbackFor?** Roll back on checked exceptions.
67. **Self-invoked @Transactional?** No tx (proxy bypassed).
68. **@Transactional on private method?** Ignored.
69. **REQUIRES_NEW use?** Independent commit (e.g., audit survives rollback).
70. **Where to put @Transactional?** Service layer.

## Security (71–80)
71. **Security core?** A servlet filter chain.
72. **AuthN vs AuthZ?** Who you are vs what you can do.
73. **Where is current auth stored?** SecurityContextHolder (thread-local).
74. **Config in Security 6?** SecurityFilterChain bean (no WebSecurityConfigurerAdapter).
75. **Password encoder?** BCrypt/Argon2 (slow+salted), not SHA-256.
76. **Role vs authority?** Role = ROLE_-prefixed authority.
77. **CSRF for stateless JWT API?** Usually disabled (no ambient cookie).
78. **CORS?** Browser origin policy, not auth.
79. **Is JWT encrypted?** No — signed; readable payload.
80. **Revoke a JWT?** Short TTL + refresh token / jti denylist / token version.

## Microservices / messaging (81–90)
81. **DB per service?** Avoid coupling; no shared DB.
82. **Config server benefit?** Central, versioned, runtime-refreshable config.
83. **@RefreshScope?** Re-bind beans on /actuator/refresh.
84. **Client vs server discovery?** Client picks instance vs LB/DNS resolves.
85. **Need Eureka on K8s?** Usually no (DNS/Services).
86. **API gateway role?** Edge routing, auth, rate limit, CORS.
87. **Circuit breaker states?** CLOSED/OPEN/HALF_OPEN.
88. **Bulkhead?** Isolate concurrency per dependency.
89. **Why timeouts critical?** Prevent thread pileup/cascading failure.
90. **RabbitMQ vs Kafka?** Smart broker/routing vs replayable log/partitions.

## Testing / reactive / AI (91–100)
91. **At-least-once → consumer must be?** Idempotent.
92. **@WebMvcTest vs @SpringBootTest?** Web slice vs full context.
93. **Testcontainers vs H2?** Real DB engine catches dialect bugs.
94. **@Mock vs @MockBean?** Plain mock vs mock in Spring context.
95. **Mono vs Flux?** 0..1 vs 0..N async.
96. **map vs flatMap?** Sync transform vs async (returns publisher).
97. **Reactive lazy?** Nothing runs until subscribe.
98. **Block event loop?** Stalls app; use boundedElastic/R2DBC.
99. **ChatModel vs ChatClient?** Low-level port vs fluent API.
100. **RAG / MCP?** Retrieve+inject context to ground answers / open protocol for AI↔tools.

---
*90+/100 from memory = ready. Weak spots → revisit that day.*
