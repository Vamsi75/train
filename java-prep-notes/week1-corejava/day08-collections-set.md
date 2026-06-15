# Day 8: Collections - Set

Unique collections with no duplicates.

---

## Quick Definition

**Set** is a collection that does **NOT allow duplicates**. Order depends on implementation.

| Implementation | Ordered | Sorted | Null | Performance | When to Use |
|:--------------|:--------|:-------|:-----|:------------|:------------|
| **HashSet** | No | No | Yes (1) | O(1) | Fast lookup, no order needed |
| **LinkedHashSet** | Insertion order | No | Yes (1) | O(1) | Maintain insertion order |
| **TreeSet** | Sorted | Yes | No | O(log n) | Sorted order needed |

---

## HashSet

Most commonly used Set implementation - backed by HashMap.

```java
Set<String> set = new HashSet<>();

// Add - duplicates ignored
set.add("Java");
set.add("Python");
set.add("Java");    // Duplicate - not added

System.out.println(set);  // [Java, Python] - no order guarantee

// Contains - O(1)
boolean has = set.contains("Java");  // true

// Remove
set.remove("Java");

// Size
int size = set.size();

// Iterate
for (String lang : set) {
    System.out.println(lang);
}
```

### HashSet Internals

- Backed by **HashMap**
- Elements stored as **keys**, dummy value `PRESENT`
- Uses **hashCode()** and **equals()** to check duplicates
- Initial capacity: 16, Load factor: 0.75
- Not synchronized

---

## LinkedHashSet

Maintains **insertion order**.

```java
Set<String> set = new LinkedHashSet<>();

set.add("Java");
set.add("Python");
set.add("JavaScript");

System.out.println(set);  // [Java, Python, JavaScript] - insertion order
```

---

## TreeSet

Sorted set - implements **NavigableSet**.

```java
Set<Integer> set = new TreeSet<>();

set.add(5);
set.add(2);
set.add(8);
set.add(1);

System.out.println(set);  // [1, 2, 5, 8] - sorted order

// NavigableSet methods
TreeSet<Integer> treeSet = new TreeSet<>(set);
System.out.println("First: " + treeSet.first());      // 1
System.out.println("Last: " + treeSet.last());        // 8
System.out.println("Higher than 3: " + treeSet.higher(3));  // 5
System.out.println("Lower than 3: " + treeSet.lower(3));    // 2
```

### TreeSet Internals

- Backed by **TreeMap** (Red-Black tree)
- Elements must be **Comparable** or provide **Comparator**
- Does NOT allow **null**
- Operations: O(log n)

---

## Comparison

| Feature | HashSet | LinkedHashSet | TreeSet |
|:--------|:--------|:--------------|:--------|
| **Order** | No | Insertion | Sorted |
| **Performance** | O(1) | O(1) | O(log n) |
| **Null** | 1 null | 1 null | No null |
| **Use when** | No order needed | Order matters | Sorted order |

---

## Common Operations

```java
Set<String> set = new HashSet<>();

// Add
set.add("A");
set.add("B");
set.addAll(Arrays.asList("C", "D"));

// Contains
boolean has = set.contains("A");

// Remove
set.remove("A");
set.removeAll(Arrays.asList("B", "C"));
set.clear();

// Size
int size = set.size();
boolean empty = set.isEmpty();

// Convert to List
List<String> list = new ArrayList<>(set);

// Convert to Array
String[] array = set.toArray(new String[0]);
```

---

## Set Operations

```java
Set<Integer> set1 = new HashSet<>(Arrays.asList(1, 2, 3, 4));
Set<Integer> set2 = new HashSet<>(Arrays.asList(3, 4, 5, 6));

// Union (all elements)
Set<Integer> union = new HashSet<>(set1);
union.addAll(set2);
System.out.println("Union: " + union);  // [1, 2, 3, 4, 5, 6]

// Intersection (common elements)
Set<Integer> intersection = new HashSet<>(set1);
intersection.retainAll(set2);
System.out.println("Intersection: " + intersection);  // [3, 4]

// Difference (in set1 but not in set2)
Set<Integer> difference = new HashSet<>(set1);
difference.removeAll(set2);
System.out.println("Difference: " + difference);  // [1, 2]
```

---

## Remove Duplicates from List

```java
// Method 1: Using HashSet
List<Integer> list = Arrays.asList(1, 2, 2, 3, 3, 4);
Set<Integer> set = new HashSet<>(list);
List<Integer> unique = new ArrayList<>(set);

// Method 2: Using LinkedHashSet (maintains order)
Set<Integer> orderedSet = new LinkedHashSet<>(list);
List<Integer> uniqueOrdered = new ArrayList<>(orderedSet);

// Method 3: Java 8 Stream
List<Integer> distinct = list.stream().distinct().collect(Collectors.toList());
```

---

## Custom Objects in Set

Must override **hashCode()** and **equals()**.

```java
class Person {
    String name;
    int age;

    Person(String name, int age) {
        this.name = name;
        this.age = age;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Person person = (Person) o;
        return age == person.age && Objects.equals(name, person.name);
    }

    @Override
    public int hashCode() {
        return Objects.hash(name, age);
    }
}

Set<Person> people = new HashSet<>();
people.add(new Person("John", 25));
people.add(new Person("John", 25));  // Duplicate - not added
System.out.println(people.size());    // 1
```

---

## Interview Questions

### Q1: What is the difference between Set and List?

- **Set**: No duplicates, no order (except LinkedHashSet/TreeSet)
- **List**: Allows duplicates, maintains insertion order

### Q2: How does HashSet check for duplicates?

Uses `hashCode()` first, then `equals()` if hash matches.

### Q3: Can Set contain null?

- **HashSet/LinkedHashSet**: One null
- **TreeSet**: No null (throws NullPointerException)

### Q4: Difference between HashSet and TreeSet?

- **HashSet**: O(1), unordered, allows null
- **TreeSet**: O(log n), sorted, no null

### Q5: How to make HashSet thread-safe?

```java
Set<String> syncSet = Collections.synchronizedSet(new HashSet<>());
```

---

## Practice Code

📁 `java-prep-practice/com/prep/week1_corejava/day08_collections/SetDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week1_corejava/day08_collections/SetDemo.java
java -cp java-prep-practice com.prep.week1_corejava.day08_collections.SetDemo
```

---

[← Day 7: Collections List](day07-collections-list.md) | [Next: Day 9 - Collections Map →](day09-collections-map.md)
