# Java Preparation — Notes

Concept notes for the Java interview-prep track: Core Java → Java 8+ → Advanced Java. Built to refresh fundamentals for a developer with ~4 years of experience. Each topic is explained simply, with production-style examples and interview Q&A.

Runnable code for every topic lives alongside these notes in [`../java-prep-practice/`](../java-prep-practice/).

> **Time:** ~45 minutes/day. **Read** the concept → **run** the matching demo in `java-prep-practice` → **do** the exercises → **review** the interview questions.

---

## Roadmap

| Week | Topic | Days |
|:-----|:------|:-----|
| [Week 1-2](week1-corejava/) | Core Java | 12 days |
| [Week 3](week3-java8/) | Java 8+ Features | 6 days |
| [Week 4](week4-advanced/) | Advanced Java (Generics, Concurrency, JVM, Modern Java) | 10 days |

**Spring Boot** and **MySQL** are covered in their own complete standalone guides at the repo root:
[`../spring-springboot-prep-guide/`](../spring-springboot-prep-guide/) (28 days) · [`../mysql-prep-guide/`](../mysql-prep-guide/) (25 days).

---

## Quick Links

- [Java Cheatsheet](cheatsheets/java-cheatsheet.md)

---

## Running the practice code

Each note ends with a **Practice Code** block pointing to its demo. From the repo root:

```bash
# compile (UTF-8 keeps the emoji/unicode in some demos happy on Windows)
javac -encoding UTF-8 java-prep-practice/com/prep/week1_corejava/day09_collections/MapDemo.java

# run (java-prep-practice is the classpath root)
java -cp java-prep-practice com.prep.week1_corejava.day09_collections.MapDemo
```

Requires JDK 17+. No build tool needed — the demos are plain `main()` classes.

---

## Progress Tracker

### Week 1-2: Core Java
- [ ] Day 1: Primitives vs Wrappers
- [ ] Day 2: OOP - Classes & Objects
- [ ] Day 3: Inheritance & Polymorphism
- [ ] Day 4: Abstraction & Interfaces
- [ ] Day 5: String Handling
- [ ] Day 6: Keywords
- [ ] Day 7: Collections - List
- [ ] Day 8: Collections - Set
- [ ] Day 9: Collections - Map (HashMap internals)
- [ ] Day 10: Exception Handling
- [ ] Day 11: Multithreading Basics
- [ ] Day 12: ExecutorService

### Week 3: Java 8+
- [ ] Day 1: Lambda Expressions
- [ ] Day 2: Functional Interfaces
- [ ] Day 3: Streams Basics
- [ ] Day 4: Streams Advanced
- [ ] Day 5: Optional
- [ ] Day 6: Date/Time API

### Week 4: Advanced Java
- [ ] Day 1: Generics
- [ ] Day 2: equals, hashCode, Comparable & Comparator
- [ ] Day 3: Enums & Nested/Inner Classes
- [ ] Day 4: Concurrency Advanced (locks, volatile, atomics)
- [ ] Day 5: CompletableFuture & Async
- [ ] Day 6: JVM Internals, Memory Model & GC
- [ ] Day 7: Annotations & Reflection
- [ ] Day 8: Serialization, I/O & NIO
- [ ] Day 9: Modern Java (Records, Sealed, Pattern Matching)
- [ ] Day 10: Design Patterns in Java

---

> "You don't have to be great to start, but you have to start to be great."
