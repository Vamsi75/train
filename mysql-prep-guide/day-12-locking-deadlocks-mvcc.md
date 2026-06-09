# Day 12 — Locking, Deadlocks & MVCC Internals

## THEORY

### 1. Lock granularity
- **Table locks** — coarse (MyISAM uses these; InnoDB uses them rarely, e.g., `LOCK TABLES`, some DDL).
- **Row locks** — InnoDB's bread and butter; lock individual index records → high concurrency.
- **Metadata locks (MDL)** — protect schema during DDL; a long-running transaction can block an `ALTER` (and that ALTER then blocks everyone — a classic outage).

### 2. InnoDB lock modes
- **Shared (S)** — for reads (`FOR SHARE`); many can hold S together.
- **Exclusive (X)** — for writes (`UPDATE/DELETE/FOR UPDATE`); only one holder, blocks S and X.
- **Intention locks (IS/IX)** — table-level flags signaling intent to lock rows; make table-vs-row lock compatibility checks fast. Mostly internal.

### 3. Record, gap, and next-key locks (the InnoDB special sauce)
- **Record lock** — locks a single index row.
- **Gap lock** — locks the *space between* index records (no row there), preventing inserts into that gap. Exists to stop **phantoms** under REPEATABLE READ.
- **Next-key lock** = record lock + gap before it. Default locking unit at RR for range scans.
- Under **READ COMMITTED**, gap locks are mostly **disabled** → more concurrency but phantoms possible.

**Key insight:** locks are on **index records**, not rows-as-such. A query with no usable index may lock *many* rows / large gaps (even the whole range), causing surprise contention. Good indexing reduces locking.

### 4. Deadlocks
Two transactions each hold a lock the other needs → cycle. InnoDB **detects** the cycle and **rolls back the "cheaper" victim** (the one with less work done), returning error **1213** (`Deadlock found; try restarting transaction`). Your app should **catch 1213 and retry**.

Common causes:
- Different transactions locking rows in **different orders**.
- Lock upgrades (S → X on the same row from two txns).
- Gap locks colliding on inserts.

Prevention:
- **Access rows/tables in a consistent order** everywhere.
- Keep transactions **short**; touch fewer rows.
- Use proper indexes so locks are narrow.
- Lower isolation to READ COMMITTED if phantoms aren't a concern (removes most gap locks).

### 5. Lock waits & timeouts
- `innodb_lock_wait_timeout` (default 50s) — a txn waiting for a lock errors out (**1205**) after this.
- Distinguish a **lock wait timeout (1205)** — waited too long — from a **deadlock (1213)** — cycle detected and victimized immediately.

### 6. Diagnosing locks
```sql
SHOW ENGINE INNODB STATUS\G                 -- LATEST DETECTED DEADLOCK section
SELECT * FROM performance_schema.data_locks;        -- current locks held/requested
SELECT * FROM performance_schema.data_lock_waits;   -- who waits for whom
-- 5.7: information_schema.innodb_locks / innodb_lock_waits (deprecated in 8.0)
SELECT * FROM sys.innodb_lock_waits\G               -- friendly view: blocking vs waiting
```

---

## PRACTICE
> Use two sessions A and B again.

```sql
-- Row lock contention
-- A:
START TRANSACTION;
UPDATE products SET stock=stock-1 WHERE product_id=1;   -- X lock on row 1
-- B:
START TRANSACTION;
UPDATE products SET stock=stock-1 WHERE product_id=1;   -- BLOCKS, waits for A
-- A:
COMMIT;   -- B now proceeds

-- Gap lock / phantom prevention (REPEATABLE READ)
-- A:
START TRANSACTION;
SELECT * FROM events WHERE user_id BETWEEN 100 AND 110 FOR UPDATE;  -- next-key locks the range
-- B:
INSERT INTO events (user_id,event_type,created_at) VALUES (105,'click',NOW()); -- BLOCKS (gap locked)
-- A:
COMMIT;   -- B proceeds

-- Force a deadlock
-- A:                                  -- B:
START TRANSACTION;                     START TRANSACTION;
UPDATE products SET price=price WHERE product_id=1;
                                       UPDATE products SET price=price WHERE product_id=2;
UPDATE products SET price=price WHERE product_id=2;   -- A waits on B
                                       UPDATE products SET price=price WHERE product_id=1; -- cycle → 1213
-- One session gets: ERROR 1213 Deadlock found. Inspect it:
SHOW ENGINE INNODB STATUS\G            -- read LATEST DETECTED DEADLOCK

-- See who blocks whom
SELECT * FROM sys.innodb_lock_waits\G
```

**Exercises:**
1. Reproduce the deadlock above, read `SHOW ENGINE INNODB STATUS`, and identify the victim and the two lock orders.
2. Show that the same range scan locks *fewer* rows when an index exists on the WHERE column vs when it doesn't.
3. Trigger a lock wait timeout (1205) by leaving session A's lock held > `innodb_lock_wait_timeout`.
4. Switch session A to READ COMMITTED and show the gap-lock insert (phantom case) no longer blocks.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Deadlock (1213) vs lock wait timeout (1205) — what's the difference?**
A **deadlock** is a *cycle* of mutual waits that InnoDB detects **immediately** and resolves by rolling back a victim transaction. A **lock wait timeout** is a single transaction waiting **too long** (> `innodb_lock_wait_timeout`) for a lock that may not be part of a cycle. Deadlock = structural cycle; timeout = excessive wait.

**Q2. How does InnoDB choose the deadlock victim?**
It rolls back the transaction that has done the **least work** (roughly, fewest rows modified / smallest undo log — "cheapest to undo"), so the more-invested transaction can proceed. Your application must catch 1213 and **retry** the victimized transaction.

**Q3. What is a gap lock and why does it exist?**
A lock on the **interval between index records** (where no row currently exists), preventing other transactions from **inserting** into that gap. It exists to stop **phantom reads** under REPEATABLE READ. Gap locks are why two transactions can deadlock on inserts even when they touch "different" rows.

**Q4. A `DELETE ... WHERE non_indexed_col = x` caused way more lock contention than expected. Why?**
Without an index, InnoDB must scan the table and takes **next-key locks on every row it examines** (not just matching rows), effectively locking large ranges or the whole table. Add an index on the WHERE column so locking is limited to the matching records.

**Q5. Two transactions update the same set of rows but in opposite orders. What's the risk and the fix?**
Classic **deadlock** risk: A locks row 1 then waits for row 2; B locks row 2 then waits for row 1. Fix by enforcing a **global, consistent locking order** (e.g., always update rows ordered by primary key) across all code paths.

**Q6. Under READ COMMITTED, what changes about gap locking, and what do you trade away?**
READ COMMITTED **largely disables gap/next-key locks** (locks only the matching index records), greatly improving concurrency and reducing deadlocks — but you **lose phantom protection** and consistent-snapshot reads (each statement sees latest committed data). Good for high-concurrency OLTP that tolerates phantoms.

**Q7. How would you debug a recurring production deadlock?**
(1) Read `SHOW ENGINE INNODB STATUS` → *LATEST DETECTED DEADLOCK* to see both transactions, their SQL, and the locks held/waited. (2) Identify the conflicting lock-acquisition order. (3) Check indexes (missing index widening locks). (4) Fix: consistent access order, shorter transactions, better indexes, possibly READ COMMITTED, and **add retry-on-1213** in the app. Enable `innodb_print_all_deadlocks` to log them all.

**Q8. Can a SELECT ever take a lock?**
Yes — `SELECT ... FOR UPDATE` (X) and `SELECT ... FOR SHARE` (S) are **locking reads**. Plain SELECT under MVCC takes no row locks. Also, foreign-key checks and `INSERT ... SELECT` can take locks on the read source.

➡ Next: [Day 13 — Stored Procedures & Functions](day-13-stored-procedures-functions.md)
