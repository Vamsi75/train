# Day 01 — RDBMS Concepts, MySQL Architecture, Storage Engines, Data Types

## THEORY

### 1. What is an RDBMS?
A **Relational Database Management System** stores data in **tables** (relations) of **rows** (tuples) and **columns** (attributes). Relationships between tables are expressed with **keys**. Built on E.F. Codd's relational model + SQL as the query language. Guarantees of a good RDBMS: data integrity (constraints), concurrency control (transactions/locks), durability (recovery), and a declarative query language.

### 2. MySQL high-level architecture (know this cold)
MySQL is layered:

```
        Clients (CLI, app, connectors)
                  │
        ┌─────────▼──────────┐
        │  Connection layer  │  auth, thread/connection handling, SSL
        ├────────────────────┤
        │   SQL layer        │  parser → optimizer → query cache* → executor
        │ (the "server")     │  *query cache removed in 8.0
        ├────────────────────┤
        │  Storage engine    │  pluggable: InnoDB (default), MyISAM, MEMORY...
        │      layer         │  handles actual data read/write, indexes, txns
        ├────────────────────┤
        │  File system /     │  .ibd files, redo log, undo log, binlog
        │  OS / disk         │
        └────────────────────┘
```

Key idea for interviews: **the optimizer and parser are engine-agnostic; transactions, locking, and storage are the engine's job.** That's why InnoDB supports transactions but MyISAM doesn't — same SQL layer, different engine.

### 3. Storage engines
| Engine | Transactions | Locking | Crash-safe | Use case |
|--------|-------------|---------|-----------|----------|
| **InnoDB** | ✅ (ACID) | Row-level | ✅ (redo log) | Default. Almost always the right choice. |
| MyISAM | ❌ | Table-level | ❌ | Legacy, read-heavy, full-text (pre-5.6). Avoid for new work. |
| MEMORY | ❌ | Table-level | ❌ (data lost on restart) | Temp/lookup tables, caching. |
| ARCHIVE | ❌ | Row (insert) | — | Append-only logs, high compression. |
| CSV | ❌ | — | — | Data exchange. |
| NDB (Cluster) | ✅ | Row | ✅ | Distributed, in-memory HA. |

`SHOW TABLE STATUS\G` shows the engine per table. `SHOW ENGINES;` lists what's available.

### 4. InnoDB internals you must name-drop
- **Clustered index:** InnoDB stores the table *physically ordered by the primary key*. The PK *is* the table. Secondary indexes store the PK value as their "pointer," not a row offset.
- **Buffer pool:** in-memory cache of data + index pages. The single most important tuning knob (`innodb_buffer_pool_size`).
- **Redo log (ib_logfile / redo):** write-ahead log for durability/crash recovery.
- **Undo log:** old row versions for MVCC + rollback.
- **Doublewrite buffer:** protects against torn pages.

### 5. Data types — pick the smallest correct type
**Numeric**
- `TINYINT`(1B) `SMALLINT`(2B) `MEDIUMINT`(3B) `INT`(4B) `BIGINT`(8B). Add `UNSIGNED` to double the positive range.
- `DECIMAL(p,s)` — **exact**, use for **money**. `FLOAT`/`DOUBLE` — approximate, never for currency.
- `BOOLEAN` is an alias for `TINYINT(1)`.

**String**
- `CHAR(n)` fixed length (padded). `VARCHAR(n)` variable (1–2 byte length prefix).
- `TEXT`/`BLOB` families (`TINYTEXT`…`LONGTEXT`) — stored off-page, can't have a default, indexing needs a prefix length.
- `ENUM`/`SET` — compact but rigid (changing values = ALTER).

**Date/Time**
- `DATE`, `TIME`, `DATETIME`(no TZ, 8B → 5B in 5.6+), `TIMESTAMP`(4B, UTC-converted, 1970–2038 range), `YEAR`.
- **`TIMESTAMP` vs `DATETIME`:** TIMESTAMP auto-converts to/from session time zone and has the 2038 limit; DATETIME stores literal wall-clock with a much larger range. Use DATETIME unless you specifically want TZ conversion.

**JSON** (5.7+): native validated JSON type, supports `->`/`->>` operators and generated-column indexing.

### 6. NULL — the three-valued logic trap
`NULL` means *unknown*, not zero or empty string. `NULL = NULL` is **not** TRUE — it's `NULL`. Use `IS NULL` / `IS NULL`. Aggregate functions (except `COUNT(*)`) **ignore NULLs**.

---

## PRACTICE

```sql
USE prep;

-- Inspect architecture
SELECT VERSION();
SHOW ENGINES;
SELECT @@default_storage_engine, @@innodb_buffer_pool_size;
SHOW TABLE STATUS LIKE 'employees'\G   -- note Engine, Row_format

-- Data type behavior: exact vs approximate
SELECT 0.1 + 0.2;                       -- decimal literal context
SELECT CAST(0.1 AS DOUBLE) + CAST(0.2 AS DOUBLE);  -- watch the float fuzz
SELECT 0.1 + 0.2 = 0.3;                 -- exact in MySQL decimal context → 1

-- CHAR vs VARCHAR padding
CREATE TEMPORARY TABLE t (c CHAR(5), v VARCHAR(5));
INSERT INTO t VALUES ('ab','ab');
SELECT CONCAT('[',c,']'), CONCAT('[',v,']'), LENGTH(c), LENGTH(v) FROM t;
-- CHAR is right-trimmed on retrieval in MySQL, so lengths may both look 2 —
-- the storage difference is the takeaway, not display.

-- NULL three-valued logic
SELECT NULL = NULL, NULL <> NULL, NULL IS NULL;
SELECT COUNT(*), COUNT(manager_id) FROM employees;  -- differ because of NULLs

-- TIMESTAMP vs DATETIME timezone behavior
CREATE TEMPORARY TABLE tz (ts TIMESTAMP, dt DATETIME);
INSERT INTO tz VALUES (NOW(), NOW());
SET time_zone = '+00:00'; SELECT * FROM tz;
SET time_zone = '+05:30'; SELECT * FROM tz;   -- ts shifts, dt does not
```

**Exercises (do these yourself):**
1. Create a table `payment(amount ?, currency ?)` choosing correct types for money. Justify each.
2. Show that `WHERE col = NULL` returns nothing but `WHERE col IS NULL` works.
3. Find the storage engine of every table in `prep` in one query (hint: `information_schema.tables`).

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Why is `FLOAT` dangerous for storing money? What do you use instead?**
Floats are binary approximations — `0.10` can't be represented exactly, so sums drift (e.g., totals off by a cent). Use `DECIMAL(p,s)` which is exact base-10. For high-volume systems some store money as integer *minor units* (paise/cents) in `BIGINT`.

**Q2. In InnoDB, what physically *is* a table?**
It's the clustered index — a B+tree ordered by the primary key, with the full row stored in the leaf nodes. There's no separate heap. That's why PK choice matters: a random PK (like a UUID v4) causes page splits and fragmentation; an auto-increment PK appends sequentially.

**Q3. A secondary index lookup in InnoDB does how many B-tree traversals to fetch a full row, and why?**
Up to **two**: one on the secondary index to get the PK value, then one on the clustered index to fetch the row ("bookmark lookup"). Unless the index is *covering* (all needed columns are in the index), in which case it's one.

**Q4. `COUNT(*)` vs `COUNT(col)` vs `COUNT(1)` — differences?**
`COUNT(*)` and `COUNT(1)` count all rows (including those with NULLs) and are equivalent in performance. `COUNT(col)` counts only rows where `col IS NOT NULL`. The "`COUNT(1)` is faster" claim is a myth in modern MySQL.

**Q5. Why was the query cache removed in MySQL 8.0?**
It was a global, mutex-protected structure that invalidated *all* cached results for a table on *any* write — a scalability bottleneck on write-heavy/concurrent workloads. Net negative for most modern apps; removed entirely.

**Q6. What's the range and storage of `TIMESTAMP`, and why does it matter in 2038?**
4 bytes, stored as seconds since the Unix epoch (UTC), range 1970-01-01 to 2038-01-19. The "Year 2038 problem" — it overflows a signed 32-bit int. Use `DATETIME` (range to year 9999) for far-future dates.

**Q7. You see `ENGINE=MyISAM` on a table in a banking app. What three risks do you raise?**
(1) No transactions → no atomic multi-row operations / rollback. (2) Table-level locking → writes block all reads, terrible concurrency. (3) Not crash-safe → a crash can corrupt the table; recovery means `REPAIR TABLE`, possible data loss. Recommend migrating to InnoDB.

➡ Next: [Day 02 — DDL & Constraints](day-02-ddl-constraints.md)