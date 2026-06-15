# Day 1: Generics

Type-safe code without casts - and the type-erasure traps every interviewer asks about.

---

## Quick Definition

**Generics** let you parameterize types so the compiler enforces type safety and removes the need for casts. They are a **compile-time** feature - at runtime the type information is **erased**.

| Concept | Syntax | Meaning |
|:--------|:-------|:--------|
| **Generic class** | `class Box<T>` | Type parameter on a class |
| **Generic method** | `<T> T pick(T a, T b)` | Type parameter on a method |
| **Bounded type** | `<T extends Number>` | T must be Number or subtype |
| **Multiple bounds** | `<T extends A & B>` | T satisfies A and B |
| **Upper-bounded wildcard** | `List<? extends Number>` | Producer (read-only) |
| **Lower-bounded wildcard** | `List<? super Integer>` | Consumer (write) |
| **Unbounded wildcard** | `List<?>` | Unknown type |

---

## Why Generics?

Before generics, collections held `Object` and required casts that failed at runtime:

```java
// Pre-generics: unsafe
List list = new ArrayList();
list.add("hello");
list.add(42);                       // No compile error
String s = (String) list.get(1);    // ClassCastException at RUNTIME

// With generics: safe
List<String> safe = new ArrayList<>();
safe.add("hello");
// safe.add(42);                    // COMPILE ERROR - caught early
String t = safe.get(0);             // No cast needed
```

Benefits: **compile-time type checking**, **no explicit casts**, **self-documenting APIs**, and enabling generic algorithms.

---

## Generic Classes & Methods

```java
// Generic class
class Box<T> {
    private T value;
    public void set(T value) { this.value = value; }
    public T get() { return value; }
}

Box<String> box = new Box<>();
box.set("hi");
String s = box.get();   // no cast

// Generic method - type inferred from arguments
static <T> T firstOf(List<T> list) {
    return list.get(0);
}

// Multiple type params
static <K, V> Map.Entry<K, V> pair(K k, V v) {
    return Map.entry(k, v);
}

// Explicit type witness (rarely needed)
List<String> empty = Collections.<String>emptyList();
```

The type parameter on a generic **method** is declared **before the return type** (`<T> T method(...)`) and is independent of any class-level type parameter.

---

## Bounded Type Parameters

```java
// Upper bound: T must be Comparable to itself
static <T extends Comparable<T>> T max(List<T> list) {
    T best = list.get(0);
    for (T item : list) {
        if (item.compareTo(best) > 0) best = item;
    }
    return best;
}

// Multiple bounds: class first, then interfaces, joined by &
static <T extends Number & Comparable<T>> T clampMin(T v, T floor) {
    return v.compareTo(floor) < 0 ? floor : v;
}
```

**Rules for multiple bounds:** at most one of the bounds may be a class, and if present it must be listed **first**. The rest are interfaces.

---

## Wildcards & PECS

`PECS` = **Producer Extends, Consumer Super**. Use `? extends T` when you only **read** (produce) `T`, and `? super T` when you only **write** (consume) `T`.

```java
// Producer: we READ Numbers out of the list -> extends
static double sum(List<? extends Number> nums) {
    double total = 0;
    for (Number n : nums) total += n.doubleValue();
    // nums.add(1);  // COMPILE ERROR - can't add to ? extends
    return total;
}

// Consumer: we WRITE Integers into the list -> super
static void fill(List<? super Integer> dst, int count) {
    for (int i = 0; i < count; i++) dst.add(i);
    // Integer x = dst.get(0);  // COMPILE ERROR - only reads Object
}

List<Integer> ints = List.of(1, 2, 3);
List<Double> dbls = List.of(1.5, 2.5);
sum(ints);                      // OK
sum(dbls);                      // OK - both are ? extends Number

List<Number> nums = new ArrayList<>();
fill(nums, 3);                  // OK - Number is super of Integer
List<Object> objs = new ArrayList<>();
fill(objs, 3);                  // OK - Object is super of Integer
```

The canonical example is `Collections.copy(List<? super T> dest, List<? extends T> src)` - destination is the consumer, source is the producer.

| Wildcard | Can read as | Can add | Use for |
|:---------|:------------|:--------|:--------|
| `List<? extends T>` | `T` | only `null` | Producer / read |
| `List<? super T>` | `Object` | `T` and subtypes | Consumer / write |
| `List<?>` | `Object` | only `null` | Type-agnostic ops (size, clear) |

---

## Type Erasure & Its Consequences

At compile time, type parameters are **erased**: replaced by their first bound (or `Object` if unbounded), and casts are inserted as needed. `List<String>` and `List<Integer>` are the **same class** `List` at runtime.

```java
List<String> ls = new ArrayList<>();
List<Integer> li = new ArrayList<>();
System.out.println(ls.getClass() == li.getClass());  // true!
```

### Consequences

```java
class Holder<T> {
    // T[] arr = new T[10];                 // ERROR: generic array creation
    // boolean isT(Object o){ return o instanceof T; }  // ERROR: illegal instanceof

    // Can't instantiate type param
    // T t = new T();                       // ERROR

    // Can't have a static field of type T
    // static T shared;                     // ERROR
}

// Can't overload on erasure - both erase to process(List)
// void process(List<String> s) {}
// void process(List<Integer> i) {}        // ERROR: same erasure

// instanceof must use unbounded wildcard
List<?> raw = new ArrayList<String>();
if (raw instanceof List<?>) { /* OK */ }
```

**Bridge methods:** when a generic class is subclassed/implemented, the compiler synthesizes a bridge method to preserve polymorphism after erasure. Example: `Comparable<T>.compareTo(T)` erases to `compareTo(Object)`, so the compiler generates a bridge `compareTo(Object)` that casts and calls your `compareTo(MyType)`.

### Reifiable vs Non-Reifiable

A type is **reifiable** if its full type information is available at runtime. `String`, `int[]`, `List` (raw), `List<?>` are reifiable. `List<String>`, `List<? extends Number>`, `T` are **non-reifiable**. You can only create arrays of reifiable types - that is why `new T[]` and `new List<String>[]` are illegal.

---

## Heap Pollution & @SafeVarargs

**Heap pollution**: when a variable of a parameterized type refers to an object that is not of that type. Generic varargs (`T...`) create a hidden `T[]` array, which is non-reifiable, so the compiler warns.

```java
@SafeVarargs   // suppress "unchecked generic array" warning - assert you don't pollute
static <T> List<T> listOf(T... items) {
    return new ArrayList<>(Arrays.asList(items));
}

// DANGEROUS pattern that @SafeVarargs must NOT hide:
static <T> T[] toArray(T... args) { return args; }   // leaks the T[]
static <T> T[] pick(T a, T b) {
    return toArray(a, b);   // creates Object[] - ClassCastException later
}
```

`@SafeVarargs` is only legal on `static`, `final`, or `private` methods (Java 9+: also `private`), because such methods cannot be overridden in an unsafe way.

---

## Recursive Generics & Advanced Patterns

```java
// Recursive bound - "self type" pattern (e.g., enums, builders)
abstract class Node<T extends Node<T>> {
    T next;
    @SuppressWarnings("unchecked")
    T self() { return (T) this; }
}

// Enum is the classic recursive generic: Enum<E extends Enum<E>>
enum Color { RED, GREEN }   // Color extends Enum<Color>

// Generic builder using self-type
static class Builder<T extends Builder<T>> {
    @SuppressWarnings("unchecked")
    T name(String n) { /* ... */ return (T) this; }
}
```

---

## Common Compile Errors

| Error | Cause | Fix |
|:------|:------|:----|
| `generic array creation` | `new T[n]` or `new List<String>[n]` | Use `(T[]) new Object[n]` or `List<List<String>>` |
| `incompatible types` on `add` to `? extends` | Adding to a producer | Use `? super` if you must add |
| `name clash: same erasure` | Overload on `List<A>` / `List<B>` | Rename methods |
| `unchecked cast` warning | Casting to parameterized type | `@SuppressWarnings("unchecked")` after verifying |
| `cannot select from a type variable` | `T.class`, `new T()`, `T.staticMethod()` | Pass `Class<T>` token |

---

## Interview Questions

### Q1: What is type erasure and why does Java use it?

The compiler removes generic type info, replacing type params with their bound (or `Object`) and inserting casts. Java did this for **backward compatibility** - pre-generics bytecode and libraries keep working, and generics added no runtime overhead.

### Q2: Why can't you create `new T[]`?

Arrays are **covariant and reified** (they check their element type at runtime), but `T` is erased so the JVM can't perform the store check. The workaround is `(T[]) new Object[n]` (with an unchecked-cast warning) or passing a `Class<T>` and using `Array.newInstance`.

### Q3: Explain PECS.

Producer Extends, Consumer Super. If a structure **produces** values you read, use `? extends T` (you can read `T`, not write). If it **consumes** values you write, use `? super T` (you can write `T`, read only `Object`). It maximizes API flexibility while staying type-safe.

### Q4: Difference between `List<Object>`, `List<?>`, and a raw `List`?

`List<Object>` accepts any Object and you can add to it, but `List<String>` is NOT a `List<Object>`. `List<?>` accepts any parameterization but you can only add `null`. Raw `List` opts out of generics entirely - it compiles with warnings and is unsafe.

### Q5: Can you overload two methods that differ only in generic type? (e.g. `f(List<String>)` and `f(List<Integer>)`)

No. Both erase to `f(List)`, giving a "same erasure" compile error.

### Q6: What is a bridge method?

A synthetic method the compiler generates to preserve polymorphism after erasure. When you implement `Comparable<MyType>`, your `compareTo(MyType)` doesn't override the erased `compareTo(Object)`, so the compiler adds a bridge `compareTo(Object)` that casts and delegates.

### Q7: What is heap pollution and how does @SafeVarargs relate?

Heap pollution is when a parameterized reference points to an object of the wrong type, typically through generic varargs (which create a non-reifiable `T[]`). `@SafeVarargs` suppresses the warning when you assert the method doesn't leak or misuse that array.

### Q8: Are generics covariant? Is `List<String>` a `List<Object>`?

No - generics are **invariant**. `List<String>` is NOT a subtype of `List<Object>` (unlike arrays, where `String[]` IS an `Object[]`). This invariance is what prevents the runtime `ArrayStoreException` problem that arrays have. Use wildcards to get controlled variance.

### Q9: Why can't a static field be of a type parameter `T`?

Type parameters belong to instances - each `new Box<String>()` vs `new Box<Integer>()` would need its own `T`. A static field is shared across all instances, so there is no single `T`. Hence `static T field;` is illegal (static generic *methods* with their own `<T>` are fine).

### Q10: Can you use `instanceof` with a generic type?

Only with an unbounded wildcard: `o instanceof List<?>`. You cannot write `o instanceof List<String>` or `o instanceof T` because that info is erased at runtime.

---

## Practice Code

📁 `java-prep-practice/com/prep/week4_advanced/day01_generics/GenericsDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week4_advanced/day01_generics/GenericsDemo.java
java -cp java-prep-practice com.prep.week4_advanced.day01_generics.GenericsDemo
```

---

## Checklist

- [ ] I can explain why generics exist (type safety, no casts)
- [ ] I can write generic classes and generic methods
- [ ] I understand bounded and multiple-bounded type parameters
- [ ] I can apply PECS and choose the right wildcard
- [ ] I understand type erasure and its consequences
- [ ] I know what reifiable vs non-reifiable means
- [ ] I can explain bridge methods and the "same erasure" rule
- [ ] I understand heap pollution and @SafeVarargs

---

[← Day 6: Date/Time API](../week3-java8/day06-datetime-api.md) | [Next: Day 2 - equals & hashCode →](day02-equals-hashcode-comparable.md)
