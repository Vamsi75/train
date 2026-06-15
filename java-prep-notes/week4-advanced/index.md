# Week 4: Advanced Java

The deeper topics that separate a junior from a senior Java engineer — the real interview differentiators for 4+ years of experience.

---

## Topics Covered

| Day | Topic | Status |
|:----|:------|:-------|
| 1 | [Generics](day01-generics.md) | ⬜ |
| 2 | [equals, hashCode, Comparable & Comparator](day02-equals-hashcode-comparable.md) | ⬜ |
| 3 | [Enums & Nested/Inner Classes](day03-enums-nested-classes.md) | ⬜ |
| 4 | [Concurrency Advanced (locks, volatile, atomics)](day04-concurrency-advanced.md) | ⬜ |
| 5 | [CompletableFuture & Async](day05-completablefuture.md) | ⬜ |
| 6 | [JVM Internals, Memory Model & GC](day06-jvm-memory-gc.md) | ⬜ |
| 7 | [Annotations & Reflection](day07-annotations-reflection.md) | ⬜ |
| 8 | [Serialization, I/O & NIO](day08-serialization-io-nio.md) | ⬜ |
| 9 | [Modern Java (Records, Sealed, Pattern Matching)](day09-modern-java.md) | ⬜ |
| 10 | [Design Patterns in Java](day10-design-patterns.md) | ⬜ |

---

## Learning Goals

After completing Week 4, you should be able to:

- Write type-safe generic classes and methods, and reason about wildcards & type erasure
- Implement `equals`/`hashCode`/`Comparable`/`Comparator` correctly
- Use enums and the four kinds of nested classes idiomatically
- Write correct, lock-free and lock-based concurrent code; explain the Java Memory Model
- Compose asynchronous pipelines with `CompletableFuture`
- Explain JVM memory areas, class loading, and how garbage collection works
- Use annotations and reflection (the foundation of Spring/JPA)
- Read and write data with classic I/O and modern NIO
- Apply Java 14–21 features: records, sealed classes, pattern matching, switch expressions, text blocks
- Recognize and implement the common GoF design patterns in idiomatic Java

---

## Practice Package

```
java-prep-practice/com/prep/week4_advanced/
├── day01_generics/
├── day02_equalshashcode/
├── day03_enums/
├── day04_concurrency/
├── day05_async/
├── day06_jvm/
├── day07_reflection/
├── day08_io/
├── day09_modern/
└── day10_patterns/
```

Each package contains runnable examples you can experiment with.
