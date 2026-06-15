# Day 10: Exception Handling

Handle failures gracefully - the difference between robust and fragile code!

---

## Quick Definition

An **exception** is an event that disrupts the normal flow of a program. Java uses objects (subclasses of `Throwable`) to represent these events and a `try/catch/finally` mechanism to handle them.

| Term | Meaning |
|:-----|:--------|
| **Checked** | Must be caught or declared (`throws`). Compile-time enforced. |
| **Unchecked** | `RuntimeException` & subclasses. Not enforced by compiler. |
| **Error** | Serious JVM problems (`OutOfMemoryError`). Don't catch normally. |
| **throw** | Statement that raises an exception object. |
| **throws** | Method clause declaring possible checked exceptions. |

---

## The Throwable Hierarchy

```
Throwable
├── Error                    (unchecked - do NOT catch normally)
│   ├── OutOfMemoryError
│   ├── StackOverflowError
│   └── NoClassDefFoundError
└── Exception                (checked - compiler enforced)
    ├── IOException          (checked)
    ├── SQLException         (checked)
    └── RuntimeException     (UNCHECKED - not enforced)
        ├── NullPointerException
        ├── ArrayIndexOutOfBoundsException
        ├── ClassCastException
        ├── IllegalArgumentException
        └── ArithmeticException
```

| Category | Compiler checks? | Examples | Typical cause |
|:---------|:-----------------|:---------|:--------------|
| **Error** | No | `OutOfMemoryError`, `StackOverflowError` | JVM/system - unrecoverable |
| **Checked Exception** | Yes | `IOException`, `SQLException` | External/recoverable conditions |
| **Unchecked (Runtime)** | No | `NPE`, `IllegalArgumentException` | Programming bugs |

**Key insight:** Both `Error` and `RuntimeException` are unchecked. Everything else under `Exception` is checked.

---

## Checked vs Unchecked

```java
// CHECKED - must handle or declare, else compile error
void readFile() throws IOException {       // declared
    Files.readString(Path.of("data.txt"));
}

void caller() {
    try {
        readFile();                        // forced to handle
    } catch (IOException e) {
        System.out.println("Failed: " + e.getMessage());
    }
}

// UNCHECKED - no compiler enforcement
int divide(int a, int b) {
    return a / b;   // may throw ArithmeticException - not declared
}
```

**Rule of thumb:** Use checked for recoverable conditions the caller should plan for; use unchecked for programming errors (bad arguments, illegal state). Many modern frameworks (Spring) lean heavily on unchecked exceptions.

---

## try / catch / finally

```java
try {
    int[] arr = new int[3];
    arr[5] = 10;                  // throws ArrayIndexOutOfBoundsException
} catch (ArrayIndexOutOfBoundsException e) {
    System.out.println("Caught: " + e.getMessage());
} finally {
    // ALWAYS runs - cleanup code (close resources, release locks)
    System.out.println("Finally always executes");
}
```

**Order matters:** More specific catch blocks must come before broader ones.

```java
try {
    risky();
} catch (FileNotFoundException e) {   // subclass first
    ...
} catch (IOException e) {             // superclass after - OK
    ...
}
// Reversing the order = compile error: "exception already caught"
```

---

## Multi-catch (Java 7+)

```java
try {
    process();
} catch (IOException | SQLException e) {   // single block, multiple types
    // e is effectively final - cannot reassign
    log.error("Operation failed", e);
}
```

The caught variable's static type is the common supertype. You cannot list types that have a subclass relationship (e.g., `IOException | FileNotFoundException` is a compile error).

---

## try-with-resources & AutoCloseable

```java
// Resources auto-closed in REVERSE order of declaration
try (BufferedReader br = new BufferedReader(new FileReader("file.txt"));
     PrintWriter pw = new PrintWriter("out.txt")) {

    pw.println(br.readLine());

}  // pw.close() then br.close() called automatically, even on exception
```

Any class implementing `AutoCloseable` (or `Closeable`) works:

```java
class Resource implements AutoCloseable {
    Resource()  { System.out.println("open"); }
    public void close() { System.out.println("close"); }
}

try (Resource r = new Resource()) {
    System.out.println("use");
}
// Output: open / use / close
```

**Why prefer it over finally?** It handles suppressed exceptions correctly and never leaks resources if `close()` and the body both throw.

---

## Exception Chaining (cause)

Wrap a low-level exception in a higher-level one while preserving the root cause.

```java
try {
    jdbc.query();
} catch (SQLException e) {
    // Translate to a domain exception, keep original as cause
    throw new DataAccessException("Could not load user", e);
}
```

```java
// Retrieve the cause
catch (DataAccessException e) {
    Throwable root = e.getCause();   // the original SQLException
}
```

The stack trace shows `Caused by: ...` - the root cause is never lost. Always pass the cause; **never** do `throw new RuntimeException(e.getMessage())` - it discards the stack trace.

---

## finally + return Gotchas

```java
static int tricky() {
    try {
        return 1;
    } finally {
        return 2;    // OVERRIDES the try's return -> method returns 2
    }
}
// finally with return swallows exceptions too - AVOID returning in finally!
```

```java
static int valueGotcha() {
    int x = 1;
    try {
        return x;        // value 1 is captured HERE
    } finally {
        x = 99;          // too late - does NOT affect the returned value
    }
}
// Returns 1, not 99 (primitives copied at return time)
```

```java
// finally can SWALLOW an exception
static void swallow() {
    try {
        throw new RuntimeException("original");
    } finally {
        return;          // exception silently lost!
    }
}
```

**Best practice:** Never `return`, `break`, `continue`, or `throw` from a `finally` block.

---

## Suppressed Exceptions

When the body throws AND `close()` throws, the body exception wins; the close exception is **suppressed** (attached, not lost).

```java
try (AutoCloseable a = () -> { throw new RuntimeException("close fails"); }) {
    throw new RuntimeException("body fails");
} catch (Exception e) {
    System.out.println("Primary: " + e.getMessage());          // body fails
    for (Throwable s : e.getSuppressed()) {
        System.out.println("Suppressed: " + s.getMessage());   // close fails
    }
}
```

With a plain `try/finally`, the close exception would have **masked** the original - a classic bug try-with-resources fixes.

---

## Custom Exceptions

```java
// Prefer extending RuntimeException unless caller must handle it
public class InsufficientFundsException extends RuntimeException {
    private final double shortfall;

    public InsufficientFundsException(String message, double shortfall, Throwable cause) {
        super(message, cause);          // pass cause for chaining
        this.shortfall = shortfall;
    }

    public double getShortfall() { return shortfall; }
}
```

Give custom exceptions the four standard constructors when reusable, and carry useful context (fields) rather than stuffing everything into the message.

---

## Best Practices

| Practice | Why |
|:---------|:----|
| **Don't swallow** (`catch (Exception e) {}`) | Hides bugs; at minimum log it |
| **Catch specific** types | Broad `catch (Exception)` hides unexpected failures |
| **Fail fast** | Validate arguments early (`Objects.requireNonNull`) |
| **Exception translation** | Wrap low-level in domain exceptions (keep cause) |
| **Don't use exceptions for flow control** | Expensive (stack capture) and unreadable |
| **Clean up in finally / try-with-resources** | Prevent resource leaks |
| **Never catch `Throwable`/`Error`** | You can't recover from `OutOfMemoryError` |
| **Log OR rethrow, not both** | Avoid duplicate noisy stack traces |

---

## Common Exceptions Cheat Sheet

| Exception | Trigger |
|:----------|:--------|
| `NullPointerException` | Dereferencing null (Java 14+ has helpful messages) |
| `ClassCastException` | Bad downcast `(String) anInteger` |
| `ArrayIndexOutOfBoundsException` | Index outside array bounds |
| `NumberFormatException` | `Integer.parseInt("abc")` |
| `IllegalArgumentException` | Invalid method argument |
| `IllegalStateException` | Object in wrong state for operation |
| `ConcurrentModificationException` | Modify collection during iteration |
| `ArithmeticException` | Integer `/ 0` |
| `UnsupportedOperationException` | Mutating an immutable collection |

---

## Interview Questions

### Q1: Difference between checked and unchecked exceptions?

Checked extend `Exception` (not `RuntimeException`) and are compiler-enforced - you must catch or declare them. Unchecked extend `RuntimeException` (or `Error`) and are not enforced. Use checked for recoverable external conditions, unchecked for programming bugs.

### Q2: What is the difference between `throw` and `throws`?

`throw` is a statement that actually raises an exception object (`throw new IOException()`). `throws` is a method-signature clause declaring which checked exceptions the method may propagate.

### Q3: Does `finally` always execute?

Almost always - including when `try`/`catch` returns or throws. Exceptions: `System.exit()`, JVM crash, infinite loop, or daemon thread killed. A `return` in `finally` overrides the try's return and can swallow exceptions.

### Q4: What happens if both try and finally have a `return`?

The `finally` return wins and silently discards any value or exception from `try`. This is an anti-pattern - never return from `finally`.

### Q5: What are suppressed exceptions?

In try-with-resources, if the body throws and `close()` also throws, the body exception is primary and the `close()` exception is attached via `addSuppressed()`, retrievable with `getSuppressed()`. Plain try/finally would lose the original.

### Q6: Why prefer try-with-resources over finally?

It auto-closes resources in reverse order, handles suppressed exceptions correctly, and removes boilerplate/null-checks. Plain finally can leak resources or mask the original exception.

### Q7: Can a constructor throw an exception?

Yes - constructors can declare and throw exceptions (checked or unchecked). If a constructor throws, the object is not created and is eligible for GC.

### Q8: What is exception chaining and why does it matter?

Wrapping a low-level exception as the `cause` of a higher-level one (`new XException(msg, cause)`). It preserves the root cause and full stack trace (`Caused by:`), enabling exception translation without losing diagnostics.

### Q9: Is it good to catch `Exception` or `Throwable`?

Catching `Exception` broadly hides unexpected runtime bugs - prefer specific types. Never catch `Throwable`/`Error`; `OutOfMemoryError` and `StackOverflowError` are not recoverable.

### Q10: What is the performance cost of exceptions?

Constructing an exception captures the stack trace (`fillInStackTrace`), which is expensive. Don't use exceptions for normal control flow. You can override `fillInStackTrace()` for high-frequency control-flow exceptions, but that's rarely needed.

---

## Practice Code

📁 `java-prep-practice/com/prep/week1_corejava/day10_exceptions/ExceptionDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week1_corejava/day10_exceptions/ExceptionDemo.java
java -cp java-prep-practice com.prep.week1_corejava.day10_exceptions.ExceptionDemo
```

---

## Checklist

- [ ] I can draw the Throwable/Error/Exception/RuntimeException hierarchy
- [ ] I know checked vs unchecked and when to use each
- [ ] I understand try/catch/finally ordering and multi-catch rules
- [ ] I can use try-with-resources and AutoCloseable
- [ ] I understand suppressed exceptions
- [ ] I know the finally + return gotchas
- [ ] I can write custom exceptions with chaining (cause)
- [ ] I know the difference between throw and throws
- [ ] I follow best practices (don't swallow, fail fast, translate)

---

[← Day 9: Collections Map](day09-collections-map.md) | [Next: Day 11 - Multithreading →](day11-multithreading.md)
