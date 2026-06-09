# Day 24 — Reactive Programming & WebFlux

## THEORY

### 1. The problem reactive solves
Traditional Spring MVC is **thread-per-request, blocking**: each request occupies a thread until it finishes. Under high concurrency with slow I/O, threads sit **blocked on I/O**, and you run out of threads (each thread also costs ~1MB stack). **Reactive (WebFlux)** is **non-blocking, event-loop** based: a few threads handle thousands of concurrent connections by never blocking — when waiting on I/O, the thread is freed to do other work.

### 2. Reactive Streams & Project Reactor
- **Reactive Streams** is a spec: `Publisher`, `Subscriber`, `Subscription`, with **backpressure** (the subscriber controls how much it receives, so a fast producer can't overwhelm a slow consumer).
- **Project Reactor** (Spring's implementation) provides:
  - **`Mono<T>`** — 0 or 1 element (async single value, like a future).
  - **`Flux<T>`** — 0..N elements (async stream).
```java
Mono<ServerDto> findById(String id);
Flux<ServerDto> findAll();
```

### 3. Nothing happens until you subscribe (lazy)
A `Mono`/`Flux` is a **blueprint** of operations; it doesn't execute until something **subscribes**. In WebFlux, the framework subscribes for you when it writes the HTTP response. Forgetting this ("I called the method but nothing ran") is the #1 reactive bug.
```java
// WRONG: result discarded, never subscribed → no-op
service.revoke(id);
// RIGHT: return it (framework subscribes) or chain it
return service.revoke(id).then(Mono.just("ok"));
```

### 4. Operators (declarative pipelines)
`map` (sync transform), `flatMap` (async transform → returns a publisher, flattened), `filter`, `zip`, `merge`, `concat`, `switchIfEmpty`, `onErrorResume` (fallback), `retryWhen`, `timeout`, `defaultIfEmpty`. **`map` vs `flatMap`** is the classic: `map` for a plain transformation, `flatMap` when the transform itself is async (returns a `Mono`/`Flux`).

### 5. WebFlux controllers
```java
@RestController
@RequestMapping("/api/servers")
class ReactiveServerController {
    private final ReactiveServerService service;
    ReactiveServerController(ReactiveServerService service) { this.service = service; }

    @GetMapping("/{id}")
    public Mono<ServerDto> get(@PathVariable String id) {
        return service.find(id).switchIfEmpty(Mono.error(new ResourceNotFoundException(id)));
    }
    @GetMapping(produces = MediaType.TEXT_EVENT_STREAM_VALUE)   // streaming (SSE)
    public Flux<ServerDto> stream() { return service.streamAll(); }
}
```
Use **`WebClient`** (non-blocking) for outbound calls; **R2DBC** for non-blocking DB access. **One blocking call (JDBC, `Thread.sleep`, blocking I/O) in a reactive pipeline blocks an event-loop thread and can stall the whole app** — never block the event loop.

### 6. When to use reactive (and when NOT)
**Use it when:** very high concurrency with I/O-bound work, streaming data, an API gateway/proxy, talking to other reactive/non-blocking systems, or you need backpressure.
**Avoid it when:** the workload is CPU-bound, you depend on blocking libraries (JDBC, many SDKs) that negate the benefit, or the team/codebase isn't ready — reactive code is **harder to write, read, and debug** (stack traces are opaque, mental model is different).
**Big modern caveat:** **Java 21 virtual threads** (Day 16) give much of the scalability of reactive **with simple blocking-style code** — for many I/O-bound services, virtual threads are now the simpler choice, and reactive's niche has narrowed to streaming/backpressure-heavy scenarios.

### 7. Context & debugging
- `SecurityContextHolder` (thread-local) **doesn't work** in reactive; use **`ReactiveSecurityContextHolder`**. Same for MDC — propagation needs the Reactor context.
- Use **`.log()`**, `checkpoint()`, and `BlockHound` (detects accidental blocking) to debug.
- Test with **`WebTestClient`** and `StepVerifier`.

---

## PRACTICE

```java
// Composing async calls: fetch server + its policies in parallel, combine
@Service
class ServerAggregator {
    private final WebClient policyClient;
    private final ReactiveServerRepo repo;
    ServerAggregator(WebClient.Builder b, ReactiveServerRepo repo) {
        this.policyClient = b.baseUrl("http://policy-engine-service").build();
        this.repo = repo;
    }
    public Mono<ServerView> view(String id) {
        Mono<ServerDto> server = repo.findById(id);
        Mono<List<Policy>> policies = policyClient.get().uri("/policies?server={id}", id)
                .retrieve().bodyToFlux(Policy.class).collectList();
        return Mono.zip(server, policies)               // run both, combine when both complete
                   .map(t -> new ServerView(t.getT1(), t.getT2()))
                   .timeout(Duration.ofSeconds(3))
                   .onErrorResume(e -> Mono.just(ServerView.degraded(id)));   // fallback
    }
}

// map vs flatMap
Mono<String> name = repo.findById(id).map(ServerDto::name);              // sync transform
Mono<Policy> policy = repo.findById(id).flatMap(s -> policyClient.fetch(s.policyId())); // async
```
```java
// StepVerifier test
@Test void emitsServer() {
    StepVerifier.create(service.find("1"))
        .expectNextMatches(s -> s.id().equals("1"))
        .verifyComplete();
}
```

**Exercises:**
1. Build a WebFlux endpoint returning `Mono`/`Flux`; verify nothing runs until subscription (log inside the pipeline).
2. Use `flatMap` to chain an async call; contrast with `map` and explain the difference in output type.
3. Combine two `WebClient` calls with `zip` and add a `timeout` + `onErrorResume` fallback.
4. Intentionally put a blocking call in a pipeline; use BlockHound to detect it.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. `Mono` vs `Flux` — and why "nothing happens until subscribe"?**
`Mono<T>` emits **0 or 1** element; `Flux<T>` emits **0..N**. Both are **lazy publishers**: they describe a pipeline but execute **only when subscribed**. Until a subscriber requests data, no work runs. In WebFlux the framework subscribes when writing the response, so returning the publisher is enough — but calling a reactive method and **ignoring the result** means it **never executes** (a top reactive bug). You must return it or chain it into a subscribed pipeline.

**Q2. `map` vs `flatMap` in Reactor?**
`map` applies a **synchronous** function `T -> R`, transforming each element. `flatMap` applies a function `T -> Publisher<R>` (an **asynchronous** operation returning a `Mono`/`Flux`) and **flattens** the resulting publishers into the stream. Use `map` for plain transforms (extract a field), `flatMap` when the transformation itself is async (call another service, query a DB). Using `map` where you need `flatMap` yields a `Mono<Mono<R>>` — a telltale sign.

**Q3. What is backpressure and why does it matter?**
Backpressure is the **subscriber controlling the rate** at which it receives elements (via `request(n)`), so a **fast producer can't overwhelm a slow consumer** (avoiding unbounded buffering/OOM). It's a first-class part of Reactive Streams. Strategies when overwhelmed: buffer, drop, latest, or error. It's the key advantage for **streaming** scenarios; in plain request/response it's less visible.

**Q4. What happens if you make a blocking call inside a reactive pipeline?**
You **block an event-loop thread**. WebFlux runs on a **small number** of non-blocking threads; blocking one (JDBC, `Thread.sleep`, blocking HTTP) removes it from serving other requests, and if you block them all, the **whole application stalls**. If you must call a blocking API, offload it to a **bounded scheduler** (`subscribeOn(Schedulers.boundedElastic())`). Tools like **BlockHound** detect accidental blocking. This is why mixing JDBC into WebFlux defeats the purpose — use **R2DBC** instead.

**Q5. When should you NOT use reactive?**
When the workload is **CPU-bound** (event loop gives no benefit), when you depend on **blocking libraries** (JDBC, many SDKs) that you'd have to wrap anyway, when the team isn't fluent (reactive is **harder to read/debug**, with opaque stack traces), or for **simple CRUD apps** where the added complexity buys nothing. And critically: with **Java 21 virtual threads**, you can get reactive-like scalability for I/O-bound work using **ordinary blocking code**, so reactive's main justification (thread efficiency) has shrunk to **streaming/backpressure** use cases.

**Q6. WebFlux vs MVC + virtual threads — which for a high-concurrency I/O service today?**
**Virtual threads (MVC, Boot 3.2+)** are often the better choice: you keep **simple, blocking, easy-to-debug** code while the JVM schedules millions of cheap virtual threads, handling high I/O concurrency without thread-pool exhaustion. **WebFlux** still wins when you genuinely need **backpressure, streaming (SSE/server-push), or end-to-end non-blocking** integration with reactive datastores/clients. For typical "call DB + a few services" endpoints, virtual threads give most of the scalability with far less complexity.

**Q7. How does the SecurityContext (or MDC) work in reactive code?**
The thread-local `SecurityContextHolder`/MDC **don't work** because a request hops across event-loop threads. Reactive uses the **Reactor `Context`** carried through the pipeline: `ReactiveSecurityContextHolder.getContext()` retrieves the authenticated principal, and MDC/tracing must be propagated via context-propagation libraries. Assuming thread-locals work is a common reactive mistake leading to "null principal" or missing trace ids.

**Q8. How do you test reactive code?**
Use **`StepVerifier`** to assert the sequence of emitted elements, errors, and completion (`expectNext`, `expectError`, `verifyComplete`), with **virtual time** for time-based operators (no real waiting). For endpoints, **`WebTestClient`** drives WebFlux controllers non-blockingly. Avoid `.block()` in tests except at the very edge; prefer `StepVerifier` so you actually exercise the asynchronous behavior.

➡ Next: [Day 25 — Spring AI Fundamentals](day-25-spring-ai-fundamentals.md)
