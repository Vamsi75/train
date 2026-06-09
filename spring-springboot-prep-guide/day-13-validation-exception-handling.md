# Day 13 — Validation & Centralized Exception Handling

## THEORY

### 1. The problem
Without central handling, every controller catches exceptions and builds error responses → duplication, inconsistent error shapes, leaked stack traces. Spring centralizes this with **`@ControllerAdvice` + `@ExceptionHandler`**.

### 2. `@RestControllerAdvice` + `@ExceptionHandler`
```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ProblemDetail handleNotFound(ResourceNotFoundException ex) {
        ProblemDetail pd = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
        pd.setTitle("Resource not found");
        pd.setProperty("resourceId", ex.getId());
        return pd;
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)   // @Valid @RequestBody failures
    public ProblemDetail handleValidation(MethodArgumentNotValidException ex) {
        ProblemDetail pd = ProblemDetail.forStatus(HttpStatus.BAD_REQUEST);
        pd.setTitle("Validation failed");
        Map<String, String> errors = new LinkedHashMap<>();
        ex.getBindingResult().getFieldErrors()
          .forEach(fe -> errors.put(fe.getField(), fe.getDefaultMessage()));
        pd.setProperty("errors", errors);
        return pd;
    }

    @ExceptionHandler(Exception.class)            // catch-all → never leak stack traces
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ProblemDetail handleGeneric(Exception ex) {
        log.error("Unexpected error", ex);        // log full detail server-side
        return ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR,
                "An unexpected error occurred");   // generic message to the client
    }
}
```

### 3. `ProblemDetail` — RFC 7807 (Spring 6+)
Spring 6 / Boot 3 has **built-in `ProblemDetail`** implementing the standard "Problem Details for HTTP APIs" error format:
```json
{ "type":"about:blank", "title":"Validation failed", "status":400,
  "detail":"...", "instance":"/api/v1/servers", "errors": { "port":"must be <= 65535" } }
```
Standardizing on it gives consistent, machine-readable errors across all cent services. Enable default mapping with `spring.mvc.problemdetails.enabled=true`.

### 4. Validation exceptions you'll handle
- `MethodArgumentNotValidException` — `@Valid @RequestBody` DTO failed.
- `ConstraintViolationException` — `@Validated` method params / `@RequestParam`/`@PathVariable` failed.
- `HttpMessageNotReadableException` — malformed/unparseable JSON.
- `MethodArgumentTypeMismatchException` — wrong type in path/query (e.g., `abc` for an int).
- `MissingServletRequestParameterException` — required param absent.

### 5. `ResponseStatusException` — programmatic, no custom class
For one-off cases you don't want a dedicated exception class:
```java
throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Server " + id + " not found");
```

### 6. `ResponseEntityExceptionHandler`
Extend it in your advice to override Spring MVC's built-in exception handling (for the framework exceptions above) in one place, returning `ProblemDetail`.

### 7. Validation groups & cross-field validation
- **Groups:** validate different rules in different scenarios (`@Validated(OnCreate.class)`).
- **Cross-field:** a class-level custom constraint (e.g., `@EndAfterStart`) since field constraints can't see siblings.

### 8. Principles
- **Never leak stack traces or internal messages** to clients (security + UX). Log details server-side; return a safe, generic message + a correlation/trace id.
- **Map exceptions to the right status** (404 vs 400 vs 409 vs 500).
- **Keep the error shape consistent** (ProblemDetail) so clients parse one format.

---

## PRACTICE

```java
// Domain exception
public class ResourceNotFoundException extends RuntimeException {
    private final String id;
    public ResourceNotFoundException(String id) { super("Not found: " + id); this.id = id; }
    public String getId() { return id; }
}

// Service throws it
@Service
class ServerService {
    public ServerDto findById(String id) {
        return repo.findById(id).map(this::toDto)
                   .orElseThrow(() -> new ResourceNotFoundException(id));
    }
}

// Cross-field custom validation
@Target(TYPE) @Retention(RUNTIME) @Constraint(validatedBy = DateRangeValidator.class)
@interface ValidDateRange { String message() default "end must be after start"; Class<?>[] groups() default {}; Class<? extends Payload>[] payload() default {}; }

class DateRangeValidator implements ConstraintValidator<ValidDateRange, ReportRequest> {
    public boolean isValid(ReportRequest r, ConstraintValidatorContext ctx) {
        return r.start() == null || r.end() == null || r.end().isAfter(r.start());
    }
}
@ValidDateRange
public record ReportRequest(@NotNull LocalDate start, @NotNull LocalDate end) {}
```

**Exercises:**
1. Add a `@RestControllerAdvice` returning `ProblemDetail`; trigger a 404 and a 400 and inspect the JSON.
2. Validate a `@RequestParam @Min(1) int page` (needs `@Validated` on the controller) and handle `ConstraintViolationException`.
3. Build a cross-field `@ValidDateRange` constraint and verify it fires.
4. Throw `ResponseStatusException` from a service and confirm the status propagates.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. `MethodArgumentNotValidException` vs `ConstraintViolationException` — when does each occur?**
`MethodArgumentNotValidException` is thrown when a **`@Valid @RequestBody`** object fails bean validation (it carries a `BindingResult` of field errors). `ConstraintViolationException` is thrown when **method-level validation** fails — e.g., constraints on `@RequestParam`/`@PathVariable` or service method args on a `@Validated` bean (it carries `ConstraintViolation`s). They have different structures, so you handle them separately in the advice.

**Q2. What is `ProblemDetail` and why standardize on it?**
`ProblemDetail` is Spring 6's implementation of **RFC 7807 "Problem Details for HTTP APIs"** — a standard JSON error format with `type`, `title`, `status`, `detail`, `instance`, plus custom properties. Standardizing means **every endpoint (and every microservice) returns errors in one predictable, machine-readable shape**, so clients write one parser and tooling/logging is consistent across the fleet.

**Q3. Why is returning stack traces to clients a problem?**
It's a **security risk** (leaks class names, library versions, file paths, SQL — useful to attackers) and **poor UX/contract** (clients shouldn't parse Java traces). Best practice: **log the full exception server-side** with a correlation/trace id, and return a **generic, safe message** plus that id so support can find the details without exposing internals.

**Q4. `@ControllerAdvice` — does it apply to all controllers? How do you scope it?**
By default it applies **globally** to all controllers. You can scope it with `@ControllerAdvice(basePackages=...)`, `assignableTypes = {SomeController.class}`, or `annotations = {RestController.class}` to limit which controllers it advises — useful when different API areas need different error formats (e.g., public vs internal APIs).

**Q5. How do you handle the same logical error differently for two API versions?**
Use multiple scoped `@ControllerAdvice` beans (by base package or assignable types) so v1 and v2 controllers get version-appropriate error shapes, or branch within a handler on the request path/version. The key is keeping each version's published error contract stable.

**Q6. Where does validation run for `@Valid` on a `@RequestBody`, and what status results by default?**
It runs in the `HandlerAdapter` when binding the body argument, **before** your controller method body executes. On failure it throws `MethodArgumentNotValidException`, which Spring maps to **HTTP 400** by default. You typically intercept it in advice to produce a structured `ProblemDetail` listing each field error instead of Spring's default body.

**Q7. Field-level constraints can't validate "end after start." How do you do cross-field validation?**
With a **class-level custom constraint** (`@Constraint` on the type) whose `ConstraintValidator` receives the **whole object**, so it can compare sibling fields. Field annotations only see one field; class-level validators see all of them, which is required for inter-field rules (date ranges, "password == confirmPassword", conditional requireds).

**Q8. Should validation live only in the controller layer?**
No — controller validation guards the API boundary, but **domain invariants should also be enforced in the domain/service layer** (and DB constraints) for defense in depth, since services may be called from message listeners, schedulers, or other entry points that bypass the controller. Validate at the edge for fast feedback *and* protect invariants deeper down.

➡ Next: [Day 14 — Spring Data JPA](day-14-spring-data-jpa.md)
