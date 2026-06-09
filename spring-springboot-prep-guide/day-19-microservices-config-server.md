# Day 19 — Microservices Principles & Spring Cloud Config

## THEORY

### 1. Monolith vs microservices
- **Monolith:** one deployable, one codebase, one DB. Simple to build/test/deploy early; hard to scale teams, mixed scaling needs, one bug can take down everything, big-bang deploys.
- **Microservices:** many small services, each owning its data, deployed independently. Independent scaling/deploy/tech choices, fault isolation — at the cost of **distributed-system complexity**: network failures, eventual consistency, distributed tracing, more ops.
**Don't start with microservices.** Split when team/scale/domain boundaries justify it. cent is a mature microservices platform (auth, AAA, certificate management, gateway, etc.), each a Spring Boot app.

### 2. Core microservice principles
- **Single responsibility / bounded context** (DDD) — a service owns one business capability.
- **Database per service** — no sharing DBs across services (else you re-couple them). Cross-service data via APIs/events.
- **Independent deployability** — versioned APIs, backward compatibility.
- **Decentralized governance** — teams own their services.
- **Design for failure** — assume the network and dependencies fail (Day 21).

### 3. The Spring Cloud landscape
| Concern | Spring Cloud component |
|---------|------------------------|
| Centralized config | **Spring Cloud Config** (cent's config-server) |
| Service discovery | Eureka / Consul / Kubernetes DNS |
| API Gateway | Spring Cloud Gateway |
| Client load balancing | Spring Cloud LoadBalancer |
| Resilience | Resilience4j |
| Declarative REST clients | OpenFeign |
| Distributed tracing | Micrometer Tracing |
| Messaging abstraction | Spring Cloud Stream |

### 4. Centralized configuration (the cent pattern)
Dozens of services each need config; managing per-service files across environments is painful. **Spring Cloud Config Server** serves configuration from a backend (Git, file system, Vault). Each service is a **config client** that fetches its config at startup.
- cent's layout: `infrastructure/spring-cloud/configuration-server/config/<service>.yml` — one file per service (`aaa-server-management-service.yml`, `api-gateway-service.yml`, etc.). The config server exposes these; each microservice pulls its own.
- Benefits: **single source of truth**, environment-specific profiles, **change config without rebuilding/redeploying** services, audit history (if Git-backed).

### 5. Config client setup (modern, no bootstrap.yml)
```yaml
# application.yml in each service
spring:
  application:
    name: aaa-server-management-service       # selects {name}.yml on the server
  config:
    import: "optional:configserver:http://config-server:8888"
  profiles:
    active: prod
```
The server resolves `{application}-{profile}.yml` + `{application}.yml` + `application.yml` (global defaults) and merges them, applying the precedence rules from Day 08.

### 6. Refreshing config at runtime
`@RefreshScope` beans re-read config when you `POST /actuator/refresh` (or broadcast via **Spring Cloud Bus** over RabbitMQ/Kafka to refresh the whole fleet at once). So you change a value in Git → push → bus event → all instances pick it up **without restart**. (cent uses AMQP, so a bus-style refresh fits naturally.)

### 7. Config precedence & secrets
Server-provided properties slot into the property-source order (Day 08); local overrides and env vars still win where appropriate. Secrets should come from a **secure backend** (Vault) or injected env, not committed YAML.

---

## PRACTICE

```yaml
# ---- Config Server application.yml ----
server.port: 8888
spring:
  cloud:
    config:
      server:
        git:
          uri: https://git.cent.example.com/platform/config-repo
          default-label: main
        # or native file backend for local:
        # native.search-locations: file:./config
management.endpoints.web.exposure.include: health,refresh,busrefresh
```
```java
@SpringBootApplication
@EnableConfigServer          // turns this app into a Spring Cloud Config Server
public class ConfigServerApplication {
    public static void main(String[] a) { SpringApplication.run(ConfigServerApplication.class, a); }
}
```
```java
// ---- A config CLIENT service that refreshes at runtime ----
@RestController
@RefreshScope                // re-binds @Value on /actuator/refresh
class FeatureController {
    @Value("${cent.feature.new-checkout:false}")
    private boolean newCheckout;

    @GetMapping("/feature")
    public boolean feature() { return newCheckout; }
}
```
```bash
# Inspect what the server resolves for a service+profile:
curl http://config-server:8888/aaa-server-management-service/prod | jq
# Refresh a running client without restart:
curl -X POST http://service:8080/actuator/refresh
```

**Exercises:**
1. Run a local Config Server (native/file backend) serving two service files; fetch each via the server's REST API.
2. Make a client read a value via `@Value` + `@RefreshScope`; change the source, hit `/actuator/refresh`, and see the new value without restart.
3. Explain how `{application}-{profile}.yml`, `{application}.yml`, and global `application.yml` merge.
4. Map cent's `infrastructure/spring-cloud/configuration-server/config/*.yml` files to the config-server model.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. When should you NOT use microservices?**
Early-stage products, small teams, or unclear domain boundaries. Microservices add **distributed-system tax**: network latency/failures, eventual consistency, distributed tracing, more deployment/ops complexity, and harder local testing. A **modular monolith** is usually the right start; extract services once you have clear bounded contexts and genuine independent scaling/deploy needs. "Microservices are a solution to an organizational/scaling problem, not a default architecture."

**Q2. Why "database per service" — what breaks if services share a DB?**
A shared database **re-couples** services: a schema change by one team breaks others, you can't deploy/scale independently, and the DB becomes a single point of contention/failure. Database-per-service preserves **autonomy and encapsulation** — each service owns its schema and exposes data only via its API/events. The cost is **distributed data** (no cross-service joins/transactions; you use API composition, events, and patterns like Saga for consistency).

**Q3. What problem does a Config Server solve over per-service `application.yml`?**
With dozens of services across multiple environments, embedding config in each artifact means **rebuilding/redeploying to change a value** and config drift. A Config Server centralizes configuration (often Git-backed for **versioning/audit/rollback**), serves environment-specific profiles, and lets services **change config at runtime** (with `@RefreshScope`) — a single source of truth. cent does exactly this with one YAML per service on the config server.

**Q4. How does a config change reach a running service without a restart?**
Mark config-dependent beans `@RefreshScope`; then a `POST /actuator/refresh` re-creates those beans with the new values. To refresh the **whole fleet** at once, use **Spring Cloud Bus** (over RabbitMQ/Kafka): one `/actuator/busrefresh` broadcasts a refresh event to every instance. So: edit config (Git) → push → trigger bus → all replicas re-bind. No restart, no redeploy.

**Q5. If the Config Server is down, can services start?**
With `spring.config.import: "optional:configserver:..."` (note **`optional:`**), a service can **start with local/cached defaults** even if the server is unreachable (graceful degradation). Without `optional:`, startup **fails fast** if it can't reach the server. You also typically run the Config Server **highly available** (multiple instances) and may cache last-known config. Design choice: fail-fast (guarantee correct config) vs resilient-start (availability).

**Q6. How is configuration precedence handled when both the server and local files define a value?**
Config-server properties are inserted into the standard Spring property-source order (Day 08). Higher-precedence sources — **command-line args, environment variables, system properties** — still override server-provided values, while server values override the local `application.yml` defaults (depending on import ordering). This lets you keep shared config centralized yet still override per-instance via env vars at deploy time.

**Q7. What are the failure modes you must design for in microservices that don't exist in a monolith?**
**Partial failure** (one service down/slow while others are up), **network latency/timeouts/partitions**, **cascading failures** (a slow dependency exhausting upstream threads), **eventual consistency** (no global transaction), **retries causing duplicates** (idempotency), and **distributed debugging** (need tracing/correlation ids). These drive the patterns on Days 20–22: discovery, gateways, circuit breakers, bulkheads, and async messaging.

➡ Next: [Day 20 — Service Discovery & API Gateway](day-20-discovery-gateway.md)
