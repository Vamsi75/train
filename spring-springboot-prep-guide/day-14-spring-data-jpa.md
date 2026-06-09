# Day 14 — Spring Data JPA: Repositories, Queries & the N+1 Problem

## THEORY

### 1. The stack
**JPA** (spec) → **Hibernate** (implementation) → **Spring Data JPA** (removes boilerplate by generating repository implementations). You write an interface; Spring Data provides the impl at runtime.

### 2. Entities
```java
@Entity
@Table(name = "aaa_server")
public class AAAServer {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    private String organizationId;

    @Enumerated(EnumType.STRING)   // ALWAYS STRING, never ORDINAL
    private ServerStatus status;

    @ManyToOne(fetch = FetchType.LAZY)   // LAZY by default for to-one is good practice
    @JoinColumn(name = "org_id")
    private Organization organization;

    @OneToMany(mappedBy = "server", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<PolicyAlias> aliases = new ArrayList<>();
    // equals/hashCode: base on a business key or id carefully (see Q)
}
```

### 3. Repository hierarchy
- `Repository` (marker) → `CrudRepository` → `ListCrudRepository` → `PagingAndSortingRepository` → **`JpaRepository`** (most used; adds `flush`, `saveAll`, batch, `getReferenceById`).
```java
public interface AAAServerRepository extends JpaRepository<AAAServer, Long> {
    List<AAAServer> findByOrganizationId(String organizationId);     // derived query
    Optional<AAAServer> findByName(String name);
    Page<AAAServer> findByStatus(ServerStatus status, Pageable pageable);
    long countByOrganizationId(String organizationId);

    @Query("select s from AAAServer s where s.status = :status and s.organizationId = :org")
    List<AAAServer> search(@Param("status") ServerStatus status, @Param("org") String org);

    @Modifying
    @Query("update AAAServer s set s.status = :status where s.organizationId = :org")
    int bulkUpdateStatus(@Param("status") ServerStatus status, @Param("org") String org);
}
```

### 4. Query options
- **Derived queries** — method-name parsing (`findByXAndYOrderByZ`). Great for simple cases; unreadable past ~3 conditions.
- **`@Query`** (JPQL) — explicit, refactor-safe-ish, type-checked against entities.
- **Native `@Query(nativeQuery=true)`** — raw SQL for DB-specific features.
- **`Specification`** / **Query by Example** / **Querydsl** — dynamic/criteria queries.
- **Projections** — interface or DTO projections to fetch only needed columns.

### 5. The N+1 problem (THE JPA interview question)
A `LAZY` association accessed in a loop fires **1 query for the parents + N queries (one per parent)** for the children.
```java
// 1 query for servers, then 1 query PER server for aliases → N+1
for (AAAServer s : repo.findAll()) {
    s.getAliases().size();   // triggers a lazy load each iteration
}
```
**Fixes:**
1. **`JOIN FETCH`** — `@Query("select s from AAAServer s join fetch s.aliases")` (one query). Watch pagination + fetch (in-memory paging).
2. **`@EntityGraph`** — declarative fetch plan on a repository method.
3. **Batch fetching** — `@BatchSize(size=50)` / `hibernate.default_batch_fetch_size` (turns N into N/batch).
4. **DTO projection** with a join — fetch exactly what you need in one query.

### 6. `FetchType` defaults & the LazyInitializationException
- `@ManyToOne`/`@OneToOne` default **EAGER**; `@OneToMany`/`@ManyToToMany` default **LAZY**.
- Accessing a LAZY association **outside an open session/transaction** → `LazyInitializationException`. Fix by fetching within the transaction (DTO/join fetch), **not** by enabling `open-session-in-view` (an anti-pattern that hides the problem and holds connections too long).

### 7. `save()` semantics, `getReferenceById`, dirty checking
- `save()` does insert or merge; within a transaction, **changes to a managed entity are auto-flushed (dirty checking)** — you often don't call `save()` at all.
- `getReferenceById` returns a **lazy proxy** (no DB hit until accessed) — good for setting FKs without loading.
- `findById` returns `Optional<T>`.

### 8. Auditing & optimistic locking
- `@Version` field → **optimistic locking** (throws `OptimisticLockException` on concurrent update) — prevents lost updates.
- `@CreatedDate`/`@LastModifiedDate` + `@EnableJpaAuditing` for automatic timestamps.

---

## PRACTICE

```java
// Fix N+1 with EntityGraph
public interface AAAServerRepository extends JpaRepository<AAAServer, Long> {
    @EntityGraph(attributePaths = "aliases")
    List<AAAServer> findByOrganizationId(String organizationId);   // single query with join
}

// DTO projection — fetch only needed columns in one query
public interface ServerSummary {            // interface projection
    Long getId(); String getName(); ServerStatus getStatus();
}
public interface ServerRepo extends JpaRepository<AAAServer, Long> {
    List<ServerSummary> findByStatus(ServerStatus status);

    @Query("select new com.cent.dto.ServerDto(s.id, s.name, s.organizationId, s.status) " +
           "from AAAServer s where s.organizationId = :org")     // class-based DTO projection
    List<ServerDto> summaries(@Param("org") String org);
}

// Optimistic locking
@Entity class Account {
    @Id Long id;
    @Version Long version;   // Hibernate checks/increments on update
    BigDecimal balance;
}
```
```yaml
spring:
  jpa:
    open-in-view: false       # turn OFF the anti-pattern; fetch in service layer
    properties:
      hibernate.default_batch_fetch_size: 50
    show-sql: false           # use logging.level.org.hibernate.SQL instead
logging.level.org.hibernate.SQL: DEBUG
```

**Exercises:**
1. Reproduce N+1: loop over parents touching a lazy collection with `org.hibernate.SQL=DEBUG`; count the queries. Fix with `@EntityGraph` and confirm one query.
2. Write a class-based DTO projection and verify only selected columns are fetched.
3. Add `@Version` and force two concurrent updates; observe `OptimisticLockException`.
4. Turn `open-in-view` off, trigger a `LazyInitializationException`, then fix it via join fetch.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Explain the N+1 problem and at least three fixes.**
Loading N parent rows in one query, then triggering one additional query per parent to load a lazy association = **1 + N queries**, which explodes with data size. Fixes: **`JOIN FETCH`** (single query; beware pagination), **`@EntityGraph`** (declarative fetch plan), **batch fetching** (`@BatchSize`/`default_batch_fetch_size` collapses N into N/batchSize queries), and **DTO projections** that select exactly the needed columns in one query. Detect it by logging SQL and counting statements.

**Q2. What are the default fetch types and why do they matter?**
`@ManyToOne` and `@OneToOne` default **EAGER**; `@OneToMany` and `@ManyToMany` default **LAZY**. EAGER to-one associations silently add joins/queries to every load (a hidden performance cost), so many teams set to-one associations to `LAZY` explicitly and fetch eagerly only where needed. LAZY collections cause `LazyInitializationException` if accessed outside a session.

**Q3. What causes `LazyInitializationException` and what's the right fix (and the wrong one)?**
It occurs when you access a **LAZY** association after the Hibernate **session/transaction is closed** (e.g., during JSON serialization in the controller). **Right fix:** fetch what you need **within the transaction** — DTO projection or `JOIN FETCH`/`@EntityGraph` — so the data is loaded before the session closes. **Wrong fix:** enabling `open-session-in-view`, which keeps the session open through view rendering, masking the problem and holding DB connections far too long (connection-pool starvation under load).

**Q4. Why store enums as `STRING` not `ORDINAL`?**
`@Enumerated(EnumType.ORDINAL)` stores the enum's **position (0,1,2)**. If someone **reorders or inserts** an enum constant, existing rows now map to the wrong value — silent data corruption. `EnumType.STRING` stores the name, which is stable across reordering. Always use STRING (the cost is a few bytes).

**Q5. Do you need to call `save()` after modifying a managed entity?**
Usually **no**. Within a transaction, Hibernate tracks managed entities and **auto-flushes changes (dirty checking)** at commit — modifying a field is enough. `save()` matters for **new** entities (insert) or **detached** entities (merge). Calling `save()` on an already-managed entity is redundant (and `merge` can have subtle semantics). This trips up developers coming from non-ORM persistence.

**Q6. How does `@Version` prevent lost updates?**
It implements **optimistic locking**: each update includes `WHERE version = :currentVersion` and increments the version. If another transaction modified the row first, the version no longer matches, **zero rows update**, and Hibernate throws `OptimisticLockException` — so the second writer is told to retry instead of silently overwriting the first writer's change. No DB locks held during the user "think time," unlike pessimistic locking.

**Q7. `getReferenceById` vs `findById`?**
`findById` executes a **SELECT** and returns `Optional<T>` (or empty). `getReferenceById` returns a **lazy proxy without hitting the DB** — useful when you only need to set a foreign key (e.g., `order.setCustomer(customerRepo.getReferenceById(id))`) and never read its fields. Accessing a field on the proxy for a non-existent id throws `EntityNotFoundException` lazily.

**Q8. JPQL `@Query` vs native query vs derived query — trade-offs?**
**Derived** (method name): zero SQL, great for simple finders, becomes unreadable/limited for complex logic. **JPQL `@Query`**: operates on **entities/fields** (portable across DBs, validated at startup), good for moderate complexity. **Native**: raw SQL for DB-specific features (window functions, hints) but **not portable** and bypasses some JPA features. Choose the least powerful tool that does the job; reach for native only when JPQL can't express it.

**Q9. Why is `@OneToMany` + `JOIN FETCH` + pagination dangerous?**
When you `JOIN FETCH` a collection and apply `Pageable`, Hibernate **can't paginate in SQL** (the join multiplies parent rows), so it fetches **all** matching rows and **paginates in memory** — logging a warning (`firstResult/maxResults specified with collection fetch; applying in memory`) and risking OOM on large data. Use `@EntityGraph` with a two-step fetch, batch fetching, or paginate ids first then fetch.

➡ Next: [Day 15 — Transactions](day-15-transactions.md)
