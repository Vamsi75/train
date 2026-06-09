# MySQL Preparation Guide — Zero to 4 Years Experience

A complete, day-wise MySQL learning + interview-prep track. Each day follows the same rhythm:

> **Theory** → **Hands-on Practice** → **Twisted / Important Interview Questions**

Production troubleshooting is woven in from Day 11 onward and gets two dedicated days near the end.

---

## How to use this guide

1. **Don't skip the practice.** Spin up MySQL locally (Docker is easiest — see Day 0 setup) and run *every* query. Reading SQL ≠ knowing SQL.
2. **Answer interview questions out loud before reading the answer.** The "twisted" ones are the ones interviewers actually use to separate a 2-year dev from a 4-year dev.
3. **Keep a scratch schema.** Most days reuse a common `shop` / `hr` schema defined in `_setup/seed.sql`.
4. **Pace:** ~2–3 hrs/day. Whole track ≈ 4–6 weeks part-time. You can compress to 2 weeks full-time.

---

## Curriculum at a glance

### Phase 1 — Foundations (Days 1–5)
| Day | Topic |
|-----|-------|
| [Day 01](day-01-rdbms-architecture-datatypes.md) | RDBMS concepts, MySQL architecture, storage engines, data types |
| [Day 02](day-02-ddl-constraints.md) | DDL — CREATE/ALTER/DROP, keys, constraints |
| [Day 03](day-03-dml-select-basics.md) | DML — INSERT/UPDATE/DELETE, SELECT basics |
| [Day 04](day-04-functions-filtering.md) | Operators, filtering, string/date/numeric functions |
| [Day 05](day-05-grouping-aggregation.md) | GROUP BY, HAVING, aggregation, DISTINCT |

### Phase 2 — Intermediate (Days 6–12)
| Day | Topic |
|-----|-------|
| [Day 06](day-06-joins.md) | All joins, self-join, anti-join, join pitfalls |
| [Day 07](day-07-subqueries-cte.md) | Subqueries, correlated subqueries, derived tables, CTEs |
| [Day 08](day-08-window-functions.md) | UNION/set ops, window functions |
| [Day 09](day-09-normalization-design.md) | Normalization, schema design, anti-patterns |
| [Day 10](day-10-indexes.md) | Indexes — B-tree, composite, covering, when they fail |
| [Day 11](day-11-transactions-acid.md) | Transactions, ACID, isolation levels |
| [Day 12](day-12-locking-deadlocks-mvcc.md) | Locking, deadlocks, MVCC |

### Phase 3 — Advanced (Days 13–18)
| Day | Topic |
|-----|-------|
| [Day 13](day-13-stored-procedures-functions.md) | Stored procedures & functions |
| [Day 14](day-14-triggers-events-cursors.md) | Triggers, events, cursors |
| [Day 15](day-15-views.md) | Views, materialized-view patterns |
| [Day 16](day-16-explain-query-optimization.md) | EXPLAIN, query plans, optimization |
| [Day 17](day-17-performance-tuning.md) | Performance tuning, slow query log, buffer pool |
| [Day 18](day-18-partitioning-sharding.md) | Partitioning & sharding |

### Phase 4 — Production & Expert (Days 19–25)
| Day | Topic |
|-----|-------|
| [Day 19](day-19-replication.md) | Replication, GTID, read scaling |
| [Day 20](day-20-backup-recovery.md) | Backup, recovery, point-in-time recovery |
| [Day 21](day-21-high-availability.md) | HA, failover, clustering |
| [Day 22](day-22-security-sql-injection.md) | Security, user mgmt, SQL injection |
| [Day 23](day-23-production-issues-playbook.md) | **Real-time production issues — playbook** |
| [Day 24](day-24-twisted-interview-questions.md) | **Twisted interview questions — master set** |
| [Day 25](day-25-mock-interview-capstone.md) | Mock interview, scenario rounds, capstone |

---

## Supporting files
- [`_setup/setup.md`](_setup/setup.md) — install MySQL via Docker / native, connect, basic admin
- [`_setup/seed.sql`](_setup/seed.sql) — the common practice schema + sample data
- [`_cheatsheets/cheatsheet.md`](_cheatsheets/cheatsheet.md) — one-page command & syntax reference
- [`_cheatsheets/interview-rapidfire.md`](_cheatsheets/interview-rapidfire.md) — 100 rapid-fire Q&A for the day before an interview

---

## What "4 years experience" actually means to interviewers
By the end you should be able to, *without notes*:
- Read an `EXPLAIN` and say why a query is slow and how to fix it.
- Explain why a deadlock happened from a `SHOW ENGINE INNODB STATUS` dump.
- Choose an isolation level and defend the trade-off.
- Design a normalized schema *and* know when to denormalize.
- Debug replication lag and a full disk at 2 AM.
- Write a correlated subquery and rewrite it as a join when it's faster.

Good luck. Start with [`_setup/setup.md`](_setup/setup.md), then [Day 01](day-01-rdbms-architecture-datatypes.md).