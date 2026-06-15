# Day 12: ExecutorService

Thread pools done right - submit tasks, get Futures, shut down cleanly!

---

## Quick Definition

`ExecutorService` is a high-level API for **managing a pool of threads** and running tasks asynchronously. You submit tasks; the framework handles thread creation, reuse, queuing, and lifecycle - so you never call `new Thread()` directly in production.

| Concept | Meaning |
|:--------|:--------|
| **Executor** | Anything that runs `Runnable`s |
| **ExecutorService** | Executor + lifecycle + `Future` results |
| **Callable** | Like Runnable but returns a value / throws checked |
| **Future** | Handle to an async result |
| **Thread pool** | Reused worker threads (bounded resource) |

---

## Why Thread Pools?

| Problem with raw threads | Thread pool solution |
|:-------------------------|:---------------------|
| Thread creation is expensive | Reuse a fixed set of workers |
| Unbounded threads → OOM / context-switch thrash | Bound the number of threads |
| No backpressure | Queue tasks when busy |
| Manual lifecycle management | `shutdown()` / `awaitTermination()` |

---

## Executors Factory Methods

```java
ExecutorService fixed     = Executors.newFixedThreadPool(4);    // N fixed workers
ExecutorService cached    = Executors.newCachedThreadPool();    // grows unbounded!
ExecutorService single    = Executors.newSingleThreadExecutor();// 1 worker, serial
ScheduledExecutorService scheduled = Executors.newScheduledThreadPool(2);
```

| Factory | Threads | Queue | Risk |
|:--------|:--------|:------|:-----|
| `newFixedThreadPool(n)` | n | **Unbounded** `LinkedBlockingQueue` | OOM if tasks pile up |
| `newCachedThreadPool()` | 0..`Integer.MAX_VALUE` | `SynchronousQueue` | **Unbounded threads** → OOM |
| `newSingleThreadExecutor()` | 1 | Unbounded | Serial, OOM on backlog |
| `newScheduledThreadPool(n)` | n | Delayed work queue | - |

> ⚠️ **Why avoid these in prod?** Each hides a danger: fixed/single have **unbounded queues** (memory blow-up under load), cached has **unbounded threads**. Production code should build a `ThreadPoolExecutor` directly with a **bounded queue** and an explicit **rejection policy**.

---

## ThreadPoolExecutor - The Real Thing

```java
ThreadPoolExecutor pool = new ThreadPoolExecutor(
    2,                                  // corePoolSize: kept alive
    4,                                  // maximumPoolSize: max workers
    60L, TimeUnit.SECONDS,              // keepAliveTime: idle non-core timeout
    new ArrayBlockingQueue<>(100),      // BOUNDED work queue (backpressure)
    new ThreadPoolExecutor.CallerRunsPolicy()  // rejection handler
);
```

**How tasks flow:**
1. If workers < `corePoolSize` → create a new core thread.
2. Else if queue not full → enqueue the task.
3. Else if workers < `maximumPoolSize` → create a new (non-core) thread.
4. Else → invoke the **RejectedExecutionHandler**.

| Rejection policy | Behavior |
|:-----------------|:---------|
| `AbortPolicy` (default) | Throws `RejectedExecutionException` |
| `CallerRunsPolicy` | Runs task on the submitting thread (natural throttle) |
| `DiscardPolicy` | Silently drops the task |
| `DiscardOldestPolicy` | Drops oldest queued task, retries |

---

## submit vs execute

```java
// execute - fire and forget, Runnable only, no result
pool.execute(() -> System.out.println("ran"));

// submit - returns a Future; works with Runnable AND Callable
Future<?> f1 = pool.submit(() -> doWork());           // Future<?>
Future<Integer> f2 = pool.submit(() -> 42);           // Callable -> Future<Integer>
```

**Critical gotcha:** With `execute`, an uncaught exception propagates to the thread's `UncaughtExceptionHandler`. With `submit`, the exception is **captured in the Future** - you only see it when you call `future.get()`. Always call `get()` (or check) on submitted tasks, or exceptions vanish silently.

---

## Callable & Future

```java
Callable<Integer> task = () -> {
    Thread.sleep(50);
    return 21 * 2;
};

Future<Integer> future = pool.submit(task);

// future.isDone();           // non-blocking status check
Integer result = future.get();              // BLOCKS until result ready
Integer r2 = future.get(1, TimeUnit.SECONDS); // blocks with timeout -> TimeoutException
future.cancel(true);                        // attempt to interrupt the task
```

`get()` rethrows task exceptions wrapped in `ExecutionException` (use `getCause()` for the real one).

---

## invokeAll / invokeAny

```java
List<Callable<Integer>> tasks = List.of(() -> 1, () -> 2, () -> 3);

// invokeAll - runs ALL, returns list of Futures, blocks until all complete
List<Future<Integer>> results = pool.invokeAll(tasks);
for (Future<Integer> f : results) System.out.println(f.get());

// invokeAny - returns the result of the FIRST to finish, cancels the rest
Integer first = pool.invokeAny(tasks);
```

---

## Lifecycle: shutdown / shutdownNow / awaitTermination

```java
pool.shutdown();                 // graceful: no new tasks, finish queued ones
boolean done = pool.awaitTermination(5, TimeUnit.SECONDS);
if (!done) {
    List<Runnable> dropped = pool.shutdownNow();  // interrupt running, drop queued
}
```

| Method | New tasks | Running tasks | Queued tasks |
|:-------|:----------|:--------------|:-------------|
| `shutdown()` | Rejected | Finish | Finish |
| `shutdownNow()` | Rejected | **Interrupted** | Returned, dropped |
| `awaitTermination(t,u)` | - | Blocks up to timeout for completion | - |

**Standard shutdown idiom:** `shutdown()` → `awaitTermination()` → `shutdownNow()` if it times out, then await again.

---

## ScheduledExecutorService

```java
ScheduledExecutorService sched = Executors.newScheduledThreadPool(1);

// One-shot delay
sched.schedule(() -> System.out.println("after 1s"), 1, TimeUnit.SECONDS);

// Fixed RATE: every 2s regardless of task duration (can overlap/pile up)
sched.scheduleAtFixedRate(task, 0, 2, TimeUnit.SECONDS);

// Fixed DELAY: 2s gap AFTER each task finishes (never overlaps)
sched.scheduleWithFixedDelay(task, 0, 2, TimeUnit.SECONDS);
```

`scheduleAtFixedRate` measures period from start-to-start; `scheduleWithFixedDelay` from end-to-start.

---

## Virtual Threads (Java 21+) - brief mention

Java 21 (Project Loom) introduced **virtual threads** - lightweight threads managed by the JVM, ideal for high-concurrency blocking I/O. You can get an executor that spawns one virtual thread per task:

```java
// Java 21+
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    executor.submit(() -> blockingCall());
}  // try-with-resources auto-shuts down (ExecutorService is AutoCloseable since 19)
```

Virtual threads make the "thread per request" model cheap again. For CPU-bound work, traditional bounded pools are still appropriate.

---

## Common Pitfalls

| Pitfall | Fix |
|:--------|:----|
| **Not shutting down** the pool | Non-daemon worker threads keep JVM alive forever |
| **Unbounded queue** (`newFixedThreadPool`) | Use `ThreadPoolExecutor` with a bounded queue |
| **Unbounded threads** (`newCachedThreadPool`) | Bound `maximumPoolSize` |
| **Swallowed exceptions** with `submit` | Always `future.get()` or check the result |
| **Blocking pool threads on each other** | Risk pool-induced deadlock; size pools for dependencies |
| **No rejection policy** chosen | Pick one deliberately (often `CallerRunsPolicy`) |
| **`shutdownNow` without interrupt handling** | Tasks must respond to interruption |

---

## Interview Questions

### Q1: Why use ExecutorService instead of creating threads manually?

It reuses threads (avoids creation cost), bounds resource usage, provides queuing/backpressure, returns `Future`s, and manages lifecycle. Raw `new Thread()` per task can exhaust memory and CPU.

### Q2: Difference between submit() and execute()?

`execute(Runnable)` returns void and lets uncaught exceptions reach the `UncaughtExceptionHandler`. `submit()` accepts `Runnable`/`Callable`, returns a `Future`, and captures exceptions inside it - visible only via `get()`.

### Q3: Why avoid Executors.newFixedThreadPool in production?

It uses an unbounded `LinkedBlockingQueue`; under sustained load tasks accumulate and cause `OutOfMemoryError`. Use a `ThreadPoolExecutor` with a bounded queue and rejection policy.

### Q4: Explain ThreadPoolExecutor's core parameters.

`corePoolSize` (threads kept alive), `maximumPoolSize` (cap), `keepAliveTime` (idle non-core timeout), `workQueue` (holds pending tasks), and `RejectedExecutionHandler` (what to do when full).

### Q5: When does a new thread get created vs queued?

Core threads first; then queue if not full; then up to max threads; then reject. (Note: with an unbounded queue, max is never reached.)

### Q6: shutdown() vs shutdownNow()?

`shutdown()` stops accepting new tasks but completes running and queued ones. `shutdownNow()` interrupts running tasks and returns the queued (undone) tasks. Use `awaitTermination()` to wait for completion.

### Q7: invokeAll vs invokeAny?

`invokeAll` runs all tasks and returns all Futures (blocks until all finish). `invokeAny` returns the result of the first to complete successfully and cancels the rest.

### Q8: How are exceptions handled in Callable/Future?

A task exception is stored in the Future and rethrown as `ExecutionException` when you call `get()`; the original is in `getCause()`. If you never call `get()`, the exception is silently lost.

### Q9: scheduleAtFixedRate vs scheduleWithFixedDelay?

Fixed rate schedules from start-to-start (period independent of task time, can pile up if slow). Fixed delay waits the gap after each task ends (no overlap).

### Q10: What are virtual threads (Java 21)?

JVM-managed lightweight threads enabling millions of concurrent blocking tasks cheaply, great for I/O-bound "thread per request" workloads. CPU-bound work still benefits from bounded platform-thread pools.

---

## Practice Code

📁 `java-prep-practice/com/prep/week1_corejava/day12_executorservice/ExecutorServiceDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week1_corejava/day12_executorservice/ExecutorServiceDemo.java
java -cp java-prep-practice com.prep.week1_corejava.day12_executorservice.ExecutorServiceDemo
```

---

## Checklist

- [ ] I understand why thread pools beat raw threads
- [ ] I know the Executors factory methods and their hidden risks
- [ ] I can configure a ThreadPoolExecutor (core/max/queue/handler)
- [ ] I understand the task-flow and rejection policies
- [ ] I know submit vs execute and how exceptions differ
- [ ] I can use Callable, Future, invokeAll, invokeAny
- [ ] I know shutdown vs shutdownNow vs awaitTermination
- [ ] I can use ScheduledExecutorService (rate vs delay)
- [ ] I'm aware of virtual threads (Java 21)
- [ ] I always shut down pools and avoid unbounded queues

---

[← Day 11: Multithreading](day11-multithreading.md) | [Next: Day 1 - Lambda Expressions →](../week3-java8/day01-lambda-expressions.md)
