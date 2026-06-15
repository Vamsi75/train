# Day 6: Important Java Keywords

Understanding special keywords and modifiers.

---

## Quick Overview

Java has **50+ reserved keywords**. We'll focus on the most important ones for interviews and production code.

| Category | Keywords |
|:---------|:---------|
| **Access Modifiers** | public, private, protected, default |
| **Non-Access Modifiers** | static, final, abstract, synchronized |
| **Special Keywords** | this, super, new, instanceof |
| **Control Flow** | if, else, switch, for, while, break, continue |
| **Exception Handling** | try, catch, finally, throw, throws |

---

## Access Modifiers

Control **who can access** classes, methods, and variables.

| Modifier | Class | Package | Subclass | World |
|:---------|:------|:--------|:---------|:------|
| **public** | ✅ | ✅ | ✅ | ✅ |
| **protected** | ✅ | ✅ | ✅ | ❌ |
| **default** (no modifier) | ✅ | ✅ | ❌ | ❌ |
| **private** | ✅ | ❌ | ❌ | ❌ |

```java
public class Example {
    public int publicVar = 1;       // Accessible everywhere
    protected int protectedVar = 2;  // Package + subclasses
    int defaultVar = 3;              // Package only
    private int privateVar = 4;      // This class only

    private void privateMethod() { }      // Only in this class
    public void publicMethod() { }        // Anywhere
}
```

---

## static Keyword

Belongs to **class**, not instance.

```java
class Counter {
    static int count = 0;     // Shared by all objects
    int instanceCount = 0;    // Each object has own copy

    static void staticMethod() {
        count++;              // Can access static members
        // instanceCount++;   // ERROR! Can't access instance members
    }

    void instanceMethod() {
        count++;              // Can access static members
        instanceCount++;      // Can access instance members
    }
}

// Usage
Counter.count = 10;           // Access via class name
Counter.staticMethod();       // Call via class name

Counter c1 = new Counter();
c1.instanceCount++;           // Each object separate
```

### static Rules

| Feature | Description |
|:--------|:------------|
| **Static variable** | Shared across all instances |
| **Static method** | Can't access instance members |
| **Static block** | Runs once when class loads |
| **Static import** | Import static members directly |

---

## final Keyword

Makes entities **unchangeable**.

### final Variable - Constant

```java
final int MAX_SIZE = 100;
MAX_SIZE = 200;  // ERROR! Cannot change

// Blank final - must initialize in constructor
class Example {
    final int id;

    Example(int id) {
        this.id = id;  // OK here
    }
}
```

### final Method - Cannot Override

```java
class Parent {
    final void show() {
        System.out.println("Parent");
    }
}

class Child extends Parent {
    // void show() { }  // ERROR! Cannot override final method
}
```

### final Class - Cannot Extend

```java
final class ImmutableClass {
    // Nobody can extend this class
}

// class MyClass extends ImmutableClass { }  // ERROR!
```

---

## this Keyword

Reference to **current object**.

```java
class Employee {
    String name;

    // 1. Distinguish field from parameter
    Employee(String name) {
        this.name = name;  // this.name is field, name is parameter
    }

    // 2. Call another constructor
    Employee() {
        this("Unknown");  // Calls above constructor
    }

    // 3. Return current object
    Employee setName(String name) {
        this.name = name;
        return this;  // Method chaining
    }

    // 4. Pass current object
    void print() {
        Display.show(this);  // Pass current Employee object
    }
}
```

---

## super Keyword

Reference to **parent class**.

```java
class Parent {
    int value = 10;

    Parent() {
        System.out.println("Parent constructor");
    }

    void display() {
        System.out.println("Parent display");
    }
}

class Child extends Parent {
    int value = 20;

    Child() {
        super();  // Call parent constructor (must be first)
        System.out.println("Child constructor");
    }

    void display() {
        super.display();     // Call parent method
        System.out.println("Child display");
        System.out.println(super.value);  // Access parent field (10)
        System.out.println(this.value);   // Access child field (20)
    }
}
```

---

## instanceof Keyword

Check **object type** at runtime.

```java
Object obj = "Hello";

if (obj instanceof String) {
    String str = (String) obj;  // Safe to cast
    System.out.println(str.length());
}

// Java 16+ Pattern Matching
if (obj instanceof String str) {
    System.out.println(str.length());  // No cast needed!
}

// Inheritance check
class Animal { }
class Dog extends Animal { }

Animal animal = new Dog();
System.out.println(animal instanceof Dog);     // true
System.out.println(animal instanceof Animal);  // true
System.out.println(animal instanceof Object);  // true
```

---

## abstract Keyword

Defines **incomplete** classes/methods.

```java
abstract class Shape {
    abstract double area();  // No implementation

    void display() {         // Can have concrete methods
        System.out.println("Shape");
    }
}

class Circle extends Shape {
    double radius;

    @Override
    double area() {
        return Math.PI * radius * radius;
    }
}
```

---

## synchronized Keyword

For **thread safety** - only one thread at a time.

```java
class Counter {
    private int count = 0;

    // Synchronized method
    public synchronized void increment() {
        count++;
    }

    // Synchronized block
    public void add(int value) {
        synchronized(this) {
            count += value;
        }
    }
}
```

---

## transient Keyword

Exclude field from **serialization**.

```java
class User implements Serializable {
    String username;
    transient String password;  // Won't be serialized

    // When saved, password will be null
}
```

---

## volatile Keyword

Ensures **visibility** across threads.

```java
class SharedData {
    // Value read from main memory, not thread cache
    private volatile boolean flag = false;

    public void setFlag() {
        flag = true;  // Visible to all threads immediately
    }
}
```

---

## strictfp Keyword

Ensures **consistent** floating-point calculations across platforms.

```java
strictfp class MathCalculations {
    double calculate() {
        return 1.0 / 3.0;  // Same result on all platforms
    }
}
```

---

## native Keyword

Methods implemented in **native code** (C/C++).

```java
class Example {
    // Implementation in C/C++
    public native void nativeMethod();
}
```

---

## assert Keyword

For **debugging** - check assumptions.

```java
public void setAge(int age) {
    assert age > 0 : "Age must be positive";  // Throws AssertionError if false
    this.age = age;
}

// Enable assertions: java -ea ClassName
```

---

## Comparison Table

| Keyword | Purpose | Example |
|:--------|:--------|:--------|
| `static` | Class-level member | `static int count` |
| `final` | Constant/unchangeable | `final int MAX = 100` |
| `this` | Current object | `this.name = name` |
| `super` | Parent class | `super.method()` |
| `abstract` | Incomplete class/method | `abstract void method()` |
| `synchronized` | Thread-safe | `synchronized void method()` |
| `transient` | Don't serialize | `transient String password` |
| `volatile` | Thread visibility | `volatile boolean flag` |
| `instanceof` | Type check | `obj instanceof String` |

---

## Common Mistakes

```java
// MISTAKE 1: Accessing instance from static
class Example {
    int instanceVar = 10;

    static void staticMethod() {
        // System.out.println(instanceVar);  // ERROR!
    }
}

// MISTAKE 2: Not calling super() first
class Child extends Parent {
    Child() {
        System.out.println("Child");
        super();  // ERROR! Must be first statement
    }
}

// MISTAKE 3: Modifying final variable
final int MAX = 100;
MAX = 200;  // ERROR!

// MISTAKE 4: Using this() and super() together
class Example {
    Example() {
        this(10);   // ERROR! Can't use both
        super();
    }
}
```

---

## Interview Questions

### Q1: Difference between static and instance members?

| Static | Instance |
|:-------|:---------|
| Belongs to class | Belongs to object |
| One copy | Each object has own copy |
| Accessed via class name | Accessed via object |
| Loaded at class loading | Created with object |

### Q2: When to use final keyword?

- **Variable**: Create constants
- **Method**: Prevent overriding
- **Class**: Prevent inheritance (e.g., String, Integer)

### Q3: Difference between this and super?

- `this`: Current class reference
- `super`: Parent class reference

### Q4: Can static method be overridden?

No! Static methods belong to class, not object. It's **method hiding**, not overriding.

### Q5: What is static block?

Code block that runs **once** when class is loaded, before constructor.

```java
class Example {
    static {
        System.out.println("Static block runs first");
    }
}
```

---

## Practice Code

📁 `java-prep-practice/com/prep/week1_corejava/day06_keywords/KeywordsDemo.java`

```bash
# Compile and run
javac -encoding UTF-8 java-prep-practice/com/prep/week1_corejava/day06_keywords/KeywordsDemo.java
java -cp java-prep-practice com.prep.week1_corejava.day06_keywords.KeywordsDemo
```

The demo covers all concepts with hands-on examples and exercises.

---

## Checklist

- [ ] I understand access modifiers (public, private, protected, default)
- [ ] I know when to use static
- [ ] I know when to use final
- [ ] I understand this vs super
- [ ] I can use instanceof safely
- [ ] I know synchronized for thread safety
- [ ] I understand abstract keyword
- [ ] I know transient and volatile keywords

---

[← Day 5: Strings](day05-strings.md) | [Next: Day 7 - Collections List →](day07-collections-list.md)
