# Day 27 — Production Readiness & Real-Time Incident Playbook

> The day that proves you've *run* Spring in production, not just written it. Each scenario: **Symptom → Diagnose → Fix → Prevent.**

## PRODUCTION-READINESS CHECKLIST (the "is it ready to ship" list)
- **Config externalized** (env/Config Server), **no secrets in code/images** (Day 8, 19).
- **Health probes** — liveness/readiness wired correctly (Day 9).
- **Graceful shutdown** — `server.shutdown=graceful` + `spring.lifecycle.timeout-per-shutdown-phase`; drains in-flight requests on SIGTERM (k8s rolling deploys).
- **Timeouts on every remote call** + circuit breakers/bulkheads (Day 21).
- **Connection pool sized** (HikariCP) for DB; thread pools bounded (Day 16).
- **Observability** — metrics (Micrometer/Prometheus), structured logs + trace ids (Day 9, 10), dashboards + alerts.
- **Resource limits** — JVM `-XX:MaxRAMPercentage`, container memory/CPU limits (Day 10).
- **Idempotency** for retried/messaging operations (Day 21, 22).
- **DB migrations** via Flyway/Liquibase (versioned, not `ddl-auto=update` in prod).
- **Security** — auth on endpoints, actuator locked down, dependencies scanned.

---

## Scenario 1 — Memory leak / `OutOfMemoryError`, container OOM-killed
**Symptom:** Heap climbs over hours/days, GC thrashes, then OOM; pod restarts.
**Diagnose:** Capture `/actuator/heapdump` (or on OOM via `-XX:+HeapDumpOnOutOfMemoryError`), analyze in Eclipse MAT for the dominator tree. Common Spring culprits: **unbounded caches** (a `Map` cache without eviction/TTL), **ThreadLocals not cleared** (MDC! Day 10), accumulating collections in singletons, classloader leaks on redeploy.
**Fix:** bound the cache (TTL/maxSize), clear ThreadLocals in `finally`, remove the leaking reference.
**Prevent:** always set cache eviction, monitor heap trend, set `-XX:MaxRAMPercentage`, alert on memory growth.

## Scenario 2 — Connection pool exhaustion (`HikariPool - Connection is not available`)
**Symptom:** Requests hang then fail to acquire a DB connection; latency spikes under load.
**Diagnose:** HikariCP metrics (active vs idle vs pending). Causes: **pool too small** for concurrency, **connections held too long** (long transactions, `open-in-view` keeping a connection across view rendering — Day 14), a slow query holding connections, or a **leak** (connection not returned).
**Fix:** turn off `open-in-view`, shorten transactions, fix the slow query, set `leak-detection-threshold`, right-size `maximum-pool-size` (often *fewer* than you think — pool size ≈ cores-based, not "bigger is better").
**Prevent:** `spring.datasource.hikari.leak-detection-threshold`, monitor pending connections, keep transactions short.

## Scenario 3 — Thread pool exhaustion / app unresponsive
**Symptom:** Tomcat accepts no new requests; everything queues; high `http.server.requests` latency.
**Diagnose:** **Thread dump** (`/actuator/threaddump`, `jstack`). Look for many threads **BLOCKED/WAITING** on the same lock or a slow downstream call (no timeout). Classic: a hung remote dependency + missing read timeout → all Tomcat worker threads blocked (Day 21).
**Fix:** add timeouts + circuit breaker + bulkhead; size the Tomcat thread pool (`server.tomcat.threads.max`); consider virtual threads for blocking I/O (Day 16).
**Prevent:** timeouts everywhere, bulkheads, async/virtual threads, load tests.

## Scenario 4 — Slow startup
**Symptom:** App takes minutes to start; failing k8s startup probes → crash loop.
**Diagnose:** startup actuator (`/actuator/startup`), enable `--debug`. Causes: too many beans eagerly created, slow `@PostConstruct` (network calls), large component scan, classpath scanning, connecting to a slow dependency at boot.
**Fix:** defer heavy work to `ApplicationReadyEvent` (Day 6), `@Lazy` where appropriate, narrow component scan, increase startup probe `initialDelay/failureThreshold`, consider AOT/native (Day 10).
**Prevent:** keep startup work minimal; never do retriable network calls synchronously in `@PostConstruct`.

## Scenario 5 — `LazyInitializationException` in production (not in tests)
**Symptom:** Works locally, fails in prod when serializing an entity. (Day 14)
**Diagnose:** A LAZY association accessed after the session closed (often during JSON serialization), usually because tests had `open-in-view` on or used a different fetch path.
**Fix:** return **DTOs**, fetch with `JOIN FETCH`/`@EntityGraph` inside the transaction. Keep `open-in-view=false`.
**Prevent:** DTO projections at the API boundary; never serialize entities (Day 12).

## Scenario 6 — N+1 queries discovered in prod (slow endpoints)
**Symptom:** An endpoint that's fine with 10 rows crawls with 10k. (Day 14)
**Diagnose:** `logging.level.org.hibernate.SQL=DEBUG` or a profiler shows 1+N queries; APM flags repeated identical queries.
**Fix:** `@EntityGraph`/`JOIN FETCH`/batch fetching/DTO projection.
**Prevent:** review SQL counts in tests; assert query counts (datasource-proxy / Hibernate statistics).

## Scenario 7 — High GC pause / latency spikes
**Symptom:** Periodic p99 latency spikes correlated with GC.
**Diagnose:** GC logs, JVM metrics (`jvm.gc.pause`). Causes: heap too small, allocation churn, wrong collector for the workload.
**Fix:** size heap, use **G1/ZGC** appropriately (ZGC for low-pause large heaps), reduce allocations (avoid per-request large object creation).
**Prevent:** GC monitoring + alerts, load testing with realistic data.

## Scenario 8 — Config/secret leaked or wrong per environment
**Symptom:** Prod used a dev endpoint / a secret appeared in logs or `/actuator/env`.
**Diagnose:** Check property precedence (Day 8), actuator exposure (Day 9).
**Fix:** lock down actuator (`env`/`configprops` off or secured), redact, rotate the secret.
**Prevent:** externalized config, secret manager, never log properties, sanitize actuator.

## Scenario 9 — Failed/blocking deploy (rolling update breaks)
**Symptom:** During deploy, requests fail or old pods get killed mid-request.
**Diagnose:** No graceful shutdown; readiness flips too late; DB migration incompatible with old+new running together.
**Fix:** `server.shutdown=graceful`; readiness gating; **backward-compatible migrations** (expand/contract pattern: add column → deploy → backfill → later remove).
**Prevent:** zero-downtime migration discipline, graceful shutdown, proper probes.

## Scenario 10 — AI endpoint cost/latency blowup (Day 25–26)
**Symptom:** LLM bill spikes; AI endpoints time out; rate-limited by provider.
**Diagnose:** Micrometer token/latency metrics; check prompt sizes (huge RAG context?), retry storms, no caching.
**Fix:** cap `maxTokens`, trim/optimize chunks, cache deterministic prompts, add timeouts + circuit breaker around the model, route simple tasks to cheaper/local models.
**Prevent:** budget alerts on tokens, bulkhead the model dependency, test prompt sizes.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Spring app's memory grows until OOM. How do you find the cause?**
Enable `-XX:+HeapDumpOnOutOfMemoryError` (or capture `/actuator/heapdump`), open the dump in **Eclipse MAT**, and inspect the **dominator tree / leak suspects** for what's retaining the most heap. In Spring apps the usual suspects are **unbounded caches** (a `@Cacheable`/`Map` with no eviction or TTL), **uncleared ThreadLocals** (MDC not cleared on pooled threads), collections that only grow in singletons, and classloader leaks across hot redeploys. Fix the retaining reference and add bounds; prevent with heap-trend monitoring and eviction policies.

**Q2. Why can making the DB connection pool *bigger* hurt performance?**
A connection pool larger than the database can effectively serve just creates **more contention** — more threads competing for limited DB CPU/IO/locks, more context switching, longer queue times — often *reducing* throughput and increasing latency (HikariCP's own guidance: small pools, sized roughly around core count, usually outperform huge ones). The right move is a **right-sized small pool** plus **short transactions** and fixing slow queries, not a bigger pool. Connection-pool exhaustion is usually a "holding connections too long" problem, not a "too few connections" problem.

**Q3. All Tomcat threads are blocked and the app stops responding. Most likely cause?**
A **downstream call with no timeout** (DB, remote service) hung, and because Spring MVC is **thread-per-request**, every worker thread that hit that path is now **blocked indefinitely** waiting — once the pool is exhausted, no new requests can be served (cascading failure). Diagnose with a **thread dump** showing threads BLOCKED/WAITING on the same call. Fix: **timeouts on every remote call**, plus circuit breaker + bulkhead (Day 21); long-term, virtual threads or async make this far less fatal.

**Q4. What is `open-in-view` and why is it considered a production anti-pattern?**
`spring.jpa.open-in-view` (default **true**) keeps the Hibernate session open for the **entire request, including view/JSON rendering**, so lazy associations can be loaded late. The problem: it **holds a database connection for the whole request duration** (including slow serialization and client I/O), which under load causes **connection-pool starvation**, and it **hides N+1/Lazy problems** that then surprise you in prod. Best practice: set it **false** and fetch exactly what you need within the service-layer transaction (DTOs/`JOIN FETCH`).

**Q5. How do you achieve zero-downtime deployments with database changes?**
Two parts. **App side:** `server.shutdown=graceful` so SIGTERM drains in-flight requests, and **readiness probes** so traffic only routes to ready instances during a rolling update. **Schema side:** **backward-compatible migrations** using the expand/contract pattern — e.g., to rename a column: add the new column, deploy code that writes both/reads new, backfill, then in a *later* release drop the old column. Never make a breaking schema change in the same deploy that requires it, because old and new app versions run **simultaneously** during the rollout.

**Q6. `ddl-auto=update` in production — why not?**
`hibernate.ddl-auto=update` lets Hibernate **alter the schema automatically** from entity mappings — which is **non-deterministic, unreviewed, can't drop/rename safely, has no rollback, and may lock tables unexpectedly** under load. Production schema changes must be **explicit, versioned, reviewed, and reversible** — use **Flyway or Liquibase** migration scripts run as part of the deploy, with `ddl-auto=validate` (or `none`) so the app verifies but never mutates the schema. Auto-DDL is for local dev only.

**Q7. Your service is fast in tests but slow under production load. How do you investigate?**
Look at **production telemetry** first: Micrometer metrics (`http.server.requests` percentiles, DB pool active/pending, GC pauses, thread states), distributed traces to find the slow span, and logs by trace id. Common gaps between test and prod: **N+1 queries** that don't show with tiny test data, **connection-pool/thread-pool exhaustion** under concurrency, **GC pressure** at scale, **missing timeouts** on dependencies, and **cold caches**. Reproduce with a **realistic-volume load test**, then `EXPLAIN` slow queries (MySQL guide) and fix the dominant bottleneck — measure, don't guess.

**Q8. How do you keep an AI-powered endpoint production-safe?**
Treat the model as an **unreliable, slow, metered external dependency**: wrap it with **timeouts, retries (backoff), circuit breaker, and a bulkhead** (Day 21); **cap `maxTokens`** and trim prompt/RAG context to control cost and latency; **cache** deterministic responses; emit **Micrometer token/latency metrics with budget alerts**; **never send secrets/PII** to a third-party model and store keys in a secret manager; and **guard tool calling** (authorization + audit + confirmation for destructive actions) and **filter RAG by tenant** to prevent data leakage (Day 26). Plus graceful fallback when the model is unavailable.

➡ Next: [Day 28 — Tricky Interview Master Set & Capstone](day-28-tricky-interview-capstone.md)
