# Day 03 — DML: INSERT / UPDATE / DELETE & SELECT Basics

## THEORY

### 1. INSERT variants
```sql
INSERT INTO t (a,b) VALUES (1,2);                  -- single
INSERT INTO t (a,b) VALUES (1,2),(3,4),(5,6);      -- multi-row (faster, fewer round trips)
INSERT INTO t (a,b) SELECT x,y FROM src;           -- insert-select
INSERT IGNORE INTO t ...                            -- skip rows that error (dupe key etc.)
INSERT INTO t (...) VALUES (...)
  ON DUPLICATE KEY UPDATE b = VALUES(b);            -- "upsert"
REPLACE INTO t (...) VALUES (...);                  -- delete+insert on key clash (careful!)
```
- **Multi-row insert** is dramatically faster than N single inserts (one parse, one round trip, one transaction).
- `INSERT IGNORE` silently swallows errors — including ones you *want* to know about. Use deliberately.
- `ON DUPLICATE KEY UPDATE` is the idiomatic upsert. `REPLACE` actually **deletes** the old row then inserts — fires DELETE triggers, breaks FKs/auto-increment expectations. Prefer ON DUPLICATE KEY UPDATE.

### 2. UPDATE
```sql
UPDATE employees SET salary = salary * 1.10 WHERE dept_id = 1;
UPDATE employees e JOIN departments d ON e.dept_id=d.dept_id
   SET e.salary = e.salary + 5000 WHERE d.location='Mumbai';   -- multi-table update
```
**Always know your WHERE.** Forgetting it updates every row. `SET SQL_SAFE_UPDATES=1` blocks UPDATE/DELETE without a key-based WHERE — turn it on while learning.

### 3. DELETE
```sql
DELETE FROM orders WHERE status='CANCELLED';
DELETE o FROM orders o JOIN customers c ON o.customer_id=c.customer_id
  WHERE c.city='Chennai';                          -- multi-table delete
DELETE FROM events ORDER BY created_at LIMIT 1000;  -- chunked delete (huge-table friendly)
```

### 4. SELECT — logical processing order (memorize!)
SQL is *written* `SELECT ... FROM ... WHERE ...` but *logically evaluated* in this order:

```
1. FROM / JOIN     → build the row set
2. WHERE           → filter rows (no aggregates allowed)
3. GROUP BY        → form groups
4. HAVING          → filter groups (aggregates allowed)
5. SELECT          → compute expressions, column aliases born here
6. DISTINCT
7. ORDER BY        → can use SELECT aliases
8. LIMIT / OFFSET
```
This explains two classic gotchas:
- You **can't** use a `SELECT` alias in `WHERE` (alias doesn't exist yet) but **can** in `ORDER BY`/`HAVING`.
- `WHERE` can't contain aggregates (`WHERE COUNT(*)>1` is illegal) — use `HAVING`.

### 5. LIMIT / OFFSET & pagination
```sql
SELECT * FROM events ORDER BY id LIMIT 20 OFFSET 40;   -- page 3, 20/page
SELECT * FROM events ORDER BY id LIMIT 40, 20;          -- MySQL shorthand: OFFSET, COUNT
```
**Deep-offset pagination is slow** — `LIMIT 1000000, 20` still scans 1,000,020 rows. Use **keyset/seek pagination**: `WHERE id > :last_id ORDER BY id LIMIT 20`.

---

## PRACTICE

```sql
USE prep;

-- Upsert pattern
INSERT INTO products (product_id, name, category, price, stock)
VALUES (2, 'Mouse', 'Electronics', 850, 250)
ON DUPLICATE KEY UPDATE price = VALUES(price), stock = VALUES(stock);
SELECT * FROM products WHERE product_id=2;

-- REPLACE vs ON DUPLICATE — observe the difference in auto-increment / triggers
-- (REPLACE would re-create the row)

-- Multi-table UPDATE: bump salary for Mumbai-located depts
UPDATE employees e
JOIN departments d ON e.dept_id = d.dept_id
SET e.salary = e.salary + 5000
WHERE d.location = 'Mumbai';

-- Logical order gotchas
SELECT salary*12 AS annual FROM employees ORDER BY annual;   -- alias in ORDER BY: OK
-- SELECT salary*12 AS annual FROM employees WHERE annual>1000000;  -- ERROR: alias in WHERE

-- Chunked delete on big table (safe pattern for production)
DELETE FROM events WHERE event_type='logout' ORDER BY id LIMIT 5000;
-- repeat in a loop until 0 rows affected

-- Keyset pagination vs offset
SELECT * FROM events ORDER BY id LIMIT 50000, 5;          -- slow: scans 50k rows
SELECT * FROM events WHERE id > 50000 ORDER BY id LIMIT 5; -- fast: seeks
```

**Exercises:**
1. Write an upsert that increments `stock` by a delivered quantity, inserting the product if missing.
2. Delete all `order_items` for cancelled orders using a multi-table delete.
3. Implement page 1 and "next page" of `employees` ordered by `salary DESC, emp_id` using keyset pagination.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. `REPLACE INTO` vs `INSERT ... ON DUPLICATE KEY UPDATE` — what's the hidden danger of REPLACE?**
REPLACE does a **DELETE then INSERT** when a unique/PK conflict occurs. Side effects: it fires DELETE *and* INSERT triggers, assigns a **new auto-increment id** (breaking external references), and can cascade-delete child rows via FK `ON DELETE CASCADE` — silently wiping related data. ON DUPLICATE KEY UPDATE modifies the existing row in place. Prefer the latter.

**Q2. Why can't you reference a column alias defined in SELECT inside the WHERE clause?**
Because of logical processing order: `WHERE` is evaluated *before* `SELECT`, so the alias doesn't exist yet. `ORDER BY` and `HAVING` run *after* SELECT, so aliases work there.

**Q3. `LIMIT 1000000, 10` is slow. Why, and what's the fix?**
MySQL must generate and discard the first 1,000,000 rows before returning 10 — work scales with the offset. Fix with **keyset (seek) pagination**: remember the last seen sort key and do `WHERE key > :last ORDER BY key LIMIT 10`, which uses the index to jump directly.

**Q4. You run `UPDATE t SET x=1` and 5 million rows change. What two safeguards prevent the "forgot the WHERE" disaster?**
(1) `SET SQL_SAFE_UPDATES=1` — refuses UPDATE/DELETE without a WHERE on a key/indexed column or a LIMIT. (2) Run inside an explicit transaction (`START TRANSACTION; ... ; SELECT to verify; COMMIT/ROLLBACK`) and/or test the WHERE with a SELECT first.

**Q5. How does `INSERT IGNORE` change error handling, and why is it risky?**
It downgrades errors (duplicate key, NOT NULL violation, data truncation) to **warnings** and skips the offending row, so the statement "succeeds" while silently dropping data. Risky because you may lose rows without noticing. Use only when skipping dupes is genuinely intended, and check `SHOW WARNINGS`.

**Q6. In a multi-row `INSERT`, one row violates a constraint. What happens — all rows fail or just that one?**
In a transactional engine (InnoDB) the whole statement is atomic: it **fails and rolls back the entire statement** (unless `INSERT IGNORE`). In non-transactional engines, rows before the failure may persist — another reason to use InnoDB.

**Q7. How do you delete 50 million rows without locking the table or blowing up the redo log/replication?**
**Chunk it:** `DELETE ... WHERE <condition> ORDER BY pk LIMIT 5000;` in a loop, with a small sleep between batches, until 0 rows affected. This keeps each transaction short (less locking, smaller undo, less replica lag). For wiping an entire table, `TRUNCATE` is far better than a giant DELETE.

➡ Next: [Day 04 — Functions & Filtering](day-04-functions-filtering.md)