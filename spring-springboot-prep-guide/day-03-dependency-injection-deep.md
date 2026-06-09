# Day 03 — Dependency Injection Deep Dive

## THEORY

### 1. Three injection styles
```java
// Constructor injection — PREFERRED
@Service
class OrderService {
    private final OrderRepo repo;
    OrderService(OrderRepo repo) { this.repo = repo; }   // @Autowired optional if single constructor
}

// Setter injection — for optional dependencies
@Service
class OrderService {
    private PaymentClient client;
    @Autowired(required = false)
    void setClient(PaymentClient client) { this.client = client; }
}

// Field injection — DISCOURAGED
@Service
class OrderService {
    @Autowired private OrderRepo repo;   // looks clean, but...
}
```

### 2. Why constructor injection wins (know these cold)
- **Immutability** — fields can be `final`; the object is fully initialized and never half-built.
- **Mandatory dependencies are explicit** — you can't construct the object without them; no NPEs from forgotten wiring.
- **Testability** — `new OrderService(mockRepo)` in a plain unit test, **no Spring needed**.
- **Detects too many dependencies** — a constructor with 8 params *screams* "this class does too much" (a design smell field injection hides).
- **No reflection-only access** — field injection requires reflection to set privates, which is why you can't `final` them and why tests need a container or reflection hacks.
- Since Spring 4.3, **`@Autowired` is optional on a single constructor**. Centurion controllers use exactly this style.

### 3. Resolving ambiguity: `@Primary`, `@Qualifier`, names
When multiple beans satisfy a type, Spring throws `NoUniqueBeanDefinitionException`. Resolve with:
```java
@Service @Primary
class EnglishGreetingService implements GreetingService {}   // default winner

@Service @Qualifier("spanish")
class SpanishGreetingService implements GreetingService {}

@Service
class Facade {
    Facade(@Qualifier("spanish") GreetingService gs) {}      // explicit pick
}
```
Resolution order: exact `@Qualifier` match → `@Primary` → match by **parameter name == bean name** → else error.

### 4. Injecting collections & maps
```java
@Service
class NotificationDispatcher {
    private final List<Notifier> notifiers;        // ALL Notifier beans, in @Order order
    private final Map<String, Notifier> byName;    // bean name → bean
    NotificationDispatcher(List<Notifier> notifiers, Map<String, Notifier> byName) { ... }
}
```
Great for the **strategy pattern** — cent uses this style for plugin/handler registries (e.g., multiple AAA plugins discovered and dispatched by type).

### 5. Optional dependencies
- `@Autowired(required = false)` — leaves field null if absent.
- `Optional<Dep>` constructor param.
- `ObjectProvider<Dep>` — lazy, supports `getIfAvailable()`, streams.
- `@Nullable`.

### 6. Circular dependencies
A → B and B → A. With **constructor injection on both**, Spring **cannot** build either first → `BeanCurrentlyInCreationException` at startup. With field/setter injection Spring can partially construct one and inject later, "resolving" it — but it's a **design smell**. Fixes (best→worst): **refactor** to remove the cycle (extract a third bean), use `@Lazy` on one dependency, or use setter injection. As of **Spring Boot 2.6+, circular references are prohibited by default** (`spring.main.allow-circular-references=false`) — you must consciously enable them, which the framework is nudging you not to do.

### 7. `@Value` and `Environment`
```java
@Value("${jamf.token-endpoint:api/v1/auth/token}")  // with default after ':'
private String tokenEndpoint;
```
Prefer **`@ConfigurationProperties`** (Day 08) over scattered `@Value` for grouped config.

---

## PRACTICE

```java
public interface Notifier { void notify(String msg); String channel(); }

@Component @Order(1)
class EmailNotifier implements Notifier {
    public void notify(String m) {}  public String channel() { return "email"; }
}
@Component @Order(2)
class SlackNotifier implements Notifier {
    public void notify(String m) {}  public String channel() { return "slack"; }
}

// Strategy registry via collection injection (cent-style plugin dispatch)
@Service
public class NotificationDispatcher {
    private final List<Notifier> ordered;
    private final Map<String, Notifier> byBeanName;
    public NotificationDispatcher(List<Notifier> ordered, Map<String, Notifier> byBeanName) {
        this.ordered = ordered; this.byBeanName = byBeanName;
    }
    public void broadcast(String msg) { ordered.forEach(n -> n.notify(msg)); }
    public Set<String> channels() {
        return ordered.stream().map(Notifier::channel).collect(Collectors.toSet());
    }
}

// Ambiguity resolution
@Service
class GreetingClient {
    private final GreetingService primary;     // gets @Primary bean
    private final GreetingService spanish;      // gets qualified bean
    GreetingClient(GreetingService primary, @Qualifier("spanishGreetingService") GreetingService spanish) {
        this.primary = primary; this.spanish = spanish;
    }
}
```

**Exercises:**
1. Create two `GreetingService` beans; resolve the conflict first with `@Primary`, then override with `@Qualifier`.
2. Build a `Map<String, Notifier>` strategy dispatcher; route a message to a channel chosen at runtime.
3. Force a constructor circular dependency between two services; observe the startup failure, then fix it by extracting a third collaborator.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Why is field injection discouraged despite being the most concise?**
It hides dependencies (not visible in the constructor/API), prevents `final` fields (so objects can be mutated/partially built), makes **unit testing without Spring hard** (you need reflection or a container to set privates), and **masks the "too many dependencies" smell**. It also encourages circular dependencies. Constructor injection fixes all of these — hence it's the recommended default.

**Q2. Two beans implement the same interface and you didn't add `@Primary`/`@Qualifier`. What happens?**
At startup Spring throws **`NoUniqueBeanDefinitionException`** (expected single matching bean but found 2). Resolution: mark one `@Primary`, or use `@Qualifier("beanName")` at the injection point, or inject by the exact bean name as the parameter name, or inject a `List<Interface>`/`Map<String,Interface>` if you actually want all of them.

**Q3. How does Spring resolve which bean to inject when several match?**
Order: (1) narrow candidates by type; (2) if `@Qualifier` is present, match by qualifier; (3) else if exactly one is `@Primary`, pick it; (4) else fall back to matching the **injection point's name** against a bean name; (5) if still ambiguous, throw. Generics also narrow (e.g., `Repository<User>` vs `Repository<Order>`).

**Q4. Constructor-injected circular dependency — why can't Spring resolve it, but field injection sometimes can?**
With constructor injection, Spring must fully build A to construct B and vice versa — neither can be created first, so it fails fast (`BeanCurrentlyInCreationException`). With field/setter injection, Spring can instantiate A (empty), instantiate B, then set the fields afterward, breaking the chicken-and-egg via a partially-initialized "early reference." It works mechanically but signals a design flaw. Boot 2.6+ disallows cycles by default.

**Q5. Is `@Autowired` required on constructors?**
Not since **Spring 4.3** — if a class has a **single constructor**, Spring uses it for injection automatically. You only need `@Autowired` to disambiguate when there are **multiple** constructors. (cent controllers often still annotate it for clarity/legacy.)

**Q6. `@Resource` vs `@Autowired` vs `@Inject` — differences?**
`@Autowired` (Spring) resolves **by type** first, then name; supports `required`. `@Resource` (JSR-250) resolves **by name** first, then type. `@Inject` (JSR-330) is the standard equivalent of `@Autowired` (by type) but lacks `required`. In Spring apps, `@Autowired` (or plain constructor injection) is idiomatic.

**Q7. How do you inject all implementations of an interface, and why is that useful?**
Inject `List<MyInterface>` (ordered via `@Order`/`Ordered`) or `Map<String, MyInterface>` (bean-name keyed). It's the backbone of the **strategy/plugin pattern**: add a new implementation as a bean and it's auto-discovered and wired into the dispatcher with no changes to the dispatcher — exactly how cent registers multiple AAA plugins/handlers.

**Q8. What does `ObjectProvider` give you over direct injection?**
Lazy, optional, and multi-instance access: `getIfAvailable()`, `getIfUnique()`, `orderedStream()`, and `.getObject()` to fetch a fresh prototype per call. It avoids hard startup failures for optional beans and solves the singleton-injects-prototype problem without scoped proxies.

➡ Next: [Day 04 — Configuration, Profiles & SpEL](day-04-configuration-profiles-spel.md)
