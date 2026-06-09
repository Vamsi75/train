# Day 24 — Twisted Interview Questions (Master Set)

> The questions that catch people. Organized by theme. Try to answer before reading. These compound everything from Days 1–23.

## A. SQL puzzles (whiteboard-style)

**Q1. Find the Nth highest salary (handle ties and "not enough rows").**
```sql
-- DENSE_RANK handles ties correctly; returns nothing if N doesn't exist
SELECT DISTINCT salary FROM (
  SELECT salary, DENSE_RANK() OVER (ORDER BY salary DESC) rnk FROM employees
) t WHERE rnk = :n;
```
Why the LIMIT/OFFSET version is wrong: `LIMIT 1 OFFSET :n-1` breaks with **duplicate salaries** (counts each duplicate as a step).

**Q2. Find duplicate rows and delete all but one (keep lowest id).**
```sql
-- Find
SELECT email, COUNT(*) FROM employees GROUP BY email HAVING COUNT(*) > 1;
-- Delete dupes, keep the min id (self-join delete)
DELETE e1 FROM employees e1
JOIN employees e2 ON e1.email = e2.email AND e1.emp_id > e2.emp_id;
```

**Q3. Gaps and islands — find missing IDs in a sequence.**
```sql
-- Missing ids between MIN and MAX using a numbers/recursive CTE LEFT JOIN
WITH RECURSIVE seq(n) AS (
  SELECT MIN(emp_id) FROM employees
  UNION ALL SELECT n+1 FROM seq WHERE n < (SELECT MAX(emp_id) FROM employees)
)
SELECT n FROM seq LEFT JOIN employees e ON e.emp_id=seq.n WHERE e.emp_id IS NULL;
```

**Q4. Running total / cumulative sum without window functions (pre-8.0).**
```sql
SELECT e.emp_id, e.salary,
  (SELECT SUM(e2.salary) FROM employees e2 WHERE e2.emp_id <= e.emp_id) running
FROM employees e ORDER BY e.emp_id;   -- O(n^2) correlated; window fn is the modern way
```

**Q5. Pivot: count orders per status as columns, one row.**
```sql
SELECT
  SUM(status='PAID') paid, SUM(status='SHIPPED') shipped,
  SUM(status='PENDING') pending, SUM(status='CANCELLED') cancelled
FROM orders;
```

**Q6. Employees who earn more than their manager.**
```sql
SELECT e.first_name FROM employees e
JOIN employees m ON e.manager_id = m.emp_id
WHERE e.salary > m.salary;
```

**Q7. Customers who ordered EVERY product in a category (relational division).**
```sql
SELECT o.customer_id
FROM orders o JOIN order_items oi ON oi.order_id=o.order_id
JOIN products p ON p.product_id=oi.product_id
WHERE p.category='Electronics'
GROUP BY o.customer_id
HAVING COUNT(DISTINCT oi.product_id) =
       (SELECT COUNT(*) FROM products WHERE category='Electronics');
```

**Q8. Median salary (no MEDIAN function in MySQL).**
```sql
WITH r AS (
  SELECT salary,
         ROW_NUMBER() OVER (ORDER BY salary) rn,
         COUNT(*) OVER () cnt
  FROM employees
)
SELECT AVG(salary) median FROM r WHERE rn IN (FLOOR((cnt+1)/2), CEIL((cnt+1)/2));
```

---

## B. Conceptual traps

**Q9. `WHERE col = NULL` returns nothing. Why, and what's correct?**
NULL comparisons use three-valued logic; `col = NULL` evaluates to `UNKNOWN` (never TRUE). Use `col IS NULL`. (See Day 1.)

**Q10. `COUNT(*)` vs `COUNT(column)` vs `COUNT(1)`?**
`COUNT(*)`/`COUNT(1)` count all rows (NULLs included), equivalent in speed. `COUNT(column)` counts non-NULL values only. (Day 1.)

**Q11. `TRUNCATE` vs `DELETE` — three differences and the rollback gotcha.**
TRUNCATE is DDL (auto-commits, can't rollback, resets auto-increment, no triggers, fast); DELETE is DML (rollback-able, fires triggers, keeps counter). (Day 2.)

**Q12. Why does `SELECT a, b FROM t GROUP BY a` error in MySQL 8 but "worked" in 5.6?**
`ONLY_FULL_GROUP_BY`: `b` is non-aggregated and not grouped → ambiguous → rejected. Old MySQL returned an arbitrary value. (Day 5.)

**Q13. A `LEFT JOIN` behaves like `INNER JOIN`. Why?**
A right-table predicate in `WHERE` filters out the NULL-extended rows. Move it to `ON`. (Day 6.)

**Q14. `NOT IN (subquery)` returns nothing. Why?**
The subquery returned a NULL; `x NOT IN (...,NULL)` is never TRUE. Use `NOT EXISTS`. (Days 4, 6.)

**Q15. Index on `(a,b,c)`: does `WHERE b=2 AND c=3` use it?**
No — no leading `a` (leftmost-prefix rule). (Day 10.)

**Q16. `WHERE YEAR(created_at)=2024` ignores the index on created_at. Fix?**
Non-sargable; rewrite as a range, or add a functional index. (Days 10, 16.)

**Q17. InnoDB default isolation is REPEATABLE READ — does it allow phantoms?**
The SQL standard says yes, but **InnoDB prevents them** via MVCC snapshots + next-key (gap) locks. (Day 11.)

**Q18. A plain SELECT and `SELECT ... FOR UPDATE` in the same RR transaction return different data. How?**
Plain = MVCC snapshot (txn-start view); FOR UPDATE = latest committed (locking read). (Day 11.)

**Q19. Deadlock (1213) vs lock wait timeout (1205)?**
Cycle detected & victim rolled back instantly vs single transaction waited too long. (Day 12.)

**Q20. Does MySQL have materialized views?**
No — emulate with a summary table + event/trigger refresh. (Day 15.)

**Q21. STATEMENT vs ROW binlog — which is safe and why?**
ROW (deterministic row images); STATEMENT diverges on `NOW()/UUID()/RAND()/LIMIT`-without-order. (Day 19.)

**Q22. Why must the partition key be in every unique index?**
Partitions enforce uniqueness only locally; including the key guarantees equal-key rows share a partition for global uniqueness. (Day 18.)

---

## C. "It depends" / judgment questions

**Q23. Should you always normalize to 3NF?**
No — normalize the OLTP core for integrity; **denormalize selectively** for read-heavy hot paths, keeping it in sync deliberately. (Day 9.)

**Q24. UUID or auto-increment PK?**
Auto-increment for InnoDB clustering performance; if you need UUIDs (distributed id generation), use **time-ordered UUID v7 / `UUID_TO_BIN(...,1)` as BINARY(16)** to avoid random-insert fragmentation. (Days 9, 18.)

**Q25. Stored procedures or application logic?**
App logic for testability/versioning/scaling; procedures for **data-intensive set operations** that would be slow to ship row-by-row to the app. (Day 13.)

**Q26. When is a full table scan the right plan?**
Low selectivity (most rows match), tiny table, or when random index lookups would cause more I/O than a sequential scan. (Days 10, 16.)

**Q27. `innodb_flush_log_at_trx_commit` = 1, 2, or 0 for a high-write logging system?**
Often `2` — survives a MySQL crash, ~1s loss only on OS/power failure, big throughput gain; `1` if even 1s of loss is unacceptable. (Day 17.)

**Q28. Read replica reads or primary reads for a user's profile right after they edit it?**
Primary (or GTID-wait on replica) for **read-after-write** consistency; replicas only for lag-tolerant reads. (Day 19.)

**Q29. Partition or shard a growing table?**
Partition for single-server manageability/archival and pruning; shard when you exceed one machine's **write/storage** capacity. (Day 18.)

**Q30. Pessimistic or optimistic locking for an inventory counter under high contention?**
High contention on the same row → either an **atomic in-place update** (`SET qty=qty-1 WHERE qty>0`) or pessimistic `FOR UPDATE`; optimistic retry storms hurt under heavy contention. (Day 11.)

---

## D. Rapid "why is this slow?" drills
For each, the one-line answer:
- **`LIKE '%term'`** → leading wildcard, no B-tree index → consider FULLTEXT.
- **`LIMIT 1000000, 10`** → deep offset scans+discards → keyset pagination.
- **`ORDER BY RAND()`** → sorts whole table → sample by random key range.
- **`WHERE status != 'X'`** → low selectivity / negation → often full scan; rethink.
- **`OR` across two columns** → may skip indexes → `UNION ALL` or composite index.
- **Implicit cast (`WHERE phone = 123`)** → per-row conversion → quote the value.
- **`SELECT *` with a covering-index opportunity** → forces row lookups → select needed columns.
- **N+1 queries from the app** → thousands of tiny queries → batch/join.
- **Function on indexed column** → non-sargable → rewrite or functional index.
- **Stale statistics** → bad plan → `ANALYZE TABLE` / histogram.

---

## E. Two killer "explain it" questions
**Q31. Walk me through exactly what InnoDB does when you `UPDATE` a row, end to end.**
Acquire an X lock on the matching index record(s); read the current version; write the new row version, recording the **undo** (old version, for rollback/MVCC) and the change in the **redo log** (write-ahead, for durability) and the in-memory buffer pool page (marked dirty); on `COMMIT`, flush/sync redo per `innodb_flush_log_at_trx_commit`, write the commit record, and (if binlog on) write the binlog event (coordinated via 2-phase commit between redo and binlog). Dirty pages flush to the `.ibd` file later via background flushing/checkpointing. Replicas pull the binlog event and apply it.

**Q32. From `SHOW ENGINE INNODB STATUS`, how do you read a deadlock?**
The *LATEST DETECTED DEADLOCK* section lists **TRANSACTION (1)** and **(2)**: each shows the SQL it was running, the lock it **holds**, and the lock it **waits for**. You match "txn 1 holds lock on index X, waits for lock on Y" against "txn 2 holds Y, waits for X" — that's the cycle. The line *"WE ROLL BACK TRANSACTION (n)"* names the victim. Read the lock modes (S/X), the index names, and the gap/record lock type to find the conflicting acquisition order, then fix the code to lock in a consistent order.

➡ Next: [Day 25 — Mock Interview & Capstone](day-25-mock-interview-capstone.md)
