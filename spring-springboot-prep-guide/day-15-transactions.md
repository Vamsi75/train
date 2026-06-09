# Day 15 — `@Transactional`: Propagation, Isolation & the Proxy Pitfalls

## THEORY

### 1. Declarative transactions
`@Transactional` (on a class or method) lets Spring manage begin/commit/rollback around the method via **AOP proxy** (recall Day 05). At method entry the proxy starts/joins a transaction; on normal return it commits; on a qualifying exception it rolls back.

### 2. The rollback rule (everyone gets this wrong once)
By default, Spring rolls back **only on unchecked exceptions (`RuntimeException`) and `Error`** — **NOT on checked exceptions**. So a method that throws a checked `IOException` **commits** by default.
```java
@Transactional(rollbackFor = Exception.class)   // roll back on checked exceptions too
public void doWork() throws IOException { ... }
```
Use `rollbackFor`/`noRollbackFor` to customize.

### 3. Propagation (how a transaction relates to an existing one)
| Propagation | Behavior |
|-------------|----------|
| **REQUIRED** (default) | Join existing tx, or start one if none. |
| **REQUIRES_NEW** | **Always start a new** tx, suspending any current one. |
| **SUPPORTS** | Join if present, else run non-transactionally. |
| **NOT_SUPPORTED** | Suspend any tx, run non-transactionally. |
| **MANDATORY** | Must run within an existing tx, else throw. |
| **NEVER** | Must run with no tx, else throw. |
| **NESTED** | Savepoint within the current tx (partial rollback). |

**Classic use of REQUIRES_NEW:** writing an **audit log that must persist even if the main transaction rolls back** — put the audit insert in a `REQUIRES_NEW` method so it commits independently.

### 4. Isolation levels (recap from DB side, applied via Spring)
`DEFAULT` (use the DB's), `READ_UNCOMMITTED`, `READ_COMMITTED`, `REPEATABLE_READ`, `SERIALIZABLE`. Set via `@Transactional(isolation = Isolation.REPEATABLE_READ)`. Controls dirty/non-repeatable/phantom reads (see the MySQL guide Day 11–12).

### 5. The proxy pitfalls (these are the senior-level questions)
- **Self-invocation:** calling a `@Transactional` method from another method **in the same bean** bypasses the proxy → **no transaction**. (Day 05.)
- **Non-public methods:** `@Transactional` on `private`/`protected`/package-private is **ignored** (proxy can't advise it). Must be `public` (with CGLIB; even more restrictive logically).
- **`final` method/class:** CGLIB can't override → advice ignored.
- **Calling through `this`:** same as self-invocation.
- **Wrong exception type:** checked exception thrown → commits by default (see #2).
- **`readOnly` is a hint:** `@Transactional(readOnly = true)` lets Hibernate skip dirty checking and DBs optimize, but it doesn't *forbid* writes universally — treat it as an optimization, not a guarantee.

### 6. Transaction boundaries belong in the service layer
Put `@Transactional` on **service methods**, not controllers or repositories. A service method is the unit of business work; the controller shouldn't hold a transaction open across HTTP concerns, and per-repository transactions can't span multiple operations atomically.

### 7. `@Transactional` and `@Async` / events
- An `@Async` method runs on **another thread** → it gets its **own** transaction context (the caller's transaction does **not** propagate across threads).
- `@TransactionalEventListener(AFTER_COMMIT)` (Day 06) ties side effects to commit.

### 8. Programmatic transactions
For fine-grained control: `TransactionTemplate` or `PlatformTransactionManager` directly — useful inside loops where you want a transaction **per item** rather than one giant transaction (avoids huge undo logs / lock durations, like the chunked patterns in the MySQL guide).

---

## PRACTICE

```java
@Service
public class TransferService {
    private final AccountRepo accounts;
    private final AuditService audit;
    public TransferService(AccountRepo accounts, AuditService audit) {
        this.accounts = accounts; this.audit = audit;
    }

    @Transactional                                   // REQUIRED, rolls back on RuntimeException
    public void transfer(Long from, Long to, BigDecimal amount) {
        Account a = accounts.findById(from).orElseThrow();
        Account b = accounts.findById(to).orElseThrow();
        if (a.getBalance().compareTo(amount) < 0)
            throw new InsufficientFundsException();   // unchecked → triggers rollback
        a.debit(amount); b.credit(amount);            // dirty checking flushes at commit
        audit.record(from, to, amount);               // see below — REQUIRES_NEW
    }
}

@Service
class AuditService {
    @Transactional(propagation = Propagation.REQUIRES_NEW)   // commits even if transfer rolls back
    public void record(Long from, Long to, BigDecimal amt) { /* insert audit row */ }
}

// Programmatic transaction-per-item (big batch, short transactions)
@Service
class BatchProcessor {
    private final TransactionTemplate tx;
    BatchProcessor(PlatformTransactionManager tm) { this.tx = new TransactionTemplate(tm); }
    public void process(List<Long> ids) {
        for (Long id : ids) {
            tx.executeWithoutResult(status -> handleOne(id));  // one tx per item
        }
    }
    void handleOne(Long id) { /* ... */ }
}
```

**Exercises:**
1. Throw a **checked** exception from a `@Transactional` method and prove it **commits**; then add `rollbackFor` and prove it rolls back.
2. Demonstrate self-invocation: call a `@Transactional` method from a non-transactional method in the same bean and show no rollback occurs; fix by extracting a bean.
3. Use `REQUIRES_NEW` so an audit row survives a rolled-back main transaction.
4. Replace one giant transaction over 100k rows with a `TransactionTemplate` per-chunk approach and explain the benefit.

---

## TRICKY INTERVIEW QUESTIONS & ANSWERS

**Q1. Does Spring roll back on checked exceptions by default?**
**No.** By default Spring rolls back only on **unchecked exceptions (`RuntimeException`) and `Error`**. A checked exception (e.g., `IOException`) thrown from a `@Transactional` method **commits** the transaction. To change this, set `@Transactional(rollbackFor = Exception.class)`. This default trips up almost everyone once.

**Q2. Why does `@Transactional` silently do nothing on a method called from within the same class?**
Because Spring's transaction management is **proxy-based** (AOP). A self-invocation (`this.method()`) calls the **target object directly**, bypassing the proxy that would start the transaction — so no transaction is created. Fixes: move the method to a separate bean, inject the bean into itself, use `AopContext.currentProxy()`, or switch to AspectJ weaving. The same applies to `private`/`final` methods, which the proxy can't advise at all.

**Q3. When would you use `REQUIRES_NEW`?**
When a piece of work must commit (or roll back) **independently** of the surrounding transaction. The classic case: an **audit/log record that should persist even if the main business transaction fails** — wrap it in `REQUIRES_NEW` so it gets its own transaction, suspends the outer one, commits, then resumes the outer. Also used to ensure a sub-operation's failure doesn't roll back unrelated work.

**Q4. `REQUIRED` vs `NESTED` — difference?**
`REQUIRED` joins the existing transaction (or creates one) — a rollback anywhere rolls back **everything**. `NESTED` creates a **savepoint** within the current transaction; the nested part can roll back to the savepoint **without** aborting the outer transaction, but if the outer rolls back, the nested work goes too. `NESTED` needs JDBC savepoint support. `REQUIRES_NEW`, by contrast, is a truly **independent** transaction (separate connection/commit).

**Q5. Where should `@Transactional` go — controller, service, or repository?**
The **service layer**, because that's where a unit of business work lives and where you compose multiple repository calls atomically. Controllers shouldn't hold transactions across HTTP/serialization concerns (and `open-in-view` issues), and per-repository transactions can't span multiple operations. Service-level boundaries make the atomic unit explicit and testable.

**Q6. Is `@Transactional(readOnly = true)` enforced?**
It's primarily an **optimization hint**, not a hard guarantee. It tells Hibernate to skip dirty-checking/flush (faster reads) and the JDBC driver/DB may optimize (e.g., route to a read replica, set the connection read-only). Depending on the DB/driver, an attempted write may or may not actually fail. Treat it as "this is a read transaction, optimize accordingly," and don't rely on it to *prevent* writes.

**Q7. Does a transaction propagate into an `@Async` method?**
No. Transactions are **thread-bound** (stored in a `ThreadLocal`), and `@Async` runs on a **different thread**, so the caller's transaction does not carry over. The async method, if annotated `@Transactional`, starts its **own** transaction on its thread. This is why you can't "fire async work inside a transaction and have it roll back together."

**Q8. Why might you prefer many small transactions over one big transaction in a batch job?**
One huge transaction holds **locks and undo/redo for the entire duration**, bloats the transaction log, lengthens lock contention and replication lag, and a failure near the end rolls back everything. Many **small transactions** (per item/chunk, via `TransactionTemplate` or `REQUIRES_NEW`) keep locks brief, allow partial progress, and bound memory/log growth — the same chunking principle as large DML in the MySQL guide.

➡ Next: [Day 16 — Caching, Scheduling & Async](day-16-caching-scheduling-async.md)
