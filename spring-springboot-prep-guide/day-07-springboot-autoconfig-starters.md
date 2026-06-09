# Day 07 — Spring Boot: Auto-Configuration, Starters & Bootstrapping

## THEORY

### 1. What Spring Boot adds over Spring
Spring Framework gives you the container + modules but you wire everything (web server, JSON, data source) yourself. **Spring Boot** adds:
- **Auto-configuration** — sensible beans configured automatically based on the classpath.
- **Starters** — curated dependency bundles.
- **Embedded server** — Tomcat/Jetty/Undertow inside the jar (no external app server).
- **Externalized configuration** + **Actuator** for production-readiness.
- **Opinionated defaults** you can override.
Goal: "just run" with minimal boilerplate.

### 2. `@SpringBootApplication` = three annotations
```java
@SpringBootApplication
// = @Configuration  (this class can define beans)
//  + @EnableAutoConfiguration  (turn on auto-config)
//  + @ComponentScan  (scan this package downward)
```
Keep it in the **root package** so the scan covers everything.

### 3. How auto-configuration actually works
1. `@EnableAutoConfiguration` imports `AutoConfigurationImportSelector`.
2. It reads **`META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`** (Boot 2.7+; previously `spring.factories`) from every jar — a list of auto-config classes.
3. Each auto-config class is gated by **`@Conditional`** annotations: `@ConditionalOnClass`, `@ConditionalOnMissingBean`, `@ConditionalOnProperty`, etc.
4. So "Tomcat on classpath + no `WebServerFactory` defined" → Boot configures an embedded Tomcat. "`spring-boot-starter-data-jpa` present + a `DataSource`" → it configures Hibernate, an `EntityManagerFactory`, a `TransactionManager`.
**The magic is just conditional beans driven by what's on the classpath and what you haven't already defined.**

### 4. Starters
A **starter** is a POM with no code — just a transitive dependency set, version-aligned by the **Boot dependency management (BOM)**. Examples: `spring-boot-starter-web` (MVC + Tomcat + Jackson), `-data-jpa`, `-security`, `-actuator`, `-validation`, `-amqp`. cent's BOM (`bom/pom.xml`) plays the same role: one place to align versions across all microservices.

### 5. Overriding auto-configuration
- **Define your own bean** — `@ConditionalOnMissingBean` makes Boot back off.
- **Set properties** — many auto-configs read `application.yml`.
- **Exclude** — `@SpringBootApplication(exclude = DataSourceAutoConfiguration.class)` or `spring.autoconfigure.exclude`.

### 6. Debugging auto-config
- Run with `--debug` (or `debug=true`) → prints the **Condition Evaluation Report**: which auto-configs **matched** (Positive matches) and which **didn't** (Negative matches) and *why*.
- Actuator `/actuator/conditions` shows the same at runtime.
This is the #1 tool when "Boot didn't configure the thing I expected."

### 7. Writing your own auto-configuration (library author / interview bonus)
```java
@AutoConfiguration
@ConditionalOnClass(JamfClient.class)
@EnableConfigurationProperties(JamfProperties.class)
public class JamfAutoConfiguration {
    @Bean
    @ConditionalOnMissingBean
    @ConditionalOnProperty(prefix = "cent.jamf", name = "enabled", havingValue = "true")
    JamfClient jamfClient(JamfProperties props) { return new JamfClient(props.baseUrl()); }
}
```
Register it in `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`. This is how an internal "cent-jamf-starter" would auto-wire itself into any service that includes it.

---

## PRACTICE

```bash
# See the condition evaluation report — what got auto-configured and why
./mvnw spring-boot:run -Dspring-boot.run.arguments=--debug
# or add to application.yml:  debug: true
```
```java
// Prove auto-config backs off when you define your own bean
@Configuration
class JsonConfig {
    @Bean
    ObjectMapper objectMapper() {                       // Boot's default ObjectMapper now backs off
        return JsonMapper.builder()
                .addModule(new JavaTimeModule())
                .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
                .build();
    }
}
```
```java
// Exclude an auto-config you don't want (e.g., no DataSource in a pure web service)
@SpringBootApplication(exclude = { DataSourceAutoConfiguration.class })
public class GatewayApplication { ... }
```

**Exercises:**
1. Run with `--debug` and find why `DataSourceAutoConfiguration` did or didn't match.
2. Define your own `ObjectMapper`; confirm via `/actuator/beans` that Boot's default is gone.
3. Add `spring-boot-starter-data-jpa` without a DB configured and read the failure — then exclude the auto-config to start cleanly.
4. Sketch a `cent-jamf-starter` auto-configuration with the right conditionals.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Explain how `@EnableAutoConfiguration` finds and applies configurations.**
It imports `AutoConfigurationImportSelector`, which loads the list of auto-configuration class names from each jar's `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` (formerly `spring.factories`). Each listed class is annotated with `@Conditional` guards; Spring evaluates those conditions against the current classpath, existing beans, and properties, and applies only the configs whose conditions pass. It's classpath-driven conditional bean registration.

**Q2. What is a "starter" and does it contain code?**
A starter is a **dependency aggregator POM** — it contains **no code**, just a curated, version-aligned set of transitive dependencies for a capability (web, JPA, security). Including `spring-boot-starter-web` pulls MVC, an embedded Tomcat, Jackson, etc., all at compatible versions managed by Boot's BOM. It saves you from hand-picking and version-matching dozens of libraries.

**Q3. How does Spring Boot avoid overriding beans you defined yourself?**
Auto-configuration beans are guarded by **`@ConditionalOnMissingBean`** — they're created only if you haven't already defined a bean of that type. The moment you declare your own `ObjectMapper`/`DataSource`/etc., the matching auto-config backs off. This "user wins" rule is what makes Boot opinionated yet fully overridable.

**Q4. `@SpringBootApplication` decomposes into what, and why does package placement matter?**
`@Configuration` + `@EnableAutoConfiguration` + `@ComponentScan`. Because `@ComponentScan` defaults to scanning the **annotated class's package and sub-packages**, the main class must sit in the **root package**; otherwise components in sibling/parent packages won't be discovered ("no qualifying bean" surprises).

**Q5. Embedded server vs traditional WAR deployment — trade-offs?**
Embedded (default): the server (Tomcat) is a dependency inside the fat jar → `java -jar` runs everything, consistent across environments, ideal for containers/microservices (cent's model). Traditional WAR: you build a WAR and deploy to an external app server → useful for legacy/shared-container mandates. Boot supports both (extend `SpringBootServletInitializer` for WAR), but embedded is the modern default.

**Q6. How do you debug "Spring Boot didn't configure X"?**
Run with `--debug` (or `/actuator/conditions`) to get the **Condition Evaluation Report**, which lists Positive matches (configs applied) and Negative matches with the **exact failing condition** (e.g., "did not find class org.X" or "found bean Y"). That tells you whether a dependency is missing, a property is unset, or your own bean caused a back-off.

**Q7. Can you have multiple auto-configurations and control their order?**
Yes. Order with `@AutoConfiguration(before=..., after=...)` (or legacy `@AutoConfigureBefore/@AutoConfigureAfter/@AutoConfigureOrder`). Ordering matters when one auto-config's beans depend on another's (e.g., a custom config that must run after `DataSourceAutoConfiguration` so a `DataSource` exists). Conditions are re-evaluated as beans get registered, so ordering affects `@ConditionalOnBean` outcomes.

➡ Next: [Day 08 — Externalized Configuration & Properties](day-08-config-properties-profiles.md)
