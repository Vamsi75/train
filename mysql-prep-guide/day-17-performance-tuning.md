# Day 17 — Performance Tuning: Slow Query Log, Buffer Pool & Server Config

## THEORY

### 1. The performance hierarchy (fix in this order)
1. **Schema & indexes** (biggest wins; Days 9–10, 16).
2. **Queries** (rewrites, pagination, batching).
3. **Server configuration** (buffer pool, etc.).
4. **Hardware / scaling** (replicas, sharding — Days 18–19).
Tuning `my.cnf` before fixing a missing index is putting lipstick on a pig.

### 2. Finding slow queries
- **Slow query log:**
  ```sql
  SET GLOBAL slow_query_log = 'ON';
  SET GLOBAL long_query_time = 0.5;          -- seconds
  SET GLOBAL log_queries_not_using_indexes = 'ON';
  ```
  Analyze the file with **`pt-query-digest`** (Percona Toolkit) — ranks queries by total time.
- **performance_schema** (live, low-overhead):
  ```sql
  SELECT digest_text, count_star, 
         ROUND(sum_timer_wait/1e12,2) AS total_s,
         ROUND(avg_timer_wait/1e9,2)  AS avg_ms
  FROM performance_schema.events_statements_summary_by_digest
  ORDER BY sum_timer_wait DESC LIMIT 10;
  ```
- **sys schema** views: `sys.statements_with_full_table_scans`, `sys.schema_unused_indexes`, `sys.statements_with_sorting`.

### 3. The InnoDB buffer pool — the #1 knob
`innodb_buffer_pool_size` caches data + index pages in RAM. Rule of thumb: **~70–80% of RAM** on a dedicated DB server. A high **buffer pool hit ratio** means most reads avoid disk.
```sql
SHOW STATUS LIKE 'Innodb_buffer_pool_read%';
-- hit ratio ≈ 1 - (reads / read_requests)
SHOW ENGINE INNODB STATUS\G   -- BUFFER POOL AND MEMORY section
```
Set `innodb_buffer_pool_instances` (multiple pools reduce mutex contention on large pools).

### 4. Redo log & durability vs speed
- `innodb_log_file_size` / `innodb_redo_log_capacity` (8.0.30+): bigger redo = fewer flushes, better write throughput, slower crash recovery.
- `innodb_flush_log_at_trx_commit`:
  - `1` (default) — flush+sync on every commit → **fully ACID-durable**, slowest.
  - `2` — write to OS cache each commit, sync ~1/sec → lose ≤1s on OS/power crash.
  - `0` — flush ~1/sec → fastest, riskiest.
- `sync_binlog=1` for binlog durability (needed for safe replication/PITR).

### 5. Other impactful settings
- `innodb_flush_method = O_DIRECT` — avoid double-caching (OS + buffer pool).
- `innodb_io_capacity` / `innodb_io_capacity_max` — match your storage IOPS (SSD ≫ HDD).
- `tmp_table_size` / `max_heap_table_size` — in-memory temp tables before spilling to disk.
- `sort_buffer_size`, `join_buffer_size` — **per-connection**; setting huge values × many connections = OOM. Keep modest; raise per-session for specific heavy queries.
- `max_connections` + a **connection pool** in the app (too many connections thrash; pooling reuses them).

### 6. Connections & threads
Each connection = a thread + memory. Hundreds of idle connections waste RAM and cause context-switch overhead. Use an app-side pool (HikariCP, etc.) and/or **ProxySQL** for multiplexing. Watch `Threads_connected`, `Threads_running` (running is the real load signal).

### 7. Monitoring signals (what to watch in prod)
- `Threads_running` spikes → contention/slow queries.
- Buffer pool hit ratio dropping → working set exceeds RAM.
- `Innodb_row_lock_waits` / lock wait time → contention.
- Replication lag (Day 19).
- Disk I/O utilization, `Created_tmp_disk_tables` (disk temp tables = bad).

---

## PRACTICE

```sql
-- Enable and use the slow query log
SET GLOBAL slow_query_log='ON';
SET GLOBAL long_query_time=0.2;
SET GLOBAL log_queries_not_using_indexes='ON';
SELECT @@slow_query_log_file;

-- Top queries by total time (performance_schema)
SELECT LEFT(digest_text,80) AS query,
       count_star AS execs,
       ROUND(sum_timer_wait/1e12,2) AS total_s,
       ROUND(avg_timer_wait/1e9,2)  AS avg_ms
FROM performance_schema.events_statements_summary_by_digest
ORDER BY sum_timer_wait DESC LIMIT 10;

-- Buffer pool sizing & hit ratio
SELECT @@innodb_buffer_pool_size/1024/1024 AS buffer_mb,
       @@innodb_buffer_pool_instances AS instances;
SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests';
SHOW STATUS LIKE 'Innodb_buffer_pool_reads';   -- physical disk reads; want this small relative to requests

-- Durability setting
SELECT @@innodb_flush_log_at_trx_commit, @@sync_binlog;

-- Disk temp tables (want low ratio of disk vs total)
SHOW STATUS LIKE 'Created_tmp_disk_tables';
SHOW STATUS LIKE 'Created_tmp_tables';

-- sys schema diagnostics
SELECT * FROM sys.schema_unused_indexes LIMIT 10;
SELECT * FROM sys.statements_with_full_table_scans LIMIT 10;

-- Live load
SHOW STATUS LIKE 'Threads_running';
SHOW STATUS LIKE 'Threads_connected';
```

**Exercises:**
1. Turn on the slow log, run a deliberately bad query, find it in `events_statements_summary_by_digest`.
2. Compute your buffer pool hit ratio. Is the working set in RAM?
3. Identify unused indexes via `sys.schema_unused_indexes` and reason about dropping them.
4. Explain (in writing) the trade-off you'd accept for `innodb_flush_log_at_trx_commit=2` on a logging system.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. What single config setting matters most for a read-heavy InnoDB workload, and how do you size it?**
`innodb_buffer_pool_size`. Size it so the **working set (hot data + indexes) fits in RAM** — typically ~70–80% of total RAM on a dedicated server. If the buffer pool can't hold the working set, you get disk reads on every query and performance collapses. Verify via the buffer pool hit ratio.

**Q2. Explain `innodb_flush_log_at_trx_commit` values and the durability trade-off.**
`1`: flush + fsync the redo log at **every commit** — full ACID durability, no data loss on crash, slowest. `2`: write to the OS page cache each commit but fsync only ~once/sec — survives a *MySQL* crash but can lose ~1s on an *OS/power* failure. `0`: write+fsync only ~once/sec — fastest, can lose ~1s even on a MySQL crash. Use `1` for financial data; `2` is a common pragmatic choice for high write throughput where ~1s loss is tolerable.

**Q3. Why is setting `sort_buffer_size = 256M` globally dangerous?**
It's a **per-connection** buffer. With, say, 500 connections each allocating up to 256MB for sorts, you can consume 128GB and OOM the server. Keep global per-connection buffers small and only raise them **per-session** for specific heavy queries.

**Q4. `Created_tmp_disk_tables` is high. What does it mean and how do you reduce it?**
MySQL is materializing temporary tables (from GROUP BY/DISTINCT/UNION/complex joins) **on disk** because they exceed `tmp_table_size`/`max_heap_table_size` or contain types that can't be in-memory. Disk temp tables are slow. Reduce by: optimizing the query to avoid temp tables (indexes for GROUP BY/ORDER BY), selecting fewer/narrower columns, and raising the temp-table size limits if RAM allows.

**Q5. More connections = more throughput — true or false?**
False. Beyond the point where `Threads_running` ≈ available CPU cores, more concurrent queries cause context-switching, lock contention, and cache thrashing — throughput *drops*. The fix is a **connection pool** (small, reused set) and/or a proxy (ProxySQL) for multiplexing, not raising `max_connections`.

**Q6. Bigger redo log — pros and cons?**
Pro: fewer/less-frequent flushes and checkpoints → **higher write throughput** and smoother performance under write spikes. Con: **longer crash recovery** (more redo to replay) and more disk space. Modern MySQL (8.0.30+) auto-manages via `innodb_redo_log_capacity`.

**Q7. Your DB was fast, then gradually slowed over months with no code changes. Likely causes?**
Data growth pushed the **working set beyond the buffer pool** (more disk I/O); **stale statistics** after large data changes; **index/table fragmentation**; growing tables making full scans slower; missing maintenance (`ANALYZE`/`OPTIMIZE TABLE`); or accumulation of rows that should have been archived/purged. Diagnose with buffer pool hit ratio, slow log trends, and EXPLAIN on the now-slow queries.

➡ Next: [Day 18 — Partitioning & Sharding](day-18-partitioning-sharding.md)
