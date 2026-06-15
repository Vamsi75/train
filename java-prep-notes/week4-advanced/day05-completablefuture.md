# Day 5: CompletableFuture & Async

Composable, non-blocking asynchronous pipelines — the modern way to do async in Java.

---

## Quick Definition

`CompletableFuture<T>` (Java 8) is a `Future` you can **complete manually**, **chain**, **combine**, and attach **callbacks** to — without blocking. It implements `Future<T>` and `CompletionStage<T>`.

| Need | Method |
|:-----|:-------|
| Run async, return a value | `supplyAsync(Supplier)` |
| Run async, no value | `runAsync(Runnable)` |
| Transform result | `thenApply(fn)` |
| Consume result | `thenAccept(consumer)` |
| Run after (ignore result) | `thenRun(runnable)` |
| Chain dependent future | `thenCompose(fn)` |
| Combine two futures | `thenCombine(other, fn)` |
| Wait for all / any | `allOf(...)` / `anyOf(...)` |
| Handle errors | `exceptionally` / `handle` / `whenComplete` |

---

## Why Future Wasn't Enough

`java.util.concurrent.Future` (Java 5) is limited:

- `get()` **blocks** the calling thread.
- **No callbacks** — you can't say "when done, do X" without polling or blocking.
- **No chaining/combining** of multiple futures.
- **No manual completion** and weak exception handling.

```java
ExecutorService ex = Executors.newFixedThreadPool(2);
Future<Integer> f = ex.submit(() -> 42);
int v = f.get();   // BLOCKS here — defeats the purpose of async
```

`CompletableFuture` fixes all of these.

---

## Creation

```java
// Async with a result (runs on the common ForkJoinPool by default)
CompletableFuture<Integer> cf = CompletableFuture.supplyAsync(() -> compute());

// Async with no result
CompletableFuture<Void> r = CompletableFuture.runAsync(() -> doWork());

// Already-completed (useful for tests / short-circuits)
CompletableFuture<String> done = CompletableFuture.completedFuture("ready");

// Manual completion
CompletableFuture<String> manual = new CompletableFuture<>();
manual.complete("value");                 // from anywhere
manual.completeExceptionally(new RuntimeException("boom"));

// Use a custom executor instead of the common pool
ExecutorService pool = Executors.newFixedThreadPool(4);
CompletableFuture.supplyAsync(() -> compute(), pool);
```

---

## Chaining: thenApply / thenAccept / thenRun

| Method | Input | Returns | Use |
|:-------|:------|:--------|:----|
| `thenApply(fn)` | result | new value | transform T → U |
| `thenAccept(c)` | result | `Void` | consume, no return |
| `thenRun(r)` | nothing | `Void` | run a side effect |

```java
CompletableFuture.supplyAsync(() -> "hello")
    .thenApply(String::toUpperCase)        // "HELLO"
    .thenApply(s -> s + " WORLD")          // "HELLO WORLD"
    .thenAccept(System.out::println)       // prints, returns CF<Void>
    .thenRun(() -> System.out.println("done"));
```

### `thenApply` vs `thenApplyAsync`

- `thenApply` runs the callback **on the thread that completed the previous stage** (or the caller, if already complete).
- `thenApplyAsync` submits the callback to the **common pool** (or a supplied executor) — use it to avoid hogging the completing thread or to control the pool.

```java
cf.thenApply(fn);                  // same thread that finished the previous stage
cf.thenApplyAsync(fn);             // common ForkJoinPool
cf.thenApplyAsync(fn, myPool);     // your executor
```

---

## thenCompose vs thenApply (flattening)

When your function itself returns a `CompletableFuture`, use `thenCompose` to **flatten** (like `flatMap`); `thenApply` would give you a nested `CompletableFuture<CompletableFuture<T>>`.

```java
CompletableFuture<User> userF = getUserAsync(id);

// WRONG type: CompletableFuture<CompletableFuture<Order>>
userF.thenApply(user -> getOrdersAsync(user));

// RIGHT: CompletableFuture<Order>
userF.thenCompose(user -> getOrdersAsync(user));
```

---

## thenCombine (independent futures)

Run two **independent** futures in parallel and combine their results when both finish.

```java
CompletableFuture<Integer> a = CompletableFuture.supplyAsync(() -> 10);
CompletableFuture<Integer> b = CompletableFuture.supplyAsync(() -> 20);

CompletableFuture<Integer> sum = a.thenCombine(b, Integer::sum);  // 30
```

---

## Composing Many: allOf / anyOf

```java
CompletableFuture<Void> all = CompletableFuture.allOf(f1, f2, f3);
all.join();   // waits for ALL; returns Void — collect results yourself:
List<String> results = Stream.of(f1, f2, f3).map(CompletableFuture::join).toList();

CompletableFuture<Object> first = CompletableFuture.anyOf(f1, f2, f3);
Object firstResult = first.join();   // result of whichever finishes FIRST
```

> Gotcha: `allOf` returns `CompletableFuture<Void>` — it does **not** give you a list of results. You join the originals (which are now complete) to extract values.

---

## Exception Handling

| Method | Sees | Can recover? | Runs when |
|:-------|:-----|:-------------|:----------|
| `exceptionally(fn)` | exception only | Yes (returns fallback) | only on failure |
| `handle(fn)` | result **and** exception | Yes | always |
| `whenComplete(bc)` | result and exception | **No** (observe only) | always |

```java
CompletableFuture.supplyAsync(() -> { throw new RuntimeException("fail"); })
    .exceptionally(ex -> {                 // recover with a fallback value
        System.out.println("recovered: " + ex.getMessage());
        return -1;
    });

cf.handle((result, ex) -> ex != null ? -1 : result);   // transform either outcome

cf.whenComplete((result, ex) -> log(result, ex));       // side-effect only, passes value through
```

> Note: exceptions are wrapped in a `CompletionException`. Inspect `ex.getCause()` for the original. `whenComplete` does not swallow the exception — the returned stage still completes exceptionally.

---

## Executors: common ForkJoinPool vs custom

By default, `*Async` methods use `ForkJoinPool.commonPool()` (sized to CPU cores − 1). Pitfalls:

- The common pool is **shared JVM-wide**; blocking I/O in it can **starve** other tasks (including parallel streams).
- For **blocking work** (DB/HTTP), pass a **dedicated executor** sized for I/O.

```java
ExecutorService io = Executors.newFixedThreadPool(20);
CompletableFuture.supplyAsync(this::blockingDbCall, io);   // don't block the common pool
// ... remember to io.shutdown() when done
```

---

## Timeouts (Java 9+)

```java
cf.orTimeout(2, TimeUnit.SECONDS);                 // fail with TimeoutException if not done
cf.completeOnTimeout(fallback, 2, TimeUnit.SECONDS); // complete with a fallback value on timeout
```

---

## Common Gotchas

- **Blocking `get()`/`join()` too early** kills the async benefit. Build the whole pipeline, then block once at the edge.
- **Swallowed exceptions**: a `CompletableFuture` that fails and is never `join`ed/handled fails *silently*. Always attach `exceptionally`/`handle` or join it.
- `get()` throws checked `ExecutionException`/`InterruptedException`; `join()` throws unchecked `CompletionException` — `join` is friendlier in lambdas/streams.
- Don't do **blocking work** on the common pool.
- `thenApply` may run on the **caller thread** if the future is already complete — don't assume it's always async.

---

## Interview Questions

### Q1: Why CompletableFuture over Future?

Future only offers blocking `get()` with no callbacks, chaining, combining, or manual completion. CompletableFuture adds non-blocking composition (`thenApply`/`thenCompose`/`thenCombine`), aggregation (`allOf`/`anyOf`), and rich exception handling.

### Q2: thenApply vs thenCompose?

`thenApply` maps `T → U` (returns a value). `thenCompose` maps `T → CompletableFuture<U>` and flattens it (like `flatMap`), avoiding nested futures. Use `thenCompose` when the mapping function is itself async.

### Q3: thenApply vs thenApplyAsync?

`thenApply` runs the callback on the thread that completed the previous stage (or the caller if already done). `thenApplyAsync` schedules it on the common ForkJoinPool (or a supplied executor), giving you control over which thread/pool runs it.

### Q4: What does allOf return and how do you get results?

`CompletableFuture<Void>`. It only signals completion. After `allOf(...).join()`, call `join()` on each original future to collect its result (they're all complete by then).

### Q5: exceptionally vs handle vs whenComplete?

`exceptionally` runs only on failure and returns a fallback. `handle` runs always, receives (result, exception), and can transform either. `whenComplete` runs always but only observes (can't change the result); the stage still propagates the original exception.

### Q6: What's the default executor and why can it be a problem?

`ForkJoinPool.commonPool()` (≈ cores − 1 threads), shared JVM-wide. Blocking I/O in it can starve other tasks and parallel streams. Use a dedicated executor for blocking work.

### Q7: How are exceptions propagated in a chain?

A failure short-circuits the dependent stages; they don't run their normal callback and instead propagate a `CompletionException` wrapping the cause, until a `handle`/`exceptionally` recovers it. Inspect `getCause()` for the original.

### Q8: How do you add a timeout?

Java 9+ `orTimeout(t, unit)` completes exceptionally with `TimeoutException`; `completeOnTimeout(value, t, unit)` completes with a fallback value. Pre-Java-9 you'd combine with a separately scheduled timeout future.

### Q9: get() vs join()?

Both block until done. `get()` throws checked `ExecutionException`/`InterruptedException`. `join()` throws unchecked `CompletionException` — more convenient inside lambdas/streams where checked exceptions are awkward.

---

## Practice Code

📁 `java-prep-practice/com/prep/week4_advanced/day05_async/CompletableFutureDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week4_advanced/day05_async/CompletableFutureDemo.java
java -cp java-prep-practice com.prep.week4_advanced.day05_async.CompletableFutureDemo
```

---

## Checklist

- [ ] I can explain why Future is insufficient
- [ ] I can create CFs with supplyAsync/runAsync/completedFuture/manual complete
- [ ] I know thenApply vs thenAccept vs thenRun
- [ ] I understand thenCompose (flatten) vs thenApply
- [ ] I can combine futures with thenCombine
- [ ] I can aggregate with allOf/anyOf and extract results
- [ ] I know exceptionally vs handle vs whenComplete
- [ ] I know the common pool pitfall and when to use a custom executor
- [ ] I can apply orTimeout/completeOnTimeout
- [ ] I avoid blocking get() too early and swallowed exceptions

---

[← Day 4: Concurrency Advanced](day04-concurrency-advanced.md) | [Next: Day 6 - JVM Internals →](day06-jvm-memory-gc.md)
