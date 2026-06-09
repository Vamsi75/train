---
layout: default
title: Java Cheatsheet
parent: Cheatsheets
nav_order: 1
---

# Java Quick Cheatsheet
{: .fs-8 }

Print this out for quick reference!
{: .fs-5 .fw-300 }

---

## Primitives vs Wrappers

| Primitive | Wrapper | Size | Default |
|:----------|:--------|:-----|:--------|
| byte | Byte | 8 bits | 0 |
| short | Short | 16 bits | 0 |
| int | Integer | 32 bits | 0 |
| long | Long | 64 bits | 0L |
| float | Float | 32 bits | 0.0f |
| double | Double | 64 bits | 0.0d |
| char | Character | 16 bits | '\u0000' |
| boolean | Boolean | 1 bit | false |

{: .important }
> Integer cache: -128 to 127. Always use `.equals()` for comparison!

---

## OOP Concepts

```
Encapsulation  → private fields + getters/setters
Inheritance    → extends (class), implements (interface)
Polymorphism   → Overloading (compile-time), Overriding (runtime)
Abstraction    → abstract class, interface
```

---

## Collections

```
List (ordered, duplicates OK)
├── ArrayList  → Fast read O(1), slow insert O(n)
├── LinkedList → Fast insert O(1), slow read O(n)
└── Vector     → Thread-safe (legacy)

Set (unique elements)
├── HashSet       → Fast, no order
├── LinkedHashSet → Insertion order
└── TreeSet       → Sorted

Map (key-value)
├── HashMap       → Fast, no order
├── LinkedHashMap → Insertion order
└── TreeMap       → Sorted by key
```

---

## HashMap Internals

```
Array of buckets → Node[]
hashCode() % capacity → bucket index
Collision → LinkedList (<8) or Tree (≥8)
Load factor 0.75 → resize at 75%
```

---

## String

```java
String s = "hello";     // Pool (preferred)
String s = new String(); // Heap (avoid)

StringBuilder  → Mutable, NOT thread-safe, fast
StringBuffer   → Mutable, thread-safe, slower
```

---

## Java 8 Functional Interfaces

| Interface | Method | Signature |
|:----------|:-------|:----------|
| Predicate | test() | T → boolean |
| Function | apply() | T → R |
| Consumer | accept() | T → void |
| Supplier | get() | () → T |

---

## Stream Operations

```java
// Intermediate (lazy)
.filter(x -> condition)
.map(x -> transform)
.sorted()
.distinct()
.limit(n)

// Terminal (eager)
.collect(Collectors.toList())
.forEach(x -> action)
.count()
.reduce()
.findFirst()
```

---

## Exception Hierarchy

```
Throwable
├── Error (don't catch)
│   └── OutOfMemoryError
└── Exception
    ├── RuntimeException (unchecked)
    │   └── NullPointerException
    └── Checked
        └── IOException
```

---

## Access Modifiers

| Modifier | Class | Package | Subclass | World |
|:---------|:------|:--------|:---------|:------|
| public | ✓ | ✓ | ✓ | ✓ |
| protected | ✓ | ✓ | ✓ | ✗ |
| default | ✓ | ✓ | ✗ | ✗ |
| private | ✓ | ✗ | ✗ | ✗ |

---

## Keywords

```
final        → constant / no override / no inherit
static       → belongs to class
abstract     → no implementation
transient    → skip serialization
volatile     → visible to all threads
synchronized → thread-safe
```

---

## Common Patterns

```java
// Reverse string
new StringBuilder(str).reverse().toString()

// Remove duplicates
new ArrayList<>(new LinkedHashSet<>(list))

// Sort list
list.sort(Comparator.comparing(User::getName))

// Find max
list.stream().max(Comparator.naturalOrder())

// Group by
list.stream().collect(Collectors.groupingBy(User::getDept))
```
