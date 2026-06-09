# Day 11 — Transactions, ACID & Isolation Levels

## THEORY

### 1. ACID
- **Atomicity** — all statements in a transaction succeed or none do (rollback). Backed by the **undo log**.
- **Consistency** — a transaction moves the DB from one valid state to another (constraints, triggers, app rules hold).
- **Isolation** — concurrent transactions don't step on each other (controlled by isolation levels).
- **Durability** — once committed, data survives a crash. Backed by the **redo log** + flush settings.

### 2. Transaction control
```sql
START TRANSACTION;          -- or BEGIN
UPDATE accounts SET bal=bal-100 WHERE id=1;
UPDATE accounts SET bal=bal+100 WHERE id=2;
COMMIT;                      -- or ROLLBACK
SAVEPOINT sp1; ... ROLLBACK TO sp1;   -- partial rollback
```
- `autocommit` is **ON by default** — each statement is its own transaction unless you `START TRANSACTION`.
- DDL causes an **implicit commit** (you can't roll it back).

### 3. The four read phenomena (concurrency anomalies)
- **Dirty read** — reading another transaction's *uncommitted* changes.
- **Non-repeatable read** — re-reading a row gives a different value because another txn committed an UPDATE in between.
- **Phantom read** — re-running a range query returns new/missing *rows* because another txn committed an INSERT/DELETE.
- **Lost update** — two txns read-modify-write the same row; one overwrites the other.

### 4. Isolation levels (SQL standard) and what they prevent
| Level | Dirty read | Non-repeatable | Phantom |
|-------|-----------|----------------|---------|
| READ UNCOMMITTED | ✅ possible | ✅ | ✅ |
| READ COMMITTED | ❌ | ✅ | ✅ |
| **REPEATABLE READ** (InnoDB default) | ❌ | ❌ | ❌* |
| SERIALIZABLE | ❌ | ❌ | ❌ |

\* **InnoDB's REPEATABLE READ also prevents phantoms** for consistent reads via MVCC snapshots, and for locking reads via **next-key (gap) locks** — stronger than the SQL standard requires. This is a favorite "gotcha" fact.

### 5. How InnoDB implements isolation: MVCC + snapshots
- **MVCC (Multi-Version Concurrency Control):** readers see a consistent **snapshot**; they don't block writers and aren't blocked by them. Old row versions live in the **undo log**.
- Under **REPEATABLE READ**, the snapshot is taken at the **first read** of the transaction and reused for all plain `SELECT`s — so you see the same data all transaction long.
- Under **READ COMMITTED**, a **fresh snapshot per statement** — so each SELECT sees the latest committed data (non-repeatable reads possible).

### 6. Consistent (snapshot) read vs locking read
- Plain `SELECT` = **consistent/snapshot read** (no locks, reads from MVCC version).
- `SELECT ... FOR UPDATE` (write lock) / `SELECT ... FOR SHARE` (shared lock) = **locking reads** — read the *latest* committed row and lock it. Used to prevent lost updates.

### 7. Setting isolation
```sql
SELECT @@transaction_isolation;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET GLOBAL  TRANSACTION ISOLATION LEVEL ...;   -- new connections
```

---

## PRACTICE
> Open **two** client sessions (A and B) to see isolation live.

```sql
-- Atomicity / rollback
START TRANSACTION;
UPDATE products SET stock = stock - 5 WHERE product_id=1;
SELECT stock FROM products WHERE product_id=1;
ROLLBACK;
SELECT stock FROM products WHERE product_id=1;   -- unchanged

-- Savepoints
START TRANSACTION;
UPDATE products SET price=price+1 WHERE product_id=1;
SAVEPOINT a;
UPDATE products SET price=price+1000 WHERE product_id=1;  -- oops
ROLLBACK TO a;                                            -- undo just the bad one
COMMIT;

-- ===== Two-session isolation demo =====
-- Session A:
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT stock FROM products WHERE product_id=1;     -- e.g. 20

-- Session B (commits a change):
UPDATE products SET stock = 99 WHERE product_id=1; -- autocommit ON

-- Session A (same txn, read again):
SELECT stock FROM products WHERE product_id=1;     -- STILL 20 (snapshot) under RR
COMMIT;
SELECT stock FROM products WHERE product_id=1;     -- now 99

-- Repeat with READ COMMITTED in Session A → second read shows 99 (non-repeatable read)

-- Lost update prevention with FOR UPDATE
-- Session A:
START TRANSACTION;
SELECT stock FROM products WHERE product_id=1 FOR UPDATE;  -- locks the row
-- Session B's UPDATE on the same row now BLOCKS until A commits/rolls back
UPDATE products SET stock = stock - 1 WHERE product_id=1;
COMMIT;
```

**Exercises:**
1. Reproduce a **non-repeatable read** under READ COMMITTED and show it doesn't happen under REPEATABLE READ.
2. Demonstrate that a plain SELECT in session A is *not* blocked by an uncommitted UPDATE in session B (MVCC).
3. Show two sessions both doing `bal=bal-100` without `FOR UPDATE` causing a lost update; then fix it with `FOR UPDATE`.
4. Prove DDL auto-commits: start a txn, run a `CREATE TABLE`, then `ROLLBACK`, and confirm prior DML was committed.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. What's InnoDB's default isolation level, and how is it stronger than the SQL standard?**
**REPEATABLE READ.** The standard allows phantom reads at RR, but InnoDB prevents them too: consistent reads use a transaction-wide MVCC snapshot, and locking reads use **next-key locks** (row + gap locks) that block inserts into the scanned range. So phantoms are effectively prevented.

**Q2. Under REPEATABLE READ, when is the read snapshot established?**
At the **first consistent read** in the transaction (not at `START TRANSACTION`). All subsequent plain SELECTs reuse that snapshot. Use `START TRANSACTION WITH CONSISTENT SNAPSHOT` to take it immediately.

**Q3. A plain SELECT and `SELECT ... FOR UPDATE` in the same RR transaction can return *different* data. How?**
The plain SELECT reads from the **MVCC snapshot** (data as of the txn's first read). `FOR UPDATE` is a **locking read** that reads the **latest committed** version (and locks it). So if another txn committed a change after your snapshot, the locking read sees the new value while the plain read still sees the old one — a classic "phantom-ish" surprise.

**Q4. How does MVCC let readers not block writers?**
Each row has hidden columns (a transaction id and a roll pointer to older versions in the **undo log**). A reader reconstructs the version visible to its snapshot from the undo chain instead of waiting for a lock. Writers create new versions; readers keep reading old ones. Only writer-vs-writer on the same row contends.

**Q5. What is a "lost update" and how do you prevent it?**
Two transactions read the same value, each computes a new value from it, and the second write overwrites the first — the first update is lost. Prevent with: pessimistic locking (`SELECT ... FOR UPDATE`), or optimistic locking (a `version` column + `WHERE version = :v` check), or atomic in-place updates (`SET bal = bal - 100` instead of read-then-write).

**Q6. Why can't you ROLLBACK a `CREATE TABLE` you ran mid-transaction?**
DDL statements perform an **implicit COMMIT** before and after executing in MySQL — there's no transactional DDL for most statements. Your prior DML is committed, the DDL runs, and a later ROLLBACK has nothing to undo. (Some engines like PostgreSQL support transactional DDL; MySQL largely does not.)

**Q7. Optimistic vs pessimistic locking — when to choose which?**
**Pessimistic** (`FOR UPDATE`) locks upfront — good for high-contention, short transactions where conflicts are likely; risk of lock waits/deadlocks. **Optimistic** (version/timestamp check, retry on conflict) avoids locks — good for low-contention, read-mostly, or stateless web requests; cost is retry logic on conflict. Choose by conflict probability and transaction length.

**Q8. Does `SELECT COUNT(*)` block or get blocked by writers in InnoDB under default isolation?**
No — it's a consistent (snapshot) read using MVCC, so it neither blocks writers nor is blocked by them. It just reads the version visible to its snapshot. (It can be slow, but not blocking.)

➡ Next: [Day 12 — Locking, Deadlocks & MVCC](day-12-locking-deadlocks-mvcc.md)
