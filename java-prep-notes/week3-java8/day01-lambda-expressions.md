# Day 1: Lambda Expressions

Anonymous functions that turbo-charged Java 8 - the foundation of everything functional.

---

## Quick Definition

A **lambda expression** is a short block of code that takes parameters and returns a value. It is an instance of a **functional interface** (an interface with exactly one abstract method - SAM).

```java
// Anonymous class (pre-Java 8)
Runnable r1 = new Runnable() {
    public void run() { System.out.println("Hello"); }
};

// Lambda (Java 8+) - same thing, less ceremony
Runnable r2 = () -> System.out.println("Hello");
```

| Concept | Meaning |
|:--------|:--------|
| **Functional interface** | Interface with exactly 1 abstract method |
| **SAM** | Single Abstract Method - what a lambda implements |
| **Target type** | The functional interface a lambda is assigned to |
| **Capture** | Lambda reading variables from enclosing scope |
| **Effectively final** | Variable not reassigned after init - required for capture |

> A lambda is **NOT** an object of an anonymous class. There is no `.class` file generated per lambda; the compiler uses `invokedynamic`.

---

## Syntax Variations

```java
// 1. No params
Runnable r = () -> System.out.println("run");

// 2. One param - parentheses optional
Consumer<String> c = s -> System.out.println(s);
Consumer<String> c2 = (s) -> System.out.println(s);

// 3. Multiple params
Comparator<Integer> cmp = (a, b) -> a - b;

// 4. Explicit types (rarely needed - target typing infers them)
Comparator<Integer> cmp2 = (Integer a, Integer b) -> a - b;

// 5. Block body - needs explicit return
Comparator<Integer> cmp3 = (a, b) -> {
    int diff = a - b;
    return diff;
};

// 6. var in params (Java 11+) - lets you add annotations
BiFunction<Integer, Integer, Integer> add = (var a, var b) -> a + b;
```

**Rules:**
- Single expression body → no braces, no `return`, value is implicit result.
- Block body `{ }` → must use `return` explicitly (unless return type is `void`).
- You cannot mix: either ALL params have explicit types, or NONE do (mixing `var` follows the same all-or-nothing rule).

---

## Lambda vs Anonymous Class - INTERVIEW FAVORITE!

| Feature | Lambda | Anonymous Class |
|:--------|:-------|:----------------|
| **`this` reference** | Enclosing instance | The anonymous instance itself |
| **Compiles to** | `invokedynamic` (no extra class) | A separate `Outer$1.class` |
| **Can have state/fields** | No | Yes |
| **Can be a class/abstract impl** | No - only functional interfaces | Yes - any class or interface |
| **Shadowing variables** | Cannot shadow enclosing locals | Can declare same-name locals |

### The `this` gotcha

```java
public class Widget {
    private String name = "Widget";

    void demo() {
        // Lambda: 'this' = the Widget instance
        Runnable lambda = () -> System.out.println(this.name);  // "Widget"

        // Anonymous class: 'this' = the Runnable instance, NOT Widget
        Runnable anon = new Runnable() {
            public void run() {
                // this.name would NOT compile (Runnable has no 'name')
                System.out.println(Widget.this.name);  // need qualified outer this
            }
        };
    }
}
```

---

## Variable Capture & Effectively-Final

A lambda can read local variables from the enclosing scope, but only if they are **final or effectively final** (never reassigned after initialization).

```java
int factor = 2;             // effectively final - OK
Function<Integer, Integer> f = x -> x * factor;
// factor = 3;              // COMPILE ERROR - now factor is not effectively final

// Workaround for "mutable" capture: use an array or AtomicInteger
int[] counter = {0};
Runnable inc = () -> counter[0]++;   // captures the reference, mutates contents - legal
```

**Why the restriction?** Local variables live on the stack and die when the method returns. The lambda may outlive the method, so the value is **copied** into the lambda. To avoid confusing aliasing bugs, Java forbids reassignment.

> Instance and static fields are **not** subject to this rule - they can be freely mutated because the lambda captures `this`, not a copy.

---

## Target Typing

The same lambda can mean different things depending on the **target type** (the interface it is assigned to). The compiler infers types from context.

```java
// Same syntax, different functional interfaces
Runnable r = () -> System.out.println("hi");          // void, no args
Callable<String> c = () -> "hi";                      // returns String, throws

interface IntOp { int apply(int x); }
interface DoubleOp { double apply(double x); }
IntOp i = x -> x + 1;        // x is int
DoubleOp d = x -> x + 1;     // x is double - same code!

// A lambda cannot stand alone - it needs a target:
// var x = () -> 42;         // COMPILE ERROR - no target type for var
Object o = (Runnable) () -> {};  // cast provides the target
```

---

## Method References - All 4 Kinds

When a lambda just calls an existing method, replace it with a `::` method reference.

| Kind | Syntax | Lambda equivalent |
|:-----|:-------|:------------------|
| **Static** | `Integer::parseInt` | `s -> Integer.parseInt(s)` |
| **Instance of particular object** | `System.out::println` | `s -> System.out.println(s)` |
| **Instance of arbitrary object (of a type)** | `String::toUpperCase` | `s -> s.toUpperCase()` |
| **Constructor** | `ArrayList::new` | `() -> new ArrayList<>()` |

```java
// 1. Static method
Function<String, Integer> parse = Integer::parseInt;

// 2. Bound instance method (specific object)
PrintStream out = System.out;
Consumer<String> printer = out::println;

// 3. Unbound instance method (first arg becomes the receiver)
Function<String, String> upper = String::toUpperCase;  // s.toUpperCase()
upper.apply("hi");   // "HI"

// 4. Constructor reference
Supplier<List<String>> maker = ArrayList::new;
Function<Integer, int[]> arrMaker = int[]::new;        // array constructor
```

### Tricky #3 - the arbitrary-object kind

`String::compareTo` is a `Comparator<String>` because the unbound instance method takes the receiver as the FIRST parameter and the method arg as the SECOND:

```java
Comparator<String> byLen = String::compareTo;  // (a, b) -> a.compareTo(b)
```

---

## invokedynamic (brief)

Lambdas are **not** compiled into anonymous inner-class files at compile time. Instead:

1. `javac` emits an `invokedynamic` bytecode instruction with a bootstrap method (`LambdaMetafactory`).
2. On **first execution**, the JVM links the call site, generating the implementation class at runtime.
3. This means lazy class loading, smaller jars, and the JVM can optimize/share instances (e.g. stateless lambdas are cached as singletons).

> Practical takeaway: a stateless `() -> {}` lambda may return the **same instance** every time, while `new Runnable(){}` always creates a new object.

---

## Gotchas

```java
// 1. Lambdas are NOT closures over mutable state - capture is by value
// (see effectively-final section)

// 2. Checked exceptions: a lambda must satisfy the SAM's throws clause.
//    Runnable.run() throws nothing, so:
// Runnable r = () -> Thread.sleep(100);   // COMPILE ERROR (InterruptedException)

// 3. Overload ambiguity - if a method has both Runnable and Callable overloads,
//    () -> doSomething() may be ambiguous; cast to disambiguate.

// 4. 'this' inside a lambda refers to the enclosing instance, not the lambda.

// 5. Returning from a lambda returns from the LAMBDA, not the enclosing method.
//    list.forEach(x -> { if (x == 5) return; });  // 'return' = continue, not break
```

---

## Interview Questions

### Q1: Is a lambda just syntactic sugar for an anonymous class?

No. They behave similarly but compile differently. Anonymous classes generate a separate `.class` file and `this` refers to the anonymous instance. Lambdas use `invokedynamic`/`LambdaMetafactory`, generate no compile-time class, and `this` refers to the enclosing instance.

### Q2: Why must captured local variables be effectively final?

Locals live on the stack and are gone after the method returns, but the lambda may outlive it. Java copies the value into the lambda. Forbidding reassignment prevents ambiguity about which value the lambda "sees" and avoids the JS-style closure bug.

### Q3: How do you mutate a captured variable then?

You can't reassign the variable, but you can mutate the object it points to: use a single-element array, an `AtomicInteger`, or a field. Fields aren't bound by the effectively-final rule because the lambda captures `this`.

### Q4: What does `this` refer to inside a lambda?

The enclosing instance (the class where the lambda is written), not the lambda itself. In an anonymous class, `this` is the anonymous instance.

### Q5: Can a lambda implement any interface?

No - only a **functional interface** (exactly one abstract method). Default and static methods don't count toward the SAM count. You cannot use a lambda for an abstract class.

### Q6: What is target typing? Why can't you do `var x = () -> 42;`?

A lambda has no type by itself; its type is inferred from the context (the functional interface it's assigned to). `var` has no target type to infer from, so the compiler can't decide which functional interface the lambda implements - compile error.

### Q7: Explain the four kinds of method references.

Static (`Integer::parseInt`), bound instance (`obj::method` - receiver fixed), unbound instance (`Type::method` - receiver is the first lambda arg), and constructor (`Type::new`). The unbound kind is the trickiest: `String::length` becomes `s -> s.length()`.

### Q8: Why might `() -> {}` return the same object twice but `new Runnable(){}` not?

Stateless lambdas capture nothing, so the JVM (via LambdaMetafactory) can cache and reuse a single instance. Anonymous class instantiation always allocates a new object.

### Q9: Can a lambda throw a checked exception?

Only if the functional interface's abstract method declares it in its `throws` clause. `Runnable.run()` declares none, so `Thread.sleep()` inside a `Runnable` won't compile. `Callable.call()` declares `throws Exception`, so it can.

### Q10: What does `return` do inside `list.forEach(x -> {...return;...})`?

It returns from the lambda for that one element (acts like `continue`), not from the enclosing method and not as a `break`. You cannot break out of a `forEach` with `return`.

---

## Practice Code

📁 `java-prep-practice/com/prep/week3_java8/day01_lambda/LambdaDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week3_java8/day01_lambda/LambdaDemo.java
java -cp java-prep-practice com.prep.week3_java8.day01_lambda.LambdaDemo
```

---

## Checklist

- [ ] I can write all lambda syntax variations (no-arg, single, multi, block body)
- [ ] I can explain lambda vs anonymous class (this, invokedynamic, state)
- [ ] I understand effectively-final capture and how to "mutate" captured state
- [ ] I understand target typing and why `var x = () -> ...` fails
- [ ] I can name and write all 4 kinds of method references
- [ ] I know the unbound instance method reference gotcha
- [ ] I know lambdas use invokedynamic, not generated inner classes
- [ ] I understand checked exceptions and `return` inside a lambda

---

[← Day 12: ExecutorService](../week1-corejava/day12-executorservice.md) | [Next: Day 2 - Functional Interfaces →](day02-functional-interfaces.md)
