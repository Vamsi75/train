# Day 8: Serialization, I/O & NIO

Turning objects into bytes, and reading/writing data the classic and modern ways.

---

## Quick Definition

**Serialization** converts an object graph into a byte stream (to store or transmit) and back (deserialization).

**I/O** is reading/writing data via streams (`java.io`). **NIO.2** (`java.nio.file`) is the modern file API (`Path`, `Files`); **NIO** (`java.nio` channels/buffers) adds non-blocking and bulk transfer.

| Topic | Package | Key types |
|:------|:--------|:----------|
| **Serialization** | `java.io` | `Serializable`, `ObjectOutputStream`, `ObjectInputStream` |
| **Classic I/O** | `java.io` | `InputStream`/`OutputStream`, `Reader`/`Writer` |
| **NIO.2 file API** | `java.nio.file` | `Path`, `Files`, `Paths` |
| **NIO channels** | `java.nio` | `ByteBuffer`, `FileChannel`, `SocketChannel`, `Selector` |

---

## Java Serialization

```java
class Session implements Serializable {
    private static final long serialVersionUID = 1L;  // ALWAYS declare this
    private final String userId;
    transient String token;   // NOT serialized (sensitive / runtime-only)
    private final int loginCount;
    // ...
}

// Write
try (var out = new ObjectOutputStream(Files.newOutputStream(path))) {
    out.writeObject(session);
}
// Read
try (var in = new ObjectInputStream(Files.newInputStream(path))) {
    Session s = (Session) in.readObject();
}
```

| Concept | Meaning |
|:--------|:--------|
| `Serializable` | Marker interface (no methods) - opts a class in |
| `serialVersionUID` | Version stamp; must match on read or `InvalidClassException` |
| `transient` | Field is skipped; comes back as default (`null` / `0` / `false`) |
| `static` fields | Never serialized (belong to the class, not the instance) |

### Why declare serialVersionUID explicitly?

If you don't, the JVM **computes one from the class structure**. Any change (add a method, reorder fields) changes it and breaks deserialization of old data with `InvalidClassException`. Declaring `1L` yourself gives you control over compatibility.

### What breaks compatibility?

| Change | Compatible? |
|:-------|:------------|
| Add a new field | Yes (old data -> default value) |
| Remove a field | Yes (extra data ignored) |
| Change a field's **type** | **No** - `InvalidClassException` |
| Change `serialVersionUID` | **No** |
| Change class -> interface, or hierarchy | **No** |

### readObject / writeObject hooks

Customize the format (validation, encryption) without abandoning default serialization:

```java
private void writeObject(ObjectOutputStream out) throws IOException {
    out.defaultWriteObject();        // write the normal fields
    out.writeObject(encrypt(secret));// then add custom data
}
private void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
    in.defaultReadObject();
    this.secret = decrypt((String) in.readObject());
}
```

### Externalizable - full manual control

```java
class Point implements Externalizable {
    private int x, y;
    public Point() {}                 // REQUIRED public no-arg ctor
    public void writeExternal(ObjectOutput o) throws IOException { o.writeInt(x); o.writeInt(y); }
    public void readExternal(ObjectInput i) throws IOException { x = i.readInt(); y = i.readInt(); }
}
```

Nothing is written automatically, so `transient` is irrelevant. Faster/smaller but more work and error-prone.

### Security risks - why teams prefer JSON

Deserialization **constructs arbitrary object graphs from untrusted bytes**, invoking `readObject`/`readResolve` of whatever classes are on the classpath. Crafted payloads (gadget chains) cause remote code execution - a top historical Java CVE source. Mitigations: never deserialize untrusted data, use `ObjectInputFilter` (Java 9+) to allow-list classes. In practice most teams use **JSON (Jackson/Gson)** or protobuf: human-readable, language-neutral, versionable, and safe by default.

---

## Classic I/O Streams

Two parallel hierarchies: **byte** streams (binary) and **char** streams (text, charset-aware).

| Byte | Char |
|:-----|:-----|
| `InputStream` / `OutputStream` | `Reader` / `Writer` |
| `FileInputStream` | `FileReader` |
| `BufferedInputStream` | `BufferedReader` |
| `ByteArrayInputStream` | `StringReader` |

```java
// Bridge bytes -> chars with an explicit charset, and BUFFER for performance
try (var r = new BufferedReader(
        new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
    String line;
    while ((line = r.readLine()) != null) System.out.println(line);
}
```

- **Always specify a charset** (`StandardCharsets.UTF_8`) - the no-arg `FileReader`/`InputStreamReader` use the platform default, a portability bug.
- **Buffer** with `BufferedReader`/`BufferedWriter` (or `BufferedInputStream`) - unbuffered single-byte reads are very slow.
- **try-with-resources** guarantees `close()` even on exception. Resources close in **reverse** order of declaration.

---

## NIO.2 - java.nio.file (preferred)

```java
Path p = Path.of("data", "a.txt");        // or Paths.get(...)

Files.writeString(p, "hello\nworld");      // write text in one call
String all  = Files.readString(p);         // read whole file
List<String> lines = Files.readAllLines(p);

Files.copy(src, dst, StandardCopyOption.REPLACE_EXISTING);
Files.move(src, dst);
Files.delete(p);                           // throws if missing
Files.deleteIfExists(p);                   // no-op if missing

// Stream APIs - MUST be closed (they hold OS handles)
try (Stream<String> s = Files.lines(p))   { s.forEach(System.out::println); }
try (Stream<Path> w = Files.walk(dir))    { w.forEach(System.out::println); }
```

> **Gotcha:** `Files.lines()`, `Files.walk()`, `Files.list()` return **streams backed by open file handles**. Use them in try-with-resources or you leak descriptors. Plain `Files.readAllLines()` returns a `List` and needs no closing.

### Deleting a directory tree

`Files.delete` only removes empty dirs. Walk the tree **in reverse order** so children go first:

```java
try (Stream<Path> walk = Files.walk(dir)) {
    walk.sorted(Comparator.reverseOrder()).forEach(p -> {
        try { Files.deleteIfExists(p); } catch (IOException ignored) {}
    });
}
```

---

## NIO Channels & Buffers (brief)

`java.nio` adds `Channel` + `ByteBuffer` for bulk, lower-level transfer and **non-blocking** I/O.

```java
ByteBuffer buf = ByteBuffer.allocate(1024);
int n = channel.read(buf);   // fills buffer
buf.flip();                  // switch from write-mode to read-mode (limit=pos, pos=0)
while (buf.hasRemaining()) process(buf.get());
buf.clear();                 // reset for next read
```

| Model | API | Behavior |
|:------|:----|:---------|
| **Blocking** | `InputStream`, blocking `SocketChannel` | Thread waits per connection |
| **Non-blocking** | `Selector` + `SelectableChannel` | One thread multiplexes many connections (basis of Netty) |

Remember the buffer dance: **write into it -> `flip()` -> read from it -> `clear()`**.

---

## Scanner vs BufferedReader

| | Scanner | BufferedReader |
|:--|:--------|:---------------|
| **Purpose** | Parse tokens/primitives (`nextInt`, `nextDouble`) | Read raw lines/chars |
| **Speed** | Slower (regex parsing) | Faster |
| **Buffer** | Small | Large (8 KB) |
| **Thread-safe** | No | `readLine()` is synchronized |
| **Use** | Console input, simple parsing | Large file/text reads |

---

## Interview Questions

### Q1: What does serialVersionUID do and why declare it?

It's a version stamp checked during deserialization. If the stored value differs from the current class's, you get `InvalidClassException`. Declaring it explicitly prevents auto-generated values from breaking compatibility on trivial code changes.

### Q2: What happens to transient and static fields on serialization?

`transient` fields are skipped and restored to defaults (`null`/`0`/`false`). `static` fields are never serialized (they belong to the class, not the instance).

### Q3: Difference between Serializable and Externalizable?

`Serializable` is a marker; the JVM serializes fields automatically. `Externalizable` requires you to implement `writeExternal`/`readExternal` and a **public no-arg constructor**; you control the entire format. Externalizable can be faster/smaller but is manual and error-prone.

### Q4: Why is Java deserialization a security risk?

`readObject` builds arbitrary object graphs from untrusted bytes, triggering gadget chains that can lead to remote code execution. Mitigate by not deserializing untrusted data and using `ObjectInputFilter`. Teams prefer JSON/protobuf for safety and interoperability.

### Q5: Byte streams vs character streams?

Byte streams (`InputStream`/`OutputStream`) handle raw binary. Character streams (`Reader`/`Writer`) handle text and apply a charset. Use `InputStreamReader`/`OutputStreamWriter` to bridge bytes to chars with an explicit charset.

### Q6: Why must you close Files.lines()/walk() but not readAllLines()?

The stream versions are lazy and keep an open file handle/descriptor until the stream is closed; not closing leaks resources. `readAllLines()` eagerly reads everything into a `List` and closes the file itself.

### Q7: What does ByteBuffer.flip() do?

It switches a buffer from write mode to read mode: sets `limit = position` and `position = 0`, so subsequent reads consume exactly what was written.

### Q8: Path vs File?

`java.io.File` is the legacy API with poor error reporting (boolean returns). `java.nio.file.Path` + `Files` is modern: rich exceptions, symbolic-link support, stream walking, atomic moves, and file attributes.

### Q9: How do you delete a non-empty directory in Java?

`Files.delete` only removes empty dirs. Walk the tree with `Files.walk` and delete in `reverseOrder()` so files are removed before their parent directories.

---

## Practice Code

📁 `java-prep-practice/com/prep/week4_advanced/day08_io/IoNioDemo.java`

```bash
javac -encoding UTF-8 java-prep-practice/com/prep/week4_advanced/day08_io/IoNioDemo.java
java -cp java-prep-practice com.prep.week4_advanced.day08_io.IoNioDemo
```

---

## Checklist

- [ ] I can serialize/deserialize an object with ObjectOutput/InputStream
- [ ] I know why serialVersionUID matters and what breaks compatibility
- [ ] I understand transient and static behavior on serialization
- [ ] I can use readObject/writeObject hooks and Externalizable
- [ ] I can explain deserialization security risks and why JSON is preferred
- [ ] I know byte vs char streams and always specify a charset
- [ ] I use buffering and try-with-resources correctly
- [ ] I can read/write/copy/move/delete/walk with java.nio.file
- [ ] I know to close Files.lines()/walk() streams
- [ ] I understand the ByteBuffer flip/clear dance and blocking vs non-blocking
- [ ] I know when to use Scanner vs BufferedReader

---

[← Day 7: Annotations & Reflection](day07-annotations-reflection.md) | [Next: Day 9 - Modern Java →](day09-modern-java.md)
