# Day 21 — Resilience: Circuit Breaker, Retry, Bulkhead & OpenFeign

## THEORY

### 1. Why resilience patterns exist
In distributed systems, **a dependency will be slow or down**. Without protection, a slow downstream service makes calling threads **block and pile up**, exhausting the caller's thread pool → the caller becomes unresponsive → its callers fail → **cascading failure** takes down the whole system. Resilience patterns contain the blast radius.

### 2. Resilience4j (replaced Netflix Hystrix)
A lightweight, functional resilience library. The key modules:
| Pattern | Purpose |
|---------|---------|
| **Circuit Breaker** | Stop calling a failing dependency; fail fast. |
| **Retry** | Re-attempt transient failures (with backoff). |
| **Rate Limiter** | Cap call rate. |
| **Bulkhead** | Limit concurrent calls so one dependency can't consume all threads. |
| **Time Limiter** | Bound how long a call may take. |

### 3. Circuit Breaker — the states
- **CLOSED** — calls flow normally; failures are counted.
- **OPEN** — failure rate crossed the threshold → calls **fail immediately** (or hit a fallback) **without** touching the dependency, giving it time to recover.
- **HALF_OPEN** — after a wait, a few **trial** calls are allowed; if they succeed → CLOSED, if they fail → back to OPEN.
This prevents hammering a struggling service and lets the caller stay responsive (fast failure + fallback).
```java
@CircuitBreaker(name = "policyService", fallbackMethod = "fallbackPolicy")
@Retry(name = "policyService")
@Bulkhead(name = "policyService")
public Policy getPolicy(String id) {
    return policyClient.fetch(id);     // remote call
}
public Policy fallbackPolicy(String id, Throwable t) {
    return Policy.defaultPolicy();     // degrade gracefully
}
```
```yaml
resilience4j:
  circuitbreaker:
    instances:
      policyService:
        sliding-window-size: 20
        failure-rate-threshold: 50          # open if >=50% of last 20 calls failed
        wait-duration-in-open-state: 10s
        permitted-number-of-calls-in-half-open-state: 3
  retry:
    instances:
      policyService:
        max-attempts: 3
        wait-duration: 500ms
        exponential-backoff-multiplier: 2
  bulkhead:
    instances:
      policyService:
        max-concurrent-calls: 10
```

### 4. Ordering of the patterns (subtle, interview-worthy)
The default aspect order (outer→inner) is **Retry → CircuitBreaker → RateLimiter → TimeLimiter → Bulkhead**. So **retry wraps the circuit breaker**: each retry is a separate call the breaker observes, and once the breaker is OPEN, retries fail fast too. Getting this wrong (e.g., breaker outside retry) changes failure behavior.

### 5. Fallbacks & graceful degradation
A fallback returns a **sensible degraded response** (cached value, default, partial data, "try later") instead of an error — keeping the user experience functional when a dependency is down. Design fallbacks to be **safe** (don't fall back to stale data where correctness is critical).

### 6. Timeouts — the most underrated control
**Every remote call must have a timeout.** A missing/too-long timeout is the #1 cause of cascading failures (threads block forever on a hung dependency). Set connect + read timeouts on every client; pair with a `TimeLimiter` for async calls.

### 7. OpenFeign — declarative REST clients
Define an interface; Feign generates the HTTP client, integrated with discovery, load balancing, and Resilience4j.
```java
@FeignClient(name = "policy-engine-service")           // resolved via discovery + load balanced
interface PolicyFeignClient {
    @GetMapping("/policies/{id}")
    Policy getPolicy(@PathVariable String id);
}
```
Enable with `@EnableFeignClients`. (Spring's native **HTTP Interface `@HttpExchange`**, Day 12, is a non-Feign alternative.) Add Resilience4j via Feign's circuit-breaker integration or wrap calls.

### 8. The bulkhead analogy
Like watertight compartments in a ship: if one floods (a dependency hangs), the bulkhead **confines it** so the whole ship (service) doesn't sink. Concretely: a separate, **bounded** thread pool / semaphore per dependency so a hung dependency can only consume *its* slice of resources, not all of them.

---

## PRACTICE

```java
@Service
public class PolicyService {
    private final PolicyFeignClient client;
    public PolicyService(PolicyFeignClient client) { this.client = client; }

    @CircuitBreaker(name = "policyService", fallbackMethod = "fallback")
    @Retry(name = "policyService")
    @TimeLimiter(name = "policyService")        // for async (CompletableFuture) variants
    public CompletableFuture<Policy> getPolicyAsync(String id) {
        return CompletableFuture.supplyAsync(() -> client.getPolicy(id));
    }
    public CompletableFuture<Policy> fallback(String id, Throwable t) {
        return CompletableFuture.completedFuture(Policy.defaultPolicy());
    }
}
```
```java
// Always set timeouts on the HTTP client
@Bean
RestClient policyRestClient() {
    var factory = new SimpleClientHttpRequestFactory();
    factory.setConnectTimeout(Duration.ofSeconds(2));
    factory.setReadTimeout(Duration.ofSeconds(3));
    return RestClient.builder().requestFactory(factory).build();
}
```
```bash
# Watch the breaker state via actuator
curl localhost:8080/actuator/circuitbreakers | jq
curl localhost:8080/actuator/metrics/resilience4j.circuitbreaker.state | jq
```

**Exercises:**
1. Wrap a flaky remote call with `@CircuitBreaker` + fallback; force failures and watch it trip to OPEN (via `/actuator/circuitbreakers`), then recover through HALF_OPEN.
2. Add `@Retry` with exponential backoff; observe how it interacts with the breaker once OPEN.
3. Add a `@Bulkhead` limiting concurrency; flood the method and show calls beyond the limit are rejected/queued.
4. Remove the read timeout and simulate a hung dependency; observe thread pileup — then add the timeout and see it contained.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Explain the circuit breaker states and what problem it solves.**
**CLOSED**: calls pass through, failures counted. When the failure rate crosses a threshold → **OPEN**: calls **fail fast** (or hit a fallback) without touching the dependency, so you stop hammering a service that's already struggling and keep your own threads free. After a wait it goes **HALF_OPEN**: a few trial calls test recovery; success → CLOSED, failure → OPEN again. It solves **cascading failure** — without it, threads block on a dead dependency until the whole caller is exhausted.

**Q2. Retry and circuit breaker together — what's the correct ordering and why?**
Default order is **Retry(outer) → CircuitBreaker(inner)**: retries wrap the breaker, so each retry attempt is a call the breaker counts, and once the breaker is **OPEN**, retries also fail fast (no point retrying a known-down service). If you inverted it (breaker outside retry), one logical call's retries would count as a single breaker event and you'd lose fast-fail on retries. Also: only retry **idempotent** operations and add **backoff + jitter** to avoid retry storms.

**Q3. What is a bulkhead and how does it prevent cascading failure?**
A **bulkhead** limits the **concurrent calls / resources** allocated to a single dependency (a bounded thread pool or semaphore per dependency). So if dependency A hangs, only A's bounded slice of threads is consumed — calls to healthy dependency B still have their own threads. Without bulkheads, a single slow dependency can consume the **entire shared thread pool**, starving everything. Named after a ship's watertight compartments.

**Q4. Why are timeouts the most important resilience control?**
Because **without a timeout, a single hung dependency blocks a thread forever**; under load those blocked threads accumulate until the pool is exhausted and the service stops responding — the classic cascading failure. A timeout bounds the wait so the thread is freed and the failure becomes a fast, handleable error (then circuit breaker/fallback kick in). Every remote call needs **connect and read timeouts**; they're the foundation the other patterns build on.

**Q5. What's a fallback, and when is a fallback dangerous?**
A fallback returns a **degraded but useful** response (cached/default/partial) when the primary call fails, keeping the app functional. It's **dangerous** when correctness matters and the fallback returns **stale or wrong data** silently (e.g., falling back to an old balance, or "access granted" when the auth service is down). Fallbacks must **fail safe**: for security/financial decisions, failing closed (deny/error) is often correct, not returning optimistic defaults.

**Q6. Hystrix vs Resilience4j — why the shift?**
**Hystrix is in maintenance mode** (no longer actively developed). **Resilience4j** is the modern replacement: **lightweight, functional, modular** (use only the patterns you need), Java 8+/functional API, no archaius dependency, and first-class Spring Boot + Micrometer integration. Spring Cloud Circuit Breaker abstracts over providers but Resilience4j is the de-facto default now.

**Q7. OpenFeign vs `RestClient`/`@HttpExchange` — when to use Feign?**
**OpenFeign** gives **declarative** clients (define an interface, get an implementation) with built-in **discovery + load balancing** integration — convenient in a Spring Cloud ecosystem. Spring's native **`@HttpExchange`** (backed by `RestClient`/`WebClient`) offers the same declarative style **without** the extra Feign dependency and is the framework's strategic direction. Use Feign in existing Spring Cloud apps; prefer `@HttpExchange`/`RestClient` for new code unless you need a Feign-specific feature.

**Q8. A retry made an outage worse. How is that possible?**
Retries **amplify load** on an already-struggling service: if 1000 clients each retry 3× against a degraded dependency, you triple the traffic exactly when it can least handle it — a **retry storm** that can keep the service down. Mitigations: **exponential backoff + jitter** (de-synchronize retries), a **circuit breaker** to stop retrying once OPEN, **retry budgets/caps**, and never retrying non-idempotent or permanently-failing requests. Retries without these controls are an anti-pattern.

➡ Next: [Day 22 — Messaging: AMQP & Kafka](day-22-messaging-amqp-kafka.md)
