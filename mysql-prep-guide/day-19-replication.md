# Day 19 — Replication, GTID & Read Scaling

## THEORY

### 1. Why replicate?
- **Read scaling** — route reads to replicas, writes to the primary.
- **High availability** — promote a replica if the primary dies (Day 21).
- **Backups** — take backups off a replica to avoid loading the primary.
- **Geo-distribution / analytics isolation.**

### 2. How MySQL replication works
The **primary (source)** records all changes to the **binary log (binlog)**. Each **replica** has:
- An **I/O thread** that pulls binlog events from the primary into a local **relay log**.
- A **SQL (applier) thread** that replays the relay log onto the replica's data.
Modern MySQL supports **multi-threaded replication** (parallel appliers) to reduce lag.

### 3. Binlog formats
- **STATEMENT** — logs the SQL text. Compact, but **unsafe** for non-deterministic statements (`NOW()`, `UUID()`, `LIMIT` without ORDER BY, some triggers) → replicas can diverge.
- **ROW** — logs the actual changed row images. Safe and deterministic; larger logs. **Default and recommended.**
- **MIXED** — STATEMENT normally, switches to ROW for unsafe statements.

### 4. Positions vs GTID
- **Binlog file + position** (classic) — replica tracks "I'm at file mysql-bin.000123, position 4567." Fragile during failover (positions differ per server).
- **GTID (Global Transaction Identifier)** — every transaction gets a globally unique id (`source_uuid:sequence`). Replicas track *which transactions they've applied*, not file positions. Makes **failover and re-pointing replicas vastly easier** (`CHANGE REPLICATION SOURCE TO ... SOURCE_AUTO_POSITION=1`). Prefer GTID.

### 5. Synchronous vs asynchronous
- **Asynchronous (default)** — primary commits without waiting for replicas → fast, but a crash can lose transactions not yet shipped (and replicas lag).
- **Semi-synchronous** — primary waits until **at least one replica acknowledges receipt** (to its relay log) before committing → reduces data-loss window, adds latency.
- **Group Replication / InnoDB Cluster** — a Paxos-based, (virtually) synchronous multi-member group with automatic conflict detection and failover (Day 21).

### 6. Replication lag — the #1 operational pain
Replicas fall behind because the single SQL applier can't keep up with the primary's write rate, or a long-running query/transaction blocks the applier, or row-based events for huge updates flood the relay log.
```sql
SHOW REPLICA STATUS\G    -- Seconds_Behind_Source, Replica_IO_Running, Replica_SQL_Running
```
Mitigations: multi-threaded replication (`replica_parallel_workers`, `replica_parallel_type=LOGICAL_CLOCK`), faster replica hardware, smaller transactions, avoid huge single-statement updates, reduce primary write amplification.

### 7. Read-after-write consistency
Because replicas lag, a user who writes then immediately reads from a replica may **not see their own write**. Solutions: route that user's reads to the primary for a short window ("sticky"/read-your-writes), use GTID-based wait (`WAIT_FOR_EXECUTED_GTID_SET`) before reading a replica, or accept eventual consistency where acceptable.

### 8. Topologies
- **Source → Replicas** (one primary, many read replicas).
- **Chained / relay** replicas.
- **Multi-source** (a replica pulls from several primaries — for consolidation).
- **Circular** (multi-primary; avoid unless you really know why — conflict hell).

---

## PRACTICE
> Full replication needs two servers; here's the conceptual setup + what you'd run.

```sql
-- ON PRIMARY: enable binlog + GTID (my.cnf)
-- server_id=1
-- log_bin=mysql-bin
-- binlog_format=ROW
-- gtid_mode=ON
-- enforce_gtid_consistency=ON

-- Create a replication user
CREATE USER 'repl'@'%' IDENTIFIED BY 'replpass';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

-- Inspect binlog
SHOW BINARY LOGS;
SHOW MASTER STATUS;            -- (SHOW BINARY LOG STATUS in newer 8.x)
SHOW BINLOG EVENTS IN 'mysql-bin.000001' LIMIT 10;
SELECT @@gtid_executed;

-- ON REPLICA: point at the primary using GTID auto-position
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='primary.host', SOURCE_USER='repl', SOURCE_PASSWORD='replpass',
  SOURCE_AUTO_POSITION=1;
START REPLICA;
SHOW REPLICA STATUS\G          -- check Replica_IO_Running=Yes, Replica_SQL_Running=Yes, Seconds_Behind_Source

-- Multi-threaded applier to cut lag
SET GLOBAL replica_parallel_workers = 4;
SET GLOBAL replica_parallel_type = 'LOGICAL_CLOCK';

-- Read-your-writes via GTID wait (on the replica, before reading)
-- SELECT WAIT_FOR_EXECUTED_GTID_SET('<gtid-from-primary-write>', 5);
```

**Exercises (conceptual / two-node if you can):**
1. Explain what each of `Replica_IO_Running`, `Replica_SQL_Running`, and `Seconds_Behind_Source` tells you.
2. Describe step-by-step how you'd diagnose a replica that's 2 hours behind.
3. Why is `binlog_format=ROW` safer than `STATEMENT`? Give a statement that breaks under STATEMENT.
4. Design read/write routing for an app so that a user always sees their own writes.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. STATEMENT vs ROW binlog — give a concrete query that diverges under STATEMENT.**
`UPDATE users SET token = UUID() WHERE id = 5;` or `INSERT ... SELECT ... LIMIT 10` (without ORDER BY), or anything using `NOW()`/`RAND()`. Under STATEMENT replication the replica re-executes the SQL and computes **different** values/row sets, diverging from the primary. ROW logs the actual resulting row images, so the replica applies identical data. Hence ROW is the safe default.

**Q2. What problem does GTID solve over binlog file+position?**
With file+position, each server has its own binlog coordinates, so after a failover you must manually find the equivalent position on the new primary — error-prone. **GTID** gives each transaction a globally unique id that's the same everywhere, so a replica just says "give me transactions I haven't applied" (`SOURCE_AUTO_POSITION=1`). Failover and re-pointing replicas become trivial and safe.

**Q3. Async replication and the primary crashes — can you lose committed data?**
Yes. In **asynchronous** replication the primary commits and acknowledges the client **before** confirming the replica received the transaction. If it crashes before shipping the latest binlog events, those committed transactions are lost on failover. **Semi-synchronous** replication narrows this window by waiting for a replica to acknowledge receipt before the commit returns.

**Q4. A replica is lagging hours behind. Walk through the diagnosis.**
Check `SHOW REPLICA STATUS`: is `Replica_SQL_Running` stuck on one event? Is `Seconds_Behind_Source` growing? Common causes: (1) single-threaded applier can't match the primary's write rate → enable multi-threaded replication; (2) a long/large transaction or huge single-statement UPDATE blocking the applier; (3) replica hardware/IO weaker than primary; (4) lock waits on the replica (e.g., a long read query); (5) replication errors. Fix the bottleneck (parallel workers, smaller transactions, faster disk) and clear any blocking queries.

**Q5. How do you guarantee read-after-write consistency with read replicas?**
Options: (1) **route reads to the primary** for that session for a short window after a write ("sticky"); (2) **GTID wait** — capture the write's GTID and `WAIT_FOR_EXECUTED_GTID_SET` on the replica before reading, so you only read once it has caught up; (3) accept eventual consistency where the UX tolerates it. Pure round-robin replica reads can't guarantee it.

**Q6. Can replication run with different binlog format on primary vs replica? What about different versions?**
The replica applies whatever the primary logged, so the **primary's** binlog format governs. Mixing is generally a misconfiguration. For versions, MySQL supports replicating from an **older primary to a newer replica** (for upgrades), but **not** reliably newer→older. Plan rolling upgrades replica-first.

**Q7. Why might a "read replica" return stale or even wrong results for analytics?**
Replication **lag** means it's behind the primary (stale). Worse, if STATEMENT-based replication was used with non-deterministic statements, the replica's data can **diverge** (wrong, not just stale). Also, reading uncommitted-on-primary data isn't possible, but reading a *consistent-but-old* snapshot can mislead time-sensitive aggregates. Use ROW format, monitor lag, and for strict numbers read the primary or wait on GTID.

➡ Next: [Day 20 — Backup & Recovery](day-20-backup-recovery.md)
