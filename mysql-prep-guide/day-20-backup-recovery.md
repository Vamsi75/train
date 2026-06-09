# Day 20 — Backup, Recovery & Point-in-Time Recovery (PITR)

## THEORY

### 1. Logical vs physical backups
| | Logical (`mysqldump`, `mysqlpump`, `mydumper`) | Physical (`Percona XtraBackup`, file copy, snapshot) |
|--|--|--|
| What | SQL statements / data files of *logical* content | Raw InnoDB data files (`.ibd`, redo) |
| Speed | Slow on large DBs (re-inserts, rebuilds indexes) | Fast (file-level copy) |
| Size | Smaller, compressible, human-readable | Larger |
| Portability | Cross-version/cross-engine friendly | Tied to layout/version |
| Restore speed | Slow (replays SQL) | Fast |
| Best for | Small/medium DBs, migrations, partial restores | Large DBs, fast full restores |

### 2. mysqldump essentials
```bash
# Consistent backup of a transactional (InnoDB) DB without locking writes:
mysqldump --single-transaction --routines --triggers --events \
          --set-gtid-purged=ON --databases prep > prep_backup.sql

# Restore
mysql prep < prep_backup.sql
```
- `--single-transaction` takes a **consistent snapshot** in one transaction (InnoDB only) — no global read lock, writes continue. **The key flag.**
- Without it, `mysqldump` uses `--lock-tables` (locks, blocks writes) — bad on production.
- `--routines --triggers --events` — otherwise stored programs are **not** included (common silent gap).
- `--master-data`/`--source-data` records the binlog position (for setting up replicas / PITR base).

### 3. Physical backup with XtraBackup
Hot, non-blocking physical backup of InnoDB: copies data files while tracking redo, then "prepares" them to a consistent state. Much faster restore for large datasets. The de-facto tool for big MySQL.

### 4. Point-in-Time Recovery (PITR) — the crown jewel
"Restore to 2:47 PM, right before the bad `DELETE`." Recipe:
1. Restore the **last full backup** (logical or physical) → gets you to backup time T0.
2. **Replay the binary logs** from T0 up to the desired moment (and *stop* before the bad statement).
```bash
# Find the binlogs and replay up to a timestamp (or a GTID / position)
mysqlbinlog --start-datetime="2024-05-01 02:00:00" \
            --stop-datetime="2024-05-01 14:46:59" \
            mysql-bin.000045 mysql-bin.000046 | mysql
# Or stop right before a specific position/GTID that caused the damage.
```
**Prerequisite: binary logging must be ON** *before* the incident. No binlog → no PITR. This is why `log_bin` + `sync_binlog=1` matter.

### 5. Backup strategy & the 3-2-1 rule
- **3** copies, **2** different media, **1** offsite.
- **Test restores regularly** — an untested backup is not a backup ("Schrödinger's backup").
- Define **RPO** (Recovery Point Objective — how much data you can lose) and **RTO** (Recovery Time Objective — how long recovery may take). Backup frequency + binlog shipping cadence flow from RPO; backup type (physical vs logical) flows from RTO.
- Automate, monitor success, and **alert on failures**.

### 6. Common backup mistakes (prod war stories)
- Backups on the same disk/server as the DB (disk dies → both gone).
- Forgetting `--routines/--triggers/--events`.
- Locking production with a naive `mysqldump` at peak.
- Never testing a restore until the real disaster.
- No binlogs, so "restore" can only reach last night's backup (huge data loss).

---

## PRACTICE

```bash
# Consistent logical backup (run in shell)
mysqldump --single-transaction --routines --triggers --events \
          --databases prep > /backups/prep_$(date +%F).sql

# Inspect what's in a backup
head -50 /backups/prep_*.sql

# Restore to a fresh DB to TEST it (always test!)
mysql -e "CREATE DATABASE prep_restore_test"
sed 's/`prep`/`prep_restore_test`/' /backups/prep_*.sql | mysql prep_restore_test
```
```sql
-- Verify binary logging is on (prerequisite for PITR)
SHOW VARIABLES LIKE 'log_bin';          -- want ON
SHOW VARIABLES LIKE 'sync_binlog';      -- want 1 for durability
SHOW BINARY LOGS;
SELECT @@binlog_expire_logs_seconds;    -- retention; must cover your backup interval

-- Simulate the disaster + PITR concept:
-- 1) full backup taken at T0
-- 2) someone runs:  DELETE FROM orders;   (the mistake) at 14:47
-- 3) restore T0 backup, then replay binlogs from T0 up to 14:46:59 only
```
```bash
# PITR replay (shell): everything up to just before the bad statement
mysqlbinlog --stop-datetime="2024-05-01 14:46:59" mysql-bin.000045 | mysql prep
# or stop at a precise position you found by inspecting the binlog:
mysqlbinlog mysql-bin.000045 | less   # locate the DELETE; note its 'at' position
mysqlbinlog --stop-position=98765 mysql-bin.000045 | mysql prep
```

**Exercises:**
1. Take a `--single-transaction` dump of `prep`, drop a table, and restore just that table from the dump.
2. Confirm whether your server can do PITR (is `log_bin` ON? what's the binlog retention?).
3. Write out your RPO/RTO targets for an e-commerce checkout DB and the backup plan that meets them.
4. Practice using `mysqlbinlog` to read events and identify a specific statement's position.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Why is `--single-transaction` important in mysqldump, and when does it NOT help?**
It wraps the dump in a single InnoDB transaction with a consistent MVCC snapshot, so you get a **point-in-time consistent** backup **without locking** writes. It does **not** help for **non-transactional engines (MyISAM)** — those still need table locks (`--lock-tables`) to be consistent. Also, mixing DDL during the dump can still break consistency.

**Q2. Someone ran `DELETE FROM orders` with no WHERE at 2:47 PM. Last full backup was 2 AM. How do you recover with minimal loss?**
**Point-in-time recovery:** restore the 2 AM full backup, then replay the **binary logs** from 2 AM up to **just before** the 2:47 PM DELETE (stop at that timestamp/position/GTID). This recovers everything except the bad statement — losing essentially zero legitimate data. It only works if **binary logging was enabled** before the incident.

**Q3. Logical vs physical backup — which for a 2 TB database that must restore in under an hour?**
**Physical** (XtraBackup or snapshot). Logical restore re-inserts every row and rebuilds indexes — far too slow for 2 TB (could take many hours/days). Physical backups copy data files and restore by placing them back, meeting a tight RTO. Logical backups shine for small DBs, migrations, and selective/partial restores.

**Q4. What are RPO and RTO, and how do they drive backup design?**
**RPO** = maximum acceptable **data loss** (how far back you can go). **RTO** = maximum acceptable **downtime** to recover. A small RPO demands frequent backups + continuous binlog shipping (so PITR is granular). A small RTO demands fast-restore methods (physical backups, standby replicas). They turn "back up sometimes" into concrete frequency and tooling choices.

**Q5. Your mysqldump restored fine but stored procedures and triggers are missing. Why?**
`mysqldump` by default does **not** include routines, triggers, or events. You must pass `--routines --triggers --events`. This is a classic silent gap — the data restores, but business logic in the DB is gone. Always include those flags (or back up the whole instance including the `mysql` system schema appropriately).

**Q6. Can you do point-in-time recovery without binary logs?**
No. PITR replays committed transactions recorded in the **binary log** on top of a base backup. Without binlogs (or with them disabled/expired), you can only restore to the moment of the last full/incremental backup — everything after is unrecoverable. Hence `log_bin` ON + adequate `binlog_expire_logs_seconds` retention is non-negotiable for PITR.

**Q7. What's "Schrödinger's backup" and how do you avoid it?**
The state of any backup is unknown until you attempt a restore — it's simultaneously good and useless until observed. Avoid it by **regularly performing test restores** (ideally automated, to a scratch instance) and validating row counts/checksums. A backup job that "succeeds" but produces an unrestorable file is worse than no backup because it creates false confidence.

**Q8. How do you take a backup without impacting the production primary at all?**
Take it from a **dedicated read replica** (so the primary's I/O and locks are untouched), using `--single-transaction` (logical) or XtraBackup (physical) on that replica. Bonus: capture the replica's GTID/binlog position so the backup doubles as a base for spinning up new replicas or for PITR.

➡ Next: [Day 21 — High Availability & Failover](day-21-high-availability.md)
