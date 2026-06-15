# Day 9: Collections - Map

Key-value pair collections - the most important for interviews!

---

## Quick Definition

**Map** stores key-value pairs. Keys are unique, values can be duplicate.

| Implementation | Ordered | Sorted | Null Key | Null Value | Performance | When to Use |
|:--------------|:--------|:-------|:---------|:-----------|:------------|:------------|
| **HashMap** | No | No | 1 | Multiple | O(1) | General purpose, fast |
| **LinkedHashMap** | Insertion | No | 1 | Multiple | O(1) | Maintain insertion order |
| **TreeMap** | Sorted | Yes | No | Multiple | O(log n) | Sorted keys |
| **Hashtable** | No | No | No | No | O(1) | Legacy (synchronized) |

---

## HashMap - Most Important!

Most commonly used Map - **know this for interviews!**

```java
Map<String, Integer> map = new HashMap<>();

// Put - adds or updates
map.put("Java", 1);
map.put("Python", 2);
map.put("JavaScript", 3);
map.put("Java", 10);  // Updates value to 10

// Get
Integer value = map.get("Java");  // 10
Integer missing = map.get("C++"); // null

// getOrDefault
Integer val = map.getOrDefault("C++", 0);  // 0

// Contains
boolean hasKey = map.containsKey("Java");     // true
boolean hasValue = map.containsValue(10);     // true

// Remove
map.remove("Python");

// Size
int size = map.size();
```

---

## HashMap Internals - INTERVIEW FAVORITE!

### How HashMap Works

1. **Hashing**: `key.hashCode()` determines bucket
2. **Index**: `index = hash & (n-1)` where n = capacity
3. **Collision**: Same bucket → LinkedList (Java 7) or Tree (Java 8+)
4. **Retrieval**: Hash → bucket → equals() to find exact key

```java
// Internal structure (simplified)
Node<K,V>[] table;  // Array of buckets

class Node<K,V> {
    final int hash;
    final K key;
    V value;
    Node<K,V> next;  // For collision handling
}
```

### Key Points

| Feature | Value |
|:--------|:------|
| **Default capacity** | 16 |
| **Load factor** | 0.75 (resize when 75% full) |
| **Threshold** | capacity × load factor |
| **Resize** | Doubles capacity (16 → 32 → 64) |
| **Tree threshold** | 8 (LinkedList → Tree in Java 8+) |
| **Time complexity** | O(1) average, O(n) worst, O(log n) with tree |

### Why Override hashCode() and equals()?

```java
class Person {
    String name;
    int age;

    // MUST override both for HashMap keys
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
```

---

## LinkedHashMap

Maintains **insertion order** or **access order**.

```java
// Insertion order (default)
Map<String, Integer> map = new LinkedHashMap<>();
map.put("C", 3);
map.put("A", 1);
map.put("B", 2);
System.out.println(map);  // {C=3, A=1, B=2}

// Access order (for LRU cache)
Map<String, Integer> lruMap = new LinkedHashMap<>(16, 0.75f, true);
```

---

## TreeMap

Sorted by keys - implements **NavigableMap**.

```java
Map<Integer, String> map = new TreeMap<>();

map.put(3, "Three");
map.put(1, "One");
map.put(2, "Two");

System.out.println(map);  // {1=One, 2=Two, 3=Three} - sorted

// NavigableMap methods
TreeMap<Integer, String> treeMap = new TreeMap<>(map);
System.out.println("First key: " + treeMap.firstKey());
System.out.println("Last key: " + treeMap.lastKey());
System.out.println("Higher key than 2: " + treeMap.higherKey(2));
```

---

## Common Operations

```java
Map<String, Integer> map = new HashMap<>();

// Put
map.put("A", 1);
map.putIfAbsent("A", 2);  // Doesn't update (key exists)
map.putAll(otherMap);

// Get
Integer value = map.get("A");
Integer defValue = map.getOrDefault("Z", 0);

// Remove
map.remove("A");
map.remove("A", 1);  // Remove only if value matches

// Contains
boolean hasKey = map.containsKey("A");
boolean hasValue = map.containsValue(1);

// Size
int size = map.size();
boolean empty = map.isEmpty();

// Clear
map.clear();

// Java 8+ methods
map.putIfAbsent("A", 1);
map.computeIfAbsent("B", k -> k.length());
map.computeIfPresent("A", (k, v) -> v + 1);
map.merge("A", 1, Integer::sum);
```

---

## Iteration Methods

```java
Map<String, Integer> map = new HashMap<>();
map.put("A", 1);
map.put("B", 2);
map.put("C", 3);

// 1. For-each with entrySet
for (Map.Entry<String, Integer> entry : map.entrySet()) {
    System.out.println(entry.getKey() + " = " + entry.getValue());
}

// 2. For-each with keySet
for (String key : map.keySet()) {
    System.out.println(key + " = " + map.get(key));
}

// 3. For-each with values
for (Integer value : map.values()) {
    System.out.println(value);
}

// 4. Iterator
Iterator<Map.Entry<String, Integer>> it = map.entrySet().iterator();
while (it.hasNext()) {
    Map.Entry<String, Integer> entry = it.next();
    System.out.println(entry.getKey() + " = " + entry.getValue());
}

// 5. Java 8 forEach
map.forEach((key, value) -> System.out.println(key + " = " + value));
```

---

## Common Use Cases

### Count Frequency

```java
String[] words = {"apple", "banana", "apple", "orange", "banana", "apple"};
Map<String, Integer> frequency = new HashMap<>();

for (String word : words) {
    frequency.put(word, frequency.getOrDefault(word, 0) + 1);
}

System.out.println(frequency);  // {apple=3, banana=2, orange=1}

// Java 8+ way
for (String word : words) {
    frequency.merge(word, 1, Integer::sum);
}
```

### Group By

```java
List<String> names = Arrays.asList("Alice", "Bob", "Anna", "Charlie", "Alex");

Map<Character, List<String>> grouped = new HashMap<>();
for (String name : names) {
    char firstLetter = name.charAt(0);
    grouped.computeIfAbsent(firstLetter, k -> new ArrayList<>()).add(name);
}

System.out.println(grouped);  // {A=[Alice, Anna, Alex], B=[Bob], C=[Charlie]}
```

### Cache/Memoization

```java
Map<Integer, Integer> cache = new HashMap<>();

public int fibonacci(int n) {
    if (n <= 1) return n;
    if (cache.containsKey(n)) return cache.get(n);

    int result = fibonacci(n - 1) + fibonacci(n - 2);
    cache.put(n, result);
    return result;
}
```

---

## HashMap vs Hashtable vs ConcurrentHashMap

| Feature | HashMap | Hashtable | ConcurrentHashMap |
|:--------|:--------|:----------|:------------------|
| **Null key** | 1 | No | No |
| **Null value** | Yes | No | No |
| **Thread-safe** | No | Yes | Yes |
| **Performance** | Fast | Slow | Fast |
| **Synchronization** | No | Method-level | Segment-level |
| **Use** | Single-threaded | Legacy | Multi-threaded |

---

## Interview Questions

### Q1: How does HashMap work internally?

Uses array of buckets. Key's hashCode() determines bucket index. Collisions handled by LinkedList (or Tree if > 8 nodes). Uses equals() to find exact key.

### Q2: What is the default capacity and load factor?

- **Capacity**: 16
- **Load factor**: 0.75
- **Resize**: Doubles when 75% full

### Q3: Why override hashCode() and equals() for HashMap keys?

HashMap uses hashCode() to find bucket and equals() to find exact key. Without proper implementation, same logical keys may be treated as different.

### Q4: Difference between HashMap and HashSet?

HashSet internally uses HashMap. HashSet values are stored as HashMap keys with dummy value `PRESENT`.

### Q5: Can HashMap have duplicate keys?

No. Putting same key updates the value.

### Q6: What happens on collision?

Java 7: LinkedList in bucket
Java 8+: LinkedList converts to Tree when > 8 nodes (improves O(n) to O(log n))

### Q7: Why is HashMap not thread-safe?

Multiple threads can modify simultaneously causing data inconsistency. Use ConcurrentHashMap for thread-safety.

---

## Practice Code

📁 `java-prep-practice/com/prep/week1_corejava/day09_collections/MapDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week1_corejava/day09_collections/MapDemo.java
java -cp java-prep-practice com.prep.week1_corejava.day09_collections.MapDemo
```

---

## Checklist

- [ ] I understand how HashMap works internally
- [ ] I know default capacity (16) and load factor (0.75)
- [ ] I can explain collision handling
- [ ] I know why to override hashCode() and equals()
- [ ] I understand HashMap vs TreeMap vs LinkedHashMap
- [ ] I can iterate Map in different ways
- [ ] I know common use cases (frequency, grouping)
- [ ] I understand thread-safety differences

---

[← Day 8: Collections Set](day08-collections-set.md) | [Next: Day 10 - Exception Handling →](day10-exceptions.md)
