# Day 4: Streams Advanced

Collectors, grouping, partitioning, reduce and parallel streams - where stream interviews get hard.

---

## Quick Definition

The `Collectors` factory and terminal `reduce`/`collect` operations turn a stream of elements into a single result - a `List`, `Map`, statistic, or a grouped/partitioned structure. Mastering them is what separates a junior from a senior stream user.

| Tool | Returns | Typical use |
|:-----|:--------|:------------|
| `collect(Collectors.toList())` | `List` | Materialize a stream |
| `groupingBy` | `Map<K, List<T>>` | SQL-style GROUP BY |
| `partitioningBy` | `Map<Boolean, List<T>>` | Split by predicate |
| `reduce` | single value / `Optional` | Fold to one result |
| `teeing` (Java 12) | combined result | Two collectors, one pass |
| parallel stream | same as sequential | CPU-bound bulk work |

---

## Collectors Deep Dive

The `Collectors` class has ~40 static factory methods. Know these cold.

```java
List<String> names = List.of("Alice", "Bob", "Charlie", "Bob");

// toList / toSet
List<String> list = names.stream().collect(Collectors.toList());   // mutable, ArrayList (no guarantee!)
Set<String>  set  = names.stream().collect(Collectors.toSet());    // duplicates removed -> [Alice, Bob, Charlie]

// toUnmodifiableList (Java 10) - throws on mutation
List<String> immutable = names.stream().collect(Collectors.toUnmodifiableList());

// joining
String joined = names.stream().collect(Collectors.joining(", ", "[", "]"));
// [Alice, Bob, Charlie, Bob]

// counting
long count = names.stream().collect(Collectors.counting());        // 4
```

### toMap and the merge function

```java
List<String> words = List.of("apple", "banana", "avocado", "cherry");

// SIMPLE toMap - throws IllegalStateException on duplicate key!
Map<Character, Integer> lengths = words.stream()
    .collect(Collectors.toMap(w -> w.charAt(0), String::length));
// 'a' appears twice (apple, avocado) -> IllegalStateException

// toMap WITH merge function - resolves duplicate keys
Map<Character, Integer> merged = words.stream()
    .collect(Collectors.toMap(
        w -> w.charAt(0),
        String::length,
        (existing, replacement) -> existing));   // keep first
// {a=5, b=6, c=6}

// toMap with map supplier (e.g. TreeMap for sorted keys)
Map<Character, Integer> sorted = words.stream()
    .collect(Collectors.toMap(
        w -> w.charAt(0), String::length,
        Integer::sum, TreeMap::new));
```

> **Gotcha:** `toMap` without a merge function throws on duplicate keys. `toMap` also throws `NullPointerException` if a *value* is null (unlike `HashMap.put`).

### Numeric collectors

```java
List<Integer> nums = List.of(1, 2, 3, 4, 5);

int sum        = nums.stream().collect(Collectors.summingInt(i -> i));        // 15
double avg     = nums.stream().collect(Collectors.averagingDouble(i -> i));   // 3.0
IntSummaryStatistics stats = nums.stream()
    .collect(Collectors.summarizingInt(i -> i));
// count=5, sum=15, min=1, average=3.0, max=5
System.out.println(stats.getMax());   // 5
```

### Downstream collectors: mapping, filtering, reducing

These are rarely used standalone - they shine as the **downstream** of `groupingBy`.

```java
List<String> names = List.of("Alice", "Bob", "Charlie");

// mapping - transform then collect
List<Integer> nameLengths = names.stream()
    .collect(Collectors.mapping(String::length, Collectors.toList()));   // [5, 3, 7]

// filtering (Java 9) - keeps empty groups, unlike stream().filter()
List<String> longNames = names.stream()
    .collect(Collectors.filtering(s -> s.length() > 3, Collectors.toList()));  // [Alice, Charlie]

// reducing - general fold as a collector
Optional<String> longest = names.stream()
    .collect(Collectors.reducing((a, b) -> a.length() >= b.length() ? a : b));
```

---

## groupingBy - SQL GROUP BY for streams

```java
List<String> words = List.of("apple", "banana", "avocado", "cherry", "blueberry");

// 1. Single-level: Map<K, List<T>>
Map<Character, List<String>> byFirst = words.stream()
    .collect(Collectors.groupingBy(w -> w.charAt(0)));
// {a=[apple, avocado], b=[banana, blueberry], c=[cherry]}

// 2. groupingBy + counting (downstream)
Map<Character, Long> countByFirst = words.stream()
    .collect(Collectors.groupingBy(w -> w.charAt(0), Collectors.counting()));
// {a=2, b=2, c=1}

// 3. groupingBy + mapping (collect a property per group)
Map<Character, List<Integer>> lengthsByFirst = words.stream()
    .collect(Collectors.groupingBy(
        w -> w.charAt(0),
        Collectors.mapping(String::length, Collectors.toList())));

// 4. Multi-level grouping (group, then sub-group)
Map<Character, Map<Integer, List<String>>> multi = words.stream()
    .collect(Collectors.groupingBy(
        w -> w.charAt(0),
        Collectors.groupingBy(String::length)));

// 5. groupingBy with map supplier + downstream
Map<Character, Set<String>> sortedGroups = words.stream()
    .collect(Collectors.groupingBy(
        w -> w.charAt(0), TreeMap::new, Collectors.toSet()));
```

> **Gotcha:** `groupingBy` returns a `HashMap` and `ArrayList` by default - no ordering guarantee. Supply a `TreeMap`/`LinkedHashMap` factory if order matters.

---

## partitioningBy - split into true/false

`partitioningBy` is `groupingBy` specialized for a boolean predicate. The returned map **always** has both `true` and `false` keys, even if one is empty.

```java
List<Integer> nums = List.of(1, 2, 3, 4, 5, 6);

Map<Boolean, List<Integer>> evenOdd = nums.stream()
    .collect(Collectors.partitioningBy(n -> n % 2 == 0));
// {false=[1, 3, 5], true=[2, 4, 6]}

// With downstream collector
Map<Boolean, Long> evenOddCount = nums.stream()
    .collect(Collectors.partitioningBy(n -> n % 2 == 0, Collectors.counting()));
// {false=3, true=3}
```

> `partitioningBy(p)` is faster than `groupingBy(p::test)` because it uses a fixed two-slot structure, and it guarantees both keys exist. `groupingBy` would omit the empty group.

---

## teeing (Java 12) - two collectors in one pass

`teeing` runs two downstream collectors over the same stream and merges their results with a `BiFunction`.

```java
List<Integer> nums = List.of(2, 4, 6, 8);

// average = sum / count, in a single pass
double average = nums.stream().collect(Collectors.teeing(
    Collectors.summingDouble(i -> i),   // first collector
    Collectors.counting(),              // second collector
    (sum, count) -> sum / count));      // merge
// 5.0

record MinMax(int min, int max) {}
MinMax range = nums.stream().collect(Collectors.teeing(
    Collectors.minBy(Integer::compareTo),
    Collectors.maxBy(Integer::compareTo),
    (min, max) -> new MinMax(min.orElseThrow(), max.orElseThrow())));
// MinMax[min=2, max=8]
```

---

## reduce - the three forms

`reduce` folds a stream into a single value. There are three overloads.

```java
List<Integer> nums = List.of(1, 2, 3, 4);

// 1. reduce(accumulator) -> Optional (empty stream = empty Optional)
Optional<Integer> sum1 = nums.stream().reduce((a, b) -> a + b);   // Optional[10]

// 2. reduce(identity, accumulator) -> T (identity returned for empty stream)
int sum2 = nums.stream().reduce(0, Integer::sum);                 // 10

// 3. reduce(identity, accumulator, combiner) -> U
//    Needed when result type differs from element type, esp. in PARALLEL.
int totalLength = List.of("a", "bb", "ccc").parallelStream()
    .reduce(0,
            (partial, str) -> partial + str.length(),   // accumulator (U, T) -> U
            Integer::sum);                                // combiner    (U, U) -> U
// 6
```

> **Gotcha:** The identity must be a true identity: `combiner.apply(identity, x) == x`. Using `1` as identity for a sum, or a non-associative accumulator, gives wrong results in parallel.

---

## flatMap - flatten nested structures

```java
List<List<Integer>> nested = List.of(
    List.of(1, 2), List.of(3, 4), List.of(5));

List<Integer> flat = nested.stream()
    .flatMap(List::stream)        // Stream<List<Integer>> -> Stream<Integer>
    .collect(Collectors.toList());
// [1, 2, 3, 4, 5]

// Split sentences into distinct words
List<String> sentences = List.of("hello world", "foo bar hello");
List<String> words = sentences.stream()
    .flatMap(s -> Arrays.stream(s.split(" ")))
    .distinct()
    .collect(Collectors.toList());
// [hello, world, foo, bar]
```

---

## Parallel Streams

Parallel streams split work across the common `ForkJoinPool`. Powerful but easy to misuse.

```java
long count = IntStream.rangeClosed(1, 1_000_000)
    .parallel()
    .filter(n -> n % 2 == 0)
    .count();
```

### When to use
- Large data sets (rule of thumb: 10,000+ elements)
- CPU-bound, stateless, independent operations
- A source that splits cheaply (`ArrayList`, arrays, `IntStream.range`) - `LinkedList` splits poorly

### Pitfalls
- **Stateful lambdas / shared mutable state** - data races. Never mutate a shared collection from a parallel `forEach`; use `collect` instead.
- **Ordering** - `forEach` does NOT preserve order in parallel; use `forEachOrdered` (which costs performance).
- **Non-associative reductions** - subtraction/division give nondeterministic results.
- **Blocking I/O** in tasks starves the shared `ForkJoinPool`, hurting the whole JVM.
- **Boxing overhead** - prefer `IntStream`/`LongStream` for primitives.

```java
// WRONG - shared mutable list, data race
List<Integer> result = new ArrayList<>();
IntStream.range(0, 1000).parallel().forEach(result::add);  // corrupt/exception

// RIGHT - let the framework merge
List<Integer> safe = IntStream.range(0, 1000).parallel()
    .boxed().collect(Collectors.toList());
```

> Briefly: a `Spliterator` is what lets a stream split itself (`trySplit`). Good `Spliterator`s (arrays) split evenly; poor ones (linked lists, iterators) make parallelism worthless.

---

## Custom Collector (brief)

When the built-ins do not fit, build one with `Collector.of(supplier, accumulator, combiner, finisher)`.

```java
// Equivalent to Collectors.joining(",")
Collector<String, StringBuilder, String> csv = Collector.of(
    StringBuilder::new,                                  // supplier
    (sb, s) -> sb.append(sb.length() == 0 ? "" : ",").append(s),  // accumulator
    (a, b) -> a.append(a.length() == 0 ? "" : ",").append(b),     // combiner
    StringBuilder::toString);                            // finisher

String result = Stream.of("a", "b", "c").collect(csv);  // a,b,c
```

---

## Interview Questions

### Q1: What does `Collectors.toMap` do on a duplicate key, and how do you fix it?

It throws `IllegalStateException: Duplicate key`. Supply the 3-arg overload with a merge `BinaryOperator` (e.g. `(a, b) -> a` to keep first, or `Integer::sum`). It also NPEs on a null value, unlike `HashMap.put`.

### Q2: Difference between `groupingBy` and `partitioningBy`?

`partitioningBy` takes a `Predicate` and always returns a `Map<Boolean, ...>` with both `true` and `false` keys present (even when empty). `groupingBy` takes a classifier returning any key type and only creates keys that actually occur. `partitioningBy` is more efficient for boolean splits.

### Q3: Why does `reduce` sometimes return `Optional` and sometimes a plain value?

The single-argument `reduce(accumulator)` has no identity, so an empty stream has no result - hence `Optional`. The `reduce(identity, accumulator)` form returns the identity for an empty stream, so it returns a plain value.

### Q4: What is the combiner in three-arg `reduce` for?

It merges partial results from parallel sub-tasks. It is only invoked for parallel streams (or when the accumulator and result types differ). It must be associative and consistent with the accumulator, or parallel results become wrong.

### Q5: Is the `List` returned by `Collectors.toList()` mutable? Modifiable order?

Currently it returns an `ArrayList`, but the spec guarantees neither mutability, serializability, nor a specific type. Don't rely on it. Use `toCollection(ArrayList::new)` if you need a mutable list, or `toUnmodifiableList()` for a guaranteed immutable one.

### Q6: When should you NOT use a parallel stream?

Small datasets (overhead dominates), operations with shared mutable state or order dependence, blocking I/O (starves the common pool), poorly-splitting sources like `LinkedList`, and non-associative reductions. Always benchmark - parallel is often slower.

### Q7: `Collectors.filtering` vs `stream().filter()` inside a `groupingBy`?

`stream().filter()` removes elements *before* grouping, so empty groups disappear entirely. `Collectors.filtering` (Java 9) filters *within* each group, so the group key still appears (possibly with an empty list). Use `filtering` when you want all keys retained.

### Q8: How does `teeing` help, and how many passes over the stream does it make?

`teeing` (Java 12) feeds each element to two downstream collectors and merges their results with a `BiFunction` - computing two aggregates (e.g. sum and count for an average) in a single pass over the stream.

### Q9: What thread pool do parallel streams use, and why is that risky?

The shared `ForkJoinPool.commonPool()`. Because it is shared JVM-wide, a long-running or blocking parallel task can starve every other parallel stream in the application. For isolation, submit the stream to your own `ForkJoinPool`.

### Q10: What's wrong with `parallelStream().forEach(list::add)`?

`forEach` runs concurrently and `ArrayList` is not thread-safe - this is a data race causing corruption or exceptions. Use `collect(Collectors.toList())`, or `forEachOrdered` only if you also need ordering (still not thread-safe for the add itself).

---

## Practice Code

📁 `java-prep-practice/com/prep/week3_java8/day04_streams_advanced/StreamsAdvancedDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week3_java8/day04_streams_advanced/StreamsAdvancedDemo.java
java -cp java-prep-practice com.prep.week3_java8.day04_streams_advanced.StreamsAdvancedDemo
```

---

## Checklist

- [ ] I can use `toMap` with a merge function and a map supplier
- [ ] I know `toList()` gives no mutability/type guarantee
- [ ] I can build multi-level `groupingBy` with downstream collectors
- [ ] I understand `groupingBy` vs `partitioningBy`
- [ ] I can use `mapping`, `filtering`, `counting`, `summarizingInt` as downstreams
- [ ] I know all three `reduce` forms and the role of identity/combiner
- [ ] I can use `teeing` for a single-pass dual aggregate
- [ ] I know when (and when not) to go parallel and the common pitfalls
- [ ] I can flatten nested data with `flatMap`
- [ ] I know how to assemble a custom `Collector`

---

[← Day 3: Streams Basics](day03-streams-basics.md) | [Next: Day 5 - Optional →](day05-optional.md)
