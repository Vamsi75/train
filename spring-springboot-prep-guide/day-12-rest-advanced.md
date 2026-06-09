# Day 12 — REST Advanced: ResponseEntity, Versioning, Clients

## THEORY

### 1. `ResponseEntity<T>` — full control of the response
```java
@GetMapping("/{id}")
public ResponseEntity<ServerDto> get(@PathVariable String id) {
    return service.find(id)
        .map(dto -> ResponseEntity.ok()
                       .eTag(dto.version())
                       .body(dto))
        .orElse(ResponseEntity.notFound().build());   // 404 with no body
}

@PostMapping
public ResponseEntity<ServerDto> create(@Valid @RequestBody CreateServerRequest req) {
    ServerDto created = service.create(req);
    URI location = URI.create("/api/v1/servers/" + created.id());
    return ResponseEntity.created(location).body(created);   // 201 + Location header
}
```
Use when status/headers vary at runtime; use `@ResponseStatus` for constant outcomes.

### 2. HTTP semantics REST must respect
- **Idempotency:** GET/PUT/DELETE are idempotent (same effect if repeated); POST is **not**. PATCH is generally not idempotent. This matters for retries (Day 21) — safely retry idempotent calls, not POST.
- **Status codes:** 200 OK, 201 Created (+`Location`), 204 No Content, 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 409 Conflict, 422 Unprocessable Entity, 429 Too Many Requests, 500/502/503.
- **Safe vs unsafe:** GET/HEAD must not change state.

### 3. API versioning strategies
| Strategy | Example | Notes |
|----------|---------|-------|
| URI path | `/api/v1/servers` | Most common/visible (cent uses `-v2` service variants). |
| Header | `X-API-Version: 2` | Clean URLs, harder to test/cache. |
| Content-type | `Accept: application/vnd.cent.v2+json` | "Media type versioning"; purest REST, most complex. |
| Query param | `/servers?version=2` | Simple but pollutes params. |
Pick one and be consistent; never break a published version.

### 4. Pagination & filtering
Return `Page<T>` (Spring Data) or a custom envelope `{content, page, size, totalElements, totalPages}`. Accept `?page=&size=&sort=field,desc`. Avoid returning unbounded lists.

### 5. DTOs vs entities (don't leak your DB model)
Expose **DTOs/records**, not JPA entities. Reasons: avoid lazy-loading serialization errors, prevent over-exposure of internal fields, decouple API contract from schema, and avoid accidental mass-assignment. Map with MapStruct or a `toApiObject()` method — cent's proxies expose a `toApiObject()` that converts internal objects to API objects, the same pattern.

### 6. HTTP clients in Spring (know the evolution)
- **`RestTemplate`** — classic, synchronous, **maintenance mode** (still supported, not deprecated for removal). Legacy code (and likely older cent services) uses it.
- **`RestClient`** (Spring 6.1+) — modern **synchronous** fluent client; the recommended replacement for `RestTemplate`.
- **`WebClient`** — reactive, non-blocking (Day 24); can also be used synchronously via `.block()`.
- **HTTP Interface** (`@HttpExchange`) — declarative client interfaces (like Feign), backed by `RestClient`/`WebClient`.
```java
RestClient client = RestClient.create("https://jamf.example.com");
JamfToken token = client.post().uri("/api/oauth/token")
    .body(form).retrieve().body(JamfToken.class);
```

### 7. Jackson essentials
`@JsonProperty`, `@JsonIgnore` (cent's `JamfOAuthIdentityProvider` uses `@JsonIgnore` to keep `clientSecret` out of JSON), `@JsonInclude(NON_NULL)`, `@JsonFormat` for dates, `@JsonCreator`. Configure a single global `ObjectMapper` (Java time module, no timestamps for dates) rather than per-class hacks.

---

## PRACTICE

```java
@RestController
@RequestMapping("/api/v1/servers")
public class ServerControllerV1 {
    private final ServerService service;
    ServerControllerV1(ServerService service) { this.service = service; }

    @GetMapping
    public ResponseEntity<Page<ServerDto>> list(
            @RequestParam(required = false) String orgId,
            @PageableDefault(size = 20, sort = "name") Pageable pageable) {
        return ResponseEntity.ok(service.list(orgId, pageable));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ServerDto> get(@PathVariable String id) {
        return service.find(id)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PostMapping
    public ResponseEntity<ServerDto> create(@Valid @RequestBody CreateServerRequest req) {
        ServerDto dto = service.create(req);
        return ResponseEntity.created(URI.create("/api/v1/servers/" + dto.id())).body(dto);
    }
}

// DTO as a record — never expose the JPA entity
public record ServerDto(String id, String name, String organizationId, ServerStatus status) {}

// Modern declarative HTTP client (HTTP interface)
@HttpExchange("/api")
interface JamfApi {
    @PostExchange("/oauth/token")
    JamfToken token(@RequestBody TokenRequest req);
}
```

**Exercises:**
1. Return `201 Created` with a `Location` header on POST; verify with `curl -i`.
2. Add pagination with `Pageable` and return a `Page<T>`; test `?page=1&size=5&sort=name,desc`.
3. Replace a `RestTemplate` call with `RestClient`; then make a declarative `@HttpExchange` interface.
4. Use `@JsonIgnore` to hide a secret field from serialization (like cent hides `clientSecret`).

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Why expose DTOs instead of JPA entities directly?**
To **decouple the API contract from the persistence model**. Returning entities causes lazy-initialization serialization errors (`LazyInitializationException` when Jackson touches an uninitialized association outside a transaction), over-exposes internal/sensitive fields, enables mass-assignment vulnerabilities on input, and couples clients to your schema so you can't refactor the DB without breaking the API. DTOs/records give a stable, intentional contract. (cent's `toApiObject()` conversion is this pattern.)

**Q2. Which HTTP methods are idempotent and why does it matter for retries?**
GET, HEAD, PUT, DELETE (and OPTIONS) are **idempotent** — repeating them yields the same server state. POST and (generally) PATCH are **not**. It matters because retry logic (timeouts, circuit breakers, gateways) may resend a request; safely retrying a POST can create duplicate resources/charges. For non-idempotent operations you need an **idempotency key** to dedupe server-side.

**Q3. `RestTemplate` vs `RestClient` vs `WebClient` — what to use today?**
`RestTemplate` is in **maintenance mode** (works, but no new features) — fine for legacy. For **new synchronous** calls use **`RestClient`** (Spring 6.1+), a modern fluent API. For **reactive/non-blocking** or streaming, use **`WebClient`**. For **declarative** clients, define an `@HttpExchange` interface backed by either. Don't start new code on `RestTemplate`.

**Q4. How would you version a REST API and what's the rule?**
Common strategies: URI path (`/v1/`, most visible), request header (`X-API-Version`), or media-type/content negotiation (`Accept: application/vnd.cent.v2+json`). The **rule**: once a version is published, **never break it** — additive, backward-compatible changes only; introduce a new version for breaking changes and deprecate old ones with a sunset window. (cent runs parallel `-v2` services for this reason.)

**Q5. What status code for "the request was well-formed but semantically invalid" vs "malformed"?**
**400 Bad Request** for malformed/syntactically invalid requests (bad JSON, missing required param). **422 Unprocessable Entity** for syntactically valid but **semantically** invalid requests (business rule violation, e.g., "end date before start date"). Many teams use 400 for validation too; 409 Conflict for state conflicts (duplicate), 404 for missing resources.

**Q6. A field appears in JSON that should be secret. How do you prevent it?**
Annotate it `@JsonIgnore` (serialization out), or better, **don't put it in the DTO at all** — expose only intended fields. For write-only fields (passwords) use `@JsonProperty(access = WRITE_ONLY)`. cent applies `@JsonIgnore` to `clientId`/`clientSecret` getters in `JamfOAuthIdentityProvider` precisely so credentials are never serialized into API responses.

**Q7. Should you configure Jackson per-class or globally?**
Prefer a **single global `ObjectMapper`** (or Boot's `Jackson2ObjectMapperBuilderCustomizer`) configuring the Java time module, `WRITE_DATES_AS_TIMESTAMPS=false`, `FAIL_ON_UNKNOWN_PROPERTIES`, and a consistent naming strategy. Per-class annotations are for genuine exceptions. Global config ensures consistent serialization across the whole API and avoids surprising one-off behaviors.

➡ Next: [Day 13 — Validation & Exception Handling](day-13-validation-exception-handling.md)
