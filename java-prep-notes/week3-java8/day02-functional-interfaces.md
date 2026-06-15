# Day 2: Functional Interfaces

The contracts behind every lambda - know the built-in toolkit cold.

---

## Quick Definition

A **functional interface** is an interface with exactly **one abstract method** (SAM). It is the target type for lambdas and method references. The `@FunctionalInterface` annotation is optional but recommended - it makes the compiler enforce the single-abstract-method rule.

```java
@FunctionalInterface
interface Calculator {
    int calc(int a, int b);   // the single abstract method

    // default & static methods DON'T count against the SAM rule
    default int twice(int a) { return calc(a, a); }
    static Calculator add() { return (a, b) -> a + b; }
}
```

| Rule | Detail |
|:-----|:-------|
| **Exactly 1 abstract method** | More than 1 → not functional → won't compile with `@FunctionalInterface` |
| **default / static methods** | Allowed, unlimited, don't count |
| **`Object` methods** | `equals`, `hashCode`, `toString` declared as abstract DON'T count |
| **Annotation** | Optional but catches mistakes at compile time |

---

## The Core Built-in Set (java.util.function)

| Interface | Abstract Method | Takes → Returns | Typical Use |
|:----------|:----------------|:----------------|:------------|
| `Function<T,R>` | `R apply(T t)` | T → R | transform/map |
| `BiFunction<T,U,R>` | `R apply(T,U)` | (T,U) → R | combine two inputs |
| `Predicate<T>` | `boolean test(T t)` | T → boolean | filter/condition |
| `BiPredicate<T,U>` | `boolean test(T,U)` | (T,U) → boolean | two-arg condition |
| `Consumer<T>` | `void accept(T t)` | T → void | side effect (print) |
| `BiConsumer<T,U>` | `void accept(T,U)` | (T,U) → void | e.g. Map.forEach |
| `Supplier<T>` | `T get()` | () → T | lazy/factory |
| `UnaryOperator<T>` | `T apply(T t)` | T → T | Function where in=out type |
| `BinaryOperator<T>` | `T apply(T,T)` | (T,T) → T | reduce/combine same type |

```java
Function<String, Integer> len = String::length;
BiFunction<Integer, Integer, Integer> add = Integer::sum;
Predicate<String> isEmpty = String::isEmpty;
Consumer<String> print = System.out::println;
Supplier<Double> rand = Math::random;
UnaryOperator<String> upper = String::toUpperCase;
BinaryOperator<Integer> max = Integer::max;

System.out.println(len.apply("hello"));   // 5
System.out.println(add.apply(2, 3));      // 5
System.out.println(isEmpty.test(""));     // true
print.accept("side effect");              // prints
System.out.println(upper.apply("hi"));    // HI
System.out.println(max.apply(4, 9));      // 9
```

> `UnaryOperator<T> extends Function<T,T>` and `BinaryOperator<T> extends BiFunction<T,T,T>` - they are just convenience specializations for the same-type case.

---

## Primitive Specializations - Why They Exist

Generics only work with objects, so `Function<Integer, Integer>` **autoboxes** on every call (int → Integer → int). For hot loops this is wasteful. The primitive specializations avoid boxing entirely.

| Generic (boxes) | Primitive (no box) | Signature |
|:----------------|:-------------------|:----------|
| `Supplier<Integer>` | `IntSupplier` | `int getAsInt()` |
| `Function<Integer,R>` | `IntFunction<R>` | `R apply(int)` |
| `Function<T,Integer>` | `ToIntFunction<T>` | `int applyAsInt(T)` |
| `Function<Integer,Integer>` | `IntUnaryOperator` | `int applyAsInt(int)` |
| `BiFunction<Integer,Integer,Integer>` | `IntBinaryOperator` | `int applyAsInt(int,int)` |
| `Predicate<Integer>` | `IntPredicate` | `boolean test(int)` |
| `Consumer<Integer>` | `IntConsumer` | `void accept(int)` |
| `Function<Integer,Double>` | `IntToDoubleFunction` | `double applyAsDouble(int)` |

(Equivalents exist for `Long` and `Double`: `LongFunction`, `DoublePredicate`, `ToLongFunction`, etc.)

```java
// Boxes 1,000,000 times - slow
Function<Integer, Integer> boxed = x -> x + 1;

// No boxing - fast, used heavily by IntStream
IntUnaryOperator unboxed = x -> x + 1;

ToIntFunction<String> length = String::length;  // returns primitive int
System.out.println(length.applyAsInt("abcd"));  // 4
```

---

## Composition - Building Pipelines

### Function: andThen vs compose

```java
Function<Integer, Integer> times2 = x -> x * 2;
Function<Integer, Integer> plus3  = x -> x + 3;

// andThen: this FIRST, then arg.  (times2 THEN plus3)
System.out.println(times2.andThen(plus3).apply(5));  // (5*2)+3 = 13

// compose: arg FIRST, then this.  (plus3 THEN times2)
System.out.println(times2.compose(plus3).apply(5));  // (5+3)*2 = 16
```

### Predicate: and / or / negate

```java
Predicate<Integer> positive = n -> n > 0;
Predicate<Integer> even     = n -> n % 2 == 0;

System.out.println(positive.and(even).test(4));    // true
System.out.println(positive.or(even).test(-2));    // true (even)
System.out.println(positive.negate().test(-5));    // true
Predicate<Integer> notPositive = Predicate.not(positive);  // Java 11+
```

### Consumer: andThen (sequences side effects)

```java
Consumer<String> log   = s -> System.out.println("LOG: " + s);
Consumer<String> store = s -> System.out.println("STORE: " + s);
log.andThen(store).accept("event");  // runs both, in order
```

> `Function.identity()` returns `t -> t` - handy as a no-op mapper (e.g. `Collectors.toMap(Function.identity(), ...)`).

---

## Custom Functional Interfaces

```java
@FunctionalInterface
interface TriFunction<A, B, C, R> {
    R apply(A a, B b, C c);

    // you can add default methods for composition
    default <V> TriFunction<A, B, C, V> andThen(Function<? super R, ? extends V> after) {
        return (a, b, c) -> after.apply(apply(a, b, c));
    }
}

TriFunction<Integer, Integer, Integer, Integer> sum3 = (a, b, c) -> a + b + c;
System.out.println(sum3.apply(1, 2, 3));  // 6
```

A custom interface that needs to throw checked exceptions is a common real-world pattern:

```java
@FunctionalInterface
interface ThrowingSupplier<T> {
    T get() throws Exception;  // lets lambdas throw checked exceptions
}
```

---

## default & static Methods in Interfaces

Java 8 added **default** (instance, inheritable, overridable) and **static** methods to interfaces. They enable interface evolution without breaking implementers and power the composition methods above.

```java
interface Greeter {
    String name();                          // abstract

    default String greet() {                // has a body, inherited
        return "Hello, " + name();
    }

    static Greeter of(String n) {           // belongs to the interface itself
        return () -> n;
    }
}

Greeter g = Greeter.of("Sam");
System.out.println(g.greet());  // Hello, Sam
```

### The diamond gotcha

If two interfaces provide the same default method, the implementing class **must override** it and can call a specific one via `Interface.super.method()`:

```java
interface A { default String hi() { return "A"; } }
interface B { default String hi() { return "B"; } }
class C implements A, B {
    public String hi() { return A.super.hi() + B.super.hi(); }  // "AB"
}
```

---

## Interview Questions

### Q1: Is `@FunctionalInterface` required to use a lambda?

No. Any interface with a single abstract method is functional and usable with a lambda (e.g. `Runnable`, `Comparator`). The annotation only asks the compiler to verify the SAM rule and document intent.

### Q2: Can a functional interface have more than one method?

It can have many default/static methods and even abstract overrides of `Object` methods (`equals`, `hashCode`, `toString`), but only **one** non-Object abstract method.

### Q3: Why do primitive specializations like `IntPredicate` exist?

To avoid autoboxing. `Predicate<Integer>` boxes every int into an Integer object on each call, creating GC pressure in tight loops. `IntPredicate` operates on raw `int` - this is why streams have `IntStream`, `mapToInt`, etc.

### Q4: Difference between `andThen` and `compose`?

Both chain Functions. `f.andThen(g)` applies `f` then `g`. `f.compose(g)` applies `g` then `f`. They're mirror images; `andThen` reads left-to-right.

### Q5: What's the difference between `Function<T,T>` and `UnaryOperator<T>`?

Functionally identical - `UnaryOperator<T> extends Function<T,T>`. It exists for readability and as the type used by APIs like `List.replaceAll`. Note a `UnaryOperator<T>` is a `Function`, but a `Function<T,T>` is NOT automatically a `UnaryOperator`.

### Q6: When would you write a custom functional interface?

When the built-ins don't fit: more than two args (`TriFunction`), methods that throw checked exceptions (`ThrowingSupplier`), or a domain-meaningful name that improves readability.

### Q7: How are default methods resolved with multiple inheritance (diamond problem)?

If two implemented interfaces have the same default method, the class must override it explicitly. Inside the override you can delegate with `InterfaceName.super.method()`. Class methods always win over interface defaults.

### Q8: `Predicate.and` short-circuits - true or false?

True. `a.and(b)` evaluates `b` only if `a` is true; `a.or(b)` evaluates `b` only if `a` is false - same short-circuit semantics as `&&`/`||`.

### Q9: What does `Function.identity()` return, and when is it useful?

It returns `t -> t`. Useful as a pass-through mapper, e.g. `Collectors.toMap(Function.identity(), String::length)` to key a map by the element itself. Note `identity()` is a distinct object, not literally `x -> x` you wrote (matters only for identity comparisons).

### Q10: Can default methods be `final` or `synchronized`?

No - interface default methods cannot be `final`, `synchronized`, or `native`. They can be overridden by implementers, which `final` would prevent.

---

## Practice Code

📁 `java-prep-practice/com/prep/week3_java8/day02_functional/FunctionalInterfaceDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week3_java8/day02_functional/FunctionalInterfaceDemo.java
java -cp java-prep-practice com.prep.week3_java8.day02_functional.FunctionalInterfaceDemo
```

---

## Checklist

- [ ] I can explain the SAM rule and what `@FunctionalInterface` enforces
- [ ] I know all 9 core built-ins and their abstract method names
- [ ] I understand why primitive specializations exist (autoboxing)
- [ ] I can compose Functions (andThen/compose) and Predicates (and/or/negate)
- [ ] I can chain Consumers with andThen
- [ ] I can write a custom functional interface (incl. throwing one)
- [ ] I understand default & static methods and the diamond problem
- [ ] I know UnaryOperator/BinaryOperator vs Function/BiFunction

---

[← Day 1: Lambda Expressions](day01-lambda-expressions.md) | [Next: Day 3 - Streams Basics →](day03-streams-basics.md)
