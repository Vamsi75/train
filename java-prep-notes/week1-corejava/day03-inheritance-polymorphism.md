# Day 3: Inheritance & Polymorphism

Code reusability and flexibility through OOP principles.

---

## Quick Definition

**Inheritance** allows a class to inherit fields and methods from another class. **Polymorphism** means "many forms" - the ability of an object to take multiple forms, allowing one interface to be used for different data types.

| Concept | Description | Keyword |
|:--------|:------------|:--------|
| **Inheritance** | Child class inherits parent class | `extends` |
| **Polymorphism** | One interface, many implementations | Method overriding |
| **Method Overriding** | Child redefines parent method | `@Override` |
| **Method Overloading** | Same name, different parameters | Multiple methods |

---

## Inheritance Basics

```java
// Parent class (Superclass/Base class)
public class Animal {
    protected String name;

    public void eat() {
        System.out.println(name + " is eating");
    }

    public void sleep() {
        System.out.println(name + " is sleeping");
    }
}

// Child class (Subclass/Derived class)
public class Dog extends Animal {

    // Inherited: name, eat(), sleep()

    // New behavior specific to Dog
    public void bark() {
        System.out.println(name + " is barking");
    }
}

// Usage
Dog dog = new Dog();
dog.name = "Buddy";
dog.eat();      // Inherited from Animal
dog.sleep();    // Inherited from Animal
dog.bark();     // Specific to Dog
```

---

## Inheritance Types in Java

| Type | Description | Supported in Java |
|:-----|:------------|:------------------|
| **Single** | One parent, one child | ✅ Yes |
| **Multilevel** | Chain: A → B → C | ✅ Yes |
| **Hierarchical** | One parent, multiple children | ✅ Yes |
| **Multiple** | Multiple parents, one child | ❌ No (use interfaces) |
| **Hybrid** | Combination of above | ❌ No |

```java
// ✅ Single Inheritance
class Animal { }
class Dog extends Animal { }

// ✅ Multilevel Inheritance
class Animal { }
class Mammal extends Animal { }
class Dog extends Mammal { }

// ✅ Hierarchical Inheritance
class Animal { }
class Dog extends Animal { }
class Cat extends Animal { }

// ❌ Multiple Inheritance - NOT ALLOWED
class A { }
class B { }
class C extends A, B { }  // Compilation error!
```

---

## Method Overriding (Runtime Polymorphism)

Child class provides a **specific implementation** of a method already defined in parent class.

```java
public class Animal {
    public void sound() {
        System.out.println("Animal makes a sound");
    }
}

public class Dog extends Animal {
    @Override
    public void sound() {
        System.out.println("Dog barks");
    }
}

public class Cat extends Animal {
    @Override
    public void sound() {
        System.out.println("Cat meows");
    }
}

// Usage - Runtime Polymorphism
Animal animal1 = new Dog();
Animal animal2 = new Cat();

animal1.sound();  // Dog barks
animal2.sound();  // Cat meows
```

### Overriding Rules

| Rule | Description |
|:-----|:------------|
| Same method signature | Name + parameters must match |
| `@Override` annotation | Not mandatory but recommended |
| Access modifier | Same or more accessible (not less) |
| Return type | Same or covariant (subtype) |
| Cannot override | `final`, `static`, `private` methods |
| Exceptions | Can throw fewer/narrower, not more/broader |

---

## Method Overloading (Compile-time Polymorphism)

Same method name but **different parameters** in the same class.

```java
public class Calculator {

    // Different number of parameters
    public int add(int a, int b) {
        return a + b;
    }

    public int add(int a, int b, int c) {
        return a + b + c;
    }

    // Different parameter types
    public double add(double a, double b) {
        return a + b;
    }

    // Different order of parameter types
    public void display(String name, int age) {
        System.out.println(name + " - " + age);
    }

    public void display(int age, String name) {
        System.out.println(age + " - " + name);
    }
}
```

### Overloading Rules

| Rule | Valid |
|:-----|:------|
| Different number of parameters | ✅ Yes |
| Different parameter types | ✅ Yes |
| Different parameter order | ✅ Yes |
| Different return type only | ❌ No |
| Different access modifier only | ❌ No |

---

## Overloading vs Overriding

| Feature | Overloading | Overriding |
|:--------|:------------|:-----------|
| **Where** | Same class | Parent-child classes |
| **Parameters** | Must differ | Must be same |
| **Return type** | Can differ | Same or covariant |
| **Binding** | Compile-time (static) | Runtime (dynamic) |
| **Inheritance** | Not required | Required |
| **`@Override`** | Not applicable | Recommended |

---

## `super` Keyword

Used to access parent class members from child class.

```java
public class Animal {
    protected String type = "Animal";

    public void display() {
        System.out.println("I am an animal");
    }

    public Animal() {
        System.out.println("Animal constructor");
    }
}

public class Dog extends Animal {
    private String type = "Dog";

    public Dog() {
        super();  // Call parent constructor (must be first line)
        System.out.println("Dog constructor");
    }

    public void display() {
        super.display();  // Call parent method
        System.out.println("I am a dog");
    }

    public void printType() {
        System.out.println(type);        // Dog
        System.out.println(super.type);  // Animal
    }
}
```

### `super` Usage

| Usage | Example |
|:------|:--------|
| Call parent constructor | `super();` |
| Access parent field | `super.fieldName` |
| Call parent method | `super.methodName()` |

---

## Polymorphism in Action

```java
public class PaymentProcessor {

    // One method handles all payment types!
    public void processPayment(Payment payment) {
        payment.pay();  // Actual method depends on runtime object
    }
}

// Parent class
abstract class Payment {
    abstract void pay();
}

// Different implementations
class CreditCard extends Payment {
    void pay() {
        System.out.println("Processing credit card payment");
    }
}

class PayPal extends Payment {
    void pay() {
        System.out.println("Processing PayPal payment");
    }
}

class Bitcoin extends Payment {
    void pay() {
        System.out.println("Processing Bitcoin payment");
    }
}

// Usage
PaymentProcessor processor = new PaymentProcessor();

Payment payment1 = new CreditCard();
Payment payment2 = new PayPal();
Payment payment3 = new Bitcoin();

processor.processPayment(payment1);  // Credit card
processor.processPayment(payment2);  // PayPal
processor.processPayment(payment3);  // Bitcoin
```

---

## Production Example

```java
// Spring Boot Controller Hierarchy
public abstract class BaseController {

    protected ResponseEntity<?> handleError(Exception e) {
        return ResponseEntity
            .status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(e.getMessage());
    }
}

@RestController
@RequestMapping("/api/users")
public class UserController extends BaseController {

    @Autowired
    private UserService userService;

    @GetMapping("/{id}")
    public ResponseEntity<?> getUser(@PathVariable Long id) {
        try {
            User user = userService.findById(id);
            return ResponseEntity.ok(user);
        } catch (Exception e) {
            return super.handleError(e);  // Inherited
        }
    }
}

@RestController
@RequestMapping("/api/products")
public class ProductController extends BaseController {
    // Also inherits handleError()
}
```

---

## Common Mistakes

```java
// ❌ Trying to override private method
class Parent {
    private void display() { }
}
class Child extends Parent {
    @Override  // Compilation error!
    private void display() { }
}

// ❌ Reducing access in override
class Parent {
    public void show() { }
}
class Child extends Parent {
    @Override
    private void show() { }  // Error! Cannot reduce visibility
}

// ❌ Overriding final method
class Parent {
    public final void calculate() { }
}
class Child extends Parent {
    @Override
    public void calculate() { }  // Error! Cannot override final
}

// ❌ Forgetting super() in constructor
class Parent {
    public Parent(String name) { }
}
class Child extends Parent {
    public Child() {
        // Implicit super() call fails!
        // Must explicitly call super(name)
    }
}

// ✅ Correct way
class Child extends Parent {
    public Child(String name) {
        super(name);  // Call parent constructor
    }
}
```

---

## Upcasting vs Downcasting

```java
// Upcasting (implicit, safe)
Dog dog = new Dog();
Animal animal = dog;  // Dog → Animal (child to parent)

// Downcasting (explicit, risky)
Animal animal = new Dog();
Dog dog = (Dog) animal;  // Animal → Dog (parent to child)

// Safe downcasting with instanceof
if (animal instanceof Dog) {
    Dog dog = (Dog) animal;
    dog.bark();
}

// Java 16+ Pattern Matching
if (animal instanceof Dog dog) {
    dog.bark();  // No explicit cast needed!
}
```

---

## Interview Questions

### Q1: What is inheritance and why use it?

Inheritance allows a class to acquire properties and behaviors from another class. Benefits:
- Code reusability (DRY principle)
- Method overriding (polymorphism)
- Establish IS-A relationship
- Logical hierarchy

### Q2: Difference between overloading and overriding?

| Overloading | Overriding |
|:------------|:-----------|
| Same class | Different classes (inheritance) |
| Different parameters | Same parameters |
| Compile-time | Runtime |
| Increases readability | Achieves polymorphism |

### Q3: Can you override static methods?

No. Static methods belong to the class, not objects. You can declare a static method with the same signature in child class, but it's **method hiding**, not overriding.

### Q4: Why doesn't Java support multiple inheritance?

To avoid the **Diamond Problem** - ambiguity when two parent classes have the same method. Java solves this with interfaces (which can have default methods with explicit resolution).

### Q5: What is the difference between `super()` and `this()`?

- `super()`: Calls parent class constructor
- `this()`: Calls another constructor in same class
- Both must be **first statement** in constructor
- Cannot use both in same constructor

---

## Tricky Questions

### Q1: What is the output?

```java
class Parent {
    public void display() {
        System.out.println("Parent");
    }
}

class Child extends Parent {
    public void display() {
        System.out.println("Child");
    }
}

public class Test {
    public static void main(String[] args) {
        Parent obj = new Child();
        obj.display();
    }
}
```

<details>
<summary>Answer</summary>

<pre>
Child
</pre>

Runtime polymorphism - method call is resolved at runtime based on actual object type (Child), not reference type (Parent).

</details>

### Q2: Will this compile?

```java
class A {
    public Number getValue() {
        return 10;
    }
}

class B extends A {
    @Override
    public Integer getValue() {
        return 20;
    }
}
```

<details>
<summary>Answer</summary>

<pre>
YES - Covariant return type
</pre>

Since Java 5, you can override a method with a return type that is a subclass of the original return type. `Integer` is a subclass of `Number`.

</details>

### Q3: What is the output?

```java
class Parent {
    static void print() {
        System.out.println("Parent");
    }
}

class Child extends Parent {
    static void print() {
        System.out.println("Child");
    }
}

public class Test {
    public static void main(String[] args) {
        Parent obj = new Child();
        obj.print();
    }
}
```

<details>
<summary>Answer</summary>

<pre>
Parent
</pre>

Static methods are resolved at **compile-time** based on reference type, not runtime object type. This is method hiding, not overriding.

</details>

---

## Practice Code

📁 `java-prep-practice/com/prep/week1_corejava/day03_inheritance/InheritanceDemo.java`

```bash
# Compile and run
javac -encoding UTF-8 java-prep-practice/com/prep/week1_corejava/day03_inheritance/InheritanceDemo.java
java -cp java-prep-practice com.prep.week1_corejava.day03_inheritance.InheritanceDemo
```

The demo covers all concepts with hands-on examples and exercises.

---

## Checklist

- [ ] I understand inheritance and `extends` keyword
- [ ] I know the difference between overloading and overriding
- [ ] I can explain runtime vs compile-time polymorphism
- [ ] I understand the `super` keyword
- [ ] I know when to use upcasting and downcasting
- [ ] I can explain why Java doesn't support multiple inheritance
- [ ] I understand covariant return types
- [ ] I know static methods cannot be overridden

---

[← Day 2: OOP Basics](day02-oop-basics.md) | [Next: Day 4 - Abstraction & Interfaces →](day04-abstraction-interfaces.md)
