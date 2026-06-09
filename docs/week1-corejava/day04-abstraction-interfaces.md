---
layout: default
title: Day 4 - Abstraction & Interfaces
parent: Week 1-2 Core Java
nav_order: 4
---

# Day 4: Abstraction & Interfaces
{: .fs-8 }

Hiding implementation details and achieving loose coupling.
{: .fs-5 .fw-300 }

---

## Quick Definition

**Abstraction** is hiding implementation details and showing only essential features. **Abstract classes** provide partial abstraction with some implementation. **Interfaces** provide complete abstraction with only method declarations (before Java 8).

| Concept | Purpose | Example |
|:--------|:--------|:--------|
| **Abstraction** | Hide complexity | Payment processing |
| **Abstract Class** | Partial abstraction | Base class with common code |
| **Interface** | Complete abstraction | Contract for implementation |
| **Multiple Inheritance** | Via interfaces only | class X implements A, B |

---

## Abstract Class

A class declared with `abstract` keyword that **cannot be instantiated** and may contain abstract methods.

```java
abstract class Animal {
    String name;  // Concrete field

    // Concrete method (has implementation)
    public void sleep() {
        System.out.println(name + " is sleeping");
    }

    // Abstract method (no implementation)
    public abstract void makeSound();
}

class Dog extends Animal {
    @Override
    public void makeSound() {
        System.out.println("Dog barks");
    }
}

// Cannot do this:
// Animal animal = new Animal();  // ERROR!

// Must do this:
Animal animal = new Dog();  // OK
animal.makeSound();
```

### Abstract Class Rules

| Rule | Description |
|:-----|:------------|
| Cannot instantiate | `new AbstractClass()` not allowed |
| Can have constructors | Called by child class |
| Can have concrete methods | With full implementation |
| Can have abstract methods | Must be implemented by child |
| Can have fields | Both static and instance |
| Can have final methods | Cannot be overridden |
| 0-100% abstraction | Mix of abstract and concrete |

---

## Interface

A **contract** that defines what a class must do, not how it does it.

```java
interface Payment {
    // Abstract method (implicitly public abstract)
    void processPayment(double amount);

    // All methods are public abstract by default
    boolean validatePayment();
}

class CreditCardPayment implements Payment {
    @Override
    public void processPayment(double amount) {
        System.out.println("Processing $" + amount + " via Credit Card");
    }

    @Override
    public boolean validatePayment() {
        return true;
    }
}
```

### Interface Rules (Java 7 and earlier)

| Rule | Description |
|:-----|:------------|
| All methods abstract | No implementation |
| All fields `public static final` | Constants only |
| Cannot instantiate | `new Interface()` not allowed |
| Multiple inheritance | `class X implements A, B, C` |
| 100% abstraction | Complete contract |

---

## Java 8+ Interface Features

### Default Methods

Provide default implementation in interface.

```java
interface Vehicle {
    void start();  // Abstract method

    // Default method (Java 8+)
    default void stop() {
        System.out.println("Vehicle stopped");
    }
}

class Car implements Vehicle {
    @Override
    public void start() {
        System.out.println("Car started");
    }

    // Can optionally override default method
    // stop() implementation inherited
}
```

### Static Methods

Utility methods in interface.

```java
interface MathOperations {
    static int add(int a, int b) {
        return a + b;
    }
}

// Call via interface name
int result = MathOperations.add(5, 3);
```

---

## Abstract Class vs Interface

| Feature | Abstract Class | Interface |
|:--------|:--------------|:----------|
| **Keyword** | `abstract class` | `interface` |
| **Methods** | Abstract + Concrete | Abstract (default/static in Java 8+) |
| **Fields** | Any type | `public static final` only |
| **Constructor** | Yes | No |
| **Multiple Inheritance** | No (single extends) | Yes (multiple implements) |
| **Access Modifiers** | Any | Public only |
| **When to use** | IS-A relationship + shared code | CAN-DO behavior contract |

---

## When to Use What?

### Use Abstract Class when:
- Classes share **common code**
- Need **constructors**
- Need **non-public members**
- True **IS-A relationship**

```java
abstract class Employee {
    String name;
    double salary;

    public Employee(String name, double salary) {
        this.name = name;
        this.salary = salary;
    }

    public abstract double calculateBonus();
}
```

### Use Interface when:
- Define **behavior contract**
- Need **multiple inheritance**
- Unrelated classes need **same behavior**
- CAN-DO relationship

```java
interface Flyable {
    void fly();
}

class Bird implements Flyable { }
class Airplane implements Flyable { }
```

---

## Multiple Inheritance with Interfaces

Java doesn't support multiple class inheritance but allows multiple interfaces.

```java
interface Printable {
    void print();
}

interface Scannable {
    void scan();
}

// Multiple inheritance via interfaces
class AllInOnePrinter implements Printable, Scannable {
    @Override
    public void print() {
        System.out.println("Printing...");
    }

    @Override
    public void scan() {
        System.out.println("Scanning...");
    }
}
```

---

## Marker Interfaces

Interface with **no methods** - just marks a class with special property.

```java
// Marker interface
interface Serializable { }

class User implements Serializable {
    // This class can now be serialized
}
```

Common marker interfaces:
- `Serializable` - Object can be serialized
- `Cloneable` - Object can be cloned
- `Remote` - Object can be used remotely

---

## Functional Interfaces (Java 8+)

Interface with **exactly one abstract method**.

```java
@FunctionalInterface
interface Calculator {
    int calculate(int a, int b);  // Single abstract method

    // Can have default/static methods
    default void display() {
        System.out.println("Calculator");
    }
}

// Used with lambda expressions
Calculator add = (a, b) -> a + b;
System.out.println(add.calculate(5, 3));  // 8
```

---

## Production Example

```java
// Interface - defines contract
interface NotificationService {
    void send(String recipient, String message);
    boolean isAvailable();
}

// Abstract class - shared implementation
abstract class BaseNotificationService implements NotificationService {
    protected String serviceName;

    public BaseNotificationService(String serviceName) {
        this.serviceName = serviceName;
    }

    @Override
    public boolean isAvailable() {
        // Common availability check
        return true;
    }

    protected void log(String message) {
        System.out.println("[" + serviceName + "] " + message);
    }
}

// Concrete implementation
class EmailService extends BaseNotificationService {
    public EmailService() {
        super("Email");
    }

    @Override
    public void send(String recipient, String message) {
        log("Sending email to " + recipient);
    }
}

class SMSService extends BaseNotificationService {
    public SMSService() {
        super("SMS");
    }

    @Override
    public void send(String recipient, String message) {
        log("Sending SMS to " + recipient);
    }
}
```

---

## Common Mistakes

```java
// ❌ Cannot instantiate abstract class
abstract class Shape { }
Shape s = new Shape();  // ERROR!

// ❌ Cannot instantiate interface
interface Drawable { }
Drawable d = new Drawable();  // ERROR!

// ❌ Abstract method in concrete class
class MyClass {
    public abstract void method();  // ERROR! Must be abstract class
}

// ❌ Multiple class inheritance
class A { }
class B { }
class C extends A, B { }  // ERROR!

// ✅ Multiple interface inheritance
interface A { }
interface B { }
class C implements A, B { }  // OK!

// ❌ Private method in interface (before Java 9)
interface MyInterface {
    private void method();  // ERROR in Java 8
}
```

---

## Interview Questions

### Q1: What is abstraction?

Abstraction is hiding implementation details and showing only essential features to the user. Achieved through abstract classes and interfaces.

### Q2: Difference between abstract class and interface?

| Abstract Class | Interface |
|:--------------|:----------|
| Can have constructors | No constructors |
| Can have concrete methods | Only abstract (before Java 8) |
| Single inheritance | Multiple inheritance |
| Any access modifiers | Public only |

### Q3: Can abstract class have constructor?

Yes! Abstract class constructors are called by child class constructors using `super()`.

### Q4: Can interface have main method?

Yes (Java 8+)! Interface can have static methods including main().

```java
interface Test {
    static void main(String[] args) {
        System.out.println("Interface main");
    }
}
```

### Q5: What is marker interface?

An interface with no methods that marks or tags a class with special behavior (e.g., `Serializable`, `Cloneable`).

### Q6: Can we achieve multiple inheritance in Java?

No through classes, but YES through interfaces.

---

## Tricky Questions

### Q1: What is the output?

```java
interface A {
    default void show() {
        System.out.println("A");
    }
}

interface B {
    default void show() {
        System.out.println("B");
    }
}

class C implements A, B {
    // What must we do here?
}
```

<details>
<summary>Answer</summary>

<pre>
Compilation error! Must override show() to resolve conflict.

class C implements A, B {
    @Override
    public void show() {
        A.super.show();  // Or B.super.show() or custom logic
    }
}
</pre>

</details>

### Q2: Will this compile?

```java
abstract class Animal {
    abstract void makeSound();
}

class Dog extends Animal {
    // Nothing here
}
```

<details>
<summary>Answer</summary>

<pre>
NO! Dog must either:
1. Implement makeSound(), OR
2. Be declared abstract
</pre>

</details>

### Q3: What is the output?

```java
interface Test {
    int VALUE = 10;
}

class Demo implements Test {
    void modify() {
        VALUE = 20;  // Will this work?
    }
}
```

<details>
<summary>Answer</summary>

<pre>
Compilation error!
Interface variables are implicitly public static final (constants).
Cannot be modified.
</pre>

</details>

---

## Practice Code

📁 `src/main/java/com/prep/week1_corejava/day04_abstraction/AbstractionDemo.java`

```bash
# Compile and run
javac src/main/java/com/prep/week1_corejava/day04_abstraction/AbstractionDemo.java
java -cp src/main/java com.prep.week1_corejava.day04_abstraction.AbstractionDemo
```

The demo covers all concepts with hands-on examples and exercises.

---

## Checklist

- [ ] I understand abstraction concept
- [ ] I know abstract class rules
- [ ] I know interface rules
- [ ] I understand abstract class vs interface
- [ ] I know Java 8+ interface features (default, static)
- [ ] I understand when to use abstract class vs interface
- [ ] I can implement multiple interfaces
- [ ] I know marker and functional interfaces
- [ ] I can resolve default method conflicts

---

[← Day 3: Inheritance](day03-inheritance-polymorphism.md) | [Next: Day 5 - String Handling →](day05-strings.md)
