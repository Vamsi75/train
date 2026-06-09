# Day 09 — Actuator, Metrics & Observability

## THEORY

### 1. What Actuator gives you
`spring-boot-starter-actuator` exposes **production-readiness endpoints**: health, metrics, info, env, loggers, thread dumps, heap dumps, mappings, conditions, and more. It's how ops/monitoring sees inside a running service.

### 2. Key endpoints
| Endpoint | Purpose |
|----------|---------|
| `/actuator/health` | Liveness/readiness; aggregates health indicators (DB, disk, broker). |
| `/actuator/info` | Build/version/custom info. |
| `/actuator/metrics` | Micrometer metrics (JVM, HTTP, datasource, custom). |
| `/actuator/prometheus` | Metrics in Prometheus scrape format. |
| `/actuator/loggers` | **View & change log levels at runtime** (no restart). |
| `/actuator/env` | Resolved configuration/property sources. |
| `/actuator/conditions` | Auto-config condition report. |
| `/actuator/threaddump`, `/actuator/heapdump` | Diagnostics for prod incidents. |
| `/actuator/mappings` | All request mappings. |

### 3. Exposure & security (critical)
By default only `health` (and `info`) are exposed over HTTP. Expose more explicitly:
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus,loggers
  endpoint:
    health:
      show-details: when-authorized   # never leak DB details to anonymous users
  server:
    port: 9090                        # run actuator on a separate, firewalled port
```
**Never expose `env`, `heapdump`, `loggers`, `shutdown` publicly** — they leak secrets or allow tampering. Secure with Spring Security and/or a management port not exposed to the internet.

### 4. Health indicators & probes
- Built-in indicators: `db`, `diskSpace`, `ping`, `rabbit`, `redis`, etc., auto-registered based on the classpath.
- **Kubernetes probes:** `/actuator/health/liveness` and `/actuator/health/readiness` (enable with `management.endpoint.health.probes.enabled=true`). **Liveness** = "is the app alive (else restart me)"; **Readiness** = "can I take traffic now (else stop routing to me)". Getting these right prevents traffic hitting a still-starting or overwhelmed pod.
```java
@Component
class JamfHealthIndicator implements HealthIndicator {
    public Health health() {
        return pingJamf() ? Health.up().withDetail("latencyMs", 42).build()
                          : Health.down().withDetail("reason", "timeout").build();
    }
    private boolean pingJamf() { return true; }
}
```

### 5. Metrics with Micrometer
Micrometer is a **vendor-neutral metrics facade** (the "SLF4J of metrics") — code to Micrometer, export to Prometheus/Datadog/CloudWatch/etc. by adding a registry dependency.
```java
@Service
class RevocationService {
    private final Counter revocations;
    private final Timer revokeTimer;
    RevocationService(MeterRegistry registry) {
        this.revocations = registry.counter("cert.revocations", "source", "policy");
        this.revokeTimer = registry.timer("cert.revoke.duration");
    }
    public void revoke(String serial) {
        revokeTimer.record(() -> { /* work */ });
        revocations.increment();
    }
}
```
Or declaratively: `@Timed` on a method, `@Counted`.

### 6. Distributed tracing & the "three pillars"
Observability = **metrics** (aggregates), **logs** (events), **traces** (request paths across services). Spring Boot 3 uses **Micrometer Tracing** (successor to Spring Cloud Sleuth) with OpenTelemetry/Zipkin bridges to propagate a **trace id / span id** across microservice calls — indispensable for debugging cent's cross-service request flows. Put the trace id in logs (`%X{traceId}` via MDC) to correlate.

### 7. `/actuator/info` and build info
Add build/git info to `info`:
```yaml
management.info.git.mode: full
management.info.env.enabled: true
```
Plus the `git-commit-id` and `spring-boot-maven-plugin build-info` to embed version/commit — invaluable for "what's actually deployed?"

---

## PRACTICE

```yaml
management:
  endpoints.web.exposure.include: health,info,metrics,prometheus,loggers
  endpoint.health.show-details: when-authorized
  endpoint.health.probes.enabled: true
  metrics.tags.application: ${spring.application.name}
```
```java
// Custom health indicator + custom metric
@Component
class DiskQueueHealth implements HealthIndicator {
    public Health health() {
        long depth = queueDepth();
        return depth < 10_000 ? Health.up().withDetail("depth", depth).build()
                              : Health.down().withDetail("depth", depth).build();
    }
    long queueDepth() { return 42; }
}

@RestController
class OrderController {
    private final MeterRegistry registry;
    OrderController(MeterRegistry registry) { this.registry = registry; }
    @PostMapping("/orders")
    public String place() {
        registry.counter("orders.placed").increment();
        return "ok";
    }
}
```
```bash
curl localhost:8080/actuator/health | jq
curl localhost:8080/actuator/metrics/jvm.memory.used | jq
# Change a log level at runtime without restart:
curl -X POST localhost:8080/actuator/loggers/com.cent \
  -H 'Content-Type: application/json' -d '{"configuredLevel":"DEBUG"}'
```

**Exercises:**
1. Expose `metrics` and `prometheus`; scrape `/actuator/prometheus` and find your custom counter.
2. Write a custom `HealthIndicator` and make `/actuator/health` go DOWN; observe the HTTP 503.
3. Flip `com.cent` to DEBUG at runtime via `/actuator/loggers`, then back — no restart.
4. Configure liveness/readiness probes and explain to a teammate when each fails.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Liveness vs readiness probe — what breaks if you confuse them?**
**Liveness** answers "is the process healthy, or should the orchestrator **restart** it?" **Readiness** answers "can it **serve traffic right now**?" If you wire a slow dependency check into *liveness*, a transient DB blip makes Kubernetes **kill and restart** healthy pods (a crash loop). If readiness never goes false under load, traffic keeps hitting an overwhelmed pod. Liveness should be cheap/local; readiness reflects dependency availability.

**Q2. Why should `/actuator/env` and `/actuator/heapdump` not be publicly exposed?**
`/env` reveals resolved configuration including potentially **secrets/credentials and internal hostnames**; `/heapdump` dumps the entire heap (containing tokens, PII, keys) and is a DoS vector. `/loggers` and `/shutdown` allow tampering. Expose only what's needed (`health`, `info`, `metrics`/`prometheus`), secure the rest with Spring Security, and/or bind actuator to a **separate management port** not reachable from the internet.

**Q3. What is Micrometer and why use it instead of a Prometheus client directly?**
Micrometer is a **vendor-neutral metrics facade**. You instrument once (counters, timers, gauges) and switch/add backends (Prometheus, Datadog, CloudWatch, New Relic) by adding a registry dependency — no code changes. It also auto-instruments JVM, HTTP server/client, datasource, and more. It's the "SLF4J for metrics," which is why Spring Boot standardizes on it.

**Q4. How do you change a log level in production without redeploying?**
`POST /actuator/loggers/{logger}` with `{"configuredLevel":"DEBUG"}` (loggers endpoint enabled). This dynamically adjusts that logger's level at runtime — invaluable for capturing debug output during a live incident, then reverting. No restart, no config change, no redeploy.

**Q5. How does a trace id flow across microservices, and why does it matter?**
Micrometer Tracing (with OpenTelemetry/Zipkin) generates a **trace id** at the edge and propagates it via HTTP headers (e.g., W3C `traceparent`) and messaging headers to downstream services, each adding **spans**. Put the trace id in the MDC so every log line carries it. Then one user request across cent's gateway → auth → cert services can be **reconstructed end-to-end**, which is the only sane way to debug latency/errors in a distributed system.

**Q6. What does `/actuator/health` return for HTTP status, and how is the overall status computed?**
It aggregates all registered `HealthIndicator`s; the overall status is the **worst** among them by a defined order (DOWN/OUT_OF_SERVICE outrank UP). UP → HTTP 200; DOWN/OUT_OF_SERVICE → **503**. You can customize the status-to-HTTP mapping and which indicators are included in liveness/readiness groups.

**Q7. A custom `HealthIndicator` makes the whole app report DOWN and Kubernetes stops routing traffic. Is that desired?**
It depends which group it's in. If it's in the **readiness** group and the dependency is genuinely required to serve requests, DOWN → no traffic is correct (fail safe). But if the dependency is **non-critical** (e.g., an optional analytics sink), it shouldn't gate readiness — put it in a separate group or don't let it affect the routing decision, or you cause unnecessary outages. Health indicator design is about **what truly blocks serving traffic**.

➡ Next: [Day 10 — Logging, DevTools & Packaging](day-10-logging-devtools-packaging.md)
