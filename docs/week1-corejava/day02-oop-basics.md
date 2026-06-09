---
layout: default
title: Day 2 - OOP Basics
parent: Week 1-2 Core Java
nav_order: 2
---

# Day 2: OOP - Classes, Objects & Encapsulation
{: .fs-8 }

The building blocks of Java applications.
{: .fs-5 .fw-300 }

---

## Quick Definition

**OOP (Object-Oriented Programming)** organizes code into objects that contain data (fields) and behavior (methods). A **class** is a blueprint, an **object** is an instance of that class, and **encapsulation** hides internal details by using private fields with public getters/setters.

---

## Core Concepts

| Concept | Description | Example |
|:--------|:------------|:--------|
| **Class** | Blueprint/template | `class Employee { }` |
| **Object** | Instance of a class | `new Employee()` |
| **Fields** | Data/state | `private String name;` |
| **Methods** | Behavior/actions | `public void work()` |
| **Constructor** | Initializes object | `Employee(String name)` |
| **Encapsulation** | Hide internals | private fields + public getters/setters |

---

## Class vs Object

```java
// Class = Blueprint (stored in memory once)
public class Employee {
    String name;
    int salary;
}

// Objects = Instances (each has own memory)
Employee emp1 = new Employee();  // Object 1
Employee emp2 = new Employee();  // Object 2
```

| Class | Object |
|:------|:-------|
| Template/Blueprint | Instance of class |
| Exists once | Multiple can exist |
| No memory allocated | Memory allocated |
| Declared with `class` | Created with `new` |

---

## Constructors

```java
public class Employee {
    private String name;
    private int salary;

    // Default constructor (no args)
    public Employee() {
        this.name = "Unknown";
        this.salary = 0;
    }

    // Parameterized constructor
    public Employee(String name, int salary) {
        this.name = name;
        this.salary = salary;
    }

    // Constructor chaining using this()
    public Employee(String name) {
        this(name, 30000);  // Calls 2-arg constructor
    }
}
```

| Constructor Rule | Description |
|:-----------------|:------------|
| Same name as class | `public Employee()` |
| No return type | Not even `void` |
| Default provided if none written | Compiler adds no-arg constructor |
| `this()` must be first statement | For constructor chaining |

---

## Encapsulation - The Right Way

Binding data (variables) and methods together into a single unit and restricting direct access to internal data.

```java
// ❌ BAD - Public fields expose internal state
public class Employee {
    public String name;      // Anyone can modify!
    public int salary;       // No validation!
}

// ✅ GOOD - Private fields + controlled access
public class Employee {
    private String name;
    private int salary;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        if (name != null && !name.isBlank()) {
            this.name = name;
        }
    }

    public int getSalary() {
        return salary;
    }

    public void setSalary(int salary) {
        if (salary >= 0) {  // Validation!
            this.salary = salary;
        }
    }
}
```

---

## Benefits of Encapsulation

| Benefit | How |
|:--------|:----|
| **Data Hiding** | Private fields not accessible directly |
| **Validation** | Setter can reject invalid values |
| **Flexibility** | Change implementation without affecting users |
| **Read-only** | Provide getter without setter |
| **Write-only** | Provide setter without getter (rare) |

---

## Production Example

```java
@Entity
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String email;

    private String password;  // Never expose!

    private boolean active;

    // Getter - provide access
    public String getEmail() {
        return email;
    }

    // Setter - with validation
    public void setEmail(String email) {
        if (email != null && email.contains("@")) {
            this.email = email.toLowerCase();
        }
    }

    // NO getter for password (security)

    // Setter - with hashing
    public void setPassword(String password) {
        this.password = hashPassword(password);
    }
}
```

---

## Common Mistakes

```java
// ❌ Using public fields
public class User {
    public String password;  // NEVER!
}

// ❌ Returning mutable objects directly
public class Employee {
    private List<String> skills;

    public List<String> getSkills() {
        return skills;  // Caller can modify!
    }
}

// ✅ Return defensive copy
public List<String> getSkills() {
    return new ArrayList<>(skills);
}

// ❌ No validation in setter
public void setAge(int age) {
    this.age = age;  // Accepts negative!
}

// ✅ With validation
public void setAge(int age) {
    if (age >= 0 && age <= 150) {
        this.age = age;
    }
}
```

---

## `this` Keyword

| Usage | Example |
|:------|:--------|
| Refer to current object | `this.name = name;` |
| Call another constructor | `this(defaultValue);` |
| Return current object | `return this;` (builder pattern) |
| Pass current object | `someMethod(this);` |

```java
public class Employee {
    private String name;

    public Employee setName(String name) {
        this.name = name;
        return this;  // Enables method chaining
    }
}

// Usage: employee.setName("John").setSalary(50000);
```

---

## Interview Questions

### Q1: What is the difference between class and object?

A class is a blueprint/template that defines fields and methods. An object is a runtime instance of a class with its own memory. You can create multiple objects from one class.

### Q2: What is encapsulation and why is it important?

Encapsulation bundles data (fields) and methods together while hiding internal state using private access. Benefits: data validation, flexibility to change implementation, and security by preventing unauthorized access.

### Q3: Can a class have multiple constructors?

Yes, this is called **constructor overloading**. Each constructor must have a different parameter list. Use `this()` to chain constructors and avoid code duplication.

### Q4: What happens if you don't define any constructor?

Java compiler adds a default no-argument constructor automatically. But if you define ANY constructor, the default is NOT added.

---

## Tricky Questions

### Q1: What is the output?

```java
public class Test {
    int x = 10;

    public Test() {
        this(5);
        System.out.println(x);
    }

    public Test(int x) {
        this.x = x;
    }

    public static void main(String[] args) {
        new Test();
    }
}
```

<details>
<summary>Answer</summary>

<pre>
5
</pre>

Execution order:
1. Field `x` initialized to 10
2. No-arg constructor calls `this(5)`
3. `this.x = 5` in parameterized constructor
4. Returns to no-arg constructor, prints 5

</details>

### Q2: Will this compile?

```java
public class Employee {
    private String name;

    public Employee(String name) {
        this.name = name;
    }
}

// In another class:
Employee emp = new Employee();
```

<details>
<summary>Answer</summary>

<pre>
NO - Compilation error!
</pre>

Since a parameterized constructor is defined, the compiler doesn't add the default no-arg constructor. You must either:
- Add explicit no-arg constructor, OR
- Use `new Employee("name")`

</details>

---

## Practice Code

📁 `src/main/java/com/prep/week1_corejava/day02_oop/`

Run `OopBasicsDemo.java` to see these concepts in action.

---

## Checklist

- [ ] I can create a class with fields and methods
- [ ] I understand object creation with `new`
- [ ] I know constructor rules and chaining
- [ ] I apply encapsulation (private fields + getters/setters)
- [ ] I understand the `this` keyword
- [ ] I can explain why encapsulation matters

---

[← Day 1: Primitives](day01-primitives-wrappers.md) | [Next: Day 3 - Inheritance →](day03-inheritance.md)
