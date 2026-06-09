# Day 14 — Triggers, Events & Cursors

## THEORY

### 1. Triggers
A stored program that fires **automatically** on a table DML event.
- Timing: `BEFORE` or `AFTER`.
- Event: `INSERT`, `UPDATE`, `DELETE`.
- 6 combinations per table. MySQL 8 allows **multiple triggers** of the same timing/event (ordered with `FOLLOWS`/`PRECEDES`).
- Access changing rows via `NEW.col` (INSERT/UPDATE) and `OLD.col` (UPDATE/DELETE).
- `BEFORE` triggers can **modify `NEW`** (e.g., normalize/validate data); `AFTER` cannot.

```sql
CREATE TRIGGER trg_audit_salary
AFTER UPDATE ON employees FOR EACH ROW
INSERT INTO salary_audit(emp_id, old_salary, new_salary, changed_at)
VALUES (OLD.emp_id, OLD.salary, NEW.salary, NOW());
```

**Uses:** auditing, denormalized counter/total maintenance, validation, enforcing complex rules.
**Cautions:** hidden side effects (debugging surprises), per-row overhead on bulk DML, can't easily be skipped, triggers calling triggers (cascades), and they run **inside the same transaction** as the DML (a trigger error rolls back the statement).

### 2. Events (the MySQL scheduler — "cron in the DB")
```sql
SET GLOBAL event_scheduler = ON;
CREATE EVENT ev_purge_old_events
ON SCHEDULE EVERY 1 DAY STARTS '2024-06-01 02:00:00'
DO DELETE FROM events WHERE created_at < NOW() - INTERVAL 90 DAY;
```
**Uses:** scheduled cleanup, rollups, archival, refreshing summary tables. Requires the scheduler ON. Watch out: events run on the **primary** and replicate their effects; disabled on replicas by default.

### 3. Cursors
Row-by-row iteration over a query result inside a stored program. **Use sparingly** — set-based SQL is almost always faster than a cursor loop ("RBAR" — Row By Agonizing Row).
```sql
DECLARE done INT DEFAULT 0;
DECLARE v_id INT;
DECLARE cur CURSOR FOR SELECT emp_id FROM employees;
DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
OPEN cur;
read_loop: LOOP
  FETCH cur INTO v_id;
  IF done THEN LEAVE read_loop; END IF;
  -- per-row work
END LOOP;
CLOSE cur;
```
Declaration order inside a block is strict: **variables → cursors → handlers**.

### 4. Generated columns (a better alternative to many triggers)
```sql
ALTER TABLE order_items
  ADD COLUMN line_total DECIMAL(12,2)
  AS (quantity * unit_price) STORED;   -- or VIRTUAL
```
- `VIRTUAL` (computed on read, no storage) vs `STORED` (computed on write, stored, indexable in all cases).
- Often replaces a BEFORE-INSERT/UPDATE trigger for derived values, and can be indexed.

---

## PRACTICE

```sql
USE prep;

-- Audit table + trigger
CREATE TABLE salary_audit (
  audit_id   INT PRIMARY KEY AUTO_INCREMENT,
  emp_id     INT,
  old_salary DECIMAL(10,2),
  new_salary DECIMAL(10,2),
  changed_at DATETIME
);

DELIMITER $$
CREATE TRIGGER trg_audit_salary
AFTER UPDATE ON employees FOR EACH ROW
BEGIN
  IF OLD.salary <> NEW.salary THEN
    INSERT INTO salary_audit(emp_id, old_salary, new_salary, changed_at)
    VALUES (OLD.emp_id, OLD.salary, NEW.salary, NOW());
  END IF;
END$$
DELIMITER ;

UPDATE employees SET salary = salary + 1000 WHERE emp_id = 3;
SELECT * FROM salary_audit;

-- BEFORE trigger that validates/normalizes
DELIMITER $$
CREATE TRIGGER trg_norm_email
BEFORE INSERT ON employees FOR EACH ROW
BEGIN
  SET NEW.email = LOWER(TRIM(NEW.email));
  IF NEW.salary <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Salary must be positive';
  END IF;
END$$
DELIMITER ;

-- Denormalized counter maintained by triggers
ALTER TABLE customers ADD COLUMN order_count INT NOT NULL DEFAULT 0;
DELIMITER $$
CREATE TRIGGER trg_oi_count AFTER INSERT ON orders FOR EACH ROW
  UPDATE customers SET order_count = order_count + 1 WHERE customer_id = NEW.customer_id;$$
DELIMITER ;

-- Generated column (preferred over a trigger for derived value)
ALTER TABLE order_items ADD COLUMN line_total DECIMAL(12,2) AS (quantity*unit_price) STORED;
SELECT order_id, product_id, line_total FROM order_items;

-- Event: nightly purge
SET GLOBAL event_scheduler = ON;
CREATE EVENT IF NOT EXISTS ev_purge
ON SCHEDULE EVERY 1 DAY
DO DELETE FROM events WHERE created_at < NOW() - INTERVAL 90 DAY;
SHOW EVENTS;

-- Inspect
SHOW TRIGGERS\G
```

**Exercises:**
1. Write an AFTER DELETE trigger on `orders` that decrements `customers.order_count`.
2. Use a BEFORE UPDATE trigger to forbid lowering an employee's salary (raise via SIGNAL).
3. Replace the `line_total` trigger idea with a VIRTUAL generated column and index it.
4. Create an event that, every hour, refreshes a summary table `dept_payroll_snapshot`.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. `NEW` vs `OLD` — which are available in each trigger type?**
- INSERT: only `NEW` (the row being inserted).
- DELETE: only `OLD` (the row being removed).
- UPDATE: both `OLD` (pre) and `NEW` (post).
Only a **BEFORE** trigger may **assign** to `NEW` (to change the value being written); AFTER triggers see them read-only.

**Q2. Can a trigger roll back the statement that fired it?**
Yes — a trigger runs **within the same transaction** as the triggering DML. If the trigger raises an error (e.g., `SIGNAL`) or fails, the entire statement (and its effects) is rolled back. This makes BEFORE triggers a valid place to enforce validation.

**Q3. Why are triggers risky for performance and maintainability?**
They fire **per row** (a 1M-row UPDATE fires the trigger a million times) and execute **synchronously inside the transaction**, adding latency and lock duration. They're "invisible" — logic hidden from application developers, hard to test/version, and can cascade (trigger → DML → another trigger). Use them deliberately, mostly for auditing/integrity.

**Q4. Generated column vs trigger for a derived value (like line_total) — which and why?**
Prefer a **generated column**: it's declarative, can't be bypassed, is automatically consistent, and `STORED` ones are indexable. A trigger achieves the same but with more code, per-row overhead, and risk of being inconsistent if logic changes. Use a trigger only when the derivation needs cross-row/cross-table logic a generated column can't express.

**Q5. VIRTUAL vs STORED generated column — trade-offs?**
**VIRTUAL**: computed on read, takes no storage, fast writes; can be indexed (8.0) but recomputed for each read otherwise. **STORED**: computed on write, persisted (more disk + write cost), good when the expression is expensive and read often, or needed for certain index/foreign-key scenarios. Default to VIRTUAL unless reads dominate or you need it materialized.

**Q6. Your nightly cleanup EVENT isn't running. What do you check first?**
Whether the **event scheduler is enabled**: `SHOW VARIABLES LIKE 'event_scheduler';` — it's often `OFF` (set `event_scheduler=ON`, and persist in config). Also check the event's `STATUS` (ENABLED vs DISABLED/SLAVESIDE_DISABLED on replicas), the schedule/timezone, and that the definer still has privileges.

**Q7. When is a cursor justified over set-based SQL?**
Almost never for plain data transforms — set-based SQL is faster. Cursors are justified when each row requires **procedural per-row side effects** that can't be expressed as a set operation (e.g., calling a different procedure per row, complex sequential state, or interfacing row-by-row with external logic). Even then, consider doing it in the application layer.

➡ Next: [Day 15 — Views](day-15-views.md)
