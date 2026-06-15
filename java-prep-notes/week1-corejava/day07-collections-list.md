# Day 7: Collections - List

Ordered collections that allow duplicates.

---

## Quick Definition

**List** is an ordered collection (sequence) that allows duplicate elements. Elements can be accessed by their index position.

| Implementation | Backed By | Access | Insert/Delete | Thread-Safe | When to Use |
|:--------------|:----------|:-------|:--------------|:------------|:------------|
| **ArrayList** | Dynamic array | O(1) | O(n) | No | Fast random access |
| **LinkedList** | Doubly-linked list | O(n) | O(1) | No | Frequent insertions/deletions |
| **Vector** | Dynamic array | O(1) | O(n) | Yes | Legacy (use ArrayList) |

---

## ArrayList

Most commonly used List implementation.

```java
// Creation
List<String> list = new ArrayList<>();

// Add elements
list.add("Java");
list.add("Python");
list.add("JavaScript");
list.add("Java");  // Duplicates allowed

// Access
String first = list.get(0);  // "Java"

// Size
int size = list.size();      // 4

// Contains
boolean has = list.contains("Python");  // true

// Remove
list.remove(0);              // Remove by index
list.remove("Python");       // Remove by object

// Iterate
for (String lang : list) {
    System.out.println(lang);
}

// Clear
list.clear();
```

### ArrayList Internals

- **Initial capacity**: 10
- **Growth**: 50% (newCapacity = oldCapacity + oldCapacity/2)
- **Random access**: O(1) - uses index
- **Insertion**: O(n) - needs to shift elements
- **Search**: O(n) - linear search

---

## LinkedList

Doubly-linked list implementation.

```java
LinkedList<String> list = new LinkedList<>();

// Add
list.add("A");
list.addFirst("Start");
list.addLast("End");

// Access
String first = list.getFirst();
String last = list.getLast();

// Remove
list.removeFirst();
list.removeLast();

// Queue operations
list.offer("X");     // Add to end
list.poll();         // Remove from front
list.peek();         // Get front without removing
```

### LinkedList as Queue/Deque

```java
LinkedList<String> queue = new LinkedList<>();

// Queue operations (FIFO)
queue.offer("First");
queue.offer("Second");
String head = queue.poll();  // "First"

// Deque operations (both ends)
LinkedList<String> deque = new LinkedList<>();
deque.offerFirst("A");
deque.offerLast("B");
deque.pollFirst();   // Remove from front
deque.pollLast();    // Remove from back
```

---

## ArrayList vs LinkedList

| Feature | ArrayList | LinkedList |
|:--------|:----------|:-----------|
| **Structure** | Dynamic array | Doubly-linked list |
| **Random access** | O(1) - Fast | O(n) - Slow |
| **Insert/Delete at beginning** | O(n) - Slow | O(1) - Fast |
| **Insert/Delete at end** | O(1) amortized | O(1) |
| **Memory** | Less overhead | More (stores pointers) |
| **Use when** | Frequent reads | Frequent insertions/deletions |

---

## Common Methods

```java
List<String> list = new ArrayList<>();

// Add
list.add("A");
list.add(0, "Start");        // Add at index
list.addAll(Arrays.asList("B", "C"));

// Get/Set
String item = list.get(0);
list.set(0, "Modified");

// Remove
list.remove(0);              // By index
list.remove("A");            // By object
list.removeAll(Arrays.asList("A", "B"));
list.clear();

// Search
boolean contains = list.contains("A");
int index = list.indexOf("A");
int lastIndex = list.lastIndexOf("A");

// Size
int size = list.size();
boolean empty = list.isEmpty();

// Convert
Object[] array = list.toArray();
String[] strArray = list.toArray(new String[0]);

// Sublist
List<String> sublist = list.subList(0, 2);

// Sort
Collections.sort(list);
list.sort(Comparator.naturalOrder());
```

---

## Iteration Methods

```java
List<String> list = Arrays.asList("A", "B", "C");

// 1. For-each loop
for (String item : list) {
    System.out.println(item);
}

// 2. Iterator
Iterator<String> it = list.iterator();
while (it.hasNext()) {
    System.out.println(it.next());
}

// 3. ListIterator (bidirectional)
ListIterator<String> lit = list.listIterator();
while (lit.hasNext()) {
    System.out.println(lit.next());
}

// 4. For loop with index
for (int i = 0; i < list.size(); i++) {
    System.out.println(list.get(i));
}

// 5. Java 8 forEach
list.forEach(System.out::println);

// 6. Stream API
list.stream().forEach(System.out::println);
```

---

## Common Operations

### Remove While Iterating

```java
List<Integer> list = new ArrayList<>(Arrays.asList(1, 2, 3, 4, 5));

// WRONG - ConcurrentModificationException
for (Integer num : list) {
    if (num % 2 == 0) {
        list.remove(num);  // ERROR!
    }
}

// CORRECT - Use Iterator
Iterator<Integer> it = list.iterator();
while (it.hasNext()) {
    if (it.next() % 2 == 0) {
        it.remove();  // Safe removal
    }
}

// CORRECT - removeIf (Java 8+)
list.removeIf(num -> num % 2 == 0);
```

### Sort

```java
List<Integer> numbers = Arrays.asList(5, 2, 8, 1, 9);

// Natural order
Collections.sort(numbers);

// Reverse order
Collections.sort(numbers, Collections.reverseOrder());

// Java 8+
numbers.sort(Comparator.naturalOrder());
numbers.sort(Comparator.reverseOrder());

// Custom comparator
List<String> names = Arrays.asList("John", "Alice", "Bob");
names.sort((a, b) -> a.length() - b.length());  // By length
```

### Convert Array to List

```java
// Fixed-size list
String[] array = {"A", "B", "C"};
List<String> list = Arrays.asList(array);  // Fixed size, can't add/remove

// Mutable list
List<String> mutableList = new ArrayList<>(Arrays.asList(array));

// Java 9+
List<String> list2 = List.of("A", "B", "C");  // Immutable
```

---

## Interview Questions

### Q1: Difference between ArrayList and LinkedList?

ArrayList uses dynamic array (fast random access), LinkedList uses doubly-linked list (fast insertion/deletion at ends).

### Q2: What is the default capacity of ArrayList?

10 (grows by 50% when full)

### Q3: How to make ArrayList thread-safe?

```java
List<String> syncList = Collections.synchronizedList(new ArrayList<>());
// Or use CopyOnWriteArrayList
```

### Q4: Can ArrayList contain duplicates?

Yes, List allows duplicates.

### Q5: How to convert ArrayList to Array?

```java
List<String> list = new ArrayList<>();
String[] array = list.toArray(new String[0]);
```

---

## Practice Code

📁 `java-prep-practice/com/prep/week1_corejava/day07_collections/ListDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week1_corejava/day07_collections/ListDemo.java
java -cp java-prep-practice com.prep.week1_corejava.day07_collections.ListDemo
```

---

[← Day 6: Keywords](day06-keywords.md) | [Next: Day 8 - Collections Set →](day08-collections-set.md)
