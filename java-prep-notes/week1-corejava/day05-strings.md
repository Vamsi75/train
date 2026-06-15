# Day 5: String Handling

Master Java's most frequently used class.

---

## Quick Definition

**String** is an immutable sequence of characters. Once created, its value cannot be changed. Any modification creates a new String object.

| Concept | Description | Example |
|:--------|:------------|:--------|
| **Immutable** | Cannot be changed after creation | `str = "Hello"` always stays "Hello" |
| **String Pool** | Special memory area for string literals | `"abc"` stored once |
| **String vs StringBuilder** | Immutable vs Mutable | Use StringBuilder in loops |
| **String vs StringBuffer** | Non-synchronized vs Synchronized | StringBuffer for threads |

---

## String Creation

### Two ways to create String:

```java
// 1. String literal (uses String Pool)
String str1 = "Hello";

// 2. Using new keyword (creates new object in heap)
String str2 = new String("Hello");

// Comparison
System.out.println(str1 == str2);        // false (different objects)
System.out.println(str1.equals(str2));   // true (same content)
```

### String Pool

```java
String s1 = "Java";
String s2 = "Java";
String s3 = new String("Java");

System.out.println(s1 == s2);     // true (same object in pool)
System.out.println(s1 == s3);     // false (s3 is in heap)
System.out.println(s1.equals(s3)); // true (same content)

// intern() moves heap string to pool
String s4 = s3.intern();
System.out.println(s1 == s4);     // true (now same pool object)
```

---

## String Immutability

```java
String str = "Hello";
str.concat(" World");  // Creates new string, but str unchanged
System.out.println(str);  // Still "Hello"

// Correct way
str = str.concat(" World");
System.out.println(str);  // "Hello World"
```

### Why Strings are Immutable?

| Reason | Benefit |
|:-------|:--------|
| **String Pool** | Memory efficiency - same string reused |
| **Security** | Cannot be modified (passwords, URLs) |
| **Thread Safety** | Multiple threads can share safely |
| **Hashcode Caching** | HashMap keys remain valid |

---

## Common String Methods

### Length & Character Access

```java
String str = "Hello World";

str.length();           // 11
str.charAt(0);          // 'H'
str.charAt(6);          // 'W'
str.isEmpty();          // false
str.isBlank();          // false (Java 11+)
```

### Case Conversion

```java
String str = "Hello World";

str.toUpperCase();      // "HELLO WORLD"
str.toLowerCase();      // "hello world"
```

### Searching

```java
String str = "Hello World";

str.indexOf('o');       // 4 (first occurrence)
str.lastIndexOf('o');   // 7 (last occurrence)
str.contains("World");  // true
str.startsWith("Hello"); // true
str.endsWith("World");  // true
```

### Substring

```java
String str = "Hello World";

str.substring(0, 5);    // "Hello" (0 to 4)
str.substring(6);       // "World" (6 to end)
```

### Replace

```java
String str = "Hello World";

str.replace('o', 'a');          // "Hella Warld"
str.replaceAll("o", "a");       // "Hella Warld"
str.replaceFirst("o", "a");     // "Hella World"
```

### Split & Join

```java
String str = "Java,Python,JavaScript";

String[] arr = str.split(",");  // ["Java", "Python", "JavaScript"]

// Join (Java 8+)
String joined = String.join("-", arr);  // "Java-Python-JavaScript"
```

### Trim & Strip

```java
String str = "  Hello  ";

str.trim();             // "Hello" (removes leading/trailing spaces)
str.strip();            // "Hello" (Java 11+, handles Unicode spaces)
str.stripLeading();     // "Hello  "
str.stripTrailing();    // "  Hello"
```

### Comparison

```java
String s1 = "Hello";
String s2 = "hello";

s1.equals(s2);              // false
s1.equalsIgnoreCase(s2);    // true
s1.compareTo(s2);           // negative (s1 < s2)
s2.compareTo(s1);           // positive (s2 > s1)
"abc".compareTo("abc");     // 0 (equal)
```

---

## StringBuilder vs StringBuffer

| Feature | String | StringBuilder | StringBuffer |
|:--------|:-------|:--------------|:-------------|
| **Mutability** | Immutable | Mutable | Mutable |
| **Thread-Safe** | Yes | No | Yes (synchronized) |
| **Performance** | Slow (creates new objects) | Fast | Slower than StringBuilder |
| **When to use** | Few modifications | Single thread, many modifications | Multi-threaded |

### StringBuilder Example

```java
// BAD: Creates 1000 new String objects!
String result = "";
for (int i = 0; i < 1000; i++) {
    result += i;  // Each += creates new String
}

// GOOD: Modifies same object
StringBuilder sb = new StringBuilder();
for (int i = 0; i < 1000; i++) {
    sb.append(i);
}
String result = sb.toString();
```

### StringBuilder Methods

```java
StringBuilder sb = new StringBuilder("Hello");

sb.append(" World");        // "Hello World"
sb.insert(5, ",");          // "Hello, World"
sb.delete(5, 6);            // "Hello World"
sb.deleteCharAt(5);         // "HelloWorld"
sb.reverse();               // "dlroWolleH"
sb.replace(0, 5, "Hi");     // "Hi"
sb.setCharAt(0, 'h');       // "hi"

// Convert back to String
String str = sb.toString();
```

---

## Performance Comparison

```java
// String concatenation - SLOW
String str = "";
for (int i = 0; i < 10000; i++) {
    str += "a";  // Creates 10000 new String objects!
}

// StringBuilder - FAST
StringBuilder sb = new StringBuilder();
for (int i = 0; i < 10000; i++) {
    sb.append("a");  // Modifies same object
}
```

**Performance:** StringBuilder > StringBuffer >> String (for concatenation)

---

## String Formatting

### String.format()

```java
String name = "John";
int age = 25;

String msg = String.format("Name: %s, Age: %d", name, age);
// "Name: John, Age: 25"

// Formatting numbers
String.format("%.2f", 3.14159);     // "3.14"
String.format("%,d", 1000000);      // "1,000,000"
```

### Common Format Specifiers

| Specifier | Type | Example |
|:----------|:-----|:--------|
| `%s` | String | `"Hello"` |
| `%d` | Integer | `123` |
| `%f` | Float/Double | `3.14` |
| `%.2f` | Float (2 decimals) | `3.14` |
| `%c` | Character | `'A'` |
| `%b` | Boolean | `true` |
| `%n` | Newline | Platform-specific |

---

## Common Mistakes

```java
// MISTAKE 1: Using == for comparison
String s1 = "Hello";
String s2 = new String("Hello");
if (s1 == s2) { }  // FALSE! Compares references
if (s1.equals(s2)) { }  // TRUE! Compares content

// MISTAKE 2: Modifying String in loop
String result = "";
for (int i = 0; i < 1000; i++) {
    result += i;  // Creates 1000 new objects! Use StringBuilder
}

// MISTAKE 3: NullPointerException
String str = null;
str.length();  // NPE! Always check null first

// MISTAKE 4: Not checking empty
String str = "";
str.charAt(0);  // StringIndexOutOfBoundsException

// MISTAKE 5: Forgetting immutability
String str = "Hello";
str.toUpperCase();  // str is still "Hello"
str = str.toUpperCase();  // NOW str is "HELLO"
```

---

## Production Example

```java
public class UserValidator {

    public boolean isValidEmail(String email) {
        if (email == null || email.isBlank()) {
            return false;
        }
        return email.contains("@") && email.contains(".");
    }

    public String sanitizeInput(String input) {
        if (input == null) {
            return "";
        }
        return input.trim().toLowerCase();
    }

    public String formatPhoneNumber(String phone) {
        // Remove all non-digits
        String digits = phone.replaceAll("[^0-9]", "");

        if (digits.length() == 10) {
            return String.format("(%s) %s-%s",
                digits.substring(0, 3),
                digits.substring(3, 6),
                digits.substring(6));
        }
        return phone;
    }

    public String buildQuery(String table, String[] columns) {
        StringBuilder query = new StringBuilder("SELECT ");
        query.append(String.join(", ", columns));
        query.append(" FROM ").append(table);
        return query.toString();
    }
}
```

---

## Interview Questions

### Q1: Why String is immutable?

1. **String Pool** - Memory efficiency
2. **Security** - Credentials/URLs can't be changed
3. **Thread Safety** - No synchronization needed
4. **Hashcode Caching** - HashMap keys work correctly

### Q2: Difference between String, StringBuilder, StringBuffer?

| Feature | String | StringBuilder | StringBuffer |
|:--------|:-------|:--------------|:-------------|
| Mutable | No | Yes | Yes |
| Thread-safe | Yes | No | Yes |
| Performance | Slow | Fast | Medium |

### Q3: What is String Pool?

Special memory area in heap where string literals are stored. When you create `String s = "Hello"`, JVM checks pool first. If "Hello" exists, reference is returned. If not, new string is created.

### Q4: What does intern() do?

Moves string from heap to String Pool (if not already there) and returns reference.

```java
String s1 = new String("Hello").intern();
String s2 = "Hello";
System.out.println(s1 == s2);  // true
```

### Q5: == vs equals() for String?

- `==` compares **references** (memory address)
- `equals()` compares **content** (actual characters)

Always use `equals()` for String comparison!

---

## Tricky Questions

### Q1: What is the output?

```java
String s1 = "Hello";
String s2 = "Hello";
String s3 = new String("Hello");

System.out.println(s1 == s2);
System.out.println(s1 == s3);
System.out.println(s1.equals(s3));
```

<details>
<summary>Answer</summary>

<pre>
true  (s1 and s2 point to same pool object)
false (s3 is new object in heap)
true  (content is same)
</pre>

</details>

### Q2: What is the output?

```java
String str = "Hello";
str.concat(" World");
str.toUpperCase();
System.out.println(str);
```

<details>
<summary>Answer</summary>

<pre>
Hello

String is immutable. concat() and toUpperCase() create new strings
but str still references original "Hello".
</pre>

</details>

### Q3: What is the output?

```java
String s1 = "AB";
String s2 = "AB";
String s3 = "A" + "B";
String s4 = new String("AB");
String s5 = new String("AB").intern();

System.out.println(s1 == s2);
System.out.println(s1 == s3);
System.out.println(s1 == s4);
System.out.println(s1 == s5);
```

<details>
<summary>Answer</summary>

<pre>
true  (both from pool)
true  (compile-time constant, goes to pool)
false (s4 in heap)
true  (intern() returns pool reference)
</pre>

</details>

---

## Practice Code

📁 `java-prep-practice/com/prep/week1_corejava/day05_strings/StringDemo.java`

```bash
# Compile and run
javac -encoding UTF-8 java-prep-practice/com/prep/week1_corejava/day05_strings/StringDemo.java
java -cp java-prep-practice com.prep.week1_corejava.day05_strings.StringDemo
```

The demo covers all concepts with hands-on examples and exercises.

---

## Checklist

- [ ] I understand String immutability
- [ ] I know String Pool concept
- [ ] I use equals() not == for comparison
- [ ] I know common String methods
- [ ] I understand StringBuilder vs StringBuffer
- [ ] I use StringBuilder in loops
- [ ] I know String formatting
- [ ] I can handle null/empty strings safely

---

[← Day 4: Abstraction](day04-abstraction-interfaces.md) | [Next: Day 6 - Keywords →](day06-keywords.md)
