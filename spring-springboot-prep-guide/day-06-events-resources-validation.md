# Day 06 — Application Events, Resources & Bean Validation

## THEORY

### 1. The application event mechanism (in-process pub/sub)
Spring's `ApplicationEventPublisher` lets beans communicate **decoupled** — a publisher doesn't know its listeners. Great for side effects (audit, email, cache invalidation) that shouldn't clutter core logic.
```java
// 1. Define an event (a plain record in modern Spring — no need to extend ApplicationEvent)
public record CertRevokedEvent(String serial, String reason) {}

// 2. Publish
@Service
class RevocationService {
    private final ApplicationEventPublisher publisher;
    RevocationService(ApplicationEventPublisher publisher) { this.publisher = publisher; }
    public void revoke(String serial) {
        // ... core revocation ...
        publisher.publishEvent(new CertRevokedEvent(serial, "manual"));
    }
}

// 3. Listen (decoupled)
@Component
class RevocationListeners {
    @EventListener
    void onRevoked(CertRevokedEvent e) { /* send notification */ }
}
```

### 2. Synchronous by default, `@Async` to decouple
`@EventListener` runs **synchronously in the publisher's thread/transaction** by default. Add `@Async` (with `@EnableAsync`) to run on a separate thread. Combine with `@TransactionalEventListener(phase = AFTER_COMMIT)` to fire **only after the publisher's transaction commits** — critical so you don't email "order placed" then roll back.

### 3. Built-in lifecycle events
`ApplicationStartingEvent`, `ApplicationReadyEvent` (app fully up — good for warmup), `ContextRefreshedEvent`, `ContextClosedEvent`. Listening to `ApplicationReadyEvent` is the clean place for "do X once on startup."

### 4. The Resource abstraction
`Resource` unifies access to files, classpath, URLs, etc. Inject via `@Value`:
```java
@Value("classpath:templates/welcome.html") private Resource welcomeTemplate;
@Value("file:/etc/cent/keys/private.pem")  private Resource keyFile;
// resource.getInputStream(), resource.exists(), resource.getContentAsString(UTF_8)
```

### 5. Bean Validation (Jakarta Validation / Hibernate Validator)
Declarative constraints on fields, validated automatically on `@Valid`/`@Validated` boundaries (controllers, `@ConfigurationProperties`, service methods).
```java
public record CreateServerRequest(
    @NotBlank String name,
    @Email String contactEmail,
    @Min(1) @Max(65535) int port,
    @Pattern(regexp = "\\d{1,3}(\\.\\d{1,3}){3}") String ipAddress,
    @NotNull @Valid AutoRevocationConfig revocation   // @Valid cascades into nested object
) {}
```
Common constraints: `@NotNull`, `@NotBlank`, `@NotEmpty`, `@Size`, `@Min`/`@Max`, `@Positive`, `@Email`, `@Pattern`, `@Past`/`@Future`, `@Valid` (cascade).

### 6. `@Valid` vs `@Validated`
- **`@Valid`** (Jakarta) — triggers validation, supports nested cascade.
- **`@Validated`** (Spring) — adds **validation groups** support and enables **method-level validation** on a bean (validating method params/return via an AOP proxy).

### 7. Custom constraints
```java
@Target({FIELD}) @Retention(RUNTIME)
@Constraint(validatedBy = SerialValidator.class)
public @interface ValidSerial { String message() default "invalid serial"; Class<?>[] groups() default {}; Class<? extends Payload>[] payload() default {}; }

class SerialValidator implements ConstraintValidator<ValidSerial, String> {
    public boolean isValid(String v, ConstraintValidatorContext ctx) {
        return v != null && v.matches("[A-Z0-9]{8,}");
    }
}
```

---

## PRACTICE

```java
// Transaction-safe event: notify only after the DB commit succeeds
@Service
public class CertService {
    private final ApplicationEventPublisher publisher;
    public CertService(ApplicationEventPublisher publisher) { this.publisher = publisher; }

    @Transactional
    public void revoke(String serial) {
        // update DB rows for revocation...
        publisher.publishEvent(new CertRevokedEvent(serial, "policy"));
    }
}

@Component
class NotificationListener {
    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void notifyAfterCommit(CertRevokedEvent e) {
        // runs on a separate thread, ONLY if revoke()'s transaction committed
        System.out.println("Notifying revocation of " + e.serial());
    }
}

// Validation in a controller (Day 11/13 cover the error handling)
@RestController
@RequestMapping("/servers")
class ServerController {
    @PostMapping
    public ResponseEntity<Void> create(@Valid @RequestBody CreateServerRequest req) {
        // if invalid → MethodArgumentNotValidException → 400 (handle on Day 13)
        return ResponseEntity.status(HttpStatus.CREATED).build();
    }
}
```
Enable async/scheduling once at startup:
```java
@SpringBootApplication
@EnableAsync
public class DemoApplication { ... }
```

**Exercises:**
1. Publish an event from a service and consume it in two listeners; confirm both fire.
2. Make one listener `@Async` and prove it runs on a different thread (print `Thread.currentThread().getName()`).
3. Use `@TransactionalEventListener(AFTER_COMMIT)`; force a rollback and confirm the listener does NOT run.
4. Build a custom `@ValidSerial` constraint and apply it to a request DTO.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Are Spring application events synchronous or asynchronous by default?**
**Synchronous** — `publishEvent` runs all matching `@EventListener`s on the **caller's thread**, within the caller's transaction, before returning. To make a listener async, annotate it `@Async` (and `@EnableAsync`); then it runs on a separate thread and exceptions don't propagate back to the publisher.

**Q2. Why use `@TransactionalEventListener(AFTER_COMMIT)` instead of `@EventListener`?**
A plain listener fires **as soon as the event is published**, even if the surrounding transaction later **rolls back** — so you might send a "cert revoked" email for a revocation that didn't actually persist. `@TransactionalEventListener(AFTER_COMMIT)` defers the listener until the publishing transaction **commits successfully**, preventing side effects on rolled-back work. (Phases: BEFORE_COMMIT, AFTER_COMMIT, AFTER_ROLLBACK, AFTER_COMPLETION.)

**Q3. `@Valid` vs `@Validated` — when do you need `@Validated`?**
`@Valid` is standard Jakarta validation and cascades into nested objects. `@Validated` is Spring's variant that adds **validation groups** (validate different rules in different contexts) and enables **method-level validation** (validating `@RequestParam`/`@PathVariable`/service method arguments) by putting an AOP validator proxy around the bean. Use `@Validated` on the class for method validation or when you need groups.

**Q4. Where does validation actually run, and what exception is thrown on failure?**
At `@Valid`/`@Validated` boundaries — most commonly the controller method argument. On a `@RequestBody` failure Spring throws **`MethodArgumentNotValidException`**; on `@RequestParam`/`@PathVariable`/method-validation failure it's **`ConstraintViolationException`**. By default these map to HTTP 400, but you typically handle them in a `@ControllerAdvice` to produce a clean error body (Day 13).

**Q5. A transactional event listener marked `@Async` — does it run in the original transaction?**
No. `@Async` runs it on a **different thread**, which has **no transaction context** (transactions are thread-bound). With `AFTER_COMMIT` the original transaction is already committed anyway. If the listener needs its own DB work, it must start a **new transaction** (`@Transactional` on the async listener method, which itself is a fresh transaction on that thread).

**Q6. Why decouple with events instead of just calling the listener's method directly?**
Events invert the dependency: the publisher depends on nothing about the consumers, so you can **add/remove side effects (audit, notify, index) without touching core logic** — better separation of concerns and easier testing. The trade-off: indirection makes flow harder to trace, and synchronous listeners still share the publisher's thread/transaction unless made async.

**Q7. How do you run code exactly once when the app is fully started?**
Listen for **`ApplicationReadyEvent`** (or implement `ApplicationRunner`/`CommandLineRunner`). `ApplicationReadyEvent` fires after the context is refreshed *and* the app is ready to serve traffic — the right place for cache warmups, registering with discovery, or kicking off schedulers. Avoid heavy work in `@PostConstruct` (the web server isn't up yet).

➡ Next: [Day 07 — Spring Boot Auto-Configuration & Starters](day-07-springboot-autoconfig-starters.md)
