# Day 23 — Real-Time Production Issues: A Troubleshooting Playbook

> This is the day that separates "knows SQL" from "has run MySQL in production." Each scenario: **Symptom → Diagnose → Fix → Prevent.** Read it like an on-call runbook.

## The universal first 60 seconds
When something's on fire, gather signal *before* changing anything:
```sql
SHOW PROCESSLIST;                       -- or: SELECT * FROM performance_schema.processlist;
SHOW FULL PROCESSLIST;                  -- full query text
SHOW ENGINE INNODB STATUS\G            -- deadlocks, lock waits, transactions, buffer pool
SHOW STATUS LIKE 'Threads_running';     -- the real load signal
SHOW STATUS LIKE 'Threads_connected';
SELECT * FROM sys.innodb_lock_waits\G  -- who blocks whom
SELECT * FROM sys.session\G            -- friendly processlist
```
Check OS too: CPU, disk space (`df -h`), disk IO (`iostat`), memory, network.

---

## Scenario 1 — "The database is slow / the site is down"
**Symptom:** App timeouts, high latency, `Threads_running` spiking.
**Diagnose:**
- `SHOW FULL PROCESSLIST` → look for many queries in the same state, long-running queries, or a flood of identical queries.
- `Threads_running` ≫ CPU cores → contention or a slow query storm.
- Find the offender: `performance_schema.events_statements_summary_by_digest` ordered by `sum_timer_wait`.
**Fix (triage):**
- `KILL <id>` a runaway query/transaction holding things up.
- If a single bad query: add the missing index / it was a deploy that shipped an unindexed query → roll back the deploy.
**Prevent:** slow-query alerts, query review in CI, `max_execution_time` hints, load testing.

---

## Scenario 2 — Deadlocks (error 1213)
**Symptom:** App logs "Deadlock found; try restarting transaction."
**Diagnose:** `SHOW ENGINE INNODB STATUS\G` → *LATEST DETECTED DEADLOCK* shows both transactions, their SQL, and lock order. Enable `innodb_print_all_deadlocks` to log every one.
**Fix:** Catch 1213 in the app and **retry** the transaction (deadlocks are normal under concurrency). Make all code paths **lock rows in a consistent order**. Keep transactions short.
**Prevent:** consistent access order, proper indexes (narrow locks), lower isolation (READ COMMITTED) if phantoms don't matter, retry logic everywhere.

---

## Scenario 3 — Lock wait timeout (error 1205) / "everything is blocked"
**Symptom:** Queries hang then fail with "Lock wait timeout exceeded."
**Diagnose:**
```sql
SELECT * FROM sys.innodb_lock_waits\G   -- blocking_pid vs waiting_pid
SELECT * FROM performance_schema.data_locks;
-- Find the long-running/idle-in-transaction blocker:
SELECT * FROM information_schema.innodb_trx ORDER BY trx_started\G
```
Usual culprit: a **long-running or abandoned transaction** (e.g., a session left `START TRANSACTION` open, or a slow app left a row locked) blocking everyone.
**Fix:** `KILL` the blocking thread/transaction. 
**Prevent:** short transactions, `autocommit` discipline, idle-transaction timeouts (`innodb_lock_wait_timeout`, app-side), don't hold locks across user think-time or external API calls.

---

## Scenario 4 — Disk full (the classic 2 AM page)
**Symptom:** "OS error 28 (No space left on device)", writes failing, server may refuse connections.
**Diagnose:** `df -h`. What ate the disk? Common: **binary logs** piling up, a runaway query writing huge temp files, ibdata/undo growth, or unrotated slow/general logs.
**Fix:**
- Purge old binlogs **safely** (only those already consumed by all replicas): `PURGE BINARY LOGS BEFORE NOW() - INTERVAL 3 DAY;` (never just `rm` binlog files — corrupts the index).
- Remove old rotated logs, clear temp.
- If undo/temp blew up from one query, kill it.
**Prevent:** `binlog_expire_logs_seconds` retention, disk-usage alerts at 70/85%, separate volumes for data/logs/tmp, archive/purge old data (partition drop).

---

## Scenario 5 — Replication lag / replica far behind
**Symptom:** Stale reads, `Seconds_Behind_Source` growing.
**Diagnose:** `SHOW REPLICA STATUS\G` — is `Replica_SQL_Running=Yes`? Is it stuck on one big event? Any error? Is the applier single-threaded?
**Fix:** Enable multi-threaded apply (`replica_parallel_workers`, `replica_parallel_type=LOGICAL_CLOCK`); kill a long read query on the replica blocking the applier; break up huge writes on the primary.
**Prevent:** smaller transactions, ROW binlog, adequate replica hardware, route only lag-tolerant reads to replicas, monitor lag with alerts.

---

## Scenario 6 — "Too many connections" (error 1040)
**Symptom:** New connections rejected; app can't connect.
**Diagnose:** `SHOW STATUS LIKE 'Threads_connected'` vs `@@max_connections`. Are connections **idle** (no pooling / leaked) or genuinely active? A traffic spike, a stuck downstream, or a connection-leak bug floods slots.
**Fix:** Temporarily raise `max_connections` (you keep an emergency `SUPER`/`SYSTEM_USER` connection reserved by `max_connections+1`); kill idle/sleeping connections; restart the leaking app instance.
**Prevent:** an **app-side connection pool** (small, reused), sane pool max, `wait_timeout` to reap idle connections, ProxySQL multiplexing.

---

## Scenario 7 — High CPU
**Symptom:** mysqld pegging CPU.
**Diagnose:** `SHOW FULL PROCESSLIST` + `events_statements_summary_by_digest` (sort by `sum_timer_wait` and by `count_star`). Usually either one expensive query (full scan/filesort/temp table) or a **high-frequency** query run millions of times (N+1 from the app).
**Fix:** Index/rewrite the expensive query; fix the N+1 (batch/join in the app); add caching for hot reads.
**Prevent:** EXPLAIN reviews, query digests in monitoring, app-level caching, rate limiting.

---

## Scenario 8 — Out of memory / mysqld killed (OOM)
**Symptom:** mysqld crashes/restarts; OOM-killer in `dmesg`.
**Diagnose:** Over-committed memory: `innodb_buffer_pool_size` + (per-connection buffers × `max_connections`) > RAM. Big `sort_buffer_size`/`join_buffer_size`/`tmp_table_size` × many connections is the classic trap.
**Fix:** Lower per-connection buffers to sane values; cap `max_connections`; right-size buffer pool (~70–80% RAM, not 95%).
**Prevent:** capacity math: `buffer_pool + (per_conn_buffers × max_conn) + overhead < RAM`. Monitor RSS.

---

## Scenario 9 — Accidental `DELETE`/`UPDATE` without WHERE
**Symptom:** "I just wiped the orders table." 
**Diagnose:** How much was lost, when, and is binlog enabled?
**Fix:** **Point-in-time recovery** (Day 20): restore last backup + replay binlogs up to **just before** the bad statement. If on a replica that hasn't applied it yet, you may grab data there.
**Prevent:** `sql_safe_updates=1`, run destructive statements in a transaction with a SELECT check first, least-privilege accounts, staging rehearsals, mandatory `WHERE`/`LIMIT` review.

---

## Scenario 10 — Data corruption / "InnoDB: page corruption"
**Symptom:** Crashes, checksum errors, table unreadable.
**Diagnose:** Error log, `CHECK TABLE`. Often failing disk/bad RAM/unsafe shutdown.
**Fix:** Restore from backup (preferred). Last resort: `innodb_force_recovery` (1→6, increasing aggressiveness) to start read-only and dump data out, then rebuild. **Never leave force_recovery on permanently.**
**Prevent:** ECC RAM, healthy disks (SMART), `innodb_flush_log_at_trx_commit=1` + doublewrite buffer on, tested backups, replication for a clean copy.

---

## Scenario 11 — Connpool/`MySQL server has gone away` (error 2006)
**Symptom:** Intermittent dropped connections.
**Diagnose:** Causes: `wait_timeout` reaped an idle pooled connection, `max_allowed_packet` too small for a large query/blob, or server restart.
**Fix:** Pool validation/keepalive (test-on-borrow), align pool idle timeout < `wait_timeout`, raise `max_allowed_packet` for big payloads.
**Prevent:** connection validation, retries, right-sized timeouts.

---

## Scenario 12 — Auto-increment exhaustion
**Symptom:** "Duplicate entry for key PRIMARY" though IDs look unique, inserts fail.
**Diagnose:** The `AUTO_INCREMENT` column hit its **type max** (e.g., signed `INT` at 2,147,483,647). Gaps from rollbacks burned the range faster than row count suggests.
**Fix:** `ALTER TABLE ... MODIFY id BIGINT` (big online operation — plan it) ; or `BIGINT UNSIGNED`.
**Prevent:** choose `BIGINT` for high-volume tables up front; monitor `AUTO_INCREMENT` vs max (`information_schema.tables` / `columns`).

---

## PRACTICE
```sql
USE prep;
-- Simulate & inspect a blocker
-- Session A: START TRANSACTION; UPDATE products SET stock=stock-1 WHERE product_id=1;  (leave open)
-- Session B: UPDATE products SET stock=stock-1 WHERE product_id=1;  (blocks)
SELECT * FROM sys.innodb_lock_waits\G
SELECT trx_id, trx_state, trx_started, trx_mysql_thread_id, trx_query
FROM information_schema.innodb_trx\G
-- Kill the blocker:  KILL <trx_mysql_thread_id>;

-- Find your worst queries right now
SELECT LEFT(digest_text,100) q, count_star execs,
       ROUND(sum_timer_wait/1e12,1) total_s
FROM performance_schema.events_statements_summary_by_digest
ORDER BY sum_timer_wait DESC LIMIT 5;

-- Safely purge binlogs (replication-aware)
SHOW BINARY LOGS;
-- PURGE BINARY LOGS BEFORE NOW() - INTERVAL 3 DAY;   -- only after confirming replicas consumed them
```

**Exercises:**
1. Create a blocking scenario and resolve it by killing the right thread (identified via `sys.innodb_lock_waits`).
2. Write the exact steps (commands) you'd run for "disk full due to binlogs" — safely.
3. Given a `Threads_running` spike, list your first five commands in order.
4. Draft a 1-page on-call runbook entry for "replication lag" in your own words.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Production is slow RIGHT NOW. What are your first three commands and why?**
`SHOW FULL PROCESSLIST` (what's running, any long/stuck queries, repeated patterns), `SHOW ENGINE INNODB STATUS` (lock waits, deadlocks, active transactions, buffer pool), and `SHOW STATUS LIKE 'Threads_running'` (the true concurrency/load signal). Plus an OS check (`df -h`, CPU, IO). Gather signal before mutating anything; then `KILL` the offender if there's a clear runaway.

**Q2. Disk is full because of binary logs. Why can't you just `rm` them?**
The binlog files are tracked in `mysql-bin.index`; deleting files at the OS level desyncs the index and can break replication and the server's binlog handling. Use **`PURGE BINARY LOGS BEFORE ...`** (or `TO 'mysql-bin.NNN'`), which removes files *and* updates the index — and only purge logs **already consumed by all replicas**, or you break replication. Then set `binlog_expire_logs_seconds` so it self-manages.

**Q3. The app keeps hitting deadlocks. Is that a bug, and what do you do?**
Occasional deadlocks are **expected** under concurrency, not necessarily a bug — InnoDB resolves them by rolling back a victim. The app **must catch error 1213 and retry** the transaction. Then reduce their frequency: enforce a **consistent lock-acquisition order** across all code paths, keep transactions short, add indexes to narrow locking, and consider READ COMMITTED. Use `SHOW ENGINE INNODB STATUS` / `innodb_print_all_deadlocks` to find the conflicting order.

**Q4. Everything is blocked but there's no deadlock error. What's happening?**
A **lock wait** (not a cycle): one long-running or **abandoned/idle-in-transaction** session holds a row/metadata lock and everyone queues behind it until `innodb_lock_wait_timeout`. Find it via `sys.innodb_lock_waits` / `information_schema.innodb_trx` (look at `trx_started` for the oldest), then `KILL` the blocker. Often it's a transaction left open across an app call or a forgotten `START TRANSACTION`.

**Q5. A long-running `ALTER TABLE` blocked all queries on an otherwise-online DDL. Why?**
Even online DDL must briefly acquire a **metadata lock (MDL)**. If a **long-running transaction or open query** holds an MDL on that table, the ALTER waits for it — and once the ALTER is *queued waiting for MDL*, **all subsequent queries on that table queue behind the ALTER**, cascading into a full stall. Fix: kill the old transaction holding the MDL (or the ALTER), and run DDL when no long transactions are open; use `lock_wait_timeout` for DDL.

**Q6. mysqld got OOM-killed. Walk through the capacity math.**
Memory ≈ `innodb_buffer_pool_size` (global) **+** per-connection buffers (`sort_buffer_size + join_buffer_size + read_buffer_size + tmp_table_size`, etc.) **× concurrent connections** **+** overhead. The classic mistake is a large per-connection buffer set globally times a high `max_connections` exceeding RAM under load. Right-size the buffer pool to ~70–80% RAM, keep per-connection buffers small (raise per-session when needed), and cap connections via pooling.

**Q7. Reads on a replica are returning data that's minutes old, breaking a feature. How do you reason about the fix?**
That's **replication lag** — inherent to async replicas. Decide per query: lag-tolerant reads stay on replicas; **read-after-write / strongly-consistent reads must go to the primary** (or use GTID `WAIT_FOR_EXECUTED_GTID_SET` to block until the replica catches up). Separately, reduce the lag (multi-threaded apply, smaller transactions, faster replica). Don't "fix" correctness by hoping lag stays low.

**Q8. You suspect a specific query is killing the DB but the app generates thousands of variants. How do you find it?**
Use the **statement digest** in `performance_schema.events_statements_summary_by_digest` (or `pt-query-digest` on the slow log), which **normalizes** queries (strips literals) so all variants of the same query collapse into one row. Sort by `sum_timer_wait` (total time = the real cost driver) and by `count_star` (frequency). The top digest by total time is your culprit — `EXPLAIN` a representative instance.

➡ Next: [Day 24 — Twisted Interview Questions (Master Set)](day-24-twisted-interview-questions.md)
