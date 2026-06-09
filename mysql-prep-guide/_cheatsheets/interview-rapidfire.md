# 100 Rapid-Fire Q&A — The Night Before

One line each. Cover the answer, recall, reveal. Aim for instant recall.

## Fundamentals (1–15)
1. **RDBMS?** Data in relational tables with keys, SQL, ACID guarantees.
2. **MySQL architecture layers?** Connection → SQL (parser/optimizer/executor) → pluggable storage engine → files.
3. **Default storage engine?** InnoDB.
4. **InnoDB vs MyISAM?** InnoDB: transactions, row locks, crash-safe, FKs. MyISAM: none of those, table locks.
5. **Clustered index?** The table itself, ordered by PK; leaves hold full rows.
6. **Secondary index stores?** Indexed cols + the PK value (not a physical pointer).
7. **CHAR vs VARCHAR?** Fixed vs variable length.
8. **DECIMAL vs FLOAT for money?** DECIMAL (exact); FLOAT is approximate.
9. **DATETIME vs TIMESTAMP?** DATETIME: literal, huge range. TIMESTAMP: UTC-converted, 4B, 2038 limit.
10. **NULL meaning?** Unknown; not 0/''. Three-valued logic.
11. **utf8 vs utf8mb4?** utf8mb4 is real 4-byte Unicode (emoji); utf8 is broken 3-byte alias.
12. **AUTO_INCREMENT reuses gaps?** No; rolled-back IDs are burned.
13. **COUNT(*) vs COUNT(col)?** All rows vs non-NULL values.
14. **PK vs UNIQUE?** One PK (no NULL, clustered); many UNIQUE (NULLs allowed).
15. **Surrogate vs natural key?** Synthetic id vs real attribute; prefer surrogate PK.

## DDL/DML (16–28)
16. **DDL examples?** CREATE/ALTER/DROP/TRUNCATE — auto-commit.
17. **TRUNCATE vs DELETE?** DDL, no rollback, resets AI, no triggers vs DML rollback-able.
18. **Can you rollback TRUNCATE/ALTER?** No (implicit commit).
19. **Upsert?** `INSERT ... ON DUPLICATE KEY UPDATE`.
20. **REPLACE danger?** Delete+insert → new AI id, fires triggers, FK cascade.
21. **INSERT IGNORE risk?** Silently drops erroring rows.
22. **Multi-row insert benefit?** One parse/round-trip/txn → much faster.
23. **Online DDL fastest algo?** INSTANT (8.0.12+) for adding columns.
24. **Big-table ALTER tool?** gh-ost / pt-online-schema-change.
25. **Delete 50M rows safely?** Chunked `DELETE ... LIMIT 5000` loop.
26. **SQL_SAFE_UPDATES?** Blocks UPDATE/DELETE without keyed WHERE.
27. **Multi-table UPDATE?** `UPDATE a JOIN b ... SET ...`.
28. **CHECK constraint enforced since?** 8.0.16.

## SELECT/functions (29–40)
29. **Logical query order?** FROM→WHERE→GROUP BY→HAVING→SELECT→ORDER BY→LIMIT.
30. **Alias in WHERE?** No (SELECT runs later); yes in ORDER BY/HAVING.
31. **WHERE vs HAVING?** Row filter (pre-group) vs group filter (post-aggregate).
32. **LENGTH vs CHAR_LENGTH?** Bytes vs characters.
33. **COALESCE vs IFNULL vs NULLIF?** First non-NULL / 2-arg replace / NULL if equal.
34. **NOT IN + NULL?** Returns nothing; use NOT EXISTS.
35. **NULL-safe equality?** `<=>`.
36. **GROUP_CONCAT silent loss?** Truncated at `group_concat_max_len` (1024).
37. **ORDER BY RAND() problem?** Sorts whole table.
38. **Pivot in MySQL?** Conditional aggregation (`SUM(CASE...)`).
39. **ONLY_FULL_GROUP_BY?** Rejects ambiguous non-grouped columns (default 5.7+).
40. **WITH ROLLUP?** Adds subtotal/grand-total rows (NULL group keys).

## Joins/subqueries (41–52)
41. **Join types?** INNER, LEFT, RIGHT, CROSS, SELF; no native FULL OUTER.
42. **FULL OUTER emulation?** LEFT UNION RIGHT.
43. **LEFT acting as INNER?** Right-table filter in WHERE — move to ON.
44. **Anti-join safe form?** NOT EXISTS.
45. **Hash join when?** Equi-join with no usable index (8.0.18+).
46. **Fan-out trap?** 1:N join multiplies rows → SUM double-counts.
47. **Correlated subquery?** References outer row; runs per outer row.
48. **Scalar subquery returns >1 row?** Error.
49. **CTE materialized always?** No; single-use often merged.
50. **Recursive CTE limit?** `cte_max_recursion_depth` (1000).
51. **EXISTS vs IN?** Both often semi-join in 8.0; EXISTS NULL-safe, short-circuits.
52. **LATERAL derived table since?** 8.0.14.

## Window functions (53–58)
53. **Window vs GROUP BY?** Window keeps all rows + per-row aggregate.
54. **ROW_NUMBER/RANK/DENSE_RANK ties?** 1,2,3 / 1,1,3 / 1,1,2.
55. **Window fn in WHERE?** No; wrap in subquery.
56. **Top-N per group?** ROW_NUMBER partitioned, filter ≤ N.
57. **Default frame gotcha?** RANGE ... CURRENT ROW lumps ties together.
58. **LAG/LEAD use?** Previous/next row value (deltas).

## Normalization/design (59–66)
59. **1NF?** Atomic values, no repeating groups.
60. **2NF?** No partial dependency on part of composite key.
61. **3NF?** No transitive dependency (non-key→non-key).
62. **BCNF?** Every determinant is a candidate key.
63. **Denormalization when?** Read-heavy hot paths; keep in sync deliberately.
64. **M:N modeling?** Junction table with composite PK.
65. **UUID PK problem?** Random inserts fragment InnoDB; use ordered UUID/BINARY(16).
66. **EAV anti-pattern?** Attributes as rows; kills perf/typing — prefer JSON/columns.

## Indexes (67–76)
67. **Leftmost-prefix?** `(a,b,c)` serves a / a,b / a,b,c only.
68. **Range stops index?** Yes — columns after a range can't seek.
69. **Covering index?** Index has all needed cols → "Using index".
70. **Non-sargable?** Function/cast on column, leading wildcard → no index.
71. **Prefix index covers?** Never (stores fragment).
72. **Invisible index?** Maintained but optimizer ignores — safe drop test.
73. **Functional index since?** 8.0.13.
74. **Index slows writes?** Yes — each must be maintained.
75. **Full scan ever right?** Low selectivity / tiny table.
76. **Refresh stats?** `ANALYZE TABLE`; histograms for skewed non-indexed cols.

## Transactions/locking (77–86)
77. **ACID?** Atomicity, Consistency, Isolation, Durability.
78. **Atomicity backed by?** Undo log. **Durability by?** Redo log.
79. **Default isolation?** REPEATABLE READ.
80. **RR phantoms in InnoDB?** Prevented (MVCC + next-key locks).
81. **MVCC?** Readers see snapshot via undo versions; don't block writers.
82. **RR snapshot taken when?** First consistent read.
83. **READ COMMITTED snapshot?** Fresh per statement.
84. **Gap lock purpose?** Prevent phantom inserts into a range.
85. **Deadlock victim?** Transaction with least work; rolled back (1213) → retry.
86. **Lost update fix?** FOR UPDATE / version column / atomic in-place update.

## Stored programs (87–90)
87. **Procedure vs function?** CALL/multi-result vs returns scalar usable in SQL.
88. **Why DELIMITER?** Body has internal `;`.
89. **EXIT vs CONTINUE handler?** Exit block vs resume.
90. **Generated column vs trigger?** Prefer generated column for derived values.

## Performance/ops (91–100)
91. **EXPLAIN ANALYZE?** Runs query, shows actual rows + timing.
92. **Biggest tuning knob?** `innodb_buffer_pool_size` (~70–80% RAM).
93. **flush_log_at_trx_commit?** 1=durable, 2=~1s loss on OS crash, 0=fastest/riskiest.
94. **Per-connection buffer danger?** sort/join buffer × connections → OOM.
95. **STATEMENT vs ROW binlog?** ROW safe/deterministic; default.
96. **GTID benefit?** Easy failover/re-pointing (transaction ids vs file positions).
97. **Replication lag fix?** Multi-threaded apply, smaller txns, faster replica.
98. **PITR needs?** Base backup + binary logs; replay to just before the mistake.
99. **Partitioning vs sharding?** One server pieces vs across servers (write scale).
100. **Stop SQL injection?** Parameterized/prepared statements + least privilege.

---
*If you can rattle off 90+/100 from memory, you're ready. Weak spots → revisit that day.*
