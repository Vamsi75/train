# Day 10: Design Patterns in Java

The GoF patterns interviewers actually ask about - in idiomatic, modern Java.

---

## Quick Definition

**Design patterns** are reusable solutions to recurring design problems. The classic 23 from the "Gang of Four" split into three groups.

| Category | Concern | Examples |
|:---------|:--------|:---------|
| **Creational** | How objects are created | Singleton, Factory Method, Abstract Factory, Builder, Prototype |
| **Structural** | How objects are composed | Adapter, Decorator, Proxy, Facade, Composite |
| **Behavioral** | How objects interact | Strategy, Observer, Template Method, Command, Iterator, State |

> Modern Java + Spring already give you many patterns for free - know which, so you don't reinvent them (see the table near the end).

---

## Creational Patterns

### Singleton

One instance, globally accessible. Three idioms, best first:

```java
// 1. ENUM - best: thread-safe, serialization-safe, reflection-proof (Effective Java)
enum Config { INSTANCE; private final Map<String,String> p = new HashMap<>(); }

// 2. Initialization-on-demand HOLDER - lazy, thread-safe via classloader guarantees
class Logger {
    private Logger() {}
    private static class Holder { static final Logger INSTANCE = new Logger(); }
    static Logger getInstance() { return Holder.INSTANCE; }
}

// 3. Double-checked locking - needs VOLATILE or you get a half-built object
class Cache {
    private static volatile Cache instance;          // volatile is mandatory
    private Cache() {}
    static Cache getInstance() {
        if (instance == null) {                      // 1st check (no lock)
            synchronized (Cache.class) {
                if (instance == null) instance = new Cache(); // 2nd check
            }
        }
        return instance;
    }
}
```

> **Why volatile in DCL?** Without it, the writing thread may publish the reference *before* the constructor finishes (instruction reordering), letting another thread see a partially-constructed object.

### Factory Method

A method decides which concrete type to create; callers depend on the interface.

```java
static Drawable create(String type) {
    return switch (type) {
        case "circle" -> new Circle();
        case "square" -> new Square();
        default -> throw new IllegalArgumentException(type);
    };
}
```

### Abstract Factory

A factory of related factories - produces **families** of objects (e.g. `WindowsUIFactory` vs `MacUIFactory`, each making matching buttons + checkboxes).

### Builder

Fluent construction for objects with many optional fields - avoids telescoping constructors.

```java
HttpRequest req = new HttpRequest.Builder("https://api.example.com")
        .method("POST")
        .header("Accept", "application/json")
        .body("{...}")
        .build();
```

### Prototype

Create new objects by **copying** an existing instance (`clone()` or a copy constructor) when construction is expensive.

---

## Structural Patterns

### Adapter

Wrap an incompatible interface to match what the client expects (e.g. `InputStreamReader` adapts bytes to chars).

### Decorator

Add behavior by wrapping, not subclassing - composable at runtime. `java.io` streams are the classic JDK example.

```java
Coffee order = new MilkDecorator(new SugarDecorator(new SimpleCoffee()));
order.cost();         // 2.00 + 0.25 + 0.50
```

### Proxy

A stand-in that controls access (lazy init, caching, security, remoting). Java has **dynamic proxies**:

```java
Foo proxy = (Foo) Proxy.newProxyInstance(
        loader, new Class[]{Foo.class},
        (p, method, args) -> { /* before */ return method.invoke(target, args); });
```

This (and CGLIB) is exactly how **Spring AOP / @Transactional** works.

### Facade

A single simplified interface over a complex subsystem (e.g. a `OrderService` hiding inventory + payment + shipping).

### Composite

Treat individual objects and compositions uniformly via a common interface (e.g. files & folders, UI component trees).

---

## Behavioral Patterns

### Strategy

Encapsulate interchangeable algorithms. In modern Java a strategy is usually a **lambda / functional interface / `Comparator`**, not a class hierarchy.

```java
Comparator<String> byLength = Comparator.comparingInt(String::length);
list.sort(byLength);                       // swap strategy at runtime

PricingStrategy blackFriday = price -> price * 0.5;  // custom @FunctionalInterface
```

### Observer

Subject notifies registered observers on change - the basis of listeners and Spring events.

```java
station.subscribe(temp -> display.show(temp));  // observers as lambdas
station.setTemperature(25);                      // pushes to all observers
```

### Template Method

A base class defines the algorithm skeleton and defers steps to subclasses (`abstract` hook methods). E.g. `AbstractList`, Spring's `JdbcTemplate`.

### Command

Encapsulate a request as an object - enables queues, undo/redo, logging. `Runnable` is a command.

### Iterator

Sequential access without exposing internals - `java.util.Iterator` / the for-each loop.

### State

An object changes behavior when its internal state changes, delegating to state objects (e.g. a `Connection` that's `Open`/`Closed`).

---

## Patterns Java / Spring Already Give You

| Pattern | You get it from |
|:--------|:----------------|
| **Singleton** | Spring beans (default singleton scope), enums |
| **Proxy** | Spring AOP, `@Transactional`, JDK dynamic proxies / CGLIB |
| **Iterator** | `java.util.Iterator`, for-each |
| **Strategy** | Lambdas, `Comparator`, functional interfaces |
| **Observer** | `ApplicationEvent`/`@EventListener`, `PropertyChangeListener` |
| **Template Method** | `JdbcTemplate`, `RestTemplate`, `AbstractList` |
| **Factory** | `BeanFactory`, `Calendar.getInstance()`, `LoggerFactory` |
| **Decorator** | `java.io` streams, `Collections.unmodifiableList(...)` |
| **Builder** | `StringBuilder`, `HttpRequest.newBuilder()`, `Stream.Builder` |

---

## Interview Questions

### Q1: What's the best way to implement a Singleton and why?

An `enum` with a single constant - the JVM guarantees one instance, it's thread-safe, serialization-safe, and immune to reflection attacks. The initialization-on-demand holder idiom is the best class-based lazy option.

### Q2: Why is volatile required in double-checked locking?

Without `volatile`, the constructor's writes can be reordered after the reference is published, so another thread may observe a non-null but partially-constructed object. `volatile` enforces the happens-before ordering.

### Q3: Factory Method vs Abstract Factory?

Factory Method creates **one** product via a method/subclass. Abstract Factory creates **families** of related products through a factory interface with multiple creation methods.

### Q4: When use Builder over a constructor?

When there are many parameters, especially optional ones, or you want immutable objects and readable call sites. It avoids telescoping constructors and ambiguous positional args.

### Q5: Decorator vs Proxy vs Adapter - all wrap an object, what differs?

Intent. **Decorator** adds responsibilities. **Proxy** controls access (lazy/security/remote) with the same interface. **Adapter** changes the interface to a different one the client expects.

### Q6: How does Strategy look in modern Java?

Usually just a lambda implementing a functional interface (or a `Comparator`). No need for a class per algorithm - pass behavior as a value and swap it at runtime.

### Q7: Where does Spring use the Proxy pattern?

In AOP: `@Transactional`, `@Cacheable`, `@Async` etc. are implemented by wrapping your bean in a JDK dynamic proxy (interface-based) or CGLIB subclass (class-based) that runs advice around your method.

### Q8: Template Method vs Strategy?

Template Method uses **inheritance** - the base class fixes the algorithm and subclasses override steps. Strategy uses **composition** - you inject the whole algorithm as an object/lambda. Prefer composition (Strategy) for flexibility.

### Q9: Is the Observer pattern still relevant given lambdas/events?

Yes - the concept underpins event systems, reactive streams, and UI listeners. Modern code just expresses observers as lambdas and often uses framework event buses instead of hand-rolled subject lists.

---

## Practice Code

📁 `java-prep-practice/com/prep/week4_advanced/day10_patterns/DesignPatternsDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week4_advanced/day10_patterns/DesignPatternsDemo.java
java -cp java-prep-practice com.prep.week4_advanced.day10_patterns.DesignPatternsDemo
```

---

## Checklist

- [ ] I can implement Singleton three ways and explain volatile in DCL
- [ ] I know Factory Method vs Abstract Factory
- [ ] I can write a fluent Builder and say when to use it
- [ ] I understand Prototype (copy-based creation)
- [ ] I can distinguish Decorator, Proxy, and Adapter by intent
- [ ] I know Facade and Composite
- [ ] I can implement Strategy with a lambda and Observer with listeners
- [ ] I know Template Method vs Strategy (inheritance vs composition)
- [ ] I understand Command, Iterator, and State
- [ ] I can name which patterns Java/Spring provide out of the box

---

[← Day 9: Modern Java](day09-modern-java.md) | [Back to Week 4 index](index.md)
