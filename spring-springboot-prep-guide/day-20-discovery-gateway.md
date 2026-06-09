# Day 20 — Service Discovery, API Gateway & Load Balancing

## THEORY

### 1. Why service discovery?
In a dynamic fleet, service instances come and go (autoscaling, restarts, failures) with changing IPs. Hard-coding hostnames is impossible. **Service discovery** lets a service find healthy instances of another **by logical name**.
- **Client-side discovery:** the caller queries a **registry** (Eureka/Consul) for instances and load-balances itself (Spring Cloud LoadBalancer).
- **Server-side discovery:** a load balancer/router (Kubernetes Service, AWS ELB) resolves the name; the client just calls a stable virtual address. **In Kubernetes, the platform does discovery via DNS + Services** — you often don't need Eureka at all.

### 2. Eureka (Netflix) — the classic Spring registry
- **Eureka Server** — the registry.
- **Eureka Client** — each service registers itself (`spring.application.name`) and fetches the registry.
- Clients cache the registry and **heartbeat**; instances that stop heartbeating are evicted.
- Eureka favors **availability** (AP) — it serves possibly-stale data during partitions rather than refusing (self-preservation mode), which suits discovery.

### 3. Client-side load balancing
**Spring Cloud LoadBalancer** (replaced Netflix Ribbon) picks an instance from the discovered list (round-robin by default). Used transparently by `@LoadBalanced RestClient/WebClient`/Feign when you call `http://service-name/...` instead of an IP.
```java
@Bean @LoadBalanced
RestClient.Builder loadBalancedRestClient() { return RestClient.builder(); }
// then: client.get().uri("http://aaa-server-management-service/api/v1/servers")...
```

### 4. API Gateway (Spring Cloud Gateway)
A single entry point in front of all services. Responsibilities:
- **Routing** — map external paths to internal services.
- **Cross-cutting concerns** — authentication, rate limiting, CORS, request/response transformation, logging, metrics — done once at the edge instead of in every service.
- **Decoupling** — clients see one URL; internal topology can change freely.
cent has an **`api-gateway-service`** doing exactly this.
```yaml
spring:
  cloud:
    gateway:
      routes:
        - id: aaa-servers
          uri: lb://aaa-server-management-service       # lb:// = load-balanced via discovery
          predicates:
            - Path=/api/v1/servers/**
          filters:
            - StripPrefix=2
            - name: RequestRateLimiter
              args:
                redis-rate-limiter.replenishRate: 100
                redis-rate-limiter.burstCapacity: 200
```
Gateway is built on **WebFlux (reactive, non-blocking)** — good, since it's an I/O-bound proxy handling many concurrent connections.

### 5. Gateway vs Load Balancer vs Service Mesh
- **Gateway (L7):** application-aware edge — routing by path/header, auth, rate limiting. North-south traffic (client→system).
- **Load balancer (L4/L7):** distributes connections across instances.
- **Service mesh (Istio/Linkerd):** sidecar proxies handle **east-west** (service↔service) concerns — mTLS, retries, traffic shifting — **out of the application code**. Complements or replaces in-app resilience libraries.

### 6. Gateway patterns
- **BFF (Backend for Frontend):** a gateway tailored per client type (web vs mobile).
- **Aggregation:** the gateway (or a dedicated service) composes responses from several services.
- **Edge authentication:** validate the token once at the gateway, relay it downstream (services still re-validate — Day 18).

### 7. Health-aware routing
Discovery + gateway route only to **healthy** instances (using actuator readiness, Day 9). A failing instance is removed from rotation; a starting one isn't routed to until ready.

---

## PRACTICE

```java
// Eureka client service
@SpringBootApplication
@EnableDiscoveryClient            // registers with the registry
public class ServerManagementApp { ... }
```
```yaml
# eureka client config
eureka:
  client:
    service-url:
      defaultZone: http://eureka:8761/eureka
  instance:
    prefer-ip-address: true
spring:
  application:
    name: aaa-server-management-service   # the logical name others discover
```
```java
// Calling another service by NAME (load-balanced, no hardcoded host)
@Service
class PolicyClient {
    private final RestClient client;
    PolicyClient(@LoadBalanced RestClient.Builder builder) {
        this.client = builder.baseUrl("http://policy-engine-service").build();
    }
    public Policy fetch(String id) {
        return client.get().uri("/policies/{id}", id).retrieve().body(Policy.class);
    }
}
```

**Exercises:**
1. Run a Eureka server + two instances of a service; watch both register and observe client-side round-robin.
2. Configure a Spring Cloud Gateway route with `Path` predicate + `StripPrefix`; call through the gateway to a backend.
3. Add a `RequestRateLimiter` filter and trigger a 429.
4. Explain how the same setup would look in Kubernetes (DNS-based discovery, Ingress instead of/with the gateway).

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Client-side vs server-side service discovery — trade-offs?**
**Client-side** (Eureka + Spring Cloud LoadBalancer): the client fetches the instance list and load-balances itself — fewer network hops, smart balancing, but every client needs the discovery logic and a registry. **Server-side** (Kubernetes Service, ELB): a router/proxy resolves the name; clients call a stable address and stay dumb — simpler clients, but an extra hop and the LB is infrastructure. In Kubernetes, server-side (DNS) discovery usually makes Eureka redundant.

**Q2. Do you need Eureka if you deploy on Kubernetes?**
Usually **no**. Kubernetes provides discovery natively via **Services + cluster DNS** (`http://service-name.namespace`), plus health-based endpoint management. Running Eureka on top adds a redundant registry to maintain. You'd keep Eureka mainly for non-K8s environments, hybrid setups, or when you need Spring-level discovery features the platform doesn't give you.

**Q3. What does an API Gateway do that you wouldn't put in each service?**
Cross-cutting **edge** concerns: a single entry point with **routing**, **authentication/authorization at the edge**, **rate limiting**, **CORS**, request/response transformation, and centralized logging/metrics — handled **once** instead of duplicated in every service. It also **decouples clients from internal topology** (one stable URL; services can move/rename). It is *not* a place for business logic.

**Q4. Why is Spring Cloud Gateway built on reactive WebFlux?**
A gateway is a **proxy** — overwhelmingly I/O-bound, holding many concurrent client and upstream connections, mostly waiting on network. A **non-blocking, event-loop** model (WebFlux/Netty) handles tens of thousands of concurrent connections with few threads, avoiding the thread-per-request exhaustion a blocking model would hit at the edge. (Zuul 1 was blocking; Gateway replaced it for this reason.)

**Q5. Gateway vs service mesh — do you need both?**
A **gateway** handles **north-south** traffic (external clients → system): routing, edge auth, rate limiting. A **service mesh** (Istio/Linkerd via sidecars) handles **east-west** traffic (service ↔ service): mTLS, retries, timeouts, traffic shifting, observability — **without app code**. They're complementary: gateway at the edge, mesh between internal services. A mesh can also reduce the need for in-app resilience libraries (Day 21) by enforcing those policies at the proxy.

**Q6. How does the system avoid routing requests to a dead or still-starting instance?**
Discovery and the gateway use **health/readiness** signals (actuator readiness probe, Day 9). Unhealthy instances stop heartbeating (Eureka) or fail readiness (K8s) and are **removed from the routable set**; starting instances aren't added until readiness passes. So traffic only reaches instances that report they can serve it — which is why correct liveness/readiness design matters.

**Q7. A service registers with Eureka but callers still get failures for a while after it dies. Why?**
Eureka is an **AP** system optimized for availability — clients **cache** the registry and the server evicts instances only after **missed heartbeats** (plus client refresh intervals and self-preservation mode), so there's a propagation delay where a dead instance is still listed. That's why you **also** need client-side resilience (timeouts, retries to other instances, circuit breakers — Day 21); discovery alone doesn't give instant failure detection.

**Q8. How should authentication be split between the gateway and downstream services?**
Authenticate/validate the token **at the gateway** (reject bad requests early, do rate limiting), then **relay the token** downstream where each service **re-validates and authorizes** for its own resources (defense in depth — never trust that the edge already checked). The gateway handles coarse access and edge concerns; fine-grained, resource-level authorization stays in the owning service (cent's model).

➡ Next: [Day 21 — Resilience4j & OpenFeign](day-21-resilience-feign.md)
