# Day 10 — Indexes: B-Tree, Composite, Covering, and When They Fail

> This is the single most interview-heavy topic for a 4-year dev. Master it.

## THEORY

### 1. What an index is
A separate, sorted data structure that lets MySQL find rows without scanning the whole table — like a book's index. InnoDB uses **B+trees** (balanced, all data in leaves, leaves linked for range scans). The trade-off: faster reads, **slower writes** (every INSERT/UPDATE/DELETE must maintain the index) and extra storage.

### 2. Clustered vs secondary (InnoDB)
- **Clustered index = the table**, ordered by the PRIMARY KEY. Leaf nodes hold the full row.
- **Secondary index** leaves hold the indexed column(s) **+ the PK value**. So a secondary lookup that needs other columns does a second lookup into the clustered index ("bookmark lookup").
- No explicit PK? InnoDB uses the first NOT NULL UNIQUE index, else an internal 6-byte rowid.

### 3. Index types
- **PRIMARY**, **UNIQUE**, plain (non-unique) — all B+trees.
- **Composite (multi-column)** — index on `(a, b, c)`.
- **Prefix index** — index first N chars of a long string: `INDEX(col(20))`.
- **FULLTEXT** — text search (`MATCH ... AGAINST`).
- **SPATIAL** — geometry (R-tree).
- **Functional / expression indexes** (8.0.13+) — `INDEX ((YEAR(created_at)))`.
- **Descending indexes** (8.0+) — truly descending B+tree for `ORDER BY ... DESC`.
- **Invisible indexes** (8.0+) — exists/maintained but optimizer ignores it (`ALTER ... ALTER INDEX x INVISIBLE`) — perfect for safely testing "can I drop this?".

### 4. The leftmost-prefix rule (the #1 composite-index question)
An index on `(a, b, c)` can serve queries filtering:
- `a` ✅, `a,b` ✅, `a,b,c` ✅
- `a` + range on `b` ✅ (but columns after the range can't use the index for equality)
- `b` alone ❌, `b,c` ❌, `c` alone ❌ (no leading `a`)

So **column order matters**. Put the most selective / most-often-equality-filtered columns first, and remember a range condition "stops" the index from using later columns for seeking.

### 5. Covering index
If an index contains **every column the query needs** (SELECT + WHERE + ORDER BY), MySQL answers entirely from the index — no clustered-index lookup. `EXPLAIN` shows **`Using index`**. This is one of the biggest wins available.

### 6. When indexes are NOT used (sargability)
- Function/expression on the indexed column: `WHERE YEAR(d)=2024`, `WHERE UPPER(name)='X'`.
- Leading wildcard: `LIKE '%abc'`.
- Implicit type conversion: string column compared to a number.
- Low selectivity: a boolean/gender column — scanning may be cheaper than the index + lookups; the optimizer may skip it.
- `OR` across different columns (sometimes) — consider `UNION` or an index merge.
- Not the leftmost prefix of a composite index.

### 7. Index maintenance & stats
- `ANALYZE TABLE t` refreshes index statistics (cardinality) used by the optimizer.
- `SHOW INDEX FROM t` shows cardinality, columns, order.
- Redundant/duplicate indexes waste space and slow writes — `(a)` is redundant if `(a,b)` exists *for prefix purposes*, but `(a)` may still help if much smaller. Use tools like `pt-duplicate-key-checker`.

---

## PRACTICE

```sql
USE prep;

-- Baseline: full scan on events (100k rows)
EXPLAIN SELECT * FROM events WHERE user_id = 42 AND event_type='purchase'\G

-- Add a composite index respecting leftmost-prefix + selectivity
CREATE INDEX idx_user_type_time ON events (user_id, event_type, created_at);
EXPLAIN SELECT * FROM events WHERE user_id=42 AND event_type='purchase'\G  -- now ref/range

-- Leftmost-prefix demonstration
EXPLAIN SELECT * FROM events WHERE user_id=42\G                 -- uses index (leading col)
EXPLAIN SELECT * FROM events WHERE event_type='purchase'\G      -- does NOT use it (no leading user_id)

-- Covering index: query satisfied entirely from the index → "Using index"
CREATE INDEX idx_cover ON events (user_id, created_at, event_type);
EXPLAIN SELECT user_id, created_at, event_type
FROM events WHERE user_id=42 ORDER BY created_at\G               -- expect "Using index"

-- Sargability: function on column kills the index
EXPLAIN SELECT * FROM events WHERE YEAR(created_at)=2024\G       -- full scan
EXPLAIN SELECT * FROM events
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01'\G -- range, index usable

-- Functional index (8.0.13+) rescues the YEAR() query if you must keep that form
CREATE INDEX idx_year ON events ((YEAR(created_at)));
EXPLAIN SELECT * FROM events WHERE YEAR(created_at)=2024\G

-- Prefix index on a long string
CREATE INDEX idx_email_prefix ON employees (email(10));

-- Invisible index: test impact of dropping without actually dropping
ALTER TABLE events ALTER INDEX idx_user_type_time INVISIBLE;
EXPLAIN SELECT * FROM events WHERE user_id=42 AND event_type='purchase'\G  -- optimizer ignores it
ALTER TABLE events ALTER INDEX idx_user_type_time VISIBLE;

-- Stats
SHOW INDEX FROM events;
ANALYZE TABLE events;
```

**Exercises:**
1. Create the *wrong* column order `(event_type, user_id)` and show with EXPLAIN that `WHERE user_id=42` can't use it.
2. Build a covering index for `SELECT user_id, COUNT(*) FROM events WHERE event_type='click' GROUP BY user_id` and confirm `Using index`.
3. Take a `LIKE '%term%'` query and explain why no B-tree index helps; propose FULLTEXT.
4. Find a redundant index in your schema and justify dropping it.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Index on `(a, b, c)`. Which of these use it: `WHERE b=1`? `WHERE a=1 AND c=3`? `WHERE a=1 AND b>5 AND c=3`?**
- `WHERE b=1`: ❌ no leading `a`.
- `WHERE a=1 AND c=3`: uses index for `a` only; `c` can't be used for seeking because `b` is skipped (it can still filter `c` as a residual, not a seek).
- `WHERE a=1 AND b>5 AND c=3`: uses `a` (equality) + `b` (range), but **`c` cannot be used for the index seek** because a range on `b` stops further index-column seeking. `c` becomes a filter.

**Q2. What is a covering index and how do you confirm one is being used?**
An index that contains all columns a query references, so MySQL never touches the table rows. Confirm via `EXPLAIN` showing **`Using index`** in the Extra column (not "Using index condition" or "Using where"). Huge win for read performance.

**Q3. `WHERE YEAR(order_date) = 2024` is slow despite an index on `order_date`. Why and two fixes?**
The function wraps the column → **non-sargable**, index unusable, full scan. Fixes: (1) rewrite as a sargable range `order_date >= '2024-01-01' AND order_date < '2025-01-01'`; (2) create a **functional index** `((YEAR(order_date)))` (8.0.13+) so the expression itself is indexed.

**Q4. How does a secondary index in InnoDB point to the row — by physical address?**
No. It stores the **primary key value**, not a physical pointer/rowid. So lookups via a secondary index do a second B+tree traversal on the clustered (PK) index unless the secondary index covers the query. This is also why a large PK bloats *every* secondary index.

**Q5. You added an index and writes got slower / a query got slower. How is that possible?**
Writes: every index must be updated on INSERT/UPDATE/DELETE, adding overhead and contention. Reads: a bad index can mislead the optimizer (stale stats), or a low-selectivity index causes many random bookmark lookups that are slower than a sequential scan. Always validate with `EXPLAIN` and `ANALYZE TABLE`, and consider invisible indexes to test.

**Q6. When is a full table scan actually the *right* choice?**
When the query selects a large fraction of rows (low selectivity), the table is tiny, or random index + bookmark lookups would cause more I/O than a sequential scan. The optimizer estimates this via cardinality stats; sometimes you want it (e.g., reporting over most rows).

**Q7. Difference between a prefix index and a covering index? Can a prefix index ever cover?**
A **prefix index** indexes only the first N characters of a long column (saves space; can't do range/order on the full value and **can't be covering** for that column since it's truncated). A **covering index** includes all needed columns fully. A prefix index can never cover a query that needs the full column value because it only stores a fragment.

**Q8. What's an "index merge" and why might you avoid relying on it?**
When a query filters on `a OR b` with separate indexes on `a` and `b`, MySQL may scan both indexes and merge results (`Using union(...)` in EXPLAIN). It works but is often slower than a single well-chosen composite index or a `UNION ALL` rewrite. Treat it as a hint that your indexing could be better.

➡ Next: [Day 11 — Transactions & ACID](day-11-transactions-acid.md)
