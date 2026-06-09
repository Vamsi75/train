# Day 02 — Beans: Definition, Scopes & Lifecycle

## THEORY

### 1. What is a bean?
A **bean** is any object **instantiated, assembled, and managed by the Spring IoC container**. The container reads *bean definitions* (from annotations, `@Bean` methods, or XML) and builds the object graph.

### 2. `@Bean` vs stereotype annotations
```java
@Configuration
public class AppConfig {
    @Bean
    public RestClient jamfRestClient(RestClient.Builder builder) {   // 3rd-party type → @Bean
        return builder.baseUrl("https://jamf.example.com").build();
    }
}
```
- Use **stereotypes** (`@Service` etc.) for *your* classes.
- Use **`@Bean`** methods for **types you don't own** (library classes you can't annotate) or when construction needs logic.

### 3. Bean scopes
| Scope | Meaning |
|-------|---------|
| **singleton** (default) | One instance per container. |
| **prototype** | A **new instance every time** it's requested/injected. |
| **request** | One per HTTP request (web). |
| **session** | One per HTTP session (web). |
| **application** | One per `ServletContext`. |
| **websocket** | One per WebSocket session. |
```java
@Service
@Scope("prototype")
public class ReportBuilder { ... }
```

### 4. The singleton-injects-prototype trap
A **singleton** bean that injects a **prototype** captures **one** prototype instance at creation — you do *not* get a fresh one each call. Fixes: inject `ObjectProvider<T>` (or `Provider<T>`), use `@Lookup` method injection, or scoped proxies.
```java
@Service
public class OrderService {
    private final ObjectProvider<ReportBuilder> builderProvider;
    OrderService(ObjectProvider<ReportBuilder> p) { this.builderProvider = p; }
    public void run() {
        ReportBuilder b = builderProvider.getObject();  // fresh prototype each call
    }
}
```

### 5. Bean lifecycle (the sequence interviewers want)
1. **Instantiation** (constructor).
2. **Populate properties** / dependency injection.
3. **Aware callbacks** (`BeanNameAware`, `ApplicationContextAware`, …).
4. **`BeanPostProcessor.postProcessBeforeInitialization`**.
5. **Initialization**: `@PostConstruct` → `InitializingBean.afterPropertiesSet()` → custom `initMethod`.
6. **`BeanPostProcessor.postProcessAfterInitialization`** (where **AOP proxies are created**!).
7. Bean is **ready / in use**.
8. **Destruction** (singletons, on context close): `@PreDestroy` → `DisposableBean.destroy()` → custom `destroyMethod`.

```java
@Service
public class CacheWarmer {
    @PostConstruct
    void init()    { /* warm caches, validate config, open resources */ }
    @PreDestroy
    void shutdown() { /* flush, close connections gracefully */ }
}
```

### 6. `BeanPostProcessor` & `BeanFactoryPostProcessor`
- **`BeanFactoryPostProcessor`** runs on bean *definitions* before any bean is instantiated (e.g., `PropertySourcesPlaceholderConfigurer` resolving `${...}`).
- **`BeanPostProcessor`** runs around *each bean's* initialization. It's how Spring applies **AOP, `@Autowired` resolution, `@Async`, transactions** — by wrapping beans in proxies in `postProcessAfterInitialization`.

### 7. Lazy initialization
By default singletons are created **eagerly** at startup (fail-fast — misconfig surfaces immediately). `@Lazy` defers creation until first use (faster startup, but errors surface later). Boot has `spring.main.lazy-initialization=true` globally — use cautiously.

---

## PRACTICE

```java
@Configuration
public class ScopeDemoConfig {
    @Bean @Scope("prototype")
    public Connection prototypeConn() { return new Connection(); }  // new each time
}

@Component
public class LifecycleBean implements InitializingBean, DisposableBean {
    public LifecycleBean() { System.out.println("1. constructor"); }
    @PostConstruct public void postConstruct() { System.out.println("3. @PostConstruct"); }
    public void afterPropertiesSet() { System.out.println("4. afterPropertiesSet"); }
    @PreDestroy public void preDestroy() { System.out.println("X. @PreDestroy"); }
    public void destroy() { System.out.println("Y. destroy()"); }
}

// Prove singleton vs prototype identity
@Component
class ScopeProof implements CommandLineRunner {
    private final ApplicationContext ctx;
    ScopeProof(ApplicationContext ctx) { this.ctx = ctx; }
    public void run(String... args) {
        var a = ctx.getBean("prototypeConn");
        var b = ctx.getBean("prototypeConn");
        System.out.println("prototype same instance? " + (a == b));   // false
        var s1 = ctx.getBean(GreetingFacade.class);
        var s2 = ctx.getBean(GreetingFacade.class);
        System.out.println("singleton same instance? " + (s1 == s2)); // true
    }
}
```

**Exercises:**
1. Add a `@PostConstruct` that prints config values; confirm it runs after injection, not in the constructor.
2. Inject a prototype into a singleton both directly and via `ObjectProvider`; prove only the provider yields fresh instances.
3. Register a custom `BeanPostProcessor` that logs every bean name as it initializes — observe the order.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Give the full bean lifecycle order including where AOP proxies are created.**
Instantiate → inject dependencies → `*Aware` callbacks → `BeanPostProcessor.postProcessBeforeInitialization` → `@PostConstruct` → `afterPropertiesSet()` → custom init → **`BeanPostProcessor.postProcessAfterInitialization` (proxy wrapping happens here)** → ready. On shutdown: `@PreDestroy` → `destroy()` → custom destroy. The proxy point is key: it's why `@Transactional`/`@Async` work via wrapping, and why self-invocation bypasses them (Day 05).

**Q2. You inject a prototype bean into a singleton but always get the same instance. Why and how to fix?**
The singleton is created **once**, and its prototype dependency is injected **once at that moment** — the prototype's "new instance per request" only applies to *container lookups*, not to an already-injected field. Fix with `ObjectProvider<T>`/`Provider<T>` `.getObject()` per call, `@Lookup` method injection, or a scoped proxy (`proxyMode = TARGET_CLASS`).

**Q3. Are prototype beans destroyed by Spring? Do `@PreDestroy` callbacks run?**
**No.** Spring does **not** manage the full lifecycle of prototype beans after creation — it hands them to you and forgets them. Destruction callbacks (`@PreDestroy`/`destroy()`) are **not** called for prototypes; you're responsible for cleanup. Only singletons get destruction callbacks on context close.

**Q4. `@PostConstruct` vs `InitializingBean.afterPropertiesSet()` vs `@Bean(initMethod=...)` — order and preference?**
Order: `@PostConstruct` → `afterPropertiesSet()` → custom `initMethod`. **Prefer `@PostConstruct`** (JSR-250, framework-agnostic, no Spring coupling). `InitializingBean` couples your class to Spring; `initMethod` is good for third-party beans you configure via `@Bean`.

**Q5. Why are singletons eagerly initialized by default, and when is `@Lazy` justified?**
**Fail-fast**: creating singletons at startup surfaces misconfiguration (missing deps, bad config) immediately rather than on first request in production. `@Lazy` is justified for expensive-to-build beans rarely used, to break certain circular dependencies, or to speed startup of dev environments — at the cost of deferring error discovery.

**Q6. Can a singleton bean hold state? What's the danger?**
It can hold **immutable/shared config** state, but holding **mutable per-request state in fields is a concurrency bug** — the single instance is shared across all threads, so requests clobber each other. Keep singletons stateless; pass request data through method parameters. (This is why cent services are stateless singletons.)

**Q7. What's the difference between a `BeanFactoryPostProcessor` and a `BeanPostProcessor`?**
`BeanFactoryPostProcessor` operates on **bean definitions** (metadata) *before* any bean is instantiated — e.g., resolving `${property}` placeholders. `BeanPostProcessor` operates on **bean instances** around their initialization — e.g., creating AOP proxies, processing `@Autowired`/`@Value`. Definition-time vs instance-time is the distinction.

➡ Next: [Day 03 — Dependency Injection Deep Dive](day-03-dependency-injection-deep.md)
