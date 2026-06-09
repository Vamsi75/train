# Day 11 — Spring MVC & REST Controllers

## THEORY

### 1. The DispatcherServlet request flow (front controller)
Every HTTP request flows through the **`DispatcherServlet`**:
1. `DispatcherServlet` receives the request.
2. **`HandlerMapping`** finds the controller method for the URL+method.
3. **`HandlerAdapter`** invokes it; **argument resolvers** bind `@PathVariable`, `@RequestParam`, `@RequestBody` (via `HttpMessageConverter`), etc.
4. The method returns an object / `ResponseEntity` / view name.
5. **`HttpMessageConverter`** (Jackson) serializes the return value to JSON (for `@ResponseBody`/`@RestController`), or a `ViewResolver` renders a view.
6. Response goes back through any filters/interceptors.
Knowing this flow lets you answer "where do I plug in X?" (filter vs interceptor vs advice vs converter).

### 2. Controller annotations
```java
@RestController                       // = @Controller + @ResponseBody
@RequestMapping("/aaaservers")        // base path (cent style)
public class AAAServerController {

    @GetMapping("/{id}")              // shortcut for @RequestMapping(method=GET)
    public AAAServer find(@PathVariable String id) { ... }

    @GetMapping                       // GET /aaaservers?organizationId=...
    public List<AAAServer> search(@RequestParam(required=false) String organizationId) { ... }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public AAAServer create(@Valid @RequestBody CreateServerRequest req) { ... }

    @PutMapping("/{id}")
    public AAAServer update(@PathVariable String id, @RequestBody UpdateRequest req) { ... }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String id) { ... }
}
```

### 3. Request data binding
- `@PathVariable` — from the URL path (`/{id}`).
- `@RequestParam` — query/form params (`?page=2`); supports `defaultValue`, `required`.
- `@RequestBody` — deserialize the JSON body into an object (via Jackson).
- `@RequestHeader`, `@CookieValue`, `@RequestPart` (multipart).
- `@ModelAttribute` — bind form/query params into an object.

### 4. `@RestController` vs `@Controller`
`@Controller` returns **view names** (server-side rendering) unless a method is `@ResponseBody`. `@RestController` applies `@ResponseBody` to **every** method → return values are serialized straight to the response body (JSON). REST APIs use `@RestController`.

### 5. Content negotiation & message converters
Spring picks an `HttpMessageConverter` based on the `Accept`/`Content-Type` headers. With Jackson on the classpath, JSON is default. The same return object can be serialized to XML if a converter and the right `Accept` header are present.

### 6. Filters vs Interceptors vs ControllerAdvice (where to put cross-cutting web logic)
- **`Filter`** (Servlet) — outermost, runs for *all* requests incl. static resources; no Spring MVC context (good for auth, CORS, MDC, gzip). cent's request correlation would live here.
- **`HandlerInterceptor`** — Spring MVC level; `preHandle`/`postHandle`/`afterCompletion`; knows the handler. Good for auth checks tied to controllers, timing.
- **`@ControllerAdvice`/`@ExceptionHandler`** — centralized exception handling & model tweaks (Day 13).
Order outermost→innermost: Filter → DispatcherServlet → Interceptor → Controller.

### 7. Validation entry point
`@Valid @RequestBody Dto` triggers Jakarta validation; failures throw `MethodArgumentNotValidException` → 400 (cleaned up by advice on Day 13).

---

## PRACTICE

```java
// A realistic REST controller mirroring cent's constructor-injected style
@RestController
@RequestMapping("/api/v1/servers")
public class ServerController {

    private final ServerService service;
    public ServerController(ServerService service) { this.service = service; }  // constructor DI

    @GetMapping
    public List<ServerDto> search(
            @RequestParam(required = false) String organizationId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return service.search(organizationId, page, size);
    }

    @GetMapping("/{id}")
    public ServerDto get(@PathVariable String id) {
        return service.findById(id);   // throws NotFoundException → handled by advice (Day 13)
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ServerDto create(@Valid @RequestBody CreateServerRequest req,
                            UriComponentsBuilder uri) {
        return service.create(req);
    }

    @PatchMapping("/{id}/status")
    public ServerDto changeStatus(@PathVariable String id, @RequestParam ServerStatus status) {
        return service.changeStatus(id, status);
    }
}
```
```java
// HandlerInterceptor for per-request timing
@Component
class TimingInterceptor implements HandlerInterceptor {
    public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object handler) {
        req.setAttribute("start", System.nanoTime()); return true;
    }
    public void afterCompletion(HttpServletRequest req, HttpServletResponse res, Object handler, Exception ex) {
        long ms = (System.nanoTime() - (long) req.getAttribute("start")) / 1_000_000;
        System.out.printf("%s %s -> %d (%d ms)%n", req.getMethod(), req.getRequestURI(), res.getStatus(), ms);
    }
}
@Configuration
class WebConfig implements WebMvcConfigurer {
    private final TimingInterceptor interceptor;
    WebConfig(TimingInterceptor i) { this.interceptor = i; }
    public void addInterceptors(InterceptorRegistry r) { r.addInterceptor(interceptor); }
}
```

**Exercises:**
1. Build CRUD endpoints for a resource; test with `curl`/HTTPie for each verb and status code.
2. Add a `@RequestParam` with a `defaultValue` and a required path variable; test missing-param behavior.
3. Add a `HandlerInterceptor` that logs timing; then move it to a `Filter` and note what changes (static resources now logged).
4. Send invalid JSON to a `@Valid` endpoint and observe the default 400 (you'll prettify it on Day 13).

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Walk through what happens from HTTP request to JSON response in Spring MVC.**
The `DispatcherServlet` (front controller) receives the request, asks a `HandlerMapping` for the matching controller method, and a `HandlerAdapter` invokes it. Argument resolvers bind `@PathVariable`/`@RequestParam` and use an `HttpMessageConverter` (Jackson) to deserialize `@RequestBody`. The method returns an object; because it's `@ResponseBody`/`@RestController`, an `HttpMessageConverter` serializes it to JSON based on content negotiation, and the response flows back out through interceptors and filters.

**Q2. `@Controller` vs `@RestController`?**
`@RestController` = `@Controller` + `@ResponseBody` on every method, so return values are serialized directly to the response body (JSON) — for REST APIs. `@Controller` returns **view names** resolved by a `ViewResolver` for server-side rendered pages, unless a method is individually `@ResponseBody`. Use `@RestController` for APIs, `@Controller` for MVC web pages.

**Q3. Filter vs HandlerInterceptor — when do you choose each?**
A **Filter** is a Servlet-level component that runs **outside** Spring MVC for *every* request (including static resources and requests that never reach a controller) and has no knowledge of the handler — ideal for CORS, authentication, MDC/trace-id setup, compression. A **HandlerInterceptor** runs **inside** Spring MVC, knows which handler will execute, and has `preHandle/postHandle/afterCompletion` hooks — ideal for handler-aware concerns like authorization tied to controllers or per-handler timing. Filters are outermost; interceptors wrap the controller.

**Q4. `@RequestParam` vs `@PathVariable` vs `@RequestBody` — semantics?**
`@PathVariable` binds a value embedded **in the URI path** (`/servers/{id}` → resource identity). `@RequestParam` binds **query string or form** parameters (`?page=2` → filters/options). `@RequestBody` deserializes the **request body** (usually JSON) into an object via Jackson (the payload for POST/PUT). Rule of thumb: identity in path, options in query, payload in body.

**Q5. How does Spring decide JSON vs XML for the response?**
**Content negotiation**: it inspects the request's `Accept` header (and optionally URL suffix/param strategies) and selects a registered `HttpMessageConverter` that can produce that media type. With only Jackson on the classpath you get JSON; add a Jackson/JAXB XML converter and `Accept: application/xml` yields XML. The same controller method serves multiple representations without code changes.

**Q6. Should a `@RestController` be thread-safe? It's a singleton.**
Yes — it's a **singleton shared across all request threads**, so it must be **stateless** (no mutable instance fields holding per-request data). Store request state in method locals/parameters. cent's controllers follow this: they hold only injected (stateless) services as `final` fields and read request data from method arguments.

**Q7. Why is constructor injection especially recommended in controllers?**
Because controllers are singletons with dependencies that must always be present; constructor injection makes them `final` and guarantees a fully-initialized controller, prevents accidental mutable state, and makes the controller unit-testable with `new ServerController(mockService)` and MockMvc standalone setup — no full context needed. (cent's `AAAServerController` injects `IAAAServerService` via the constructor for exactly this reason.)

**Q8. What's the difference between `@ResponseStatus` and returning a `ResponseEntity`?**
`@ResponseStatus(HttpStatus.CREATED)` sets a **fixed** status for the method (declarative, simple). `ResponseEntity` lets you set status, headers, and body **dynamically at runtime** (e.g., 200 vs 404 depending on logic, add a `Location` header). Use `@ResponseStatus` for constant outcomes, `ResponseEntity` when status/headers vary (covered Day 12).

➡ Next: [Day 12 — REST Advanced](day-12-rest-advanced.md)
