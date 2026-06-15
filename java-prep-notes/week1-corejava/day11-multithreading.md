# Day 11: Multithreading Basics

Concurrency fundamentals - threads, locks, and coordination!

---

## Quick Definition

A **thread** is the smallest unit of execution within a process. Multithreading lets a single program run multiple threads concurrently, sharing memory (heap) while each has its own stack.

| Concept | Meaning |
|:--------|:--------|
| **Thread** | Independent path of execution |
| **Runnable** | Task (`run()`) that a thread executes |
| **Race condition** | Result depends on thread interleaving |
| **synchronized** | Mutual exclusion via intrinsic lock (monitor) |
| **volatile** | Visibility guarantee (no caching) for a field |

---

## Thread vs Runnable

```java
// 1. Extend Thread (NOT preferred - uses up your single inheritance)
class MyThread extends Thread {
    public void run() { System.out.println("Running: " + getName()); }
}
new MyThread().start();

// 2. Implement Runnable (PREFERRED - flexible, separates task from thread)
class MyTask implements Runnable {
    public void run() { System.out.println("Running task"); }
}
new Thread(new MyTask()).start();

// 3. Lambda (Runnable is a functional interface)
new Thread(() -> System.out.println("Lambda task")).start();
```

**Why prefer Runnable?** It decouples the task from the execution mechanism, allows reuse with thread pools, and leaves your class free to extend something else.

---

## start() vs run() - CLASSIC GOTCHA!

```java
Thread t = new Thread(() -> System.out.println(Thread.currentThread().getName()));

t.start();   // Creates a NEW thread -> prints "Thread-0"
t.run();     // Just a normal method call on CURRENT thread -> prints "main"
```

Calling `run()` directly does **not** start a new thread - it runs synchronously on the calling thread. Also, calling `start()` twice throws `IllegalThreadStateException`.

---

## Thread Lifecycle (States)

```
NEW ──start()──> RUNNABLE ──┬── (scheduler) ──> RUNNING ──run() ends──> TERMINATED
                            │
              ┌─────────────┴──────────────────┐
              │ wait/join/lock        sleep/timed │
              v                                  v
          WAITING                         TIMED_WAITING
              │                                  │
              └──── notify / lock acquired ──────┘
                            │
                    BLOCKED (waiting for monitor lock)
```

| State (`Thread.State`) | Meaning |
|:-----------------------|:--------|
| `NEW` | Created, not yet started |
| `RUNNABLE` | Eligible to run (running or ready) |
| `BLOCKED` | Waiting to acquire a monitor lock |
| `WAITING` | `wait()`, `join()` with no timeout |
| `TIMED_WAITING` | `sleep(ms)`, `wait(ms)`, `join(ms)` |
| `TERMINATED` | Finished execution |

Note: Java has no separate "RUNNING" state - it's part of `RUNNABLE`.

---

## sleep / join / yield

```java
Thread t = new Thread(() -> {
    try { Thread.sleep(100); }       // pauses ~100ms, KEEPS held locks
    catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    System.out.println("Worker done");
});
t.start();

t.join();   // current thread WAITS until t finishes (makes output deterministic)
System.out.println("Main continues after worker");

Thread.yield();  // hint to scheduler "I'm willing to pause" - rarely needed
```

| Method | Behavior | Releases lock? |
|:-------|:---------|:---------------|
| `sleep(ms)` | Pause current thread for given time | No |
| `join()` | Wait for another thread to die | No (waits on that thread) |
| `yield()` | Hint to give up CPU | No |
| `wait()` | Release lock, wait for notify | Yes |

**Always use `join()` in demos** so output is deterministic.

---

## Daemon Threads & Priorities

```java
Thread daemon = new Thread(() -> { while (true) {} });
daemon.setDaemon(true);   // MUST set before start()
daemon.start();
// JVM exits when only daemon threads remain (e.g., GC is a daemon)

Thread t = new Thread(task);
t.setPriority(Thread.MAX_PRIORITY);  // 1..10, default 5 - only a HINT, OS-dependent
```

Daemon threads do not block JVM shutdown. Priorities are merely hints - don't rely on them for correctness.

---

## Race Conditions

```java
class Counter {
    int count = 0;
    void increment() { count++; }   // NOT atomic: read, add, write
}
// 1000 threads each incrementing -> final count often < expected
```

`count++` is three operations. Without synchronization, threads interleave and updates are lost (lost-update problem).

---

## synchronized - Method & Block

```java
class SafeCounter {
    private int count = 0;

    // Synchronized method - locks on 'this'
    synchronized void increment() { count++; }

    // Synchronized block - finer-grained, lock on chosen object
    private final Object lock = new Object();
    void incrementBlock() {
        synchronized (lock) { count++; }
    }

    // Static synchronized - locks on the CLASS object (SafeCounter.class)
    static synchronized void staticMethod() { }
}
```

**Intrinsic lock (monitor):** Every Java object has one. `synchronized` acquires it on entry and releases on exit (even on exception). Instance-locks (`this`) and class-locks (`Class`) are independent.

---

## wait / notify / notifyAll (Producer-Consumer)

```java
class Buffer {
    private final Queue<Integer> queue = new LinkedList<>();
    private final int capacity = 5;

    synchronized void produce(int item) throws InterruptedException {
        while (queue.size() == capacity) wait();   // ALWAYS wait in a loop!
        queue.add(item);
        notifyAll();                               // wake consumers
    }

    synchronized int consume() throws InterruptedException {
        while (queue.isEmpty()) wait();
        int item = queue.poll();
        notifyAll();                               // wake producers
        return item;
    }
}
```

| Rule | Reason |
|:-----|:-------|
| Call `wait/notify` only while **holding the lock** | Else `IllegalMonitorStateException` |
| Always `wait()` in a **`while`** loop, not `if` | Guards against spurious wakeups & stale conditions |
| Prefer `notifyAll()` over `notify()` | `notify()` may wake the wrong waiter -> deadlock/missed signals |

`wait()` releases the lock and suspends; `notify()` wakes one waiter but does NOT release the lock until the synchronized block exits.

---

## volatile

```java
class Flag {
    private volatile boolean running = true;   // visibility guaranteed

    void stop()  { running = false; }
    void loop()  { while (running) { /* work */ } }   // sees update from other thread
}
```

`volatile` guarantees **visibility** (reads/writes go to main memory, not CPU cache) and prevents reordering, but does **NOT** provide atomicity. `volatile count++` is still a race. Use it for flags/state signals; use `synchronized`/`AtomicInteger` for compound actions.

| | volatile | synchronized | AtomicInteger |
|:--|:---------|:-------------|:--------------|
| **Visibility** | Yes | Yes | Yes |
| **Atomicity** | No | Yes | Yes (CAS) |
| **Blocking** | No | Yes | No (lock-free) |

---

## Thread Safety Basics

- **Immutable objects** (`final` fields, no setters) are inherently thread-safe.
- **Confinement**: keep data on one thread (e.g., local variables, `ThreadLocal`).
- **Synchronization**: guard shared mutable state.
- **Concurrent collections**: `ConcurrentHashMap`, `CopyOnWriteArrayList` over `Collections.synchronizedXxx`.
- **Atomics**: `AtomicInteger`, `AtomicReference` for lock-free counters.

---

## Common Pitfalls

| Pitfall | Fix |
|:--------|:----|
| Calling `run()` instead of `start()` | Use `start()` for a new thread |
| `wait()` in an `if` (spurious wakeup) | Use a `while` loop |
| Swallowing `InterruptedException` | Restore the flag: `Thread.currentThread().interrupt()` |
| Deadlock (lock ordering) | Acquire locks in a consistent global order |
| Using `volatile` for compound ops | Use `synchronized`/atomics |
| Forgetting `setDaemon` before `start` | Set daemon status before starting |

---

## Interview Questions

### Q1: Difference between extending Thread and implementing Runnable?

`Runnable` separates the task from the thread, allows your class to extend something else, and works with thread pools. Extending `Thread` consumes your single inheritance and couples task with execution. Prefer `Runnable`.

### Q2: start() vs run()?

`start()` registers a new thread with the scheduler and invokes `run()` on it. Calling `run()` directly executes it synchronously on the current thread - no new thread is created.

### Q3: What are the thread states?

`NEW`, `RUNNABLE`, `BLOCKED`, `WAITING`, `TIMED_WAITING`, `TERMINATED` (`Thread.State` enum). There's no separate RUNNING state.

### Q4: sleep() vs wait()?

`sleep()` is a static `Thread` method, pauses for a fixed time, and does NOT release locks. `wait()` is an `Object` method, must be called holding the lock, releases the lock, and waits until `notify`/`notifyAll` or timeout.

### Q5: Why wait/notify in a while loop, not if?

To handle spurious wakeups and re-check the condition (it may have changed by the time the thread re-acquires the lock). An `if` would proceed on a false condition.

### Q6: notify() vs notifyAll()?

`notify()` wakes one arbitrary waiting thread; `notifyAll()` wakes all (they then re-contend for the lock). `notifyAll()` is safer - `notify()` can wake the wrong thread and cause missed signals/deadlock.

### Q7: What does volatile guarantee?

Visibility and ordering (no caching, no reordering across the access) but NOT atomicity. Good for flags; insufficient for compound operations like `count++`.

### Q8: What is a race condition and how do you prevent it?

When correctness depends on thread interleaving over shared mutable state. Prevent via synchronization, atomics, immutability, or thread confinement.

### Q9: What is a daemon thread?

A background thread (e.g., GC) that does not prevent JVM shutdown. The JVM exits when only daemon threads remain. Must call `setDaemon(true)` before `start()`.

### Q10: What is deadlock and how to avoid it?

Two+ threads each holding a lock the other needs, waiting forever. Avoid by acquiring locks in a consistent global order, using timeouts (`tryLock`), or reducing lock scope.

---

## Practice Code

📁 `java-prep-practice/com/prep/week1_corejava/day11_multithreading/ThreadDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week1_corejava/day11_multithreading/ThreadDemo.java
java -cp java-prep-practice com.prep.week1_corejava.day11_multithreading.ThreadDemo
```

---

## Checklist

- [ ] I know Thread vs Runnable and why Runnable is preferred
- [ ] I understand start() vs run()
- [ ] I can list the six thread states
- [ ] I know sleep vs wait vs join vs yield
- [ ] I can explain race conditions and fix them with synchronized
- [ ] I understand intrinsic locks (monitors), instance vs class locks
- [ ] I can implement producer-consumer with wait/notifyAll in a while loop
- [ ] I know what volatile does and does not guarantee
- [ ] I understand daemon threads and that priorities are hints
- [ ] I can identify common pitfalls (deadlock, swallowed interrupts)

---

[← Day 10: Exception Handling](day10-exceptions.md) | [Next: Day 12 - ExecutorService →](day12-executorservice.md)
