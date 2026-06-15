# Day 9: Modern Java (Records, Sealed, Pattern Matching)

The Java 10-21 features that make modern code concise, safe, and expressive.

---

## Quick Definition

A tour of the headline features since Java 9, **with the version each landed**. For a 4-year dev, interviewers expect you to know what they generate, their restrictions, and which version a feature became standard (vs preview).

| Feature | Version | One-liner |
|:--------|:--------|:----------|
| `var` (local type inference) | 10 | Infer local variable types |
| switch expressions | 14 | `switch` that returns a value, no fall-through |
| text blocks | 15 | Multi-line string literals `""" ... """` |
| records | 16 | Concise immutable data carriers |
| pattern matching for `instanceof` | 16 | Test + cast + bind in one |
| sealed classes/interfaces | 17 | Restrict who can extend/implement |
| record patterns | 21 | Deconstruct records in patterns |
| switch pattern matching | 21 | `case Type t ->` in switch |
| virtual threads | 21 | Cheap, JVM-scheduled threads |

> The runnable `.java` for this day uses **only Java-17 standard** features. Java 21 features (record patterns, switch pattern matching) are shown below clearly labeled.

---

## var - Local Variable Type Inference (Java 10)

```java
var message = "hello";              // String
var list = new ArrayList<String>(); // ArrayList<String>
var total = 0L;                     // long
for (var s : list) { ... }          // works in loops
```

- Compile-time only - still **statically and strongly typed**, not dynamic.
- **Restrictions:** locals only - **not** fields, method parameters, or return types; must have an initializer; can't be `null` alone (no type to infer); can't infer for lambda/array literals without target type.
- Style: use when the type is obvious from the RHS; avoid when it hurts readability.

---

## switch Expressions (Java 14)

```java
String kind = switch (day) {
    case SATURDAY, SUNDAY -> "weekend";   // multiple labels, arrow = no fall-through
    case MONDAY -> {
        var msg = "start of week";
        yield msg;                        // yield returns from a block arm
    }
    default -> "weekday";
};
```

- Arrow form = **no fall-through**, no `break` needed.
- Returns a value (an expression).
- **Exhaustiveness** is enforced for enums and sealed types - the compiler errors if a case is missing (then you may not even need `default`).
- Use `yield` to return from a `{ }` block arm.

---

## Text Blocks (Java 15)

```java
String json = """
        {
            "name": "Alice",
            "age": 30
        }""";
```

- No escaping of `"` or newlines.
- Incidental leading whitespace is stripped relative to the **closing** `"""` position.
- `\` at line end suppresses the newline; `\s` keeps a trailing space.

---

## Records (Java 16)

Immutable, transparent data carriers.

```java
record Range(int low, int high) {
    Range {                              // COMPACT canonical constructor
        if (low > high) throw new IllegalArgumentException("low must be <= high");
    }                                    // fields are assigned for you after this
    int span() { return high - low; }    // extra methods allowed
}
```

The compiler **generates** for you:
- `private final` field per component
- a **canonical constructor**
- an accessor per component (`low()`, `high()` - no `get` prefix)
- value-based `equals()`, `hashCode()`, `toString()`

**Constructor forms:**
- **Compact** (`Range { ... }`) - validate/normalize; field assignments are implicit and happen *after* the body.
- **Canonical** (full param list) - if you write it, you must assign every field.

**Restrictions:** records are `final`, cannot extend a class (they extend `java.lang.Record`), cannot declare instance fields beyond the components, but may have static fields/methods and implement interfaces.

---

## Pattern Matching for instanceof (Java 16)

```java
if (obj instanceof String s) {           // test + cast + bind
    System.out.println(s.length());      // 's' in scope only when true
} else if (obj instanceof Integer i && i > 10) {  // flow scoping with &&
    System.out.println(i);
}
```

Eliminates the redundant `(String) obj` cast. The binding variable's scope follows flow analysis.

---

## Sealed Classes & Interfaces (Java 17)

Restrict the set of permitted subtypes - perfect with records for **algebraic data types**.

```java
sealed interface Shape permits Circle, Rectangle, Triangle {}

record Circle(double radius)             implements Shape {}
record Rectangle(double w, double h)     implements Shape {}
record Triangle(double base, double h)   implements Shape {}
```

- Permitted subtypes must be `final`, `sealed`, or `non-sealed`.
- They must be in the same module (or same package if unnamed).
- Because the set is closed, the compiler can verify **exhaustive** switches with no `default`.

### Area calculation - Java 17 (instanceof patterns)

```java
static double area(Shape s) {
    if (s instanceof Circle c)         return Math.PI * c.radius() * c.radius();
    else if (s instanceof Rectangle r) return r.w() * r.h();
    else if (s instanceof Triangle t)  return 0.5 * t.base() * t.h();
    throw new IllegalStateException(); // unreachable - Shape is sealed
}
```

---

## Java 21 Preview-Graduated Features (label clearly!)

> These are **Java 21** and are *preview* in Java 17 - do **not** use them in a Java-17 build.

### Record Patterns + switch Pattern Matching (Java 21)

```java
// Java 21 - deconstruct records AND switch on type in one expression
static double area(Shape s) {
    return switch (s) {
        case Circle(double r)          -> Math.PI * r * r;   // record pattern binds r
        case Rectangle(double w, double h) -> w * h;
        case Triangle(double b, double h)  -> 0.5 * b * h;
        // no default needed: Shape is sealed -> exhaustive
    };
}
```

Compare to the Java-17 `instanceof` chain above - same logic, far less code, and compiler-checked exhaustiveness.

### Guarded patterns (Java 21)

```java
case Integer i when i > 100 -> "big";   // 'when' guard
```

---

## Helpful NullPointerException Messages (Java 14)

Since Java 14 (on by default in 15+), NPEs say **exactly which reference was null**:

```
Cannot invoke "String.length()" because "<local1>.name" is null
```

No more guessing which `.` on a chained line threw.

---

## Virtual Threads (Java 21, brief)

Lightweight threads scheduled by the JVM, not the OS - millions can run concurrently. Blocking I/O no longer wastes an OS thread.

```java
// Java 21
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    executor.submit(() -> handle(request));   // 1 virtual thread per task is fine
}
```

Write simple blocking code that scales like async - "thread-per-request" becomes cheap again.

---

## Interview Questions

### Q1: Is var dynamic typing?

No. It's compile-time **inference** - the variable has a fixed static type, just not spelled out. Java stays statically and strongly typed.

### Q2: What does a record generate, and what are its restrictions?

Generates final fields, a canonical constructor, accessors, `equals`, `hashCode`, `toString`. Restrictions: implicitly `final`, can't extend a class, no extra instance fields beyond components; can implement interfaces and have static members.

### Q3: Compact vs canonical constructor?

The compact constructor omits the parameter list and field assignments (done implicitly after the body) - ideal for validation/normalization. The canonical constructor takes all components explicitly and you must assign every field.

### Q4: Why combine sealed interfaces with records?

To model algebraic data types: a closed set of variants. The compiler then knows every case, enabling **exhaustive** switch/pattern matching without a `default`.

### Q5: What's flow scoping in instanceof patterns?

The bound variable is in scope only where the compiler can prove the `instanceof` was true - e.g. inside the `if` body, or after `&&`. This lets `obj instanceof Integer i && i > 10` work.

### Q6: Switch statement vs switch expression?

The statement form falls through (needs `break`) and produces no value; the arrow expression form has no fall-through, returns a value via `yield`, and enforces exhaustiveness for enums/sealed types.

### Q7: Two records with equal components - equal and/or same instance?

`.equals()` is `true` (value-based, generated). `==` is `false` - they're distinct objects unless you intern them.

### Q8: Which features here are NOT available in Java 17?

Record patterns, switch pattern matching, guarded `when` patterns, and virtual threads are **Java 21**. In 17 they exist only as preview features and must not be used in production builds.

### Q9: Are records truly immutable?

The components are `final`, but if a component is a mutable type (e.g. a `List`), the contents can still change. Defensive-copy in a compact constructor for deep immutability.

---

## Practice Code

📁 `java-prep-practice/com/prep/week4_advanced/day09_modern/ModernJavaDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week4_advanced/day09_modern/ModernJavaDemo.java
java -cp java-prep-practice com.prep.week4_advanced.day09_modern.ModernJavaDemo
```

---

## Checklist

- [ ] I know var is compile-time inference and its restrictions
- [ ] I can write switch expressions with arrows and yield, and know exhaustiveness
- [ ] I can use text blocks and explain whitespace stripping
- [ ] I know what records generate and their restrictions
- [ ] I can write a compact constructor for validation
- [ ] I can use instanceof pattern matching and explain flow scoping
- [ ] I can model an ADT with a sealed interface + records
- [ ] I know record patterns & switch pattern matching are Java 21
- [ ] I can name the version each feature landed in
- [ ] I understand virtual threads at a high level

---

[← Day 8: Serialization, I/O & NIO](day08-serialization-io-nio.md) | [Next: Day 10 - Design Patterns →](day10-design-patterns.md)
