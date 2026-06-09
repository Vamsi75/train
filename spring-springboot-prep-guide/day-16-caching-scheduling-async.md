# Day 16 — Caching, Scheduling, Async & Retry

> All four are AOP-proxy features — so **all** suffer the self-invocation trap (Day 05).

## THEORY

### 1. Caching abstraction
`@EnableCaching` + annotations give a provider-agnostic cache (backed by ConcurrentHashMap, Caffeine, Redis, etc.).
```java
@Cacheable(cacheNames = "servers", key = "#id")
public ServerDto find(String id) { /* expensive load */ }

@CachePut(cacheNames = "servers", key = "#dto.id")   // update cache AND execute method
public ServerDto update(ServerDto dto) { ... }

@CacheEvict(cacheNames = "servers", key = "#id")      // remove on delete
public void delete(String id) { ... }

@CacheEvict(cacheNames = "servers", allEntries = true) // clear whole cache
public void reloadAll() { ... }
```
- `@Cacheable` — return cached if present, else run + cache.
- `@CachePut` — **always** run, then store result (for updates).
- `@CacheEvict` — remove entries.
- `condition`/`unless` — conditional caching (`unless = "#result == null"`).

### 2. Cache provider choice
- **Caffeine** — high-performance in-process (per-instance). Great for single-node or read-mostly local data.
- **Redis** — distributed cache shared across instances; needed when multiple service replicas must see the same cache (cent runs many replicas → local caches diverge, so shared Redis or short TTLs matter).
- Always set **TTL/eviction** — an unbounded cache is a memory leak.

### 3. Scheduling
```java
@Scheduled(cron = "${cleanup.cron:0 0 2 * * *}")  // 2 AM daily; property-driven
public void nightlyCleanup() { ... }

@Scheduled(fixedDelay = 30_000)   // 30s AFTER previous completes
@Scheduled(fixedRate  = 30_000)   // every 30s regardless of duration (can overlap/pile up!)
@Scheduled(initialDelay = 10_000, fixedDelay = 30_000)
```
Enable with `@EnableScheduling`. **Default scheduler is single-threaded** — long jobs delay others; size a `TaskScheduler` pool. **Multi-instance gotcha:** `@Scheduled` runs on **every** replica → use a distributed lock (ShedLock) so a job runs once across the cluster. (cent's `DataDownloadServiceScheduler` is exactly this kind of scheduled component.)

### 4. Async
```java
@Async                                  // runs on a separate thread, returns immediately
public void sendEmail(String to) { ... }

@Async
public CompletableFuture<Report> buildReport(Long id) {
    return CompletableFuture.completedFuture(report);
}
```
Enable with `@EnableAsync`. **Configure your own `Executor`** — the default `SimpleAsyncTaskExecutor` creates a new thread per task (no pooling, unbounded → resource exhaustion). Define a bounded `ThreadPoolTaskExecutor` and reference it: `@Async("taskExecutor")`.

### 5. Retry (Spring Retry / Resilience4j)
```java
@Retryable(retryFor = TransientException.class,
           maxAttempts = 3,
           backoff = @Backoff(delay = 500, multiplier = 2))   // 500ms, 1s, 2s
public JamfToken fetchToken() { ... }

@Recover
public JamfToken recover(TransientException e) { return cachedToken(); }  // fallback after retries
```
Only retry **idempotent** operations and **transient** failures (timeouts, 503) — never retry a non-idempotent POST blindly, and never retry a validation/auth error.

### 6. Virtual threads (Java 21 / Boot 3.2+)
`spring.threads.virtual.enabled=true` runs request handling on **virtual threads** — cheap, massively scalable for **blocking I/O** workloads (a thread-per-request model that no longer costs OS threads). Often a simpler alternative to reactive (Day 24) for I/O-bound services.

---

## PRACTICE

```java
@Configuration
@EnableCaching @EnableScheduling @EnableAsync
public class InfraConfig {
    @Bean
    public Caffeine<Object,Object> caffeineConfig() {
        return Caffeine.newBuilder().maximumSize(10_000).expireAfterWrite(Duration.ofMinutes(10));
    }
    @Bean("taskExecutor")
    public Executor taskExecutor() {
        ThreadPoolTaskExecutor ex = new ThreadPoolTaskExecutor();
        ex.setCorePoolSize(8); ex.setMaxPoolSize(16); ex.setQueueCapacity(100);
        ex.setThreadNamePrefix("async-"); ex.setRejectedExecutionHandler(new CallerRunsPolicy());
        ex.initialize(); return ex;
    }
}

@Service
public class ServerService {
    @Cacheable(cacheNames = "servers", key = "#id", unless = "#result == null")
    public ServerDto find(String id) { /* slow DB/remote call */ return load(id); }

    @CacheEvict(cacheNames = "servers", key = "#id")
    public void delete(String id) { repo.deleteById(id); }
}

@Component
public class CleanupScheduler {
    @Scheduled(cron = "${cleanup.cron:0 0 2 * * *}")
    // @SchedulerLock(name = "nightlyCleanup")   // ShedLock: run once across the cluster
    public void run() { /* purge old data in chunks */ }
}
```

**Exercises:**
1. Add `@Cacheable`; call the method twice and prove the body runs once (log inside it). Then `@CacheEvict` and prove it reloads.
2. Show the self-invocation trap with `@Cacheable`: call the cached method internally and watch the cache get bypassed.
3. Configure a bounded `@Async` executor; submit more tasks than the pool+queue and observe the rejection policy.
4. Add `@Retryable` with exponential backoff to a flaky call; add an `@Recover` fallback.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. `@Cacheable` on a method called internally doesn't cache. Why?**
Same **self-invocation/proxy** issue as `@Transactional`: caching is applied by an AOP proxy, and an internal `this.method()` call bypasses the proxy, so no caching advice runs. The method executes every time. Fix by calling through the proxy (separate bean, self-injection, or `AopContext`).

**Q2. `@Cacheable` vs `@CachePut` — both seem to cache.**
`@Cacheable` **short-circuits**: if a cached value exists for the key, the **method body does not run** — it returns the cached value. `@CachePut` **always runs the method** and then stores the result, updating the cache. Use `@Cacheable` for reads, `@CachePut` for writes/updates where you want the fresh result cached. Mixing them up means stale reads or unnecessary executions.

**Q3. What's the danger of the default `@Async` executor and the default scheduler?**
The default async executor (`SimpleAsyncTaskExecutor`) **doesn't pool** — it spawns a new thread per task, so a burst can exhaust threads/memory. The default scheduler is **single-threaded**, so one long-running `@Scheduled` job **delays all others**. Fix both by defining bounded `ThreadPoolTaskExecutor`/`ThreadPoolTaskScheduler` beans sized for the workload, with a sensible rejection policy.

**Q4. `fixedRate` vs `fixedDelay` — and what's the overlap risk?**
`fixedDelay` waits a fixed gap **after the previous execution finishes** — runs never overlap. `fixedRate` triggers **every N ms regardless of how long the task takes** — if a run exceeds the interval (and the scheduler has spare threads), executions can **overlap or pile up**, potentially compounding load. Use `fixedDelay` for jobs whose duration varies; `fixedRate` only when you truly need a steady cadence and runs are short.

**Q5. `@Scheduled` runs on all instances in a cluster — how do you make it run once?**
Use a **distributed lock**: a library like **ShedLock** (`@SchedulerLock`) backed by the DB/Redis ensures only one node acquires the lock and executes; others skip. Alternatives: leader election (e.g., via the discovery server) or an external scheduler/quartz cluster. Otherwise every replica fires the job — duplicate work, race conditions, or duplicated side effects (emails, charges).

**Q6. When should you retry, and when is retrying dangerous?**
Retry only **idempotent** operations on **transient** failures (network timeout, 503, deadlock). Use **exponential backoff + jitter** to avoid synchronized retry storms. Dangerous: retrying **non-idempotent** calls (POST that creates resources/charges → duplicates), retrying **permanent** errors (400/401/validation — they'll just fail again wasting resources), and retrying without a cap or circuit breaker (amplifies an outage). Pair retry with idempotency keys and circuit breakers (Day 21).

**Q7. Caffeine vs Redis for `@Cacheable` in a multi-replica deployment?**
**Caffeine** is in-process: blazing fast but **per-instance**, so each replica has its own copy — fine for read-mostly, tolerant-of-staleness data, but caches **diverge** and evictions aren't coordinated. **Redis** is a **shared distributed cache**: all replicas see the same entries and invalidations, at the cost of a network hop. In a fleet like cent, use Redis (or short-TTL local caches) when consistency across replicas matters; Caffeine for hot, local, eventually-consistent lookups.

**Q8. How do virtual threads change the caching/async/blocking story?**
Virtual threads (Java 21, `spring.threads.virtual.enabled=true`) make **blocking I/O cheap** — you can have millions of them, so the traditional "thread-per-request blocks and exhausts the pool" concern largely disappears for I/O-bound work. This often removes the need to go reactive (Day 24) for scalability, and reduces pressure to offload blocking calls to `@Async`. CPU-bound work and the proxy/self-invocation rules are unchanged.

➡ Next: [Day 17 — Spring Security Fundamentals](day-17-spring-security-fundamentals.md)
