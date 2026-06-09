# Day 10 — Logging, DevTools, Packaging & Deployment

## THEORY

### 1. Logging stack
Spring Boot uses **SLF4J** as the API and **Logback** as the default implementation (cent uses SLF4J `LoggerFactory.getLogger(...)` — you saw it in `AAAServerController`). You can swap to Log4j2.
```java
private static final Logger log = LoggerFactory.getLogger(MyClass.class);
log.info("Revoking cert {} for org {}", serial, orgId);   // parameterized — no string concat
```
- **Always use parameterized logging** (`{}`), never `"... " + value` — the latter builds the string even when the level is disabled.
- Levels: TRACE < DEBUG < INFO < WARN < ERROR.
- Configure in `application.yml`:
```yaml
logging:
  level:
    root: INFO
    com.cent: DEBUG
    org.hibernate.SQL: DEBUG       # see generated SQL
  pattern:
    level: "%5p [%X{traceId:-},%X{spanId:-}]"   # include trace ids from MDC
  file:
    name: /var/log/cent/app.log
```

### 2. Structured (JSON) logging
For log aggregation (ELK, Loki, Splunk), emit **JSON** logs. Spring Boot **3.4+** has built-in structured logging (`logging.structured.format.console=ecs`); otherwise use `logstash-logback-encoder`. JSON logs let you query by field (orgId, traceId) instead of grepping text.

### 3. MDC (Mapped Diagnostic Context)
Per-thread key/value context attached to every log line — put `traceId`, `orgId`, `userId` in the MDC (often via a filter/interceptor) so all logs in a request are correlated.
```java
MDC.put("orgId", orgId);
try { /* handle request */ } finally { MDC.clear(); }  // ALWAYS clear (thread reuse!)
```

### 4. DevTools (dev only)
`spring-boot-devtools`: automatic restart on classpath change, LiveReload, sensible dev property defaults. **Excluded from production** automatically (it's not packaged in a fully executable jar / disabled when running from a jar). Speeds the inner dev loop.

### 5. Packaging: the executable fat jar
`spring-boot-maven-plugin` repackages into an **executable "fat"/"uber" jar** containing your code + all dependencies + a launcher. Run with `java -jar`. Internally it uses a custom layout (`BOOT-INF/classes`, `BOOT-INF/lib`) and a `JarLauncher` — nested jars, not a shaded jar.

### 6. Layered jars & efficient Docker images
A naive Docker image re-downloads all dependencies on every code change. **Layered jars** split content into layers (dependencies, snapshot deps, resources, application classes) so Docker caches the rarely-changing dependency layer:
```dockerfile
# Multi-stage, layered
FROM eclipse-temurin:21-jre AS builder
WORKDIR /app
COPY target/app.jar app.jar
RUN java -Djarmode=layertools -jar app.jar extract

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /app/dependencies/ ./
COPY --from=builder /app/spring-boot-loader/ ./
COPY --from=builder /app/snapshot-dependencies/ ./
COPY --from=builder /app/application/ ./       # changes most often → last layer
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
```
Or use **buildpacks**: `./mvnw spring-boot:build-image` → OCI image, no Dockerfile.

### 7. GraalVM native images
`spring-boot-starter` + native build (`-Pnative`) produces an **AOT-compiled native executable**: sub-second startup, low memory — great for serverless/scale-to-zero. Cost: longer builds, reflection needs hints, some libraries unsupported. JIT (JVM) still wins for long-running, high-throughput services.

### 8. Running configuration in containers
Pass config via env vars (relaxed binding), set `-XX:MaxRAMPercentage` (not fixed `-Xmx`) so the JVM respects the container memory limit, and enable graceful shutdown (`server.shutdown=graceful`).

---

## PRACTICE

```yaml
# application.yml — production-ish logging
logging:
  level:
    root: INFO
    com.cent.authentication: DEBUG
  pattern:
    console: "%d{HH:mm:ss.SSS} %-5level [%X{traceId:-}] %logger{36} - %msg%n"
```
```java
// Request-scoped MDC via a filter (correlate every log in a request)
@Component
public class MdcFilter extends OncePerRequestFilter {
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        MDC.put("traceId", Optional.ofNullable(req.getHeader("X-Trace-Id"))
                                   .orElse(UUID.randomUUID().toString()));
        try { chain.doFilter(req, res); }
        finally { MDC.clear(); }   // critical: threads are pooled and reused
    }
}
```
```bash
./mvnw clean package
java -jar target/demo-0.0.1-SNAPSHOT.jar --server.port=9000
java -Djarmode=layertools -jar target/demo-*.jar list   # see layers
./mvnw spring-boot:build-image                            # buildpack image, no Dockerfile
```

**Exercises:**
1. Replace a `"x=" + x` log with a parameterized `{}` version; explain the performance difference at disabled levels.
2. Add an MDC filter that injects a `traceId`; verify every log line in a request shares it.
3. Build a layered Docker image; change one line of code and confirm only the application layer rebuilds.
4. Turn on `org.hibernate.SQL: DEBUG` and watch generated SQL (foreshadows Day 14's N+1).

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Why prefer `log.info("x={}", x)` over `log.info("x=" + x)`?**
With string concatenation, the message string is **built every time regardless of level** — wasteful (and possibly expensive `toString()`s) when DEBUG/INFO is disabled. Parameterized logging defers substitution until SLF4J confirms the level is enabled, so a disabled `log.debug("...{}", expensive())` costs almost nothing (though the *argument* `expensive()` still evaluates — guard with `isDebugEnabled()` if the argument itself is costly).

**Q2. Why must you `MDC.clear()` in a finally block?**
Servlet containers **reuse threads** from a pool. MDC is **thread-local**, so values left over from a previous request would **leak into the next request's logs** on the same thread (wrong traceId/orgId). Clearing in `finally` guarantees cleanup even on exceptions. (Same reasoning applies to any thread-local state.)

**Q3. What's in a Spring Boot fat jar and how does `java -jar` run it?**
It's a **nested-jar** layout: your classes in `BOOT-INF/classes`, dependency jars in `BOOT-INF/lib`, plus Spring Boot's `JarLauncher` as the jar's `Main-Class`. It is **not** a shaded jar (classes aren't merged). `JarLauncher` sets up a special classloader that can load classes from the nested jars, then invokes your `main`. This avoids classpath-hell and version-clobbering that shading can cause.

**Q4. Why use layered jars for Docker?**
Dependencies change rarely; your code changes constantly. Layered jars split the jar into layers (dependencies / snapshot-deps / resources / application) so Docker can **cache the large dependency layer** and only rebuild the small application layer on a code change. This slashes image build time and registry push/pull size compared to copying one monolithic jar that invalidates the cache on every build.

**Q5. GraalVM native image vs JVM jar — trade-offs?**
Native: **near-instant startup, low memory footprint** (ideal for serverless/scale-to-zero and CLIs), but **longer build times**, requires reflection/resource **hints** (Spring AOT generates many), some libraries don't work, and **peak throughput is often lower** than a warmed-up JIT JVM. For long-running, high-throughput services, the JVM (with JIT optimizing hot paths) typically wins; native shines where startup latency and density matter.

**Q6. Is DevTools safe in production?**
No — and Spring Boot guards against it. DevTools enables auto-restart, dev-only property overrides, and a LiveReload server. It's **automatically disabled when running from a fully packaged jar** and excluded from the production artifact. Never rely on it in prod; it's an inner-loop developer convenience only.

**Q7. SLF4J vs Logback vs Log4j2 — how do they relate?**
**SLF4J** is the logging **facade/API** you code against. **Logback** is the default **implementation** Boot wires in (SLF4J's native backend). **Log4j2** is an alternative implementation you can swap to (exclude `spring-boot-starter-logging`, add `spring-boot-starter-log4j2`). Coding to SLF4J means you can change the backend without touching application code — the same decoupling principle as Micrometer for metrics.

**Q8. How should you set JVM heap in a container?**
Use **`-XX:MaxRAMPercentage`** (e.g., 75) so the JVM sizes the heap relative to the **container's** memory limit, rather than a hard-coded `-Xmx` that ignores cgroup limits and risks the kernel OOM-killing the container. Modern JVMs are container-aware, but explicitly setting RAM percentage and enabling `server.shutdown=graceful` are production hygiene.

➡ Next: [Day 11 — Spring MVC & REST Controllers](day-11-rest-controllers-mvc.md)
