# Day 6: JVM Internals, Memory Model & GC

How your code actually runs, where objects live, and how memory is reclaimed — the questions that separate seniors from juniors.

---

## Quick Definition

The **JVM** loads `.class` bytecode, verifies it, manages memory, JIT-compiles hot code to native instructions, and reclaims unused objects via **garbage collection** — so you write portable code and never call `free()`.

| Layer | Responsibility |
|:------|:---------------|
| **Class Loader Subsystem** | Loads, links, and initializes classes |
| **Runtime Data Areas** | Heap, Stacks, Metaspace, PC registers |
| **Execution Engine** | Interpreter + JIT compiler + Garbage Collector |
| **Native Interface (JNI)** | Calls into native (C/C++) libraries |

---

## JVM Architecture

```
        .java  --javac-->  .class (bytecode)
                                 |
   +-----------------------------v------------------------------+
   |                      JVM                                    |
   |  Class Loader  ->  Runtime Data Areas  ->  Execution Engine|
   |   (Bootstrap,        (Heap, Stack,           (Interpreter, |
   |    Platform,          Metaspace, PC,          JIT, GC)     |
   |    Application)       Native stack)                        |
   +------------------------------------------------------------+
                                 |
                          Native OS / Hardware
```

---

## Runtime Data Areas (Memory Model)

| Area | Shared? | Holds | OOM type |
|:-----|:--------|:------|:---------|
| **Heap** | All threads | All objects + arrays | `OutOfMemoryError: Java heap space` |
| **Metaspace** | All threads | Class metadata (replaced PermGen in Java 8) | `OutOfMemoryError: Metaspace` |
| **JVM Stack** | Per thread | Frames: local vars, operand stack, partial results | `StackOverflowError` |
| **PC Register** | Per thread | Address of current instruction | — |
| **Native Method Stack** | Per thread | State for native (JNI) calls | — |

### Heap Layout (Generational)

```
Heap
├── Young Generation
│   ├── Eden          (new objects allocated here)
│   ├── Survivor S0
│   └── Survivor S1   (objects surviving minor GC copy between S0/S1)
└── Old Generation    (long-lived objects promoted from young)
```

- **Most objects die young** → the *Weak Generational Hypothesis*. GC is cheap in the young gen because most of it is garbage.
- Surviving a configurable number of minor GCs (tenuring threshold) → promoted to Old Gen.

### Stack vs Heap

```java
void example() {
    int x = 10;                  // primitive 'x' lives on the STACK (this frame)
    Person p = new Person();     // reference 'p' on STACK, object on HEAP
    // when example() returns, the frame (and x, p) is popped;
    // the Person object stays on the heap until unreachable, then GC'd
}
```

---

## Class Loading

Three phases, lazily triggered on first active use:

| Phase | What happens |
|:------|:-------------|
| **Loading** | Find `.class`, create `Class` object in memory |
| **Linking** | *Verify* (bytecode safety) → *Prepare* (static fields to defaults) → *Resolve* (symbolic refs) |
| **Initialization** | Run static initializers and static field assignments |

### The Three Built-in Class Loaders + Parent Delegation

```
Bootstrap ClassLoader   (java.base / core JDK; written in native code)
        ^
Platform ClassLoader    (formerly Extension; JDK modules)
        ^
Application ClassLoader  (your classpath)
```

**Parent delegation:** a loader first asks its *parent* to load a class; only if the parent can't does it try itself. This prevents you from overriding core classes (you can't sneak in a fake `java.lang.String`).

```java
System.out.println(String.class.getClassLoader());          // null = Bootstrap
System.out.println(MyClass.class.getClassLoader());         // AppClassLoader
```

---

## Garbage Collection Fundamentals

### What is garbage?

An object is collectable when it is **unreachable** from any **GC root**. GC roots include:
- Local variables / operands on thread stacks
- Static fields of loaded classes
- JNI references
- Active threads

> **Key point:** GC is about *reachability*, not reference counting. Two objects referencing each other (a cycle) are still collected if nothing reachable points to them — so Java has no reference-cycle leak like naive ref-counting.

### Phases (Mark-Sweep-Compact)

1. **Mark** – walk from GC roots, mark every reachable object.
2. **Sweep** – reclaim unmarked (dead) objects.
3. **Compact** – move survivors together to remove fragmentation.

### Minor vs Major vs Full GC

| Term | Scope | Cost |
|:-----|:------|:-----|
| **Minor GC** | Young gen only | Fast, frequent |
| **Major GC** | Old gen | Slower |
| **Full GC** | Whole heap (+ metaspace) | Slowest, "Stop-The-World" pause |

**Stop-The-World (STW):** application threads are paused during (parts of) GC. Modern collectors minimize STW duration.

---

## GC Algorithms (Collectors)

| Collector | Flag | Best for | Notes |
|:----------|:-----|:---------|:------|
| **Serial** | `-XX:+UseSerialGC` | Small heaps, single CPU | One thread, long pauses |
| **Parallel (Throughput)** | `-XX:+UseParallelGC` | Batch jobs, max throughput | Multi-threaded, STW |
| **CMS** | `-XX:+UseConcMarkSweepGC` | Low pause (legacy) | **Deprecated/removed** (gone in JDK 14) |
| **G1** | `-XX:+UseG1GC` | General purpose | **Default since Java 9**; region-based, predictable pauses |
| **ZGC** | `-XX:+UseZGC` | Huge heaps, ultra-low pause | Sub-millisecond pauses, concurrent |
| **Shenandoah** | `-XX:+UseShenandoahGC` | Low pause | Concurrent compaction |

**G1 (Garbage First):** divides the heap into equal **regions** and collects the regions with the most garbage first, aiming for a target pause time (`-XX:MaxGCPauseMillis`).

---

## Common JVM Flags

```bash
-Xms512m              # initial heap size
-Xmx2g                # max heap size  (set Xms == Xmx in prod to avoid resizing)
-Xmn256m              # young generation size
-Xss512k              # thread stack size
-XX:+UseG1GC          # select G1 collector
-XX:MaxGCPauseMillis=200
-XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=256m
-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp/dump.hprof
-Xlog:gc*             # GC logging (Java 9+; was -XX:+PrintGCDetails)
```

---

## OutOfMemoryError Types & Memory Leaks

| Error | Typical cause |
|:------|:--------------|
| `Java heap space` | Genuinely too small heap, or a leak retaining objects |
| `GC overhead limit exceeded` | >98% time in GC, <2% heap recovered |
| `Metaspace` | Too many loaded classes (e.g. classloader leak on redeploys) |
| `Unable to create new native thread` | Too many threads / OS limit |
| `Direct buffer memory` | Leaked `DirectByteBuffer` / off-heap |

**Java still leaks memory** (logically) when you keep references you no longer need:
- Static collections that only ever grow (caches without eviction)
- Unremoved listeners/callbacks
- `ThreadLocal`s not cleaned in thread pools
- Inner classes holding the enclosing instance

---

## References Strength (java.lang.ref)

| Reference | Collected when… | Use |
|:----------|:----------------|:----|
| **Strong** (`new Object()`) | never (while reachable) | normal |
| **Soft** (`SoftReference`) | only under memory pressure | memory-sensitive caches |
| **Weak** (`WeakReference`) | next GC if only weakly reachable | `WeakHashMap`, canonical maps |
| **Phantom** (`PhantomReference`) | after finalization, for cleanup | replace `finalize()` |

> `finalize()` is **deprecated** (since Java 9) — unpredictable, slow, can resurrect objects. Use **`try-with-resources`** for deterministic cleanup or **`java.lang.ref.Cleaner`** for last-resort native cleanup.

---

## String Pool & intern()

```java
String a = "hello";                 // string literal -> goes into the String Pool
String b = "hello";                 // same pooled instance
String c = new String("hello");     // NEW object on the heap (not pooled)

System.out.println(a == b);         // true  (same pooled reference)
System.out.println(a == c);         // false (different objects)
System.out.println(a == c.intern());// true  (intern() returns the pooled ref)
System.out.println(a.equals(c));    // true  (always compare with equals!)
```

The string pool lives in the **heap** (since Java 7; was PermGen before).

---

## Interview Questions

### Q1: PermGen vs Metaspace?
PermGen (≤ Java 7) was a fixed-size region in the heap for class metadata and caused frequent `OutOfMemoryError: PermGen`. Java 8 replaced it with **Metaspace**, which lives in **native memory** and auto-grows (bounded by `MaxMetaspaceSize`).

### Q2: What is the default garbage collector and why?
**G1** (since Java 9). It's region-based and targets a configurable max pause time, giving a good balance of throughput and low latency for typical server heaps.

### Q3: Does Java have memory leaks?
GC reclaims *unreachable* objects, so you can't leak in the C sense. But you can keep objects *reachable* unintentionally (static caches, unremoved listeners, ThreadLocals in pools) — a logical leak that still causes `OutOfMemoryError`.

### Q4: Why is GC based on reachability instead of reference counting?
Reference counting can't reclaim **reference cycles** (A→B→A) and adds per-assignment overhead. Reachability tracing from GC roots collects cycles correctly.

### Q5: Stack vs heap — what goes where?
Stack: per-thread frames holding primitives, references, and method call state (fast, auto-freed on return). Heap: all objects and arrays, shared across threads, managed by GC.

### Q6: What triggers a StackOverflowError vs OutOfMemoryError?
`StackOverflowError`: a thread's stack is exhausted, usually deep/infinite recursion. `OutOfMemoryError`: the heap (or metaspace/native) can't satisfy an allocation.

### Q7: What is the JIT compiler?
The JVM starts by **interpreting** bytecode, profiles "hot" methods, then the **JIT** (C1/C2 tiered compilation) compiles them to optimized native code (inlining, escape analysis, loop unrolling). That's why a JVM "warms up."

### Q8: What is escape analysis?
A JIT optimization: if an object never "escapes" a method/thread, the JVM can **scalar-replace** or **stack-allocate** it, avoiding heap allocation and GC pressure.

### Q9: minor vs major vs full GC?
Minor = young gen only (frequent, fast). Major = old gen. Full = entire heap + metaspace (longest stop-the-world pause). Frequent full GCs signal a problem (undersized heap or a leak).

### Q10: How do you diagnose a memory problem in production?
Enable GC logs (`-Xlog:gc*`), capture a heap dump (`-XX:+HeapDumpOnOutOfMemoryError` or `jmap`), analyze with Eclipse MAT/VisualVM for dominator trees and leak suspects; watch live with `jstat`/`jcmd`.

---

## Practice Code

📁 `java-prep-practice/com/prep/week4_advanced/day06_jvm/JvmMemoryDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week4_advanced/day06_jvm/JvmMemoryDemo.java
java -cp java-prep-practice com.prep.week4_advanced.day06_jvm.JvmMemoryDemo

# Try it with GC logging and a small heap:
java -Xms64m -Xmx64m -Xlog:gc -cp java-prep-practice com.prep.week4_advanced.day06_jvm.JvmMemoryDemo
```

---

## Checklist

- [ ] I can name the runtime data areas and what each holds
- [ ] I understand the generational heap (Eden, Survivor, Old) and the weak generational hypothesis
- [ ] I can explain class loading phases and parent delegation
- [ ] I know GC is reachability-based and can list GC roots
- [ ] I can compare Serial/Parallel/G1/ZGC and name the default
- [ ] I know the common OOM types and their causes
- [ ] I understand strong/soft/weak/phantom references and why `finalize()` is dead
- [ ] I can explain the String pool and `intern()`
- [ ] I know the key tuning flags and how to capture a heap dump

---

[← Day 5: CompletableFuture](day05-completablefuture.md) | [Next: Day 7 - Annotations & Reflection →](day07-annotations-reflection.md)
