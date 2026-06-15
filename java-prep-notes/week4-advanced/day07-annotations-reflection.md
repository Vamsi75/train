# Day 7: Annotations & Reflection

The runtime metadata + introspection machinery that powers Spring, JUnit, JPA and Jackson.

---

## Quick Definition

**Annotations** are metadata attached to code (classes, methods, fields, params). They do nothing by themselves - a *processor* (compiler, framework, or your reflection code) reads them and acts.

**Reflection** is the ability to inspect and manipulate classes, methods, fields and constructors at runtime - including creating objects, calling methods, and reading annotations on types you didn't know about at compile time.

| Concept | What it is | Example |
|:--------|:-----------|:--------|
| **Annotation** | Compile-time metadata | `@Override`, `@Entity` |
| **Meta-annotation** | Annotation on an annotation | `@Retention`, `@Target` |
| **Retention** | How long the annotation survives | `SOURCE` / `CLASS` / `RUNTIME` |
| **Reflection** | Runtime introspection API | `Class`, `Field`, `Method` |

---

## Built-in Annotations

| Annotation | Applies to | Purpose |
|:-----------|:-----------|:--------|
| `@Override` | methods | Compiler check: this really overrides a supertype method |
| `@Deprecated` | any | Marks API as obsolete (compiler warning); `@Deprecated(forRemoval=true, since="11")` |
| `@SuppressWarnings` | any | Silence specific compiler warnings, e.g. `"unchecked"`, `"deprecation"` |
| `@FunctionalInterface` | interfaces | Compiler check: exactly one abstract method |
| `@SafeVarargs` | methods/ctors | Suppress the "unchecked generic varargs" warning when you know it's safe |

```java
@FunctionalInterface
interface Transformer<T> { T apply(T t); }   // compile error if 2 abstract methods

@SafeVarargs
static <T> List<T> listOf(T... items) {       // no heap-pollution warning
    return Arrays.asList(items);
}
```

---

## Meta-Annotations

Annotations you place **on your own annotation definitions**.

| Meta-annotation | Purpose |
|:----------------|:--------|
| `@Retention` | SOURCE / CLASS / RUNTIME - how long it survives |
| `@Target` | Where it may be applied (TYPE, METHOD, FIELD, PARAMETER, ...) |
| `@Documented` | Include it in generated Javadoc |
| `@Inherited` | A subclass inherits a *class-level* annotation from its superclass |
| `@Repeatable` | Allow the annotation more than once on the same element |

```java
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
@Repeatable(Roles.class)        // needs a container annotation
@interface Role { String value(); }

@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
@interface Roles { Role[] value(); }   // the container

@Role("ADMIN")
@Role("AUDITOR")
class AdminTask {}
// read with: AdminTask.class.getAnnotationsByType(Role.class)
```

---

## Retention Policies - the Key Gotcha

| Policy | Kept in .class? | Visible at runtime? | Use |
|:-------|:----------------|:--------------------|:----|
| `SOURCE` | No | No | Lint/compile-only: `@Override`, Lombok |
| `CLASS` | Yes | No (default!) | Bytecode tools, not reflection |
| `RUNTIME` | Yes | **Yes** | Anything read via reflection: Spring, JUnit, JPA |

> **The single most common annotation bug:** you write a custom annotation, try to read it with `getAnnotation(...)`, and get `null`. Cause: the default retention is `CLASS`, so it's invisible to reflection. **You must add `@Retention(RetentionPolicy.RUNTIME)`** for any framework/reflection use.

---

## Defining a Custom Annotation

```java
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.FIELD)
@interface Column {
    String name() default "";     // element with default
    boolean nullable() default true;
}

@Column(name = "account_id", nullable = false)
private long id;
```

Element rules:
- Allowed element types: primitives, `String`, `Class`, enums, other annotations, and 1-D arrays of those.
- `default` makes the element optional.
- A single element named `value` can be set positionally: `@Role("ADMIN")`.

---

## Reflection API Essentials

```java
// 1. Get the Class object (3 ways)
Class<String> c1 = String.class;            // class literal
Class<?> c2 = "hi".getClass();              // from instance
Class<?> c3 = Class.forName("java.lang.String"); // by FQCN (JDBC drivers etc.)

// 2. Inspect members  (getDeclaredXxx = this class incl. private;
//                      getXxx        = public incl. inherited)
Field[]       fields = User.class.getDeclaredFields();
Method[]      methods = User.class.getDeclaredMethods();
Constructor<?>[] ctors = User.class.getDeclaredConstructors();

// 3. Create an instance (clazz.newInstance() is DEPRECATED since Java 9)
Constructor<User> ctor = User.class.getDeclaredConstructor(String.class, int.class);
User u = ctor.newInstance("Alice", 30);

// 4. Invoke a method:  invoke(target, args...);  static -> target is null
Method greet = User.class.getDeclaredMethod("greet", String.class);
Object r = greet.invoke(u, "world");

// 5. Read a private field with setAccessible
Field age = User.class.getDeclaredField("age");
age.setAccessible(true);     // suppress language access checks
int a = (int) age.get(u);
```

### setAccessible & the Module System

`setAccessible(true)` bypasses `private`/`protected` checks. On the **classpath** (the unnamed module) this works because the unnamed module is implicitly open. Under **JPMS** (module-path), calling it on a type whose package is not `open`/`exported` throws `InaccessibleObjectException`. Open the package with `opens com.pkg;` in `module-info.java`, or run with `--add-opens`. This is why Spring asks you to `opens` your entity packages.

---

## Reading Annotations at Runtime

```java
// Class-level
Entity e = Account.class.getAnnotation(Entity.class);
if (e != null) System.out.println(e.table());

// Field-level
for (Field f : Account.class.getDeclaredFields()) {
    Column col = f.getAnnotation(Column.class);
    if (col != null) { /* map field -> column */ }
}

// Repeatable
Role[] roles = AdminTask.class.getAnnotationsByType(Role.class);

// Presence check
boolean isTest = m.isAnnotationPresent(Test.class);
```

---

## A Mini Test Runner (how JUnit works)

```java
static void runTests(Class<?> testClass) throws Exception {
    for (Method m : testClass.getDeclaredMethods()) {
        if (!m.isAnnotationPresent(Test.class)) continue;
        Object instance = testClass.getDeclaredConstructor().newInstance();
        m.setAccessible(true);
        try {
            m.invoke(instance);
            System.out.println("[PASS] " + m.getName());
        } catch (InvocationTargetException ex) {
            // The real assertion error is wrapped - unwrap with getCause()
            System.out.println("[FAIL] " + m.getName() + " -> " + ex.getCause());
        }
    }
}
```

> **Gotcha:** an exception thrown by a reflectively-invoked method is wrapped in `InvocationTargetException`. Always call `.getCause()` to get the real exception.

---

## How Frameworks Use This

| Framework | Uses reflection/annotations to... |
|:----------|:-----------------------------------|
| **Spring** | `@Component`/`@Autowired` scanning, DI wiring, `@Transactional` proxies |
| **JUnit** | Discover & run `@Test`/`@BeforeEach` methods |
| **JPA/Hibernate** | Map `@Entity`/`@Column` to tables, set fields on load |
| **Jackson/Gson** | Read/write fields, honor `@JsonProperty`/`@JsonIgnore` |
| **Lombok** | `SOURCE`-retained annotations processed at compile time (annotation processor, not reflection) |

---

## Performance & Security Downsides

- **Performance:** reflective calls are slower than direct calls (access checks, no inlining by default). Frameworks cache `Method`/`Field` handles, and `MethodHandle`/`invokedynamic` close much of the gap. Don't reflect in hot loops.
- **Encapsulation:** `setAccessible(true)` breaks `private` - it can corrupt invariants and read secrets.
- **Type safety:** errors that would be compile-time become runtime `NoSuchMethodException` / `ClassCastException`.
- **Security:** deserialization + reflection is a classic RCE vector; modern JDKs restrict `setAccessible` under JPMS for this reason.

---

## Interview Questions

### Q1: Why does my custom annotation return null from getAnnotation()?

Default retention is `CLASS`, which is not visible to reflection. Add `@Retention(RetentionPolicy.RUNTIME)`.

### Q2: Difference between getFields() and getDeclaredFields()?

`getFields()` returns **public** fields including inherited ones. `getDeclaredFields()` returns **all** fields (private/protected/public) declared **in that class only** (not inherited).

### Q3: How does JUnit find and run test methods?

It scans the class via reflection for methods annotated `@Test` (RUNTIME retention), instantiates the class, calls `setAccessible(true)`, and `invoke()`s each. Failures arrive as `InvocationTargetException`, unwrapped via `getCause()`.

### Q4: What's the difference between the three retention policies?

`SOURCE` discarded by the compiler (lint only); `CLASS` kept in bytecode but not loaded at runtime; `RUNTIME` kept and readable via reflection.

### Q5: Why is clazz.newInstance() deprecated?

It can only call a no-arg constructor and it **swallows checked exceptions** thrown by the constructor, rethrowing them undeclared. Use `getDeclaredConstructor(...).newInstance(...)` which propagates exceptions correctly (wrapped in `InvocationTargetException`).

### Q6: What is @Inherited and what are its limits?

A subclass inherits a **class-level** annotation marked `@Inherited` from its superclass. It does **not** apply to interface annotations and does **not** make method/field annotations inherited.

### Q7: How do you make an annotation usable multiple times on one element?

Mark it `@Repeatable(Container.class)` and define a container annotation whose `value()` is an array of the repeated type. Read with `getAnnotationsByType()`.

### Q8: Why might setAccessible(true) throw at runtime even though it compiles?

Under the Java Platform Module System, reflecting into a package that isn't `open` throws `InaccessibleObjectException`. Fix with `opens` in `module-info.java` or `--add-opens` on the command line.

### Q9: Is reflection slow, and how do frameworks cope?

Reflective access is slower (access checks, missed JIT inlining). Frameworks cache `Method`/`Field` objects and increasingly use `MethodHandle`/`invokedynamic` and even compile-time code generation to avoid runtime reflection in hot paths.

---

## Practice Code

📁 `java-prep-practice/com/prep/week4_advanced/day07_reflection/AnnotationsReflectionDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week4_advanced/day07_reflection/AnnotationsReflectionDemo.java
java -cp java-prep-practice com.prep.week4_advanced.day07_reflection.AnnotationsReflectionDemo
```

---

## Checklist

- [ ] I know the 5 built-in annotations and what each checks
- [ ] I can list the meta-annotations and explain @Repeatable/@Inherited
- [ ] I understand SOURCE vs CLASS vs RUNTIME and why RUNTIME is needed for reflection
- [ ] I can define a custom annotation with elements and defaults
- [ ] I can get the Class object three ways and inspect fields/methods/constructors
- [ ] I can instantiate via a Constructor and invoke a Method reflectively
- [ ] I know to unwrap InvocationTargetException with getCause()
- [ ] I understand setAccessible and the module-system caveat
- [ ] I can explain how Spring/JUnit/JPA use annotations + reflection
- [ ] I know the performance and security downsides

---

[← Day 6: JVM Internals](day06-jvm-memory-gc.md) | [Next: Day 8 - Serialization, I/O & NIO →](day08-serialization-io-nio.md)
