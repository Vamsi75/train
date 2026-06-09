# Day 08 — Externalized Configuration & `@ConfigurationProperties`

## THEORY

### 1. Externalized config = 12-factor config
Never hard-code environment-specific values. Spring Boot reads config from many sources and lets you override anything at deploy time without rebuilding — essential for running the same artifact in dev/stage/prod (exactly what cent does with its config server).

### 2. Property source precedence (full, high → low)
1. Devtools global settings (dev only)
2. `@TestPropertySource` / test properties
3. **Command-line arguments** (`--server.port=9000`)
4. `SPRING_APPLICATION_JSON` (inline JSON)
5. `ServletConfig`/`ServletContext` params
6. JNDI
7. **Java System properties** (`-Dkey=value`)
8. **OS environment variables** (`SERVER_PORT=9000`)
9. Profile-specific app config (`application-{profile}.yml`)
10. Application config (`application.yml`)
11. `@PropertySource`
12. Default properties
Higher wins. **Relaxed binding**: `cent.base-url`, `cent.baseUrl`, `CENT_BASEURL` (env) all bind to the same property — env vars use `UPPER_SNAKE_CASE`.

### 3. `@Value` vs `@ConfigurationProperties`
```java
// @Value — fine for one-offs
@Value("${server.port:8080}") int port;

// @ConfigurationProperties — PREFERRED for grouped, type-safe, validated config
@ConfigurationProperties(prefix = "cent.jamf")
@Validated
public record JamfProperties(
    @NotBlank String baseUrl,
    @NotNull Duration tokenTtl,          // "30m" → Duration, auto-converted
    boolean enabled,
    AutoRevocation autoRevocation
) {
    public record AutoRevocation(List<String> computerGroups, List<String> mobileDeviceGroups) {}
}
```
Enable with `@EnableConfigurationProperties(JamfProperties.class)` or `@ConfigurationPropertiesScan`.
```yaml
cent:
  jamf:
    base-url: https://jamf.example.com
    token-ttl: 30m
    enabled: true
    auto-revocation:
      computer-groups: [eng-laptops, contractors]
      mobile-device-groups: [byod]
```
**Why `@ConfigurationProperties` wins:** type-safe, supports nested objects/lists/maps, relaxed binding, **JSR-303 validation**, IDE metadata, and groups related config instead of scattering `@Value`s. The cent `JamfOAuthIdentityProvider.AutoRevocationConfiguration` (with `computerGroups`/`mobileDeviceGroups` lists) is exactly the shape that maps cleanly to a `@ConfigurationProperties` record.

### 4. Type conversion & `Duration`/`DataSize`
Boot converts strings to rich types: `Duration` (`30s`, `5m`, `2h`), `DataSize` (`10MB`), enums, `List`, `Map`, `Resource`. No manual parsing.

### 5. Config files location & names
- Default name `application`, formats `.yml`/`.properties`.
- Locations searched: classpath root, `classpath:/config/`, current dir, `./config/`.
- Override: `spring.config.name`, `spring.config.location`, `spring.config.import` (e.g., import from a config server, Vault, or another file).
- **Boot 2.4+** introduced `spring.config.import` and **deprecated `bootstrap.yml`** for most config-server use (now `spring.config.import: configserver:` ).

### 6. Secrets — don't put them in `application.yml`
Use env vars, a secrets manager (Vault, AWS Secrets Manager), or `spring.config.import`. Mark sensitive actuator data and avoid logging properties. cent serves config centrally; secrets are injected via the environment, not committed.

### 7. `@RefreshScope` (Spring Cloud)
With Spring Cloud Config, `@RefreshScope` beans can pick up changed config at runtime via the `/actuator/refresh` endpoint without restart (Day 19).

---

## PRACTICE

```java
@ConfigurationProperties(prefix = "cent.cleanup")
@Validated
public record CleanupProperties(
    @NotNull Duration retention,    // e.g., 90d
    @Min(1) int batchSize,
    boolean dryRun
) {}

@SpringBootApplication
@ConfigurationPropertiesScan          // discovers @ConfigurationProperties records
public class DemoApplication { ... }

@Service
class CleanupService {
    private final CleanupProperties props;
    CleanupService(CleanupProperties props) { this.props = props; }
    public void run() {
        System.out.printf("retention=%s batch=%d dryRun=%s%n",
            props.retention(), props.batchSize(), props.dryRun());
    }
}
```
```yaml
cent:
  cleanup:
    retention: 90d
    batch-size: 5000
    dry-run: false
```
```bash
# Override at deploy time — no rebuild
java -jar app.jar --cent.cleanup.batch-size=10000
SERVER_PORT=9090 CENT_CLEANUP_DRY_RUN=true java -jar app.jar   # env vars + relaxed binding
```

**Exercises:**
1. Bind a nested list/map config into a `@ConfigurationProperties` record and print it.
2. Add `@Validated` with `@Min`/`@NotBlank`; start with an invalid value and read the startup failure.
3. Override one property via command-line arg, another via env var; confirm precedence.
4. Bind a `Duration` (`30m`) and a `DataSize` (`10MB`) without manual parsing.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. `@Value` vs `@ConfigurationProperties` — which and why?**
`@ConfigurationProperties` for any non-trivial config: it's **type-safe**, supports **nested objects/collections/maps**, does **relaxed binding**, integrates **JSR-303 validation**, generates IDE metadata, and groups related keys. `@Value` is fine for a single, simple value or a SpEL expression but scatters config, has no validation, and fails awkwardly on complex structures. Seniors default to `@ConfigurationProperties`.

**Q2. What is relaxed binding?**
Boot binds a single property to multiple naming styles: `cent.base-url` (kebab, canonical in YAML), `cent.baseUrl` (camel), `cent.base_url`, and the env var `CENT_BASEURL`/`CENT_BASE_URL` all map to the same target. This lets you set properties via OS environment variables (which can't contain dots/dashes) using `UPPER_SNAKE_CASE`.

**Q3. Give the top of the property precedence order and a practical implication.**
Command-line args > `SPRING_APPLICATION_JSON` > system properties > **OS environment variables** > `application-{profile}.yml` > `application.yml`. Implication: you ship **one immutable artifact** and override per environment with env vars/args at deploy time — the foundation of 12-factor config and how a single cent service image runs across environments.

**Q4. How do you validate configuration at startup?**
Annotate the `@ConfigurationProperties` class with `@Validated` and put JSR-303 constraints (`@NotBlank`, `@Min`, `@NotNull`) on fields. Invalid config causes a **fail-fast startup error** (`BindValidationException`) instead of a runtime NPE deep in the app — surfacing misconfig immediately, ideally before traffic.

**Q5. Where should secrets live, and where should they NOT?**
**Not** in `application.yml` committed to source control. Use environment variables, a secrets manager (Vault/AWS Secrets Manager/K8s secrets), or `spring.config.import` from a secure backend. Keep them out of logs and out of unsecured actuator endpoints. Externalized config means the artifact has no secrets baked in.

**Q6. `application.yml` vs `bootstrap.yml` — is bootstrap still needed?**
`bootstrap.yml` was historically loaded **before** `application.yml` to configure the Spring Cloud Config client (where to fetch remote config). Since **Boot 2.4 / Spring Cloud 2020**, the preferred approach is `spring.config.import: configserver:...` in `application.yml`, and `bootstrap` is **disabled by default** (needs `spring-cloud-starter-bootstrap` to re-enable). So for new apps you generally don't use `bootstrap.yml`.

**Q7. How does Boot convert `"30m"` into a `Duration` or `"10MB"` into a size?**
Built-in converters: `Duration` understands ISO-8601 (`PT30M`) and simple suffixes (`s`, `m`, `h`, `d`), configurable with `@DurationUnit`. `DataSize` parses `KB/MB/GB`. There are converters for enums, `List`, `Map`, `Resource`, etc. You bind the rich type directly in `@ConfigurationProperties`; Boot does the parsing.

**Q8. Can config change without a restart?**
With **Spring Cloud Config** + `@RefreshScope`, hitting `/actuator/refresh` (or a bus event) re-binds annotated beans to updated values without restarting the JVM. Plain Boot (no Cloud) reads config at startup only; changing `application.yml` requires a restart. This refresh capability is a key reason microservice fleets like cent centralize config.

➡ Next: [Day 09 — Actuator & Observability](day-09-actuator-observability.md)
