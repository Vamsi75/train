# Day 15 — Views & Materialized-View Patterns

## THEORY

### 1. What a view is
A **named, stored SELECT** — a virtual table. It stores no data; querying it runs the underlying query. Uses: simplify complex queries, provide a stable interface over changing schema, restrict column/row access (security), and encapsulate business logic.

```sql
CREATE VIEW v_active_orders AS
SELECT o.order_id, c.name AS customer, o.status, o.order_date
FROM orders o JOIN customers c ON c.customer_id=o.customer_id
WHERE o.status <> 'CANCELLED';
```

### 2. View algorithms: MERGE vs TEMPTABLE
- **MERGE** — the view definition is merged into the outer query (like a macro). Fast; the outer `WHERE` pushes down. Possible only when the view is "simple" (no aggregation/DISTINCT/UNION/subquery-in-select/window funcs).
- **TEMPTABLE** — MySQL materializes the view into a temp table first, then the outer query runs against it. Slower, can't push predicates down, and the view is **not updatable**. Triggered automatically when MERGE isn't possible.
- `CREATE ALGORITHM=MERGE|TEMPTABLE|UNDEFINED VIEW ...` to hint.

### 3. Updatable views
A view is **updatable** (you can INSERT/UPDATE/DELETE through it) only if it maps rows 1:1 to a single base table: no aggregation, `DISTINCT`, `GROUP BY`, `HAVING`, `UNION`, most subqueries, or window functions. `WITH CHECK OPTION` prevents updates that would make a row fall outside the view's `WHERE`.

### 4. MySQL has NO materialized views (important!)
Unlike PostgreSQL/Oracle, MySQL has **no native materialized views**. Patterns to emulate:
1. **Summary table + scheduled refresh** — a real table populated by an EVENT or job (`REPLACE`/`TRUNCATE+INSERT ... SELECT`).
2. **Summary table + triggers** — keep the rollup updated incrementally on every base change (more complex, real-time).
3. **Generated/denormalized columns** for simple per-row derivations.

### 5. View performance traps
- A view over a view over a view → the optimizer may be forced into TEMPTABLE materialization, killing performance.
- Predicates may not push into aggregated/UNION views, so `SELECT * FROM v WHERE x=1` can compute the *entire* view then filter.
- Views don't add indexes — they inherit the base tables' indexes only when MERGE-able.

---

## PRACTICE

```sql
USE prep;

-- Simple (MERGE) view
CREATE OR REPLACE VIEW v_emp_dept AS
SELECT e.emp_id, e.first_name, e.salary, d.dept_name, d.location
FROM employees e LEFT JOIN departments d ON e.dept_id=d.dept_id;
SELECT * FROM v_emp_dept WHERE location='Mumbai';   -- predicate pushes into base query

-- Check the algorithm chosen
SHOW CREATE VIEW v_emp_dept\G
EXPLAIN SELECT * FROM v_emp_dept WHERE location='Mumbai'\G

-- Aggregated view → TEMPTABLE, NOT updatable
CREATE OR REPLACE VIEW v_dept_payroll AS
SELECT dept_id, COUNT(*) headcount, SUM(salary) payroll
FROM employees GROUP BY dept_id;
SELECT * FROM v_dept_payroll;
-- UPDATE v_dept_payroll SET payroll=0;   -- ERROR: not updatable

-- Updatable view + CHECK OPTION
CREATE OR REPLACE VIEW v_eng AS
SELECT emp_id, first_name, salary, dept_id FROM employees
WHERE dept_id = 1 WITH CHECK OPTION;
UPDATE v_eng SET salary = salary + 1 WHERE emp_id = 2;   -- OK, stays in dept 1
-- UPDATE v_eng SET dept_id = 2 WHERE emp_id = 2;        -- ERROR: violates CHECK OPTION

-- Security view: expose only non-sensitive columns
CREATE OR REPLACE VIEW v_emp_public AS
SELECT emp_id, first_name, last_name, dept_id FROM employees;  -- hides salary/email
-- GRANT SELECT ON prep.v_emp_public TO 'reporting'@'%';

-- "Materialized view" pattern: summary table + refresh event
CREATE TABLE dept_payroll_snapshot (
  dept_id INT PRIMARY KEY, headcount INT, payroll DECIMAL(14,2), refreshed_at DATETIME
);
DELIMITER $$
CREATE PROCEDURE refresh_dept_payroll()
BEGIN
  REPLACE INTO dept_payroll_snapshot (dept_id, headcount, payroll, refreshed_at)
  SELECT dept_id, COUNT(*), SUM(salary), NOW() FROM employees GROUP BY dept_id;
END$$
DELIMITER ;
CALL refresh_dept_payroll();
SELECT * FROM dept_payroll_snapshot;
-- Schedule it: CREATE EVENT ev_refresh ON SCHEDULE EVERY 1 HOUR DO CALL refresh_dept_payroll();
```

**Exercises:**
1. Create a MERGE view and confirm with EXPLAIN that a WHERE on it uses the base index.
2. Create an aggregated view and verify it's not updatable.
3. Build a "materialized" daily revenue summary table refreshed by an event.
4. Use `WITH CHECK OPTION` to prevent inserting a row that wouldn't appear in the view.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Does a view improve performance?**
Not inherently — a view is just a stored query. A **MERGE** view performs identically to writing the query inline (predicates push down, base indexes used). A **TEMPTABLE** view (forced by aggregation/UNION/etc.) can be *slower* because it materializes first and blocks predicate pushdown. Views improve **readability/security/maintainability**, not raw speed.

**Q2. When is a view NOT updatable?**
When it doesn't map 1:1 to base-table rows: it uses `GROUP BY`/aggregates, `DISTINCT`, `UNION`/`UNION ALL`, `HAVING`, certain subqueries, window functions, or references no base table (literal-only). Such views are read-only; you must update the base tables directly.

**Q3. Does MySQL have materialized views? If not, how do you get the benefit?**
**No native materialized views.** Emulate with a **summary table** refreshed either on a schedule (EVENT/cron calling `INSERT ... SELECT`/`REPLACE`) for periodic freshness, or **incrementally via triggers** for near-real-time. Choose based on freshness needs vs write overhead.

**Q4. What does `WITH CHECK OPTION` do?**
For an updatable view with a `WHERE`, it ensures any INSERT/UPDATE through the view produces rows that **still satisfy the view's WHERE** — otherwise the operation errors. Prevents "updating a row out of the view" (e.g., changing dept_id so it leaves a single-department view).

**Q5. `SELECT * FROM aggregated_view WHERE region='X'` is slow even though region is indexed on the base table. Why?**
Because the view aggregates, MySQL materializes the **entire** aggregated result (TEMPTABLE) before applying the outer `WHERE region='X'` — the predicate can't push down past the GROUP BY. The base index doesn't help post-aggregation. Fix by filtering inside the view definition or querying the base table directly with the filter.

**Q6. Nested views (view on view on view) — what's the risk?**
Each layer can force materialization and defeats predicate pushdown/optimization, leading to repeated temp-table creation and poor plans. Deep nesting also obscures what query actually runs. Flatten when possible, or replace with a well-indexed summary table.

**Q7. How can views serve as a security mechanism?**
Grant users access to a **view** that exposes only permitted columns/rows (e.g., hides `salary`, filters to their region) and revoke direct access to the base table. Combined with the `DEFINER`/`SQL SECURITY DEFINER|INVOKER` clause, the view can run with the definer's privileges, letting restricted users read controlled subsets without base-table rights.

➡ Next: [Day 16 — EXPLAIN & Query Optimization](day-16-explain-query-optimization.md)
