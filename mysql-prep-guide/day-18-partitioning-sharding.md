# Day 18 — Partitioning & Sharding

## THEORY

### 1. Partitioning vs sharding (don't confuse them)
- **Partitioning** = splitting **one table within one MySQL server** into physical pieces (partitions). Transparent to queries; still one database, one server.
- **Sharding** = splitting data across **multiple independent servers/databases**. Application- or middleware-managed; each shard is a full MySQL instance.
Partitioning helps manageability and some query/maintenance patterns; sharding is how you scale **writes/storage beyond one machine**.

### 2. Partitioning types (MySQL)
- **RANGE** — by value ranges (most common: by date). Great for time-series + dropping old partitions.
- **LIST** — by discrete value sets (e.g., region codes).
- **HASH** — by a hash of an expression → even distribution, no natural ranges.
- **KEY** — like HASH but uses MySQL's internal hashing (works on non-integer columns).
- Sub-partitioning (RANGE/LIST then HASH/KEY) is possible.

```sql
CREATE TABLE events_part (
  id BIGINT AUTO_INCREMENT,
  user_id INT, event_type VARCHAR(30), created_at DATETIME NOT NULL,
  PRIMARY KEY (id, created_at)            -- partition key MUST be in every unique key
) PARTITION BY RANGE (YEAR(created_at)) (
  PARTITION p2023 VALUES LESS THAN (2024),
  PARTITION p2024 VALUES LESS THAN (2025),
  PARTITION pmax  VALUES LESS THAN MAXVALUE
);
```

### 3. The big partitioning rule (interview favorite)
**Every UNIQUE/PRIMARY key must include the partitioning column.** Because partitions are independent, MySQL can't enforce global uniqueness across them without the partition key in the index. This often forces a composite PK like `(id, created_at)`.

### 4. Partition pruning
The optimizer skips partitions that can't match (`WHERE created_at >= '2024-01-01'` → only scans 2024+ partitions). **Pruning only works if the WHERE filters on the partition key.** A query without the partition key scans **all** partitions (often slower than an unpartitioned indexed table!).

### 5. When partitioning helps / hurts
**Helps:**
- **Time-series data**: archive/drop old data instantly via `ALTER TABLE ... DROP PARTITION` (no giant DELETE), `TRUNCATE PARTITION`.
- Queries that filter on the partition key (pruning).
- Spreading I/O.

**Hurts / caveats:**
- Queries that **don't** use the partition key hit every partition.
- Too many partitions add overhead.
- It is **not** a substitute for proper indexing — a well-indexed unpartitioned table often beats a poorly-partitioned one.
- Foreign keys are **not supported** on partitioned tables.

### 6. Sharding strategies
- **Range sharding** — by id/date ranges (hot-spot risk on the newest range).
- **Hash/modulo sharding** — even spread, but **resharding is painful** (changing N rehashes everything).
- **Consistent hashing** — minimizes data movement when adding/removing shards.
- **Directory/lookup-based** — a mapping service resolves key→shard (flexible, extra hop + SPOF risk).
- **Shard key choice** is everything: it should be in most queries (avoid scatter-gather across all shards) and distribute evenly (avoid hot shards).

### 7. Sharding pain points
- **Cross-shard joins/transactions** are hard (no distributed transactions out of the box) — denormalize or do app-side joins.
- **Cross-shard aggregations** = scatter-gather + merge.
- **Global uniqueness / IDs**: use UUIDs, snowflake-style IDs, or a central sequence — auto-increment per shard collides.
- **Rebalancing** when a shard fills up.
Tools/approaches: **Vitess** (YouTube's MySQL sharding layer), ProxySQL routing, or app-level sharding.

---

## PRACTICE

```sql
USE prep;

-- RANGE partition by year
CREATE TABLE events_part (
  id BIGINT AUTO_INCREMENT,
  user_id INT, event_type VARCHAR(30), created_at DATETIME NOT NULL,
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (YEAR(created_at)) (
  PARTITION p2023 VALUES LESS THAN (2024),
  PARTITION p2024 VALUES LESS THAN (2025),
  PARTITION pmax  VALUES LESS THAN MAXVALUE
);
INSERT INTO events_part (user_id,event_type,created_at)
SELECT user_id,event_type,created_at FROM events;

-- Partition pruning: filtering on the partition key
EXPLAIN SELECT COUNT(*) FROM events_part WHERE created_at >= '2024-06-01'\G  -- note 'partitions' column
EXPLAIN SELECT COUNT(*) FROM events_part WHERE event_type='login'\G          -- ALL partitions (no pruning)

-- See partition row distribution
SELECT partition_name, table_rows
FROM information_schema.partitions
WHERE table_name='events_part' AND table_schema='prep';

-- Instant archival: drop a whole year (vs a massive DELETE)
ALTER TABLE events_part DROP PARTITION p2023;        -- gone instantly
-- Add a new year ahead of time (split MAXVALUE properly in practice via REORGANIZE)
ALTER TABLE events_part REORGANIZE PARTITION pmax INTO (
  PARTITION p2025 VALUES LESS THAN (2026),
  PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- HASH partition for even distribution
CREATE TABLE sessions_part (
  id BIGINT, user_id INT, PRIMARY KEY(id, user_id)
) PARTITION BY HASH(user_id) PARTITIONS 4;
```

**Exercises:**
1. Show with EXPLAIN that a query filtering on the partition key prunes partitions, and one that doesn't.
2. Drop the oldest partition and confirm it's far faster than `DELETE WHERE year=...`.
3. Explain why `PRIMARY KEY (id)` alone fails on a table partitioned by `created_at`.
4. Sketch (in writing) a shard key for an e-commerce `orders` table and justify it; identify which queries become scatter-gather.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Partitioning vs sharding — what problem does each actually solve?**
**Partitioning** is within a single server — it aids data management (fast drop/archive of old ranges), maintenance, and queries that prune on the partition key. It does **not** scale you beyond one machine's CPU/RAM/disk/write capacity. **Sharding** splits data across many servers — it's how you scale **writes and storage horizontally**, at the cost of cross-shard complexity.

**Q2. Why must the partitioning column be part of every unique key?**
Each partition is a separate physical structure with its own indexes. MySQL enforces uniqueness *within* a partition, not globally. If the partition key weren't in the unique index, two equal values could land in different partitions and both be "unique" locally — violating global uniqueness. Including the partition key guarantees equal-key rows share a partition.

**Q3. You partitioned by date for "performance" but queries got slower. Why?**
Likely the queries **don't filter on the partition key**, so there's no pruning — every partition is scanned (more overhead than one indexed table). Or there are too many partitions, or you relied on partitioning instead of a proper index. Partitioning helps only when access patterns align with the partition key.

**Q4. What's the cleanest way to purge data older than 1 year from a 2-billion-row time-series table?**
Partition by date (RANGE) and **`ALTER TABLE ... DROP PARTITION`** — it removes the old partition's files almost instantly, with minimal locking and no redo/undo bloat. Compare to a `DELETE WHERE created_at < ...` which would scan/lock/log billions of rows for hours. This is the canonical reason to partition.

**Q5. Hash sharding makes resharding painful. Why, and what's the alternative?**
With `shard = hash(key) % N`, changing `N` (adding a server) remaps **almost every key**, forcing a massive data migration. **Consistent hashing** maps keys and nodes onto a ring so adding/removing a node only moves the keys in the adjacent arc (~1/N of data), drastically reducing rebalancing. Directory-based sharding also allows targeted moves.

**Q6. How do you generate unique primary keys across shards?**
Per-shard `AUTO_INCREMENT` collides. Options: (1) **UUIDs** (or ordered UUID v7) — globally unique, but wide/random; (2) **Snowflake-style IDs** — time + shard/worker id + sequence packed into a 64-bit int (sortable, compact); (3) a **central ticket/sequence server** with per-shard offsets/steps (`auto_increment_increment`/`offset`). Snowflake-style is the common high-scale choice.

**Q7. What makes a *good* shard key?**
It should (a) appear in the **majority of queries** so they route to a single shard (avoiding scatter-gather across all shards), (b) **distribute data evenly** (no hot shard), and (c) keep related data that's queried together on the same shard. E.g., sharding by `customer_id` keeps a customer's orders together; sharding `orders` by `order_date` creates a hot "current" shard and forces customer-history queries to fan out.

**Q8. Can a partitioned table have foreign keys?**
No — InnoDB does **not** support foreign keys on partitioned tables (in either direction). You must enforce referential integrity in the application or avoid partitioning tables that need FKs. This is a common gotcha when introducing partitioning to an existing schema.

➡ Next: [Day 19 — Replication](day-19-replication.md)
