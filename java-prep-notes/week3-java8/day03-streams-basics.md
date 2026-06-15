# Day 3: Streams Basics

Declarative data processing pipelines - lazy, single-use, and everywhere in modern Java.

---

## Quick Definition

A **Stream** is a sequence of elements supporting sequential and parallel aggregate operations. It is **NOT a data structure** - it stores no elements. It pulls from a source (collection, array, generator) and pushes elements through a pipeline of operations.

```java
List<String> names = List.of("Alice", "Bob", "Charlie", "Dave");

long count = names.stream()        // source
    .filter(n -> n.length() > 3)   // intermediate (lazy)
    .map(String::toUpperCase)      // intermediate (lazy)
    .count();                      // terminal (triggers execution)

System.out.println(count);         // 3
```

| Property | Stream |
|:---------|:-------|
| **Stores data?** | No - it's a view over a source |
| **Mutates source?** | No - non-destructive |
| **Reusable?** | No - single-use, throws on re-traversal |
| **Lazy?** | Yes - nothing runs until a terminal op |
| **Ordered?** | Depends on source (List=yes, HashSet=no) |

---

## Stream Sources

```java
// 1. From a collection
List<Integer> list = List.of(1, 2, 3);
Stream<Integer> s1 = list.stream();

// 2. Stream.of (varargs)
Stream<String> s2 = Stream.of("a", "b", "c");

// 3. From an array
int[] arr = {1, 2, 3};
IntStream s3 = Arrays.stream(arr);

// 4. IntStream.range / rangeClosed
IntStream s4 = IntStream.range(0, 5);        // 0,1,2,3,4 (exclusive end)
IntStream s5 = IntStream.rangeClosed(1, 5);  // 1,2,3,4,5 (inclusive end)

// 5. Stream.iterate - INFINITE, must limit (or use 3-arg form Java 9+)
Stream<Integer> powers = Stream.iterate(1, x -> x * 2).limit(5);  // 1,2,4,8,16
Stream<Integer> bounded = Stream.iterate(1, x -> x <= 100, x -> x * 2); // Java 9+

// 6. Stream.generate - INFINITE, must limit
Stream<Double> randoms = Stream.generate(Math::random).limit(3);

// 7. Empty stream
Stream<String> empty = Stream.empty();
```

> Prefer `IntStream`/`LongStream`/`DoubleStream` for primitives to avoid boxing. Convert with `mapToInt`, or box back with `.boxed()`.

---

## Intermediate vs Terminal Operations - INTERVIEW FAVORITE!

| | Intermediate | Terminal |
|:--|:-------------|:---------|
| **Returns** | A new Stream | A value / collection / void |
| **Lazy?** | Yes - just records the step | No - triggers the pipeline |
| **Examples** | `filter, map, sorted, distinct, limit, skip, peek, mapToInt` | `forEach, collect, count, reduce, min, max, anyMatch, findFirst` |

```java
Stream<String> pipeline = Stream.of("a", "b")
    .filter(s -> true)   // intermediate - NOTHING happens yet
    .map(s -> s);        // still nothing - stream is lazy
// No terminal op = the lambdas above NEVER run.
```

---

## Laziness & Short-Circuiting

Intermediate ops are lazy. Elements are pulled **one at a time** through the whole pipeline (vertical, not horizontal). `peek` reveals the order:

```java
List<String> result = Stream.of("apple", "banana", "cherry", "date")
    .peek(s -> System.out.println("filter: " + s))
    .filter(s -> s.length() > 5)
    .peek(s -> System.out.println("  map: " + s))
    .map(String::toUpperCase)
    .limit(1)                // short-circuits after first match
    .collect(Collectors.toList());

// Output shows it stops EARLY:
// filter: apple
// filter: banana
//   map: banana
// (cherry/date never processed because limit(1) was satisfied)
```

**Short-circuiting ops** can finish without consuming the whole stream: `limit`, `findFirst`, `findAny`, `anyMatch`, `allMatch`, `noneMatch`. They make infinite streams usable.

---

## Common Intermediate Operations

```java
Stream.of(3, 1, 2, 3, 4, 5)
    .filter(n -> n > 1)     // keep matching: 3,2,3,4,5
    .distinct()             // remove dupes: 3,2,4,5
    .sorted()               // natural order: 2,3,4,5
    .skip(1)                // drop first n: 3,4,5
    .limit(2)               // keep first n: 3,4
    .map(n -> n * 10)       // transform: 30,40
    .forEach(System.out::println);

// mapToInt: object stream -> IntStream (unlocks sum/average)
int total = Stream.of("a", "bb", "ccc")
    .mapToInt(String::length)
    .sum();                 // 6

// peek: debugging side-effects, NOT for mutation
list.stream().peek(System.out::println).count();
```

| Op | Purpose |
|:---|:--------|
| `filter(Predicate)` | Keep elements matching |
| `map(Function)` | Transform each element |
| `mapToInt/Long/Double` | To primitive stream |
| `flatMap(Function)` | Flatten nested streams (covered Day 4) |
| `distinct()` | Remove duplicates (uses equals) |
| `sorted()` / `sorted(Comparator)` | Sort (stateful - buffers all) |
| `limit(n)` / `skip(n)` | Take first n / drop first n |
| `peek(Consumer)` | Observe without consuming |

---

## Common Terminal Operations

```java
List<Integer> nums = List.of(5, 3, 8, 1, 9, 2);

// forEach - side effects
nums.stream().forEach(System.out::println);

// collect - into a collection
List<Integer> evens = nums.stream().filter(n -> n % 2 == 0).collect(Collectors.toList());

// count
long c = nums.stream().filter(n -> n > 4).count();           // 3

// reduce - fold into one value
int sum = nums.stream().reduce(0, Integer::sum);             // 28
Optional<Integer> product = nums.stream().reduce((a, b) -> a * b);

// min / max - return Optional
Optional<Integer> max = nums.stream().max(Integer::compareTo); // 9
Optional<Integer> min = nums.stream().min(Comparator.naturalOrder());

// matching - boolean, short-circuit
boolean anyBig  = nums.stream().anyMatch(n -> n > 8);   // true
boolean allPos  = nums.stream().allMatch(n -> n > 0);   // true
boolean noneNeg = nums.stream().noneMatch(n -> n < 0);  // true

// finding - return Optional
Optional<Integer> first = nums.stream().filter(n -> n > 4).findFirst(); // 5
Optional<Integer> any   = nums.stream().filter(n -> n > 4).findAny();   // any (5 here, but parallel may differ)
```

> `allMatch` on an **empty** stream returns `true` (vacuous truth); `anyMatch` returns `false`; `noneMatch` returns `true`.

---

## Streams Are Single-Use

A stream can be traversed **once**. Reusing it throws `IllegalStateException`.

```java
Stream<Integer> s = Stream.of(1, 2, 3);
s.forEach(System.out::println);   // OK
// s.count();                     // IllegalStateException: stream has already been operated upon or closed

// Fix: create a fresh stream each time, or use a Supplier<Stream<>>
Supplier<Stream<Integer>> factory = () -> Stream.of(1, 2, 3);
factory.get().forEach(System.out::println);
System.out.println(factory.get().count());   // works - new stream
```

---

## Ordering

- **Encounter order** comes from the source: `List`/`LinkedHashSet` preserve order; `HashSet` doesn't.
- `sorted()` imposes order; `unordered()` allows the pipeline to drop ordering for performance.
- In a **sequential** stream `findFirst` and `findAny` return the same thing; in **parallel**, `findAny` may return any element (faster), `findFirst` still returns the first in encounter order.

```java
// forEach does NOT guarantee order in parallel; forEachOrdered does
List.of(1, 2, 3, 4).parallelStream().forEachOrdered(System.out::print); // 1234
```

---

## Interview Questions

### Q1: Is a Stream a data structure?

No. It holds no elements and doesn't store data. It's a lazily-evaluated pipeline over a source. It also doesn't mutate the source.

### Q2: What's the difference between intermediate and terminal operations?

Intermediate ops return a new Stream and are lazy (filter, map, sorted...). Terminal ops produce a result or side effect and trigger execution (collect, count, reduce, forEach). Without a terminal op, no intermediate lambda ever runs.

### Q3: Can you reuse a stream?

No. Streams are single-use; calling a second operation after a terminal (or even a second terminal) throws `IllegalStateException`. Re-create the stream or wrap it in a `Supplier<Stream<T>>`.

### Q4: How can an infinite stream (Stream.iterate/generate) ever terminate?

Via short-circuiting operations like `limit`, `findFirst`, `anyMatch`, or the 3-arg `Stream.iterate` predicate (Java 9+). Laziness means only as many elements as needed are generated.

### Q5: What does `peek` do and why is it discouraged in production?

It performs a side effect on each element as it passes, mainly for debugging. It's discouraged for business logic because it may be skipped by optimizations (e.g. `count()` on a sized stream may not run peek at all in Java 9+), and side effects in pipelines are error-prone.

### Q6: filter then map vs map then filter - does order matter?

Yes for performance and sometimes correctness. Filtering first reduces how many elements get mapped (cheaper). The result set can also differ if the map changes the property you filter on.

### Q7: Why do `min`, `max`, `findFirst`, `reduce` (no-identity) return `Optional`?

Because the stream might be empty - there may be no element to return. `Optional` forces the caller to handle the empty case instead of returning null.

### Q8: What does `allMatch` return on an empty stream?

`true` (vacuous truth). `anyMatch` returns `false`, `noneMatch` returns `true`. A classic gotcha.

### Q9: Difference between `findFirst` and `findAny`?

In sequential streams they're equivalent. In parallel streams `findAny` may return any element and is faster (no ordering constraint), while `findFirst` still respects encounter order.

### Q10: Why prefer IntStream over Stream<Integer>?

To avoid autoboxing of every element, and because IntStream exposes numeric terminal ops like `sum()`, `average()`, `summaryStatistics()` that the object stream lacks.

---

## Practice Code

📁 `java-prep-practice/com/prep/week3_java8/day03_streams/StreamsBasicsDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week3_java8/day03_streams/StreamsBasicsDemo.java
java -cp java-prep-practice com.prep.week3_java8.day03_streams.StreamsBasicsDemo
```

---

## Checklist

- [ ] I can explain why a stream is not a data structure
- [ ] I know all the stream sources (collection, of, range, iterate, generate)
- [ ] I can classify ops as intermediate (lazy) vs terminal
- [ ] I understand laziness, vertical processing, and short-circuiting
- [ ] I can use filter/map/mapToInt/sorted/distinct/limit/skip/peek
- [ ] I can use collect/count/reduce/min/max/match/find terminals
- [ ] I know streams are single-use and how to work around it
- [ ] I know the empty-stream match results and findFirst vs findAny

---

[← Day 2: Functional Interfaces](day02-functional-interfaces.md) | [Next: Day 4 - Streams Advanced →](day04-streams-advanced.md)
