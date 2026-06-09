# Day 01 — What Spring Is, IoC & DI, the Container

## THEORY

### 1. What problem does Spring solve?
Spring is an **application framework** whose core job is **managing objects (beans) and their dependencies** for you, plus a huge ecosystem (web, data, security, messaging, cloud, AI) built on that core. Instead of `new`-ing collaborators and wiring them by hand, you declare *what* you need; Spring constructs, configures, and connects them.

### 2. Inversion of Control (IoC)
Normally **your code controls** object creation: `var service = new OrderService(new OrderRepo(), new PaymentClient());`. With **IoC, control is inverted** — a **container** creates objects and hands them their dependencies. Your class just declares "I need an `OrderRepo` and a `PaymentClient`." This is the "Hollywood Principle": *don't call us, we'll call you.*

### 3. Dependency Injection (DI) — IoC's concrete mechanism
DI = the container **supplies (injects)** a bean's dependencies from outside rather than the bean creating them. Benefits:
- **Loose coupling** — depend on interfaces, not concretions.
- **Testability** — inject mocks/stubs in tests.
- **Single responsibility** — classes don't manage their collaborators' lifecycles.
- **Configurability** — swap implementations via config/profiles without code changes.

```java
// Tightly coupled (no DI) — hard to test, hard to swap
class OrderService {
    private final OrderRepo repo = new JpaOrderRepo();   // baked in
}

// DI — the dependency is provided; OrderService doesn't care which impl
@Service
class OrderService {
    private final OrderRepo repo;
    OrderService(OrderRepo repo) { this.repo = repo; }   // constructor injection
}
```

### 4. The IoC container & `ApplicationContext`
- **`BeanFactory`** — the most basic container (lazy, minimal).
- **`ApplicationContext`** — the one you actually use: extends `BeanFactory` and adds event publishing, i18n, resource loading, `Environment`/property resolution, and **eager singleton instantiation** at startup.
- In Spring Boot, `SpringApplication.run(...)` creates and refreshes an `ApplicationContext` for you (typically an `AnnotationConfigServletWebServerApplicationContext` for a web app).

### 5. Ways to define beans
1. **Stereotype annotations** + component scanning: `@Component`, `@Service`, `@Repository`, `@Controller`/`@RestController`.
2. **`@Bean` methods** inside a `@Configuration` class (best for third-party types you can't annotate).
3. (Legacy) **XML** `<bean>` definitions — still asked about, rarely written new.

### 6. Stereotypes — same thing, different intent
All of these are `@Component` specializations; the distinction is **semantic + behavioral**:
- `@Service` — business logic (no extra behavior, marks intent).
- `@Repository` — persistence; **adds exception translation** (DB-specific exceptions → Spring's `DataAccessException`).
- `@Controller`/`@RestController` — web layer (`@RestController` = `@Controller` + `@ResponseBody`).

### 7. The cent connection
Every Centurion service is a Spring app whose `ApplicationContext` holds beans like `AAAServerController`, `IAAAServerService`, factories, and proxies. The controller doesn't build its service — Spring injects `IAAAServerService` via the constructor. That's IoC/DI in production.

---

## PRACTICE

```java
// 1. Define an interface and two implementations
public interface GreetingService { String greet(String name); }

@Service
public class EnglishGreetingService implements GreetingService {
    public String greet(String name) { return "Hello, " + name; }
}

// 2. A consumer that depends on the abstraction
@Service
public class GreetingFacade {
    private final GreetingService greetingService;
    public GreetingFacade(GreetingService greetingService) {  // injected by Spring
        this.greetingService = greetingService;
    }
    public String welcome(String name) { return greetingService.greet(name); }
}

// 3. Expose it (mirrors cent's constructor-injected @RestController)
@RestController
@RequestMapping("/greet")
public class GreetingController {
    private final GreetingFacade facade;
    public GreetingController(GreetingFacade facade) { this.facade = facade; }

    @GetMapping("/{name}")
    public String greet(@PathVariable String name) { return facade.welcome(name); }
}
```
```java
// 4. Inspect the container at startup — see how many beans Spring manages
@SpringBootApplication
public class DemoApplication {
    public static void main(String[] args) {
        var ctx = SpringApplication.run(DemoApplication.class, args);
        System.out.println("Total beans: " + ctx.getBeanDefinitionCount());
        // Arrays.stream(ctx.getBeanDefinitionNames()).sorted().forEach(System.out::println);
        System.out.println(ctx.getBean(GreetingFacade.class).welcome("Vamsi"));
    }
}
```

**Exercises:**
1. Add a second impl `SpanishGreetingService`. Run it — what error do you get, and why? (Foreshadows Day 03's `@Primary`/`@Qualifier`.)
2. Print all bean names; find the auto-configured ones (e.g., `dispatcherServlet`).
3. Convert `GreetingController` to use field injection (`@Autowired` on a field) and list two reasons that's worse.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Difference between IoC and DI — are they the same?**
No. **IoC** is the general *principle* — control over object creation/flow is inverted to a framework/container. **DI** is one *implementation* of IoC specifically about *supplying dependencies* from outside. (Other IoC forms: the template method pattern, service locator, callbacks.) Spring's container realizes IoC primarily through DI.

**Q2. `BeanFactory` vs `ApplicationContext` — when would you ever use `BeanFactory`?**
`ApplicationContext` is a superset: events, i18n, resource loading, environment/property resolution, BeanPostProcessor auto-registration, and eager singleton creation. `BeanFactory` is lazy and bare-bones. You'd rarely choose `BeanFactory` directly today — only in extremely memory-constrained or very specialized embedded scenarios. In practice you always use `ApplicationContext`.

**Q3. Are Spring beans singletons? Is that the same as the GoF Singleton pattern?**
By default beans are **singleton-scoped**, meaning **one instance per Spring container** — *not* the JVM-wide GoF singleton (private constructor + static instance). Two different `ApplicationContext`s would each have their own instance. So "Spring singleton" ≠ "Java singleton"; it's container-scoped.

**Q4. `@Component` vs `@Service` vs `@Repository` — functional differences?**
`@Service` and `@Controller` are purely *semantic* specializations of `@Component` (no behavioral difference for `@Service`). `@Repository` is special: it enables **persistence exception translation** via a `PersistenceExceptionTranslationPostProcessor`, converting vendor-specific exceptions into Spring's unified `DataAccessException` hierarchy. `@RestController` = `@Controller` + `@ResponseBody`.

**Q5. If beans are singletons, are they thread-safe?**
Spring does **not** make them thread-safe. Singleton beans are shared across threads, so **keep them stateless** (no mutable instance fields holding request state). The repos/services in cent are singletons precisely because they're stateless; per-request state lives in method parameters/locals, not fields.

**Q6. How does Spring know which classes to turn into beans?**
**Component scanning**: `@SpringBootApplication` includes `@ComponentScan`, which scans the package of the main class and its sub-packages for stereotype annotations. Classes outside that package tree won't be picked up unless you widen the scan. (Classic bug: putting a `@Service` in a sibling package that isn't scanned → "no qualifying bean.")

**Q7. Why is "program to an interface" emphasized so much with DI?**
Because injecting an *interface* lets the container (or tests) substitute any implementation — real, mock, profile-specific, or a proxy (for AOP/transactions). It's what makes code loosely coupled and testable. Note: with constructor injection and a single concrete type, you don't *strictly* need an interface, but interfaces shine when you have multiple impls, want AOP via JDK proxies, or test in isolation.

➡ Next: [Day 02 — Beans, Scopes & Lifecycle](day-02-beans-scopes-lifecycle.md)
