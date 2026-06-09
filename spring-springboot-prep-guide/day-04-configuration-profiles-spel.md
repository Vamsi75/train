# Day 04 — Configuration, Component Scanning, Profiles & SpEL

## THEORY

### 1. `@Configuration` and `@Bean`
A `@Configuration` class is a source of bean definitions via `@Bean` methods. By default it's a **full** configuration: Spring CGLIB-proxies it so that calling one `@Bean` method from another returns the **same singleton**, not a new object.
```java
@Configuration
public class Config {
    @Bean RestClient client() { return RestClient.create(); }
    @Bean OrderApi api() { return new OrderApi(client()); }  // client() returns the SAME bean, not a new one
}
```
`@Configuration(proxyBeanMethods = false)` ("lite" mode) skips the CGLIB proxy — faster startup, but inter-bean method calls create new instances. Use it when `@Bean` methods don't call each other.

### 2. `@Import` and modular config
Split configuration and compose with `@Import(OtherConfig.class)`. Auto-configuration (Day 07) uses `@Import` + `@Conditional` heavily.

### 3. Component scanning control
`@ComponentScan(basePackages = "com.cent.aaa")`, filters with `includeFilters`/`excludeFilters`. `@SpringBootApplication` implies a scan of the main class's package downward — keep your main class at the **root package**.

### 4. Profiles — environment-specific beans/config
```java
@Service @Profile("prod")
class RealPaymentClient implements PaymentClient {}

@Service @Profile({"dev","test"})
class FakePaymentClient implements PaymentClient {}

@Service @Profile("!prod")          // everything except prod
class DebugToolbar {}
```
Activate via `spring.profiles.active=prod` (env var `SPRING_PROFILES_ACTIVE`, JVM `-Dspring.profiles.active`, or in config). Profile-specific files: `application-prod.yml`, `application-dev.yml` layered over `application.yml`. **cent** uses this to vary each microservice's behavior per environment.

### 5. `@Conditional` family (the engine behind auto-config)
- `@ConditionalOnProperty`, `@ConditionalOnClass`, `@ConditionalOnMissingBean`, `@ConditionalOnBean`, `@ConditionalOnExpression`, `@Profile`.
```java
@Bean
@ConditionalOnProperty(name = "feature.jamf.enabled", havingValue = "true")
JamfClient jamfClient() { ... }   // only created when the property is true
```

### 6. Property sources & precedence (high → low, abbreviated)
1. Command-line args
2. `SPRING_APPLICATION_JSON`
3. OS environment variables / Java system properties
4. `application-{profile}.yml`
5. `application.yml`
6. `@PropertySource` / defaults
Later (lower) sources are overridden by earlier (higher) ones. (Full list on Day 08.)

### 7. SpEL — Spring Expression Language
Runtime expressions in annotations/config:
```java
@Value("#{systemProperties['user.region'] ?: 'US'}") String region;
@Value("#{${app.max-retries} * 2}")                 int doubled;
@PreAuthorize("#userId == authentication.name")      // security expressions (Day 18)
@Scheduled(cron = "${cleanup.cron}")                 // ${} property, #{} SpEL
```
`${...}` = **property placeholder** (resolved from config). `#{...}` = **SpEL** (evaluated expression). Mixing them is common and a frequent point of confusion.

---

## PRACTICE

```java
// Profile-based wiring
public interface FeatureFlags { boolean newCheckout(); }

@Configuration
public class FeatureConfig {
    @Bean @Profile("prod")
    FeatureFlags prodFlags() { return () -> false; }
    @Bean @Profile("!prod")
    FeatureFlags devFlags() { return () -> true; }
}

// Conditional bean — only when enabled
@Configuration
public class IntegrationConfig {
    @Bean
    @ConditionalOnProperty(name = "integration.jamf.enabled", havingValue = "true")
    JamfClient jamfClient(@Value("${integration.jamf.base-url}") String url) {
        return new JamfClient(url);
    }
}
```
```yaml
# application.yml
spring:
  profiles:
    active: dev
integration:
  jamf:
    enabled: true
    base-url: https://jamf.example.com
cleanup:
  cron: "0 0 2 * * *"   # 2 AM daily
```
```java
// SpEL + property placeholder together
@Component
class CleanupJob {
    @Value("${cleanup.cron}") private String cron;            // ${} placeholder
    @Value("#{T(java.time.LocalDate).now().getYear()}") int year;  // #{} SpEL
}
```

**Exercises:**
1. Define two `PaymentClient` beans by profile; switch `spring.profiles.active` and confirm which loads.
2. Gate a bean behind `@ConditionalOnProperty`; toggle the property and verify creation/absence via the actuator `/beans` endpoint.
3. Use SpEL to inject a value computed from another property (e.g., a derived timeout).
4. Move your main class into a sub-package and watch a `@Service` in the parent package stop being found — then fix the scan.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. `@Configuration` vs `@Component` for holding `@Bean` methods — what's the real difference?**
A `@Configuration` class is **CGLIB-proxied** so inter-`@Bean` method calls return the **same singleton** (Spring intercepts the call and returns the managed bean). A `@Component` with `@Bean` methods is **"lite" mode** — calling one `@Bean` method from another executes it as a **plain Java method**, creating a *new* object that **isn't** a managed bean. This causes subtle duplicate-instance bugs. Use `@Configuration` for inter-dependent beans.

**Q2. What does `proxyBeanMethods = false` do and when is it appropriate?**
It disables the CGLIB proxy on a `@Configuration` class, so `@Bean` methods aren't intercepted — faster startup and less memory. Appropriate when your `@Bean` methods **don't call each other** (each is independent). Spring Boot's own auto-configuration classes use it. If a `@Bean` method calls another expecting the singleton, turning this off breaks that.

**Q3. `${...}` vs `#{...}` — what's the difference?**
`${...}` is a **property placeholder** resolved from the `Environment`/property sources (config files, env vars). `#{...}` is a **SpEL expression** evaluated at runtime (method calls, operators, bean references). You can nest a placeholder inside SpEL: `#{${app.factor} * 10}` reads property `app.factor` then computes via SpEL.

**Q4. How do profiles interact with `application.yml` files?**
`application.yml` is always loaded; `application-{profile}.yml` is loaded **and overrides** it for each active profile. Multiple profiles can be active; later-listed profiles win on conflicts. You can also use multi-document YAML with `spring.config.activate.on-profile`. Active profiles come from `spring.profiles.active` (config, env var `SPRING_PROFILES_ACTIVE`, CLI, or programmatically).

**Q5. A `@Service` isn't being picked up — give the top reasons.**
(1) It's **outside the component-scan path** (not under the main class's package). (2) Missing stereotype annotation. (3) Excluded by a `@ComponentScan` filter. (4) Conditional/profile not matched. (5) Two beans of the same type causing the context to fail before reaching it. Check `/actuator/beans` and startup logs.

**Q6. Order of property source precedence — name the top three.**
Command-line arguments (highest), then `SPRING_APPLICATION_JSON`, then OS environment variables / Java system properties — all of which override `application-{profile}.yml`, which overrides `application.yml`. This is why you can override any config at deploy time with an env var without rebuilding — central to 12-factor and how cent injects per-environment config.

**Q7. How does `@ConditionalOnMissingBean` enable "sensible defaults that users can override"?**
Auto-configuration declares a bean with `@ConditionalOnMissingBean`, meaning "create this **only if the user hasn't defined their own**." So Spring Boot provides a default `ObjectMapper`, `DataSource`, etc., but the moment you declare your own, the auto-config backs off. It's the core mechanism that makes Boot opinionated yet overridable.

➡ Next: [Day 05 — AOP & Proxies](day-05-aop-proxies.md)
