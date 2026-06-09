# MySQL One-Page Cheatsheet

## Connect & admin
```sql
mysql -u root -p                       -- connect
SHOW DATABASES; USE db; SHOW TABLES;
DESCRIBE t;  SHOW CREATE TABLE t\G
SHOW PROCESSLIST;  KILL <id>;
SELECT VERSION(); SELECT @@variable;
SHOW VARIABLES LIKE 'innodb%'; SHOW STATUS LIKE 'Threads%';
```

## DDL
```sql
CREATE TABLE t (id INT PRIMARY KEY AUTO_INCREMENT, ...) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
ALTER TABLE t ADD COLUMN x INT, ADD INDEX idx(x), ALGORITHM=INSTANT;
ALTER TABLE t MODIFY col BIGINT;  ALTER TABLE t DROP COLUMN x;
TRUNCATE TABLE t;   DROP TABLE t;   RENAME TABLE a TO b;
```
Constraints: `PRIMARY KEY`, `UNIQUE`, `NOT NULL`, `FOREIGN KEY ... REFERENCES`, `CHECK (...)` (8.0.16+), `DEFAULT`.

## DML
```sql
INSERT INTO t (a,b) VALUES (1,2),(3,4);
INSERT ... ON DUPLICATE KEY UPDATE b=VALUES(b);     -- upsert
UPDATE t SET x=1 WHERE id=5;                         -- ALWAYS have a WHERE
DELETE FROM t WHERE id=5;                            -- chunk big deletes: ... ORDER BY id LIMIT 5000
```

## SELECT (logical order: FROM→WHERE→GROUP BY→HAVING→SELECT→ORDER BY→LIMIT)
```sql
SELECT col, AGG(x) FROM t
JOIN u ON u.id=t.uid
WHERE cond                 -- no aggregates, no SELECT aliases
GROUP BY col
HAVING AGG(x) > n          -- aggregates ok
ORDER BY col2              -- aliases ok
LIMIT 20 OFFSET 40;        -- keyset for deep pages: WHERE id>:last ... LIMIT 20
```

## Joins
```sql
INNER JOIN  -- matches only
LEFT JOIN   -- all left + matched right (put right-table filters in ON, not WHERE)
SELF JOIN   -- t a JOIN t b ON a.parent=b.id
-- FULL OUTER: LEFT ... UNION RIGHT ...
-- anti-join: WHERE NOT EXISTS (SELECT 1 FROM u WHERE u.k=t.k)
```

## Aggregation / pivot
```sql
COUNT(*) | COUNT(col) | SUM | AVG | MIN | MAX | GROUP_CONCAT(x ORDER BY y SEPARATOR ',')
-- pivot:
SUM(status='PAID') AS paid, SUM(status='SHIPPED') AS shipped
```

## Window functions (8.0+)
```sql
ROW_NUMBER() | RANK() | DENSE_RANK() | NTILE(n) OVER (PARTITION BY a ORDER BY b)
SUM(x) OVER (ORDER BY d ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)   -- running total
LAG(x)/LEAD(x) OVER (ORDER BY d)                                            -- prev/next
-- top-N per group: filter ROW_NUMBER()=1 in an outer query
```

## CTE / recursive
```sql
WITH t AS (SELECT ...) SELECT * FROM t;
WITH RECURSIVE r(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM r WHERE n<10) SELECT * FROM r;
```

## Indexes
```sql
CREATE INDEX idx ON t(a,b,c);      -- leftmost-prefix: serves a / a,b / a,b,c (range on b stops c)
CREATE UNIQUE INDEX ...; CREATE INDEX idx ON t(col(20));   -- prefix index
CREATE INDEX idx ON t((YEAR(d)));  -- functional (8.0.13+)
ALTER TABLE t ALTER INDEX idx INVISIBLE;   -- test impact safely
ANALYZE TABLE t;  SHOW INDEX FROM t;
-- covering index → EXPLAIN shows "Using index"
```

## EXPLAIN
```sql
EXPLAIN SELECT ...\G               -- estimates; watch type=ALL, rows, Extra
EXPLAIN ANALYZE SELECT ...\G       -- ACTUAL timings + rows (8.0.18+)
EXPLAIN FORMAT=TREE SELECT ...\G
-- type best→worst: const > eq_ref > ref > range > index > ALL
-- Extra good: "Using index"; bad: "Using filesort","Using temporary"
```

## Transactions & isolation
```sql
START TRANSACTION; ... COMMIT|ROLLBACK;  SAVEPOINT s; ROLLBACK TO s;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;  -- RU | RC | RR(default) | SERIALIZABLE
SELECT ... FOR UPDATE;   -- X lock      SELECT ... FOR SHARE;   -- S lock
-- MVCC: plain SELECT = snapshot read (no locks)
```

## Locks / deadlocks
```sql
SHOW ENGINE INNODB STATUS\G                 -- LATEST DETECTED DEADLOCK
SELECT * FROM sys.innodb_lock_waits\G        -- blocker vs waiter
SELECT * FROM information_schema.innodb_trx; -- find long/idle txn
-- 1213 = deadlock (retry); 1205 = lock wait timeout
```

## Stored programs
```sql
DELIMITER $$
CREATE PROCEDURE p(IN a INT, OUT b INT) BEGIN ... SET b=ROW_COUNT(); END$$
CREATE FUNCTION f(x INT) RETURNS INT DETERMINISTIC BEGIN RETURN x*2; END$$
DELIMITER ;
CALL p(1,@b);  SELECT f(5);
-- trigger: CREATE TRIGGER tg BEFORE INSERT ON t FOR EACH ROW SET NEW.col=LOWER(NEW.col);
-- event: SET GLOBAL event_scheduler=ON; CREATE EVENT e ON SCHEDULE EVERY 1 DAY DO ...;
```

## Backup / recovery
```bash
mysqldump --single-transaction --routines --triggers --events --databases db > db.sql
mysql db < db.sql
mysqlbinlog --stop-datetime="..." mysql-bin.000045 | mysql   # PITR replay
```

## Replication
```sql
SHOW REPLICA STATUS\G   -- Seconds_Behind_Source, Replica_IO/SQL_Running
CHANGE REPLICATION SOURCE TO ..., SOURCE_AUTO_POSITION=1;  START REPLICA;
-- binlog_format=ROW, gtid_mode=ON for safety
```

## Security
```sql
CREATE USER 'app'@'%' IDENTIFIED BY '...';
GRANT SELECT,INSERT,UPDATE,DELETE ON db.* TO 'app'@'%';   -- least privilege
CREATE ROLE 'ro'; GRANT SELECT ON db.* TO 'ro'; GRANT 'ro' TO 'u'@'%';
SHOW GRANTS FOR 'app'@'%';
-- prepared statement (injection-proof): PREPARE s FROM 'SELECT * FROM t WHERE c=?'; EXECUTE s USING @v;
```

## NULL / gotchas
- `x = NULL` → never true; use `IS NULL`. NULL-safe equality: `<=>`.
- `NOT IN (...,NULL)` → no rows; use `NOT EXISTS`.
- Aggregates ignore NULL (except `COUNT(*)`).
- Function on indexed col / implicit cast → no index (non-sargable).
- DDL auto-commits (can't rollback).
