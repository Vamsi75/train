# Day 05 — AOP & Proxies (the self-invocation trap lives here)

## THEORY

### 1. What AOP solves
**Cross-cutting concerns** — logging, security, transactions, caching, metrics, retries — apply across many methods. Scattering them duplicates code. **AOP** lets you define them once (an *aspect*) and apply them declaratively. Spring's `@Transactional`, `@Cacheable`, `@Async`, `@Retryable`, and method security are **all built on AOP**.

### 2. Core vocabulary
- **Aspect** — a module of cross-cutting logic (`@Aspect` class).
- **Join point** — a point where advice can apply (in Spring AOP, always a **method execution**).
- **Advice** — the action, by timing: `@Before`, `@After`, `@AfterReturning`, `@AfterThrowing`, `@Around` (the most powerful — wraps the call).
- **Pointcut** — an expression selecting join points (`execution(* com.cent..*Service.*(..))`).
- **Weaving** — linking aspects to target code (Spring AOP weaves at **runtime via proxies**).

### 3. How Spring AOP works: PROXIES (the crux)
Spring AOP is **proxy-based**, not bytecode weaving (that's AspectJ). When a bean needs advice, Spring's `BeanPostProcessor` wraps it in a proxy at creation (Day 02 step 6). Callers get the **proxy**; the proxy runs advice then delegates to the real target.
- **JDK dynamic proxy** — used when the bean **implements an interface**; proxy implements the same interface.
- **CGLIB proxy** — used when there's **no interface** (subclasses the class). Spring Boot **defaults to CGLIB** (`proxyTargetClass = true`) even with interfaces, for consistency.

### 4. The two consequences every senior must know
**(a) Self-invocation bypasses the proxy.** If a method calls `this.otherMethod()` internally, the call goes to the **target object directly, not the proxy** — so `@Transactional`/`@Cacheable`/`@Async` on `otherMethod` **do nothing**. The proxy only intercepts calls that come *through it from outside*.
```java
@Service
class ReportService {
    public void run() { generate(); }              // self-call → proxy bypassed
    @Transactional public void generate() { ... }  // NOT transactional when called via run()
}
```
Fixes: split into two beans, inject self (`@Autowired ReportService self`), or use `AopContext.currentProxy()`.

**(b) Proxies only work on Spring-managed beans and (typically) `public` methods.** `@Transactional` on a `private`/`protected`/`final` method, or on a method of a `final` class (CGLIB can't subclass `final`), is silently ignored.

### 5. Advice ordering
Multiple aspects on the same join point order by `@Order` / `Ordered` (lower = outer). `@Around` advice surrounds everything; you must call `joinPoint.proceed()` or the target never runs.

### 6. AspectJ vs Spring AOP
| | Spring AOP | AspectJ |
|--|-----------|---------|
| Weaving | Runtime (proxy) | Compile/load-time (bytecode) |
| Join points | Method execution only | Methods, fields, constructors, etc. |
| Self-invocation | Bypassed | Intercepted |
| Setup | Built-in, simple | More powerful, more setup |
Use Spring AOP for 95% of needs; AspectJ when you need field/constructor interception or to defeat self-invocation.

---

## PRACTICE

```java
// A logging+timing aspect (cent-style cross-cutting: log every service call duration)
@Aspect
@Component
public class TimingAspect {

    private static final Logger log = LoggerFactory.getLogger(TimingAspect.class);

    // Pointcut: all public methods in any *Service in the cent packages
    @Pointcut("execution(public * com.cent..*Service+.*(..))")
    public void serviceMethods() {}

    @Around("serviceMethods()")
    public Object time(ProceedingJoinPoint pjp) throws Throwable {
        long start = System.nanoTime();
        try {
            return pjp.proceed();                      // MUST call, or target never runs
        } catch (Throwable t) {
            log.warn("{} threw {}", pjp.getSignature(), t.getClass().getSimpleName());
            throw t;
        } finally {
            long ms = (System.nanoTime() - start) / 1_000_000;
            log.info("{} took {} ms", pjp.getSignature().toShortString(), ms);
        }
    }
}

// Custom annotation + aspect (declarative auditing)
@Retention(RetentionPolicy.RUNTIME) @Target(ElementType.METHOD)
public @interface Audited { String action(); }

@Aspect @Component
class AuditAspect {
    @AfterReturning("@annotation(audited)")
    public void audit(JoinPoint jp, Audited audited) {
        System.out.println("AUDIT: " + audited.action() + " by " + currentUser());
    }
    private String currentUser() { return "system"; }
}

@Service
class AccountService {
    @Audited(action = "REVOKE_CERT")
    public void revoke(String serial) { /* ... */ }
}
```

**Exercises:**
1. Write the `TimingAspect`, hit an endpoint, and confirm timing logs appear — proving the proxy intercepts external calls.
2. Add a method that **self-invokes** an `@Audited` method; observe the audit does NOT fire. Fix it by extracting a second bean.
3. Add a second aspect and use `@Order` to control which wraps the other.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Why does `@Transactional` on a method called internally by the same class do nothing?**
Because Spring AOP is **proxy-based**: advice is applied by a proxy that wraps the bean. Internal `this.method()` calls go **straight to the target object**, never passing through the proxy, so the transactional advice is never triggered. This **self-invocation** problem also affects `@Cacheable`, `@Async`, `@Retryable`. Fixes: move the method to another bean, inject the bean into itself, use `AopContext.currentProxy()`, or switch to AspectJ weaving.

**Q2. JDK dynamic proxy vs CGLIB — when is each used and what are the limits?**
**JDK dynamic proxy** requires the target to **implement an interface** and proxies the interface. **CGLIB** **subclasses** the target (no interface needed) but **can't proxy `final` classes or `final`/`private` methods**. Spring Boot defaults to CGLIB (`proxyTargetClass=true`) for uniformity. Limit to remember: proxying needs a non-final, instantiable class or an interface.

**Q3. Which methods can be advised by Spring AOP?**
Effectively **public** methods of Spring-managed beans, called **from outside** the bean. `private`, `protected`, package-private, `static`, and `final` methods aren't proxied (CGLIB can't override final/private; the transaction/cache infra targets public). Putting `@Transactional` on a private method is a silent no-op.

**Q4. Difference between Spring AOP and AspectJ?**
Spring AOP = **runtime, proxy-based**, method-execution join points only, can't intercept self-invocation, zero extra build setup. AspectJ = **compile-time/load-time bytecode weaving**, supports field/constructor/method join points, intercepts self-calls, more powerful but needs a weaver/agent. Spring uses AspectJ's *annotation syntax* (`@Aspect`, pointcut expressions) even though the default runtime is proxy-based.

**Q5. In `@Around` advice, what happens if you forget `joinPoint.proceed()`?**
The **target method is never executed** — the proxy returns whatever the advice returns (often `null`), silently skipping the real logic. `proceed()` is what invokes the next advice/the target. This is a classic bug: an `@Around` that "works" but the real method never runs.

**Q6. What is weaving and when does it happen in Spring AOP?**
Weaving is linking aspects into target code. In **Spring AOP it happens at runtime** when the container creates the bean — a `BeanPostProcessor` (`AnnotationAwareAspectJAutoProxyCreator`) wraps the bean in a proxy during `postProcessAfterInitialization`. (AspectJ weaves at compile or class-load time instead.)

**Q7. You have `@Transactional` and a custom `@Around` aspect on the same method. How do you control order?**
Use `@Order`/`Ordered` on the aspects (lower value = higher precedence = outer). Transaction management has a default order (`Ordered.LOWEST_PRECEDENCE`), so your aspect usually wraps it unless configured. Getting this wrong matters: e.g., a retry aspect must sit **outside** the transaction so each retry starts a fresh transaction.

**Q8. Can two beans be proxied differently in the same app (one JDK, one CGLIB)?**
Yes, unless you force `proxyTargetClass=true` globally. By default Spring picks per-bean: interface-implementing beans → JDK proxy, others → CGLIB. Boot sets CGLIB globally for consistency, but the mechanism is per-bean capable.

➡ Next: [Day 06 — Events, Resources & Validation](day-06-events-resources-validation.md)
