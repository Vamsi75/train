# Day 2: equals, hashCode, Comparable & Comparator

The contracts that make HashMap, HashSet and sorting actually work.

---

## Quick Definition

| Method | From | Purpose |
|:-------|:-----|:--------|
| **equals(Object)** | Object | Logical equality between two objects |
| **hashCode()** | Object | Integer bucket hint for hash-based collections |
| **compareTo(T)** | Comparable | Natural ordering (a class's "default" sort) |
| **compare(T, T)** | Comparator | External, swappable ordering |

The golden rule: **if you override `equals`, you MUST override `hashCode`** - otherwise `HashMap`/`HashSet` break.

---

## The equals Contract

For non-null references `x`, `y`, `z`, `equals` must be:

| Property | Meaning |
|:---------|:--------|
| **Reflexive** | `x.equals(x)` is `true` |
| **Symmetric** | `x.equals(y) == y.equals(x)` |
| **Transitive** | if `x.equals(y)` and `y.equals(z)` then `x.equals(z)` |
| **Consistent** | repeated calls return the same result (no random/mutable state) |
| **Non-null** | `x.equals(null)` is `false` (never throws NPE) |

```java
@Override
public boolean equals(Object o) {
    if (this == o) return true;                       // reflexive fast-path
    if (o == null || getClass() != o.getClass()) return false;  // non-null + type
    Point p = (Point) o;
    return x == p.x && y == p.y;                       // Objects.equals for refs
}
```

---

## The hashCode Contract

| Rule | Meaning |
|:-----|:--------|
| **Consistency** | Same object returns same hash during one execution (unless equals fields change) |
| **equals implies equal hash** | If `a.equals(b)` then `a.hashCode() == b.hashCode()` |
| **Unequal may collide** | Different objects MAY share a hashCode (collisions are allowed, just slower) |

The dangerous direction is **equal objects MUST have equal hashCodes**. The reverse is not required.

```java
@Override
public int hashCode() {
    return Objects.hash(x, y);   // null-safe, uses same fields as equals
}
```

**Use the same fields in `equals` and `hashCode`** - mismatched fields silently corrupt hash collections.

---

## Why Both Matter for HashMap/HashSet

A `HashMap` locates a key in two steps:
1. **hashCode()** picks the bucket (`hash & (n-1)`).
2. **equals()** finds the exact key within that bucket.

If `hashCode` is wrong, two "equal" objects land in **different buckets** and the map never compares them with `equals` - so lookups miss and duplicates sneak into a `HashSet`.

```java
// Broken: equals overridden, hashCode NOT -> uses identity hash
class BadKey {
    int id;
    BadKey(int id) { this.id = id; }
    @Override public boolean equals(Object o) {
        return o instanceof BadKey b && b.id == id;
    }
    // no hashCode()!
}

Set<BadKey> set = new HashSet<>();
set.add(new BadKey(1));
set.add(new BadKey(1));            // logically equal...
System.out.println(set.size());    // 2  (!!) - different buckets, never compared
System.out.println(set.contains(new BadKey(1)));  // false (!!)
```

---

## Correct Implementation with Objects helpers

```java
class Person {
    private final String name;
    private final int age;

    Person(String name, int age) { this.name = name; this.age = age; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Person p = (Person) o;
        return age == p.age && Objects.equals(name, p.name);
    }

    @Override
    public int hashCode() {
        return Objects.hash(name, age);
    }
}
```

`Objects.equals(a, b)` handles nulls; `Objects.hash(...)` builds a combined hash (boxes args into an array - for a single field prefer `field.hashCode()` or `Integer.hashCode(x)` to avoid allocation in hot paths).

---

## The Inheritance / Symmetry Trap: instanceof vs getClass

```java
class Point { int x, y; /* equals uses instanceof */ }
class ColorPoint extends Point { String color; }
```

- **`instanceof`** breaks **symmetry**: `point.equals(colorPoint)` may be true while `colorPoint.equals(point)` is false (the subclass also checks color).
- **`getClass()`** keeps symmetry but breaks **Liskov substitution**: a `Point` and a subclass instance are never equal, even when used as plain points.

There is no perfect fix - this is "Effective Java" Item 10. Practical guidance:
- Use **`getClass()`** for value classes where subclasses add state.
- Prefer **composition over inheritance**, or make the class `final`, to dodge the dilemma.
- **Records** sidestep it: they are implicitly final and generate a `getClass`-based equals.

---

## Comparable - Natural Ordering

```java
class Version implements Comparable<Version> {
    int major, minor;
    @Override
    public int compareTo(Version o) {
        int c = Integer.compare(major, o.major);
        return c != 0 ? c : Integer.compare(minor, o.minor);
    }
}
```

**compareTo contract:**
- `sgn(a.compareTo(b)) == -sgn(b.compareTo(a))` (anti-symmetric)
- transitive
- consistent with itself
- **Strongly recommended:** consistent with `equals`, i.e. `a.compareTo(b) == 0` iff `a.equals(b)`.

If `compareTo` is **inconsistent with equals**, sorted collections misbehave: `TreeSet`/`TreeMap` use `compareTo` (not `equals`) for membership, so `BigDecimal("1.0")` and `BigDecimal("1.00")` are treated as duplicates in a `TreeSet` but distinct in a `HashSet`.

**Never** compute `compareTo` as `a - b` for ints - it can overflow. Use `Integer.compare`.

---

## Comparator - External Ordering

```java
List<Person> people = new ArrayList<>(...);

// comparingInt avoids boxing
people.sort(Comparator.comparingInt(Person::getAge));

// Multi-key, with tie-breakers and reversal
people.sort(
    Comparator.comparing(Person::getLastName)
              .thenComparing(Person::getFirstName)
              .thenComparingInt(Person::getAge)
              .reversed()
);

// Null-friendly ordering
Comparator<String> nullSafe =
    Comparator.nullsFirst(Comparator.naturalOrder());

// Reverse natural order
people.sort(Comparator.comparing(Person::getName).reversed());
```

| Factory / chain | Use |
|:----------------|:----|
| `comparing(keyExtractor)` | sort by a key |
| `comparingInt/Long/Double` | primitive key, no boxing |
| `thenComparing(...)` | tie-breaker |
| `reversed()` | invert the whole comparator |
| `nullsFirst / nullsLast` | place nulls predictably |
| `naturalOrder / reverseOrder` | use Comparable ordering |

**Gotcha with `reversed()`:** `comparing(A).thenComparing(B).reversed()` reverses the **entire** chain, not just B. To reverse only one key, reverse that key's comparator: `thenComparing(B, Comparator.reverseOrder())`.

---

## Records: Auto equals/hashCode/toString

```java
record Coordinate(int x, int y) { }

Coordinate a = new Coordinate(1, 2);
Coordinate b = new Coordinate(1, 2);
System.out.println(a.equals(b));     // true - generated
System.out.println(a.hashCode() == b.hashCode());  // true
```

Records generate `equals`, `hashCode`, and `toString` from **all components**. They do **not** implement `Comparable` automatically - add it yourself if you need ordering. Records are implicitly `final`, avoiding the inheritance/symmetry trap.

---

## Interview Questions

### Q1: What is the relationship between equals and hashCode?

If `a.equals(b)` is true, then `a.hashCode()` must equal `b.hashCode()`. The reverse is not required - unequal objects may share a hashCode (a collision). Violating the forward direction breaks hash-based collections.

### Q2: What happens if you override equals but not hashCode?

Object's default `hashCode` returns an identity-based value, so two "equal" objects get different hashes, land in different buckets, and a `HashMap`/`HashSet` treats them as distinct - lookups fail and duplicates appear.

### Q3: instanceof vs getClass in equals - tradeoffs?

`instanceof` allows subclass instances to be equal to superclass ones but can break **symmetry** when subclasses add state. `getClass()` enforces exact-type equality (symmetric and transitive) but violates Liskov substitution. Value types usually use `getClass()`; or make the class final.

### Q4: Why can't compareTo use `a - b` for ints?

Subtraction can **overflow** for large/negative values, flipping the sign and corrupting ordering. Use `Integer.compare(a, b)`.

### Q5: Difference between Comparable and Comparator?

`Comparable` defines a single **natural ordering** inside the class (`compareTo`). `Comparator` is an **external**, swappable strategy (`compare`) - you can have many, and chain them with `thenComparing`. Comparator doesn't require modifying the class.

### Q6: What does "consistent with equals" mean and why does it matter?

`a.compareTo(b) == 0` should match `a.equals(b)`. Sorted collections (`TreeSet`, `TreeMap`) use **compareTo/compare** for uniqueness, not equals. If they disagree, you get surprising results - e.g. `BigDecimal("1.0")` and `"1.00"` are "equal" in a TreeSet but not a HashSet.

### Q7: Demonstrate what breaks in a HashSet with a wrong hashCode.

Add two logically-equal objects whose `hashCode` differs (e.g. equals overridden, hashCode not). `set.size()` becomes 2 and `set.contains(equalObject)` returns false, because they hash to different buckets and equals is never invoked.

### Q8: Does `reversed()` reverse only the last key in a comparator chain?

No - it reverses the **entire** composed comparator. To reverse a single key, pass a reversed comparator to that step: `thenComparing(key, Comparator.reverseOrder())`.

### Q9: Are records' equals/hashCode safe for use as map keys?

Yes. Records generate equals/hashCode over all components and are immutable if components are immutable, making them excellent map keys - provided component types themselves have correct equals/hashCode.

### Q10: If a mutable field used in hashCode changes after insertion into a HashSet, what happens?

The object's bucket no longer matches its stored hash, so `contains`/`remove` may fail to find it - effectively a lost/leaked entry. Use immutable fields (or fields that don't change) in equals/hashCode for keys.

---

## Practice Code

📁 `java-prep-practice/com/prep/week4_advanced/day02_equalshashcode/EqualsHashCodeDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week4_advanced/day02_equalshashcode/EqualsHashCodeDemo.java
java -cp java-prep-practice com.prep.week4_advanced.day02_equalshashcode.EqualsHashCodeDemo
```

---

## Checklist

- [ ] I know the five equals contract properties
- [ ] I know the hashCode contract and the equals-hashCode relationship
- [ ] I can explain why HashMap/HashSet need both
- [ ] I can implement equals/hashCode with Objects helpers
- [ ] I understand the instanceof vs getClass symmetry trap
- [ ] I know the compareTo contract and "consistent with equals"
- [ ] I can build multi-key Comparators with thenComparing/reversed/nullsFirst
- [ ] I know records auto-generate equals/hashCode

---

[← Day 1: Generics](day01-generics.md) | [Next: Day 3 - Enums & Nested Classes →](day03-enums-nested-classes.md)
