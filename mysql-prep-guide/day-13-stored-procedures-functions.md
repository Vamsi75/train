# Day 13 — Stored Procedures & Functions

## THEORY

### 1. Stored program types
- **Stored Procedure** — a callable routine (`CALL p(...)`), can have `IN`/`OUT`/`INOUT` params, can run multiple statements, can return result sets, **cannot be used inside a SQL expression**.
- **Stored Function** — returns a single scalar value, **usable inside SQL** (`SELECT f(x)`), only `IN` params, must be deterministic-ish/declared with data-access characteristics.
- **Trigger** (Day 14), **Event** (Day 14) — also stored programs.

### 2. Procedure anatomy
```sql
DELIMITER $$
CREATE PROCEDURE give_raise(IN p_dept INT, IN p_pct DECIMAL(5,2), OUT p_count INT)
BEGIN
  UPDATE employees SET salary = salary * (1 + p_pct/100) WHERE dept_id = p_dept;
  SET p_count = ROW_COUNT();
END$$
DELIMITER ;

CALL give_raise(1, 10, @n);
SELECT @n;
```
- `DELIMITER` is changed because the body contains `;` — you need a different statement terminator.
- `ROW_COUNT()` gives rows affected by the last statement.

### 3. Variables, control flow
```sql
DECLARE v_total DECIMAL(12,2) DEFAULT 0;   -- DECLAREs must be at top of BEGIN block
SET v_total = ...;
SELECT col INTO v_var FROM ... ;           -- assign from a query (must return 1 row)

IF cond THEN ... ELSEIF ... THEN ... ELSE ... END IF;
CASE ... WHEN ... THEN ... END CASE;
WHILE cond DO ... END WHILE;
REPEAT ... UNTIL cond END REPEAT;
LOOP ... LEAVE label; ... END LOOP;
```

### 4. Error handling — HANDLERs
```sql
DECLARE EXIT HANDLER FOR SQLEXCEPTION
BEGIN
  ROLLBACK;
  RESIGNAL;            -- re-raise to caller
END;
DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;   -- cursor loop termination
DECLARE EXIT HANDLER FOR 1062 ...;  -- specific error (duplicate key)
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Custom error';  -- raise your own
```

### 5. Deterministic & data-access characteristics
Functions should declare: `DETERMINISTIC` / `NOT DETERMINISTIC`, and one of `NO SQL` / `READS SQL DATA` / `MODIFIES SQL DATA`. This matters for replication safety and the optimizer. (With binary logging on, non-deterministic functions may require `log_bin_trust_function_creators` or proper declaration.)

### 6. When to use (and NOT use) stored procedures
**Pros:** reduce round trips, centralize logic, can be faster for set-heavy batch ops, enforce access via `DEFINER` rights.
**Cons:** business logic hidden in the DB (hard to version-control, test, debug), DB CPU is expensive to scale horizontally, portability suffers, weak tooling. Modern consensus: keep heavy business logic in the app; use procedures for **data-intensive batch operations**, migrations, and tight DB-side loops.

---

## PRACTICE

```sql
USE prep;

-- Procedure with OUT param
DELIMITER $$
CREATE PROCEDURE dept_payroll(IN p_dept INT, OUT p_total DECIMAL(12,2))
BEGIN
  SELECT IFNULL(SUM(salary),0) INTO p_total FROM employees WHERE dept_id = p_dept;
END$$
DELIMITER ;
CALL dept_payroll(1, @t); SELECT @t AS engineering_payroll;

-- Function usable in SELECT
DELIMITER $$
CREATE FUNCTION tenure_years(p_hire DATE) RETURNS INT
DETERMINISTIC READS SQL DATA
BEGIN
  RETURN TIMESTAMPDIFF(YEAR, p_hire, CURDATE());
END$$
DELIMITER ;
SELECT first_name, tenure_years(hire_date) AS yrs FROM employees;

-- Transactional procedure with error handling
DELIMITER $$
CREATE PROCEDURE transfer_stock(IN p_from INT, IN p_to INT, IN p_qty INT)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN ROLLBACK; RESIGNAL; END;

  START TRANSACTION;
    UPDATE products SET stock = stock - p_qty WHERE product_id = p_from;
    IF (SELECT stock FROM products WHERE product_id=p_from) < 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient stock';
    END IF;
    UPDATE products SET stock = stock + p_qty WHERE product_id = p_to;
  COMMIT;
END$$
DELIMITER ;
CALL transfer_stock(2, 3, 10);

-- Inspect / drop
SHOW PROCEDURE STATUS WHERE Db='prep';
SHOW CREATE PROCEDURE transfer_stock\G
-- DROP PROCEDURE IF EXISTS transfer_stock;
```

**Exercises:**
1. Write a procedure that, given a customer id, returns (OUT) their total spend and order count.
2. Write a function `is_high_value(order_id)` returning 1 if the order total > 50000.
3. Add a CONTINUE HANDLER for a duplicate-key and count how many inserts were skipped in a loop.
4. Write a procedure that loops over departments and prints (result set) payroll per department.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Procedure vs function — three concrete differences.**
(1) A function returns a single value and is callable inside SQL expressions (`SELECT f()`); a procedure is invoked with `CALL` and can't appear in expressions. (2) Functions take only `IN` params; procedures support `IN/OUT/INOUT`. (3) Procedures can return multiple result sets and do transaction control freely; functions are restricted (e.g., generally shouldn't do transaction control and have limits on statements that cause commits).

**Q2. Why do you need `DELIMITER` when creating a procedure?**
The routine body contains internal `;` statement terminators. Without changing the client delimiter, the client would send the procedure to the server at the first internal `;`, truncating it. You temporarily switch to `$$` (or `//`) so the whole `CREATE` is sent as one statement, then switch back.

**Q3. `EXIT` vs `CONTINUE` handler — and what does `NOT FOUND` mean?**
An **EXIT** handler runs its action then **exits the enclosing BEGIN…END block**; a **CONTINUE** handler runs its action then **resumes** the next statement. `NOT FOUND` fires when a cursor `FETCH` finds no more rows (or a `SELECT INTO` returns none) — the standard way to terminate a cursor loop (`SET done=1`).

**Q4. What does `SIGNAL SQLSTATE '45000'` do?**
Raises a **user-defined exception** with a custom message — SQLSTATE 45000 is the generic "unhandled user-defined exception" class. It's how you throw a business-rule error from inside a stored program (e.g., "Insufficient stock"), which the caller receives as an error.

**Q5. Are stored procedures cached/compiled? How does that affect performance?**
MySQL parses and caches a procedure's execution plan **per-connection/session** in recent versions (not a global compiled object like some DBs). The benefit is fewer client-server round trips and reduced parsing on repeated calls within a session, not a heavyweight precompiled binary. Don't assume Oracle-style global plan caching.

**Q6. Why might a deterministic-looking function silently break replication?**
If a function is actually **non-deterministic** (uses `NOW()`, `RAND()`, `UUID()`, or reads tables that differ) but is used in a statement-based-replicated write, replicas can compute **different results**, diverging data. You must declare characteristics correctly (`NOT DETERMINISTIC`, `READS/MODIFIES SQL DATA`) and/or use **row-based binlog format**. `log_bin_trust_function_creators` controls whether such functions are even allowed.

**Q7. When would you push logic into a stored procedure vs keep it in the application?**
Use procedures for **data-intensive, set-based batch work** where shipping rows to the app would be slow (bulk transforms, ETL, archival, complex multi-statement transactions needing minimal latency). Keep core **business logic in the app** for testability, version control, observability, and horizontal scalability. Avoid scattering critical logic across both layers.

➡ Next: [Day 14 — Triggers, Events & Cursors](day-14-triggers-events-cursors.md)
