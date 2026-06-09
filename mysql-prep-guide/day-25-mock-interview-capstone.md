# Day 25 — Mock Interview, Scenario Rounds & Capstone

> Simulate the real thing. Time yourself. Speak answers aloud. Resist peeking.

## Round 1 — Rapid fire (10 min, 1–2 sentences each)
1. Clustered vs secondary index in InnoDB?
2. Why is the PK choice critical for InnoDB write performance?
3. `CHAR` vs `VARCHAR`?
4. When does a composite index `(a,b,c)` NOT get used?
5. `WHERE` vs `HAVING`?
6. `UNION` vs `UNION ALL`?
7. Default isolation level and why it's special in InnoDB?
8. `DELETE` vs `TRUNCATE` vs `DROP`?
9. What's a covering index?
10. STATEMENT vs ROW binlog?
11. `ROW_NUMBER` vs `RANK` vs `DENSE_RANK`?
12. Why parameterize queries?
13. What does `--single-transaction` do in mysqldump?
14. Partitioning vs sharding?
15. Deadlock vs lock wait timeout?

*(Answers: all in Days 1–24. Grade yourself: 13+/15 = strong.)*

---

## Round 2 — SQL at the keyboard (25 min)
Using the `prep` schema, write and test:
1. **Second-highest salary per department**, handling ties.
2. **Customers who placed orders in May 2024 but not in any other month.**
3. **Running total of revenue by order_date.**
4. **Each product's revenue and its rank within its category.**
5. **Detect and delete duplicate `order_items`** (same order+product), keeping one.
6. **Month-over-month order count change** using `LAG`.
7. **Customers who bought every Electronics product** (relational division).

> Self-check: did you use the right window function? Avoid correlated O(n²) when a join works? Handle NULLs/ties?

---

## Round 3 — Design (20 min, talk through)
**Prompt:** *Design the schema for a ride-hailing app (users, drivers, rides, payments, ratings). It must handle 50M rides/month.*
Address:
- Tables, keys, relationships (1:N, M:N), and which columns are indexed.
- PK strategy at this scale (auto-increment BIGINT vs ordered UUID; why).
- How you'd store money and timestamps (and timezone handling).
- Where you'd **denormalize** (e.g., ride summary, driver rating average) and how you'd keep it consistent.
- How you'd **partition** `rides` (by date?) and what queries that helps/hurts.
- Read scaling: replicas + read/write routing; read-after-write for "your last ride."
- When/how you'd **shard** and on what key (and which queries become scatter-gather).

---

## Round 4 — Production incident (20 min, think aloud)
**Prompt:** *It's 2 AM. Pager: "Checkout API p99 latency 8s, error rate climbing." The DB is the suspected cause. Walk me through it.*
Expected narrative:
1. **Gather signal** without mutating: `SHOW FULL PROCESSLIST`, `SHOW ENGINE INNODB STATUS`, `Threads_running`, OS (`df -h`, CPU, IO).
2. **Classify**: query storm? lock contention/blocking transaction? deadlocks? disk full? replication-related? OOM? connection exhaustion?
3. **Localize**: digest table for the top query by total time; `sys.innodb_lock_waits` for blockers.
4. **Triage fix**: `KILL` a runaway/blocker; roll back a bad deploy; purge binlogs if disk-full; raise connections if exhausted (with reserved admin slot).
5. **Stabilize & verify**: latency back to normal? errors clearing?
6. **Root cause + prevent**: missing index from last deploy? long transaction across an external call? add the index, add retry-on-1213, add alerts, write the runbook entry.
*(Full detail: Day 23.)*

---

## Round 5 — "Optimize this query" (15 min)
Given:
```sql
SELECT c.name, COUNT(*) orders, SUM(oi.quantity*oi.unit_price) revenue
FROM customers c
JOIN orders o      ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id   = o.order_id
WHERE YEAR(o.order_date) = 2024
  AND o.status <> 'CANCELLED'
GROUP BY c.customer_id, c.name
ORDER BY revenue DESC
LIMIT 20;
```
Talk through:
- The `YEAR(o.order_date)=2024` → **non-sargable**; rewrite to a range so an index on `orders(order_date)` (or `(status, order_date)`) helps.
- Supporting indexes: `orders(customer_id)`, `order_items(order_id)` (FK indexes), maybe `orders(order_date, status)`.
- The `<> 'CANCELLED'` negation is low-selectivity — fine here since most filtering is by date.
- Watch **fan-out**: joining `order_items` multiplies order rows; `COUNT(*)` now counts *items*, not orders — use `COUNT(DISTINCT o.order_id)` or pre-aggregate items per order in a subquery.
- `ORDER BY revenue DESC LIMIT 20` needs a sort (filesort) over the grouped set — acceptable post-aggregation, but verify with `EXPLAIN ANALYZE`.
- Corrected:
```sql
SELECT c.name, x.orders, x.revenue
FROM customers c
JOIN (
  SELECT o.customer_id,
         COUNT(*) orders,
         SUM(oi.quantity*oi.unit_price) revenue
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.order_id
  WHERE o.order_date >= '2024-01-01' AND o.order_date < '2025-01-01'
    AND o.status <> 'CANCELLED'
  GROUP BY o.customer_id
) x ON x.customer_id = c.customer_id
ORDER BY x.revenue DESC
LIMIT 20;
```

---

## Capstone project (do this for real — best portfolio signal)
Build a small **"E-commerce analytics" database** end to end:
1. **Schema** (3NF): customers, products, orders, order_items, payments, plus an `events` table. Add FKs, constraints, sensible types.
2. **Seed** ~1M rows (recursive CTE / a script) so EXPLAIN is meaningful.
3. **Queries**: top customers, revenue by month (window functions), cohort/retention with `events`, product affinity.
4. **Indexing**: profile each query with `EXPLAIN ANALYZE`, add the right indexes, document before/after timings.
5. **A stored procedure** that refreshes a daily revenue **summary table** (materialized-view pattern) + an **EVENT** to schedule it.
6. **A trigger** maintaining a denormalized `customers.lifetime_value`.
7. **Ops doc**: backup command (`--single-transaction`), a PITR plan, and a 1-page incident runbook.
8. **Security**: a least-privilege app user + a read-only reporting role with column restrictions.

Write a short README explaining each decision — *that document is what gets you the offer.*

---

## Final self-assessment checklist
You're ready when you can, **without notes**:
- [ ] Read any `EXPLAIN`/`EXPLAIN ANALYZE` and propose a fix.
- [ ] Explain the leftmost-prefix rule and predict index usage.
- [ ] Defend an isolation-level choice and explain MVCC.
- [ ] Diagnose a deadlock from `SHOW ENGINE INNODB STATUS`.
- [ ] Design a normalized schema and justify each denormalization.
- [ ] Describe replication, lag causes, and read-after-write handling.
- [ ] Perform a point-in-time recovery in words, step by step.
- [ ] Write window-function, CTE, and pivot queries fluently.
- [ ] Run the production playbook for slow DB / disk full / blocked queries.
- [ ] Explain why parameterized queries stop SQL injection.

Revisit any unchecked box's day. Then go get the job. 🚀

⬅ Back to [README](README.md) · See also [Rapid-fire 100](_cheatsheets/interview-rapidfire.md) & [Cheatsheet](_cheatsheets/cheatsheet.md)
