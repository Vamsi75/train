# Day 07 — Subqueries, Correlated Subqueries, Derived Tables, CTEs

## THEORY

### 1. Subquery flavors
- **Scalar subquery:** returns one value → usable anywhere an expression is. `SELECT (SELECT MAX(salary) FROM employees) AS top;`
- **Row subquery:** returns one row of several columns.
- **Table/column subquery:** returns many rows → used with `IN`, `ANY`, `ALL`, `EXISTS`, or in `FROM`.
- **Derived table:** a subquery in `FROM` (must be aliased). `SELECT * FROM (SELECT ...) AS t;`

### 2. Correlated subquery
References a column from the outer query → re-evaluated *per outer row* (conceptually). Powerful but can be slow if not index-supported.
```sql
-- Employees earning more than their dept average
SELECT e.* FROM employees e
WHERE e.salary > (SELECT AVG(s.salary) FROM employees s WHERE s.dept_id=e.dept_id);
```

### 3. ANY / ALL / SOME
- `> ALL (subq)` → greater than the maximum. `> ANY` → greater than the minimum.
- Often clearer rewritten with `MAX`/`MIN` or `EXISTS`.

### 4. CTEs (Common Table Expressions) — MySQL 8.0+
`WITH name AS (SELECT ...) SELECT ... FROM name`. Benefits: readability, reuse within the statement, and **recursion**.
```sql
WITH paid AS (SELECT * FROM orders WHERE status='PAID')
SELECT customer_id, COUNT(*) FROM paid GROUP BY customer_id;
```

### 5. Recursive CTE
For hierarchies/sequences (org charts, BOM, graph walks):
```sql
WITH RECURSIVE chain AS (
  SELECT emp_id, first_name, manager_id, 1 AS lvl
  FROM employees WHERE manager_id IS NULL          -- anchor
  UNION ALL
  SELECT e.emp_id, e.first_name, e.manager_id, c.lvl+1
  FROM employees e JOIN chain c ON e.manager_id=c.emp_id   -- recursive
)
SELECT * FROM chain ORDER BY lvl;
```
Guard against infinite loops with `cte_max_recursion_depth` (default 1000).

### 6. Derived table vs CTE vs View
- **Derived table:** inline, single-use, no name reuse.
- **CTE:** named, reusable *within one statement*, supports recursion. In MySQL 8 a non-recursive CTE referenced once may be **merged** into the outer query (no materialization); referenced multiple times it may be materialized.
- **View:** persistent, reusable across statements (Day 15).

### 7. Subquery → JOIN rewrite
Many subqueries are faster as joins (the optimizer often does this for you, but not always). Knowing both forms — and when to convert — is a 4-year-dev skill.

---

## PRACTICE

```sql
USE prep;

-- Scalar subquery
SELECT first_name, salary,
       salary - (SELECT AVG(salary) FROM employees) AS vs_avg
FROM employees;

-- Correlated: earn above own-dept average
SELECT e.first_name, e.dept_id, e.salary
FROM employees e
WHERE e.salary > (SELECT AVG(s.salary) FROM employees s WHERE s.dept_id=e.dept_id);

-- Derived table: dept averages joined back
SELECT e.first_name, e.salary, da.avg_sal
FROM employees e
JOIN (SELECT dept_id, AVG(salary) avg_sal FROM employees GROUP BY dept_id) da
  ON da.dept_id = e.dept_id;

-- CTE version (more readable)
WITH dept_avg AS (
  SELECT dept_id, AVG(salary) avg_sal FROM employees GROUP BY dept_id
)
SELECT e.first_name, e.salary, da.avg_sal
FROM employees e JOIN dept_avg da ON da.dept_id=e.dept_id
WHERE e.salary > da.avg_sal;

-- Recursive: management chain levels
WITH RECURSIVE chain AS (
  SELECT emp_id, first_name, manager_id, 1 lvl
  FROM employees WHERE manager_id IS NULL
  UNION ALL
  SELECT e.emp_id, e.first_name, e.manager_id, c.lvl+1
  FROM employees e JOIN chain c ON e.manager_id=c.emp_id
)
SELECT lvl, GROUP_CONCAT(first_name) FROM chain GROUP BY lvl;

-- Recursive number/date series (no numbers table needed)
WITH RECURSIVE days AS (
  SELECT DATE('2024-05-01') d
  UNION ALL SELECT d + INTERVAL 1 DAY FROM days WHERE d < '2024-05-07'
)
SELECT d, (SELECT COUNT(*) FROM orders o WHERE DATE(o.order_date)=days.d) orders
FROM days;

-- EXISTS semi-join
SELECT p.name FROM products p
WHERE EXISTS (SELECT 1 FROM order_items oi WHERE oi.product_id=p.product_id);
```

**Exercises:**
1. Find the employee(s) with the maximum salary in each department (try with a correlated subquery, then with a window function on Day 08 and compare).
2. List customers whose total spend exceeds the overall average customer spend (derived table).
3. Use a recursive CTE to generate a calendar of all dates in June 2024 and left-join order counts.
4. Rewrite the "earn above dept average" correlated query as a JOIN to a derived table and compare `EXPLAIN`.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Correlated vs non-correlated subquery — how do they differ in execution?**
A non-correlated subquery is independent and can be evaluated **once**. A correlated subquery references the outer row, so conceptually it runs **once per outer row** (the optimizer may transform it into a join/semi-join to avoid that). Correlated subqueries are the ones to watch for performance.

**Q2. In MySQL 8, is a CTE always materialized into a temp table?**
No. A non-recursive CTE referenced **once** is typically **merged** into the outer query (like a derived table), no temp table. Referenced **multiple times**, or when merging isn't possible, it may be **materialized** once and reused. Recursive CTEs are materialized. (Note: MySQL has no `MATERIALIZED`/`NOT MATERIALIZED` hints like PostgreSQL.)

**Q3. Write "the second highest salary" without LIMIT.**
```sql
SELECT MAX(salary) FROM employees
WHERE salary < (SELECT MAX(salary) FROM employees);
```
This is NULL-safe-ish and handles ties (returns the distinct second value). The `LIMIT 1 OFFSET 1` version fails with duplicate top salaries.

**Q4. Why might `WHERE col IN (SELECT ...)` be slow, and what's the rewrite?**
If the subquery is re-executed or materialized poorly, or the optimizer can't convert it to a semi-join, it scans repeatedly. Rewrites: `EXISTS` (correlated, short-circuits) or an explicit `JOIN` with `DISTINCT`. In MySQL 8 the optimizer usually does semi-join conversion automatically, but verify with `EXPLAIN`.

**Q5. A recursive CTE errors with "Recursive query aborted after 1001 iterations." What happened and what are the two fixes?**
It exceeded `cte_max_recursion_depth` (default 1000), usually due to a **cycle** in the data (e.g., emp A manages B manages A) or a missing termination condition. Fixes: (1) fix the termination predicate / detect cycles by tracking a visited path; (2) raise `cte_max_recursion_depth` if the depth is legitimately large.

**Q6. Difference between a derived table and a correlated subquery in the FROM clause?**
A plain derived table is non-correlated and computed independently. MySQL historically did **not** support correlated derived tables (LATERAL); MySQL 8.0.14+ added **`LATERAL`** derived tables, which *can* reference columns from preceding tables in the FROM clause — enabling per-row subqueries in FROM.

**Q7. Scalar subquery in SELECT returns more than one row — what happens?**
Runtime error: *"Subquery returns more than 1 row."* A scalar subquery must yield at most one row/one column. Guard it with an aggregate (`MAX`/`MIN`) or a `LIMIT 1` (with deterministic ordering), or restructure as a join.

➡ Next: [Day 08 — Window Functions & Set Operations](day-08-window-functions.md)
