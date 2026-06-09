# Spring / Spring Boot Annotations Cheatsheet

## Core / stereotypes
| Annotation | Meaning |
|-----------|---------|
| `@Component` | Generic Spring-managed bean. |
| `@Service` | Business-logic bean (semantic). |
| `@Repository` | Persistence bean + **exception translation**. |
| `@Controller` / `@RestController` | Web bean; `@RestController` = `@Controller` + `@ResponseBody`. |
| `@Configuration` | Source of `@Bean` definitions (CGLIB-proxied; inter-bean calls return singletons). |
| `@Bean` | Declares a bean from a method (3rd-party types). |
| `@ComponentScan` | Where to scan for components. |
| `@Import` | Pull in other config classes. |

## Dependency injection
| Annotation | Meaning |
|-----------|---------|
| `@Autowired` | Inject by type (optional on single constructor). |
| `@Qualifier("name")` | Disambiguate among multiple beans. |
| `@Primary` | Default choice when multiple candidates. |
| `@Value("${prop}")` / `#{spel}` | Inject a property / SpEL expression. |
| `@Lazy` | Defer bean creation. |
| `@Scope("prototype")` | Bean scope. |
| `@Lookup` | Method injection for prototype-in-singleton. |

## Lifecycle
`@PostConstruct` (init) · `@PreDestroy` (cleanup) · `InitializingBean.afterPropertiesSet()` · `DisposableBean.destroy()`.

## Configuration & conditions
| Annotation | Meaning |
|-----------|---------|
| `@SpringBootApplication` | `@Configuration`+`@EnableAutoConfiguration`+`@ComponentScan`. |
| `@EnableAutoConfiguration` | Turn on auto-config. |
| `@ConfigurationProperties(prefix)` | Type-safe config binding (preferred over `@Value`). |
| `@ConfigurationPropertiesScan` / `@EnableConfigurationProperties` | Register them. |
| `@Profile("prod")` | Bean active only in profile(s); `!prod` for negation. |
| `@Conditional*` | `OnClass`, `OnMissingBean`, `OnBean`, `OnProperty`, `OnExpression`. |
| `@AutoConfiguration` | Declare an auto-config class (libraries). |

## Web / REST
| Annotation | Meaning |
|-----------|---------|
| `@RequestMapping` | Base/Generic mapping. |
| `@GetMapping/@PostMapping/@PutMapping/@DeleteMapping/@PatchMapping` | HTTP verb shortcuts. |
| `@PathVariable` | Bind URI path segment. |
| `@RequestParam` | Bind query/form param (`required`, `defaultValue`). |
| `@RequestBody` / `@ResponseBody` | Deserialize body / serialize return. |
| `@RequestHeader`, `@CookieValue`, `@RequestPart` | Other bindings. |
| `@ResponseStatus` | Fixed status for method/exception. |
| `@RestControllerAdvice` + `@ExceptionHandler` | Centralized error handling. |
| `@CrossOrigin` | CORS at controller/method. |

## Validation
`@Valid` (cascade) · `@Validated` (groups + method validation) · `@NotNull/@NotBlank/@NotEmpty/@Size/@Min/@Max/@Email/@Pattern/@Past/@Future`.

## Data / JPA
| Annotation | Meaning |
|-----------|---------|
| `@Entity`, `@Table`, `@Id`, `@GeneratedValue` | Map class to table. |
| `@Column`, `@Enumerated(EnumType.STRING)` | Column mapping (STRING for enums!). |
| `@ManyToOne/@OneToMany/@ManyToMany/@OneToOne`, `@JoinColumn` | Associations (set to-one LAZY). |
| `@Query`, `@Modifying`, `@Param` | Custom queries. |
| `@EntityGraph` | Fetch plan (fix N+1). |
| `@Version` | Optimistic locking. |
| `@CreatedDate/@LastModifiedDate` + `@EnableJpaAuditing` | Auditing. |
| `@Transactional(propagation, isolation, rollbackFor, readOnly)` | Tx boundary (on **services**). |

## Cross-cutting (all proxy-based → self-invocation trap)
| Annotation | Enable with |
|-----------|------------|
| `@Aspect` + `@Before/@After/@Around/@AfterReturning/@AfterThrowing` + `@Pointcut` | `@EnableAspectJAutoProxy` (auto in Boot). |
| `@Cacheable/@CachePut/@CacheEvict` | `@EnableCaching`. |
| `@Scheduled(cron/fixedRate/fixedDelay)` | `@EnableScheduling`. |
| `@Async` | `@EnableAsync`. |
| `@Retryable` + `@Recover` | `@EnableRetry` (Spring Retry). |
| `@EventListener` / `@TransactionalEventListener` | (built-in). |

## Security
| Annotation | Meaning |
|-----------|---------|
| `@EnableWebSecurity` | Enable web security; declare a `SecurityFilterChain` bean. |
| `@EnableMethodSecurity` | Enable method security. |
| `@PreAuthorize/@PostAuthorize` | SpEL authorization before/after method. |
| `@PreFilter/@PostFilter` | Filter collection args/returns. |
| `@AuthenticationPrincipal` | Inject current principal. |

## Microservices / Spring Cloud
`@EnableConfigServer` · `@EnableDiscoveryClient` · `@RefreshScope` · `@FeignClient` + `@EnableFeignClients` · `@LoadBalanced` · Resilience4j: `@CircuitBreaker/@Retry/@Bulkhead/@RateLimiter/@TimeLimiter`.

## Testing
| Annotation | Meaning |
|-----------|---------|
| `@SpringBootTest` | Full context (+ optional server). |
| `@WebMvcTest` / `@WebFluxTest` | Web slice (MockMvc / WebTestClient). |
| `@DataJpaTest` | JPA slice (test DB). |
| `@MockBean/@SpyBean` | Replace beans in context. |
| `@Mock/@InjectMocks/@Spy` (Mockito) | Plain unit mocks. |
| `@Testcontainers` + `@Container` + `@ServiceConnection` | Real deps in Docker. |
| `@WithMockUser` | Authenticated principal in tests. |
| `@ActiveProfiles/@TestPropertySource/@DirtiesContext` | Test config. |

## Spring AI
- Inject `ChatClient.Builder`; `chat.prompt().system().user().call().content()` / `.entity(Type.class)` / `.stream()`.
- `@Tool(description=...)` — expose a method as an LLM tool.
- Advisors: `QuestionAnswerAdvisor` / `RetrievalAugmentationAdvisor` (RAG), `MessageChatMemoryAdvisor` (memory).
- Beans: `ChatModel`, `EmbeddingModel`, `VectorStore`. Starters: `spring-ai-starter-model-<provider>`, `spring-ai-starter-mcp-server/client`.

## Boot properties you must know
```yaml
spring.profiles.active, spring.config.import, spring.application.name
spring.datasource.*, spring.jpa.open-in-view=false, spring.jpa.hibernate.ddl-auto=validate
spring.datasource.hikari.maximum-pool-size, .leak-detection-threshold
management.endpoints.web.exposure.include, management.endpoint.health.probes.enabled
server.shutdown=graceful, spring.threads.virtual.enabled
logging.level.<pkg>, logging.level.org.hibernate.SQL=DEBUG
resilience4j.circuitbreaker.instances.*, spring.ai.<provider>.api-key
```
