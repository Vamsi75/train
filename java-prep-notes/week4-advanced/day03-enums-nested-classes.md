# Day 3: Enums & Nested/Inner Classes

Type-safe constants with behavior, plus the four flavors of nested classes and their gotchas.

---

## Quick Definition

An **enum** is a special class whose instances are a fixed set of named constants. Each constant is a `public static final` singleton of the enum type.

| Nested class type | Static? | Holds outer instance? | Typical use |
|:------------------|:--------|:----------------------|:------------|
| **Static nested** | Yes | No | Helper grouped with outer, no outer state needed |
| **Inner (non-static)** | No | Yes (implicit `Outer.this`) | Needs the enclosing instance's state |
| **Local class** | No | Yes (if in instance method) | One-off class scoped to a method |
| **Anonymous class** | No | Yes (if in instance context) | One-shot implementation of an interface/class |

---

## Enums: Fields, Constructors, Methods

```java
enum Planet {
    EARTH(5.976e24, 6.37814e6),
    MARS(6.421e23, 3.3972e6);

    private final double mass;     // fields are typically final
    private final double radius;

    Planet(double mass, double radius) {   // constructor is implicitly private
        this.mass = mass;
        this.radius = radius;
    }

    double surfaceGravity() {
        return 6.67300E-11 * mass / (radius * radius);
    }
}

double g = Planet.EARTH.surfaceGravity();
```

Enum constructors are **always private** (you cannot call `new Planet(...)`). Constants are created once, eagerly, when the enum is loaded.

---

## Constant-Specific Behavior (Abstract Methods)

Each constant can override methods - a clean replacement for `switch`:

```java
enum Operation {
    PLUS  { public int apply(int a, int b) { return a + b; } },
    MINUS { public int apply(int a, int b) { return a - b; } },
    TIMES { public int apply(int a, int b) { return a * b; } };

    public abstract int apply(int a, int b);   // each constant must implement
}

Operation.TIMES.apply(6, 7);   // 42
```

This is the **constant-specific method body** pattern - each constant becomes an anonymous subclass of the enum.

---

## Enums Implementing Interfaces

```java
interface Describable { String describe(); }

enum Status implements Describable {
    ACTIVE   { public String describe() { return "running"; } },
    INACTIVE { public String describe() { return "stopped"; } };
}
```

Enums can implement interfaces (but cannot `extends` a class - they already extend `java.lang.Enum`).

---

## EnumMap & EnumSet

Specialized, high-performance collections backed by **arrays indexed by ordinal** - far faster and smaller than `HashMap`/`HashSet` for enum keys.

```java
EnumMap<Status, Integer> counts = new EnumMap<>(Status.class);
counts.put(Status.ACTIVE, 5);

EnumSet<Status> all = EnumSet.allOf(Status.class);
EnumSet<Status> some = EnumSet.of(Status.ACTIVE);
EnumSet<Status> none = EnumSet.noneOf(Status.class);
```

`EnumMap` preserves **natural (declaration) order**, accepts no null keys, and is not synchronized. Always prefer these over generic collections for enum keys.

---

## values(), valueOf(), ordinal() - Cautions

```java
Status[] all = Status.values();        // returns a NEW array each call (defensive copy)
Status s = Status.valueOf("ACTIVE");   // throws IllegalArgumentException if not found
int pos = Status.ACTIVE.ordinal();     // 0-based position
String n = Status.ACTIVE.name();       // "ACTIVE" (the exact identifier)
```

| Pitfall | Detail |
|:--------|:-------|
| **`values()` copies** | It clones the backing array each call - cache it in a hot loop |
| **`ordinal()` is fragile** | Don't persist/serialize it - reordering or inserting constants silently shifts values. Store `name()` instead |
| **`valueOf` throws** | Unknown name -> `IllegalArgumentException`, not null |

---

## Enum Singleton Pattern

The most robust singleton in Java - serialization-safe and reflection-proof by construction:

```java
enum Registry {
    INSTANCE;
    private final Map<String, Object> data = new HashMap<>();
    public void put(String k, Object v) { data.put(k, v); }
    public Object get(String k) { return data.get(k); }
}

Registry.INSTANCE.put("key", 42);
```

The JVM guarantees a single instance even across serialization and reflection - something a hand-written singleton must work hard to achieve.

---

## Static Nested Classes

A static nested class is a top-level class scoped inside another - **no link to an outer instance**.

```java
class Outer {
    private static int counter = 0;
    static class Builder {           // no Outer instance needed
        Builder() { counter++; }      // can touch static members only
    }
}

Outer.Builder b = new Outer.Builder();   // no Outer instance required
```

Use it for helpers tightly coupled to the outer class that don't need outer instance state (e.g. `Map.Entry`).

---

## Inner (Non-Static) Classes

A non-static nested class holds an **implicit reference to its enclosing instance** (`Outer.this`).

```java
class Counter {
    private int count = 0;
    class Incrementer {              // inner class
        void bump() { count++; }      // accesses Outer's instance field directly
    }
    Incrementer make() { return new Incrementer(); }
}

Counter c = new Counter();
Counter.Incrementer inc = c.new Incrementer();   // requires an outer instance
inc.bump();
```

You instantiate it via `outerInstance.new Inner()`. It cannot declare static members (except constants).

### Memory-Leak Gotcha

Because an inner class **silently retains `Outer.this`**, an inner-class instance (e.g. a listener, `Runnable`, or `Iterator`) that outlives its outer object keeps the **entire outer object alive** - a classic Android/Swing leak. Fix: make the helper a **static nested class** and pass only what it needs, or use a `WeakReference`.

---

## Local & Anonymous Classes

```java
// Local class - declared inside a method
static Runnable makeTask(String label) {
    class Task implements Runnable {            // local class
        public void run() { System.out.println("running " + label); }
    }
    return new Task();
}

// Anonymous class - declare + instantiate in one expression
Comparator<String> byLen = new Comparator<>() {  // anonymous class
    public int compare(String a, String b) {
        return Integer.compare(a.length(), b.length());
    }
};
```

### Variable Capture

Local and anonymous classes can only capture variables that are **final or effectively final** (assigned once). The captured value is a snapshot - this is why a lambda/anonymous class can't mutate a local `int` (workaround: an array or `AtomicInteger`).

```java
int base = 10;            // effectively final
Runnable r = () -> System.out.println(base);
// base = 20;             // would break it: no longer effectively final
```

---

## When to Use Each

| Situation | Choice |
|:----------|:-------|
| Helper needs outer instance state | Inner class |
| Helper logically grouped, no outer state | Static nested class |
| One method needs a named throwaway type | Local class |
| One-shot interface/abstract impl | Anonymous class (or lambda if functional interface) |
| Functional interface, short body | **Lambda** (preferred over anonymous) |

---

## Interview Questions

### Q1: Why are enums a better singleton than a static field?

The JVM guarantees one instance per constant, even against **serialization** (no extra `readResolve`) and **reflection** (constructing an enum via reflection throws). A hand-rolled singleton must defend both manually.

### Q2: Why avoid ordinal() for persistence or business logic?

`ordinal()` is just the declaration position. Reordering constants or inserting one in the middle silently changes every later ordinal, corrupting stored data. Persist `name()` and read back with `valueOf()`.

### Q3: What is a constant-specific method body?

Each enum constant can override a method (often abstract), making each constant its own anonymous subclass. It replaces big `switch` statements with polymorphism and is checked at compile time.

### Q4: Difference between a static nested class and an inner class?

A static nested class has **no** reference to an outer instance and can be created standalone (`new Outer.Nested()`). An inner (non-static) class holds an implicit `Outer.this` and needs an outer instance (`outer.new Inner()`).

### Q5: How can an inner class cause a memory leak?

It implicitly retains the enclosing instance. If the inner-class object (listener, callback, Iterator) lives longer than the outer object, the outer object can't be garbage-collected. Use a static nested class plus explicit references, or weak references.

### Q6: Why must captured local variables be effectively final?

The local class/lambda captures a **copy** of the value (locals live on the stack and may vanish). Requiring effective finality avoids the confusion of two diverging copies and keeps the semantics consistent. Use a holder (array/AtomicInteger) to mutate.

### Q7: Can an enum extend a class or another enum?

No. Every enum implicitly extends `java.lang.Enum`, and Java has no multiple inheritance of classes. Enums **can** implement interfaces.

### Q8: Why prefer EnumMap/EnumSet over HashMap/HashSet for enum keys?

They're backed by plain arrays indexed by ordinal: O(1) with no hashing, no boxing, lower memory, and EnumMap keeps natural order. Much faster and tighter than the hash-based equivalents.

### Q9: When would you choose an anonymous class over a lambda?

When you need to implement an interface with **multiple abstract methods** (not a functional interface), capture `this` referring to the new instance, declare extra fields/state, or extend a class rather than implement an interface. Otherwise prefer a lambda.

### Q10: Are enum constructors public? Can you call new on an enum?

Constructors are implicitly **private** - you can't use `new`. Constants are instantiated once when the enum type is loaded.

---

## Practice Code

📁 `java-prep-practice/com/prep/week4_advanced/day03_enums/EnumsNestedDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week4_advanced/day03_enums/EnumsNestedDemo.java
java -cp java-prep-practice com.prep.week4_advanced.day03_enums.EnumsNestedDemo
```

---

## Checklist

- [ ] I can add fields, constructors, and methods to an enum
- [ ] I can write constant-specific (abstract) method bodies
- [ ] I know when to use EnumMap/EnumSet and why they're fast
- [ ] I understand the dangers of ordinal() and values() copying
- [ ] I can write an enum singleton and explain why it's robust
- [ ] I know the difference between static nested and inner classes
- [ ] I can explain the inner-class memory-leak gotcha
- [ ] I understand variable capture and effectively-final rules

---

[← Day 2: equals & hashCode](day02-equals-hashcode-comparable.md) | [Next: Day 4 - Concurrency Advanced →](day04-concurrency-advanced.md)
