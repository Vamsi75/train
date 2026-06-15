# Day 1: Primitives vs Wrappers

Understanding the foundation of Java data types.

---

## Quick Definition

| Primitive | Wrapper |
|:----------|:--------|
| `int`, `char`, `boolean` | `Integer`, `Character`, `Boolean` |
| Stored in **stack** (fast) | Stored in **heap** (slower) |
| Cannot be `null` | Can be `null` |
| Not used in Collections | Used in Collections |

---

## The 8 Primitives

| Primitive | Wrapper | Size | Default |
|:----------|:--------|:-----|:--------|
| `byte` | `Byte` | 8 bits | 0 |
| `short` | `Short` | 16 bits | 0 |
| `int` | `Integer` | 32 bits | 0 |
| `long` | `Long` | 64 bits | 0L |
| `float` | `Float` | 32 bits | 0.0f |
| `double` | `Double` | 64 bits | 0.0d |
| `char` | `Character` | 16 bits | '\u0000' |
| `boolean` | `Boolean` | 1 bit | false |

---

## Autoboxing & Unboxing

```java
// Autoboxing: primitive → wrapper (automatic)
Integer num = 10;  // int becomes Integer

// Unboxing: wrapper → primitive (automatic)
int value = num;   // Integer becomes int
```

---

## Integer Cache Trap ⚠️

Integer caching is an internal optimization in Java where certain integer objects are reused instead of creating new objects every time.

```java
Integer a = 127;
Integer b = 127;
System.out.println(a == b);  // TRUE (cached)

Integer x = 128;
Integer y = 128;
System.out.println(x == y);  // FALSE (new objects!)
```

**Why?** Java caches Integer values from **-128 to 127**.

> Always use `.equals()` for wrapper comparison!

---

## When to Use What?

| Use Primitive | Use Wrapper |
|:--------------|:------------|
| Loop counters | Collections |
| Calculations | Database entities (nullable) |
| Method parameters | Optional values |
| Performance critical | Generics |

---

## Production Example

```java
@Entity
public class Employee {

    @Id
    private Long id;           // Wrapper - null before save

    private String name;

    private Integer age;       // Wrapper - might be unknown

    private boolean active;    // Primitive - always has value

    private int loginCount;    // Primitive - defaults to 0
}
```

---

## Common Mistakes

```java
// ❌ NullPointerException
Integer num = null;
int value = num;  // BOOM!

// ✅ Safe way
int value = (num != null) ? num : 0;

// ❌ Performance issue in loops
Long sum = 0L;
for (int i = 0; i < 1000; i++) {
    sum += i;  // Creates new object each time!
}

// ✅ Use primitive
long sum = 0L;
for (int i = 0; i < 1000; i++) {
    sum += i;
}
```

---

## Interview Questions

### Q1: Difference between `int` and `Integer`?

| `int` | `Integer` |
|:------|:----------|
| Primitive | Object |
| Stack | Heap |
| Cannot be null | Can be null |
| Faster | Slower |

### Q2: What is Integer caching?

Java caches Integer objects from -128 to 127. Within this range, `==` works because both references point to the same cached object.

### Q3: What happens when you unbox null?

`NullPointerException` is thrown.

---

## Tricky Question

**What is the output?**

```java
Integer a = 100;
Integer b = 100;
Integer c = 200;
Integer d = 200;

System.out.println(a == b);
System.out.println(c == d);
```

<details>
<summary>Answer</summary>

<pre>
true   (100 is cached)
false  (200 is not cached)
</pre>

</details>

---

## Practice Code

📁 `java-prep-practice/com/prep/week1_corejava/day01_primitives/`

Run `PrimitivesDemo.java` to see these concepts in action.

---

## Checklist

- [ ] I understand primitive vs wrapper
- [ ] I know autoboxing/unboxing
- [ ] I understand Integer caching
- [ ] I can handle null safely
- [ ] I know when to use which

---

[Next: Day 2 - OOP Basics →](day02-oop-basics.md)
