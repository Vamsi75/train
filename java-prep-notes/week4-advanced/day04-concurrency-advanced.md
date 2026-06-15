# Day 4: Concurrency Advanced

Locks, volatile, atomics, the Java Memory Model, and the concurrency toolkit — the part interviewers dig into for senior roles.

---

## Quick Definition

Beyond `synchronized` and `Thread`, the `java.util.concurrent` (JUC) toolkit gives you **lock-free atomics**, **explicit locks**, **concurrent collections**, and **synchronizers**. Knowing *when* and *why* to reach for each — and the **Java Memory Model (JMM)** rules that make them correct — is what separates a 4-year dev from a junior.

| Mechanism | Guarantees | Cost | When to Use |
|:----------|:-----------|:-----|:------------|
| **volatile** | Visibility + ordering (no atomicity for compound ops) | Cheap | Flags, single-writer/multi-reader |
| **synchronized** | Visibility + atomicity (mutual exclusion) | Medium | Critical sections, simple locking |
| **Atomic\*** | Lock-free atomicity via CAS | Cheap under low contention | Counters, accumulators, CAS loops |
| **ReentrantLock** | Atomicity + tryLock/fairness/interruptible | Medium | Advanced locking needs |
| **ReadWriteLock** | Many readers OR one writer | Medium | Read-heavy shared state |
| **Concurrent collections** | Thread-safe, scalable | Low | Shared maps/queues/lists |

---

## Java Memory Model (JMM) Essentials — INTERVIEW FAVORITE

The JMM defines **when writes by one thread become visible to another** and **what reorderings the compiler/CPU may perform**.

### Three problems the JMM addresses

1. **Visibility** — a thread may read a *stale* cached value of a field written by another thread.
2. **Reordering** — compiler, JIT, and CPU may reorder instructions; this is invisible single-threaded but breaks naive concurrent code.
3. **Atomicity** — `count++` is read-modify-write (3 ops), not atomic.

### Happens-before (the core rule)

If action A *happens-before* B, then A's effects are visible to B. Key happens-before edges:

| Edge | Rule |
|:-----|:-----|
| **Program order** | Within a thread, earlier statements happen-before later ones |
| **Monitor lock** | Unlock of a monitor happens-before every subsequent lock of the same monitor |
| **volatile** | Write to a volatile field happens-before every subsequent read of it |
| **Thread start** | `Thread.start()` happens-before any action in the started thread |
| **Thread join** | All actions in a thread happen-before another thread returns from `join()` |
| **Transitivity** | If A hb B and B hb C, then A hb C |

```java
// The classic visibility bug
volatile boolean running = true;   // WITHOUT volatile, the loop may NEVER see the change

void worker() {
    while (running) { /* work */ }  // JIT may hoist running into a register
}
void stop() { running = false; }    // volatile write -> visible to the reading thread
```

> Gotcha: 64-bit `long`/`double` writes are NOT guaranteed atomic without `volatile` (the spec allows tearing into two 32-bit writes). `volatile long` fixes this.

---

## volatile vs synchronized

| Aspect | volatile | synchronized |
|:-------|:---------|:-------------|
| Visibility | Yes | Yes |
| Ordering | Yes | Yes |
| Atomicity (compound ops) | **No** | Yes |
| Mutual exclusion | No | Yes |
| Blocking | Never | Can block |
| Use for | Flags, single write | Critical sections |

```java
volatile int counter = 0;
counter++;   // STILL a race! read-modify-write is 3 steps, volatile doesn't make it atomic
```

Use `volatile` only when **one thread writes and others read**, or for a simple state flag. For increments, use atomics or a lock.

---

## Atomic Classes & CAS

`AtomicInteger`, `AtomicLong`, `AtomicReference`, `AtomicBoolean` provide **lock-free** atomic operations built on **Compare-And-Swap (CAS)** — a CPU instruction (`cmpxchg`) that atomically sets a value only if it still equals the expected value.

```java
AtomicInteger ai = new AtomicInteger(0);
ai.incrementAndGet();              // atomic ++   (returns 1)
ai.getAndAdd(5);                   // returns old value 1, now 6
ai.compareAndSet(6, 100);          // sets to 100 only if currently 6 -> true
ai.updateAndGet(x -> x * 2);       // atomic apply of a function (CAS loop inside)
ai.accumulateAndGet(3, Integer::sum);

AtomicReference<String> ref = new AtomicReference<>("init");
ref.compareAndSet("init", "next"); // CAS on object references
```

### How CAS works (the retry loop)

```java
// updateAndGet is roughly:
int prev, next;
do {
    prev = get();
    next = prev * 2;
} while (!compareAndSet(prev, next));   // retry if another thread won the race
```

### ABA problem

CAS only checks the *value*, not whether it changed-and-changed-back (A→B→A). `AtomicStampedReference` adds a version stamp to detect ABA.

### LongAdder — beats AtomicLong under high contention

`AtomicLong` has all threads CAS the **same** cell → cache-line contention. `LongAdder` keeps **multiple cells** (striping), summing them in `sum()`. Prefer it for hot counters where you write often and read rarely.

```java
LongAdder adder = new LongAdder();
adder.increment();
adder.add(5);
long total = adder.sum();   // not a live snapshot under concurrency
```

---

## ReentrantLock vs synchronized

`ReentrantLock` is an explicit lock with abilities `synchronized` lacks.

```java
ReentrantLock lock = new ReentrantLock();   // optional fairness: new ReentrantLock(true)
lock.lock();
try {
    // critical section
} finally {
    lock.unlock();   // ALWAYS unlock in finally
}

// tryLock — back off instead of blocking forever (deadlock avoidance)
if (lock.tryLock(1, TimeUnit.SECONDS)) {
    try { /* ... */ } finally { lock.unlock(); }
} else {
    // couldn't acquire — do something else
}

// lockInterruptibly — respond to Thread.interrupt() while waiting
lock.lockInterruptibly();
```

| Feature | synchronized | ReentrantLock |
|:--------|:-------------|:--------------|
| Reentrant | Yes | Yes |
| tryLock / timeout | No | Yes |
| Interruptible wait | No | Yes (`lockInterruptibly`) |
| Fairness option | No | Yes |
| Multiple conditions | No (one wait set) | Yes (`newCondition()`) |
| Auto-release on exception | Yes | No (need `finally`) |

> "Reentrant" = the same thread can acquire the lock it already holds (count increments); it must release the same number of times.

### ReadWriteLock & StampedLock

```java
ReadWriteLock rw = new ReentrantReadWriteLock();
rw.readLock().lock();   // many readers concurrently
rw.writeLock().lock();  // exclusive, blocks all readers/writers
```

`StampedLock` (Java 8) adds **optimistic reads** — no lock acquired, just a stamp you validate after reading. Much faster for read-heavy code, but it is **not reentrant** and has no `Condition` support.

```java
StampedLock sl = new StampedLock();
long stamp = sl.tryOptimisticRead();
int x = sharedX;                 // read without locking
if (!sl.validate(stamp)) {       // a write happened — fall back to a real read lock
    stamp = sl.readLock();
    try { x = sharedX; } finally { sl.unlockRead(stamp); }
}
```

---

## Condition vs wait/notify

`Condition` (from a `Lock`) replaces `Object.wait/notify`. It allows **multiple wait sets** per lock (e.g. "not full" and "not empty" for a bounded buffer).

```java
ReentrantLock lock = new ReentrantLock();
Condition notEmpty = lock.newCondition();
Condition notFull  = lock.newCondition();

// await() releases the lock and blocks; signal() wakes one waiter.
// Always wait in a loop guarding against spurious wakeups:
while (queueIsEmpty) notEmpty.await();
```

> Gotcha: `wait/notify/notifyAll` MUST be called while holding the object's monitor (`synchronized`), else `IllegalMonitorStateException`. Same for `await/signal` and the lock. Always re-check the condition in a `while` loop, never an `if`.

---

## Concurrent Collections

| Collection | Use | Notes |
|:-----------|:----|:------|
| **ConcurrentHashMap** | Shared map | Lock-free reads, bin-level locking on writes |
| **CopyOnWriteArrayList** | Read-mostly list | Every write copies the array; great for listener lists |
| **ConcurrentLinkedQueue** | Unbounded MPMC queue | Lock-free (CAS); `poll()` returns null when empty |
| **ArrayBlockingQueue / LinkedBlockingQueue** | Producer/consumer | Bounded; `put`/`take` block |

### ConcurrentHashMap internals & atomic ops

Java 8 CHM dropped segments. The table is an array of bins; **reads are non-blocking** (volatile reads), and writes lock **only the bin** (first node) via `synchronized`, falling back to a red-black tree per bin when collisions exceed 8. Resizing is cooperative (multiple threads help).

Use its **atomic compound operations** instead of get-then-put races:

```java
ConcurrentHashMap<String, Integer> chm = new ConcurrentHashMap<>();

// WRONG under concurrency:
chm.put(k, chm.getOrDefault(k, 0) + 1);   // read + write are separate -> lost updates

// RIGHT — atomic:
chm.merge(k, 1, Integer::sum);             // atomic increment
chm.compute(k, (key, v) -> v == null ? 1 : v + 1);
chm.computeIfAbsent(k, key -> new ArrayList<>());
```

> Gotcha: CHM allows **no null keys or values** (null is ambiguous with "absent"). The lambdas passed to `compute/merge` should be short and side-effect-free — they run while holding the bin lock.

### BlockingQueue — producer/consumer

```java
BlockingQueue<Integer> q = new ArrayBlockingQueue<>(10);
q.put(item);    // blocks if full
Integer x = q.take();   // blocks if empty
// Use a poison-pill or count to terminate consumers cleanly.
```

---

## Synchronizers

| Synchronizer | Purpose | Reusable |
|:-------------|:--------|:---------|
| **CountDownLatch** | Wait for N events once | No (one-shot) |
| **CyclicBarrier** | N threads wait for each other | Yes (resets) |
| **Semaphore** | Limit concurrent access to N permits | Yes |
| **Phaser** | Flexible multi-phase barrier | Yes |

```java
CountDownLatch latch = new CountDownLatch(3);
// workers: latch.countDown();
latch.await();   // main waits until count hits 0

CyclicBarrier barrier = new CyclicBarrier(3, () -> System.out.println("all arrived"));
barrier.await(); // each thread blocks until 3 have arrived, then all proceed

Semaphore sem = new Semaphore(2);   // at most 2 threads in the section
sem.acquire(); try { /* ... */ } finally { sem.release(); }
```

> CountDownLatch counts **down** and can't be reset. CyclicBarrier counts **up** to a trip point and **reuses**. That distinction is a classic interview question.

---

## Liveness Failures

| Failure | Meaning |
|:--------|:--------|
| **Deadlock** | Threads each hold a lock the other needs → frozen forever |
| **Livelock** | Threads keep reacting to each other and make no progress (not blocked) |
| **Starvation** | A thread never gets CPU/lock (e.g. low priority, unfair lock) |

**Avoiding deadlock:** acquire locks in a **global order**, use `tryLock` with timeout, minimize lock scope, prefer immutable data / single locks.

---

## Immutability, Thread-Confinement & ThreadLocal

- **Immutable objects** (`final` fields, no setters, defensive copies) are inherently thread-safe — no synchronization needed.
- **Thread confinement** — keep data in one thread (e.g. local variables, `ThreadLocal`) to avoid sharing entirely.
- **ThreadLocal** gives each thread its own copy.

```java
ThreadLocal<SimpleDateFormat> fmt =
    ThreadLocal.withInitial(() -> new SimpleDateFormat("yyyy-MM-dd")); // SDF isn't thread-safe
String s = fmt.get().format(new Date());
fmt.remove();   // MUST remove in thread pools to avoid leaks / stale state
```

> Gotcha: In a thread pool, threads are reused. Forgetting `remove()` leaks memory and leaks data across unrelated tasks.

---

## Interview Questions

### Q1: Does `volatile` make `count++` thread-safe?

No. `count++` is read-modify-write (3 operations). `volatile` only guarantees visibility and ordering, not atomicity of compound operations. Use `AtomicInteger.incrementAndGet()` or a lock.

### Q2: Explain happens-before. Give two edges.

If A happens-before B, A's memory effects are visible to B. Edges: an unlock happens-before a subsequent lock of the same monitor; a `volatile` write happens-before every subsequent read of that field; `Thread.start()` happens-before the thread's first action; the thread's last action happens-before another's return from `join()`.

### Q3: AtomicInteger vs LongAdder — when to use which?

`AtomicInteger`/`AtomicLong` CAS a single value — fine under low contention. Under high write contention, all threads contend on one cache line. `LongAdder` stripes across multiple cells, reducing contention; prefer it for hot counters read infrequently. Downside: `sum()` is not an atomic snapshot.

### Q4: What is CAS and the ABA problem?

Compare-And-Swap atomically sets a value only if it equals an expected value (one CPU instruction). It's the basis of lock-free algorithms. ABA: the value changed A→B→A, so CAS thinks nothing changed. Fix with `AtomicStampedReference` (adds a version stamp).

### Q5: ReentrantLock advantages over synchronized?

`tryLock` (with timeout), `lockInterruptibly`, fairness option, multiple `Condition`s per lock, and the ability to lock/unlock across method boundaries. Downside: you must `unlock()` in a `finally`.

### Q6: How does ConcurrentHashMap achieve thread-safety in Java 8+?

Reads are lock-free (volatile reads). Writes lock only the individual bin (first node) using `synchronized`, with a red-black tree per bin for heavy collisions. No global lock and no segments (removed in Java 8). Resizing is cooperative.

### Q7: CountDownLatch vs CyclicBarrier?

Latch is one-shot: counts down to zero, waiting threads proceed, can't reset. Barrier is reusable: N threads each `await()` until all arrive, then all proceed, then it resets (optionally running a barrier action).

### Q8: Why must you call `wait()` inside a `while`, not an `if`?

Spurious wakeups: a thread can wake without being signaled. Re-checking the condition in a loop ensures it only proceeds when the condition is actually true. Same applies to `Condition.await()`.

### Q9: How do you prevent deadlock?

Acquire locks in a consistent global order, use `tryLock` with timeout and back off, reduce lock scope/hold time, and prefer immutable data or a single coarse lock over multiple fine-grained ones.

### Q10: Why remove() a ThreadLocal in a thread pool?

Pool threads are long-lived and reused. A leftover value leaks memory (the entry stays in the thread's map) and can leak stale data into an unrelated future task running on the same thread.

---

## Practice Code

📁 `java-prep-practice/com/prep/week4_advanced/day04_concurrency/ConcurrencyAdvancedDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week4_advanced/day04_concurrency/ConcurrencyAdvancedDemo.java
java -cp java-prep-practice com.prep.week4_advanced.day04_concurrency.ConcurrencyAdvancedDemo
```

---

## Checklist

- [ ] I can explain visibility, reordering, and atomicity (the 3 JMM problems)
- [ ] I know the main happens-before edges
- [ ] I understand why `volatile` doesn't make `++` atomic
- [ ] I can use AtomicInteger / CAS / LongAdder and explain ABA
- [ ] I know when to choose ReentrantLock over synchronized
- [ ] I understand ReadWriteLock and StampedLock optimistic reads
- [ ] I can use ConcurrentHashMap's atomic compute/merge correctly
- [ ] I can implement producer/consumer with a BlockingQueue
- [ ] I know CountDownLatch vs CyclicBarrier vs Semaphore
- [ ] I can describe and prevent deadlock/livelock/starvation
- [ ] I know to remove() ThreadLocals in pooled threads

---

[← Day 3: Enums & Nested Classes](day03-enums-nested-classes.md) | [Next: Day 5 - CompletableFuture →](day05-completablefuture.md)
