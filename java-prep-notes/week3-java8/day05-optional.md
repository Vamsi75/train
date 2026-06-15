# Day 5: Optional

A container that may or may not hold a value - the antidote to NullPointerException.

---

## Quick Definition

`Optional<T>` is a container object that explicitly models "a value that might be absent". It forces the caller to *think* about the empty case instead of silently dereferencing `null`.

| Concern | Without Optional | With Optional |
|:--------|:-----------------|:--------------|
| Absence | `null` (implicit, easy to forget) | `Optional.empty()` (explicit) |
| Failure to handle | `NullPointerException` at runtime | compiler-visible API |
| Intent | unclear | "this may have no value" |

> Optional was designed primarily as a **method return type** to signal "no result", not as a general-purpose null replacement.

---

## Creation

```java
// of - value MUST be non-null, otherwise NullPointerException immediately
Optional<String> a = Optional.of("hello");
// Optional<String> bad = Optional.of(null);  // throws NPE

// ofNullable - allows null, becomes empty
Optional<String> b = Optional.ofNullable(maybeNull());   // empty if null

// empty - explicitly no value
Optional<String> c = Optional.empty();
```

> **Rule:** use `of` when you *know* it is non-null (fail fast on a bug), `ofNullable` when it might legitimately be null.

---

## Accessing the value

```java
Optional<String> opt = Optional.of("hello");

// get() - DANGEROUS: throws NoSuchElementException if empty
String value = opt.get();

// orElse - return a default; default is ALWAYS evaluated
String v1 = opt.orElse("default");

// orElseGet - default from a Supplier; only evaluated if empty (lazy)
String v2 = opt.orElseGet(() -> expensiveDefault());

// orElseThrow - throw if empty (no-arg throws NoSuchElementException since Java 10)
String v3 = opt.orElseThrow();
String v4 = opt.orElseThrow(() -> new IllegalStateException("missing"));
```

### orElse vs orElseGet - the classic gotcha

`orElse` evaluates its argument **eagerly, every time**, even when the Optional is present. `orElseGet` invokes the supplier **only when empty**.

```java
Optional<String> present = Optional.of("value");

// createDefault() is CALLED even though present has a value!
String a = present.orElse(createDefault());     // wasteful / side-effects fire

// createDefault() is NOT called because present has a value
String b = present.orElseGet(() -> createDefault());  // lazy - preferred
```

> If the default is expensive, has side effects, or could itself throw, **always use `orElseGet`**.

---

## Transformation: map, flatMap, filter

```java
Optional<String> name = Optional.of("alice");

// map - transform the contained value; result wrapped in Optional
Optional<Integer> length = name.map(String::length);          // Optional[5]
Optional<String> upper = name.map(String::toUpperCase);       // Optional[ALICE]

// map returns empty if the function returns null (no NPE)
Optional<String> none = name.map(s -> null);                  // Optional.empty

// filter - keep value only if predicate matches, else empty
Optional<String> longName = name.filter(s -> s.length() > 3); // Optional[alice]
Optional<String> shortOnly = name.filter(s -> s.length() < 3); // Optional.empty

// flatMap - when the mapper ITSELF returns an Optional (avoid Optional<Optional<T>>)
Optional<String> upperCity = findUser("alice")   // Optional<User>
        .flatMap(User::getCity)                  // getCity returns Optional<String>
        .map(String::toUpperCase);
```

> Use `map` when the function returns a plain value, `flatMap` when it returns an `Optional` (otherwise you get nested `Optional<Optional<T>>`).

---

## Conditional actions: ifPresent, ifPresentOrElse

```java
Optional<String> opt = Optional.of("hello");

// ifPresent - run consumer only if value present
opt.ifPresent(v -> System.out.println("Got: " + v));

// ifPresentOrElse (Java 9) - present action OR empty action
opt.ifPresentOrElse(
        v -> System.out.println("Got: " + v),
        () -> System.out.println("Nothing here"));
```

### isPresent vs isEmpty

```java
if (opt.isPresent()) { ... }   // true if value present
if (opt.isEmpty())   { ... }   // Java 11+, true if empty
```

> **Anti-pattern:** `if (opt.isPresent()) { use(opt.get()); }` is just a verbose null check. Prefer `ifPresent`, `map`, or `orElse`.

---

## Optional with Streams

```java
// Optional.stream() (Java 9) - 0 or 1 element; great for flatMap to drop empties
List<String> names = List.of("alice", "bob", "carol");
List<String> cities = names.stream()
        .map(this::lookupCity)        // Stream<Optional<String>>
        .flatMap(Optional::stream)    // drops the empty ones
        .collect(Collectors.toList());

// Collecting a stream that may be empty
Optional<String> first = names.stream()
        .filter(n -> n.startsWith("z"))
        .findFirst();                 // Optional.empty here
```

---

## OptionalInt / OptionalLong / OptionalDouble

Primitive specializations avoid boxing. Note: they have **no** `map`/`filter` and use `getAsInt()` etc.

```java
OptionalInt max = IntStream.of(3, 1, 4, 1, 5).max();   // OptionalInt[5]
int value = max.getAsInt();                            // 5 (or orElse(0))

OptionalDouble avg = IntStream.rangeClosed(1, 5).average();  // OptionalDouble[3.0]
System.out.println(avg.orElse(0.0));                   // 3.0
```

---

## When NOT to use Optional

Optional is for return types signalling "no result". Misusing it adds overhead and confusion.

| Don't | Why | Do instead |
|:------|:----|:-----------|
| Optional fields | Serialization issues, extra object per field | nullable field / sensible default |
| Optional method parameters | Forces callers to wrap; overload is cleaner | overloaded methods / `@Nullable` |
| `Optional<List<T>>` / collections | Return an empty collection instead | `Collections.emptyList()` |
| `Optional<Optional<T>>` | Never; use `flatMap` | `flatMap` |
| `opt.isPresent() ? opt.get() : default` | Verbose null check | `orElse` / `orElseGet` |
| Storing Optional in a Map value | Just omit the key | leave key absent |

---

## Interview Questions

### Q1: What problem does Optional solve, and what is it NOT a silver bullet for?

It makes the *absence* of a return value explicit and forces callers to handle it, reducing accidental NPEs. It is not a general null replacement - using it for fields, parameters, or collections is an anti-pattern and can even introduce new NPEs (an Optional reference itself can be null).

### Q2: Difference between `orElse` and `orElseGet`?

`orElse(x)` evaluates `x` eagerly every call, even when the value is present. `orElseGet(supplier)` calls the supplier only when empty. Use `orElseGet` for expensive or side-effecting defaults.

### Q3: Difference between `Optional.of` and `Optional.ofNullable`?

`of(value)` throws `NullPointerException` immediately if value is null (fail-fast for "this can't be null"). `ofNullable(value)` returns empty for null. Using `of` on a possibly-null value is a common bug.

### Q4: When do you use `map` vs `flatMap`?

`map` when the mapping function returns a plain value (it auto-wraps in Optional). `flatMap` when the function already returns an `Optional`, to avoid a nested `Optional<Optional<T>>`.

### Q5: Why is calling `get()` discouraged?

It throws `NoSuchElementException` if empty - reintroducing the very failure Optional aims to prevent. Prefer `orElse`, `orElseGet`, `orElseThrow`, `map`, or `ifPresent`.

### Q6: Is `if (opt.isPresent()) opt.get()` good style?

No - it is just a verbose null check and defeats the purpose. Use `ifPresent`, `map`, or `orElse` instead. Reserve `isPresent`/`isEmpty` for cases with no cleaner functional alternative.

### Q7: Why shouldn't Optional be used as a field type?

It is not `Serializable`, adds a wrapper object per field (memory/GC), complicates frameworks (JPA, Jackson), and the field itself could be null - giving you two ways to represent absence. Use a nullable field or a default value.

### Q8: How does `Optional.stream()` help?

Introduced in Java 9, it turns an Optional into a 0-or-1 element stream. Combined with `flatMap(Optional::stream)`, it cleanly filters out empties when mapping a stream to Optionals.

### Q9: What's special about `OptionalInt`/`OptionalLong`/`OptionalDouble`?

They avoid boxing for primitive results (e.g. `IntStream.max()`). They lack `map`/`filter`/`flatMap` and use `getAsInt`/`getAsLong`/`getAsDouble`. Don't create `Optional<Integer>` when a primitive specialization exists.

### Q10: Can an `Optional` reference be null, and what does that imply?

Yes - a poorly written method can return a null `Optional`, which NPEs on the very first method call. A method returning Optional must never return null; return `Optional.empty()` instead.

---

## Practice Code

📁 `java-prep-practice/com/prep/week3_java8/day05_optional/OptionalDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week3_java8/day05_optional/OptionalDemo.java
java -cp java-prep-practice com.prep.week3_java8.day05_optional.OptionalDemo
```

---

## Checklist

- [ ] I understand Optional is primarily a return type, not a null replacement
- [ ] I know `of` vs `ofNullable` vs `empty`
- [ ] I can explain the `orElse` vs `orElseGet` evaluation difference
- [ ] I avoid `get()` and the `isPresent()/get()` anti-pattern
- [ ] I can chain `map`, `flatMap`, and `filter`
- [ ] I use `ifPresent` / `ifPresentOrElse` for side effects
- [ ] I know when NOT to use Optional (fields, params, collections)
- [ ] I can drop empties from a stream with `Optional::stream`
- [ ] I know the primitive specializations and why they exist

---

[← Day 4: Streams Advanced](day04-streams-advanced.md) | [Next: Day 6 - Date/Time API →](day06-datetime-api.md)
