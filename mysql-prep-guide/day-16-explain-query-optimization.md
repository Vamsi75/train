# Day 16 — EXPLAIN, Query Plans & Optimization

> If you can read an `EXPLAIN` out loud and say *why* a query is slow, you interview like a senior.

## THEORY

### 1. EXPLAIN forms
- `EXPLAIN SELECT ...` — the classic tabular plan (estimates).
- `EXPLAIN FORMAT=JSON SELECT ...` — detailed cost model, used by Workbench's visual explain.
- `EXPLAIN FORMAT=TREE SELECT ...` — readable tree of operations (8.0.16+).
- `EXPLAIN ANALYZE SELECT ...` — **actually runs** the query and shows *real* timing, actual vs estimated rows (8.0.18+). The truth-teller.

### 2. Key columns in tabular EXPLAIN
- **type** (access method, best→worst): `system` > `const` > `eq_ref` > `ref` > `range` > `index` > **`ALL`** (full table scan — the red flag).
- **key** — the index actually chosen (`possible_keys` lists candidates).
- **rows** — estimated rows examined at this step (multiply down the plan for a feel of total work).
- **filtered** — % of rows remaining after the condition.
- **Extra** — the gold:
  - `Using index` → **covering index** (great).
  - `Using index condition` → Index Condition Pushdown (good).
  - `Using where` → filtering after fetch (often fine, but watch with ALL).
  - `Using temporary` → a temp table built (GROUP BY/DISTINCT/some ORDER BY) — often costly.
  - `Using filesort` → sorting not satisfied by an index — costly on large sets.
  - `Using join buffer (hash join)` → no index on join, hash join used.

### 3. The optimization workflow
1. Find the slow query (slow query log, `performance_schema`, app traces).
2. `EXPLAIN`/`EXPLAIN ANALYZE` it.
3. Look for `type=ALL`, large `rows`, `Using filesort`, `Using temporary`, `filtered` very low.
4. Fix: add/adjust an index (right columns, right order, covering), rewrite the query (sargable predicates, avoid functions on columns, replace correlated subquery with join), update statistics (`ANALYZE TABLE`).
5. Re-measure. Confirm with `EXPLAIN ANALYZE` (real rows match estimates?).

### 4. Common rewrites
- **Non-sargable → sargable:** `WHERE DATE(d)=x` → range; `WHERE col+0=5` → `col=5`.
- **Kill filesort:** add an index matching `ORDER BY` (same columns + direction). A composite index can satisfy `WHERE a=? ORDER BY b`.
- **Kill temporary:** index that provides GROUP BY order, or reduce DISTINCT scope.
- **Deep OFFSET → keyset pagination** (Day 03).
- **`SELECT *` → select only needed columns** so a covering index can apply.
- **OR across columns → UNION ALL** or composite index/index-merge.

### 5. Statistics & the cost model
The optimizer is cost-based, using **index cardinality** statistics (sampled from random pages, `innodb_stats_persistent`). Stale stats → bad plans. `ANALYZE TABLE t` recomputes. MySQL 8 also supports **histograms** (`ANALYZE TABLE t UPDATE HISTOGRAM ON col`) for skewed non-indexed columns, helping `filtered` estimates.

### 6. Optimizer hints (8.0)
`SELECT /*+ INDEX(t idx) */ ...`, `/*+ JOIN_ORDER(a,b) */`, `/*+ NO_INDEX_MERGE(t) */`, `STRAIGHT_JOIN`, `FORCE INDEX (idx)`. Use as a last resort after understanding *why* the optimizer chose otherwise.

---

## PRACTICE

```sql
USE prep;

-- Red flag: full scan
EXPLAIN SELECT * FROM events WHERE event_type='purchase'\G   -- type=ALL likely

-- Add supporting index, re-check
CREATE INDEX idx_type ON events(event_type);
EXPLAIN SELECT * FROM events WHERE event_type='purchase'\G   -- type=ref now

-- filesort: ORDER BY not index-backed
EXPLAIN SELECT * FROM events WHERE user_id=42 ORDER BY created_at\G   -- Using filesort?
CREATE INDEX idx_user_time ON events(user_id, created_at);
EXPLAIN SELECT * FROM events WHERE user_id=42 ORDER BY created_at\G   -- filesort gone

-- temporary + filesort from GROUP BY
EXPLAIN SELECT event_type, COUNT(*) FROM events GROUP BY event_type\G

-- The truth: EXPLAIN ANALYZE (actual timings, actual vs estimated rows)
EXPLAIN ANALYZE
SELECT user_id, COUNT(*) FROM events WHERE event_type='click' GROUP BY user_id\G

-- TREE format readability
EXPLAIN FORMAT=TREE
SELECT c.name, SUM(oi.quantity*oi.unit_price)
FROM customers c JOIN orders o ON o.customer_id=c.customer_id
JOIN order_items oi ON oi.order_id=o.order_id
GROUP BY c.customer_id\G

-- Histogram for a skewed column the optimizer mis-estimates
ANALYZE TABLE events UPDATE HISTOGRAM ON event_type WITH 10 BUCKETS;

-- Force / ignore index to compare plans
EXPLAIN SELECT * FROM events FORCE INDEX(idx_type) WHERE event_type='login'\G
```

**Exercises:**
1. Take a query showing `type=ALL` and `Using filesort`; add one composite index that removes both. Show before/after EXPLAIN.
2. Use `EXPLAIN ANALYZE` to find a query where estimated rows differ wildly from actual; fix with `ANALYZE TABLE`/histogram.
3. Rewrite `WHERE YEAR(created_at)=2024 AND event_type='login'` to be sargable and show the plan improve.
4. Demonstrate a covering index achieving `Using index` for a SELECT of two columns.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. In EXPLAIN, what's the difference between `Using index` and `Using index condition`?**
`Using index` = **covering index**: the query is answered entirely from the index, no row fetch. `Using index condition` = **Index Condition Pushdown (ICP)**: parts of the WHERE are evaluated at the index/storage-engine level to filter before fetching rows, reducing row reads — but rows are still fetched. Covering is the stronger win.

**Q2. EXPLAIN says `rows=10` but the query is slow. How do you find the truth?**
`EXPLAIN` shows **estimates** from statistics, which can be wrong (stale stats, skew). Use **`EXPLAIN ANALYZE`** which executes the query and reports *actual* rows and per-operator timing. A large gap between estimated and actual rows points to stale statistics (fix with `ANALYZE TABLE` / histograms) or correlated-column misestimation.

**Q3. `type: index` vs `type: ALL` — both scan everything, so what's the difference?**
`ALL` = full **table** (clustered index) scan reading all rows. `index` = full **index** scan — it walks the entire secondary index in order. `index` is often used to avoid a filesort or to provide a covering read; it can be cheaper than ALL if the index is narrow, but it's still scanning everything. Neither is great for selective lookups.

**Q4. What causes `Using filesort`, and is it always bad?**
The result must be sorted (`ORDER BY`/`GROUP BY`) and **no index provides that order**, so MySQL sorts in memory or on disk. Not always catastrophic — small result sets sort fast in memory (`sort_buffer_size`). It's bad when sorting large/disk-spilled sets. Fix by adding an index whose order matches the sort.

**Q5. You added the perfect index but the optimizer ignores it. Name three reasons.**
(1) **Low selectivity** — it'd match most rows, so a scan is cheaper. (2) **Stale statistics** — optimizer misjudges cardinality (run `ANALYZE TABLE`). (3) **Non-sargable predicate** — a function/implicit cast on the column. Others: the index isn't the leftmost prefix for the predicate, type mismatch, or a small table where it doesn't matter. Diagnose, then `FORCE INDEX` only as a last resort.

**Q6. What is Index Condition Pushdown (ICP) and why does it help?**
ICP lets the storage engine evaluate index-covered parts of the `WHERE` **while traversing the index**, rejecting non-matching entries before the (expensive) clustered-index row fetch. Without ICP, MySQL fetches the full row first, then filters. It reduces random I/O on partially-covered predicates. Shown as `Using index condition`.

**Q7. How does a histogram help when you have no index on a column?**
A histogram captures the **value distribution** (frequency/buckets) of a column, so the optimizer can estimate selectivity (`filtered`) for predicates on **non-indexed** columns it would otherwise guess at (often defaulting to ~10–33%). Better estimates → better join order and access choices. Build with `ANALYZE TABLE t UPDATE HISTOGRAM ON col`.

**Q8. Walk through how you'd optimize a slow report query end to end.**
Capture it (slow log / PS), run `EXPLAIN ANALYZE`, identify the costly operator (full scan, filesort, temp table, fan-out). Check predicates for sargability, ensure supporting/composite/covering indexes, verify stats with `ANALYZE TABLE`, consider rewriting (join vs subquery, pre-aggregation, pagination), and for heavy recurring reports consider a summary table. Re-measure and confirm actual rows ≈ estimates.

➡ Next: [Day 17 — Performance Tuning](day-17-performance-tuning.md)
