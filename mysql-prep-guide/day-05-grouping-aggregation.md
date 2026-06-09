# Day 05 — GROUP BY, HAVING, Aggregation, DISTINCT

## THEORY

### 1. Aggregate functions
`COUNT`, `SUM`, `AVG`, `MIN`, `MAX`, `GROUP_CONCAT`, `STDDEV`, `VARIANCE`, `BIT_OR/AND`.
All aggregates **ignore NULLs** except `COUNT(*)`. `AVG(col)` divides by the count of *non-NULL* values, not total rows — a frequent surprise.

### 2. GROUP BY
Collapses rows sharing the grouped column values into one row per group. Every column in `SELECT` must either be (a) in `GROUP BY` or (b) inside an aggregate — otherwise you get an indeterminate value.

**ONLY_FULL_GROUP_BY** (default ON in MySQL 5.7+): rejects ambiguous non-aggregated columns. Pre-5.7 MySQL silently returned an arbitrary row's value — a notorious source of subtle bugs. Know this mode by name.

### 3. HAVING vs WHERE
- `WHERE` filters **rows before grouping**; cannot use aggregates.
- `HAVING` filters **groups after aggregation**; can use aggregates.
- Put non-aggregate filters in WHERE (faster — fewer rows to group). Reserve HAVING for aggregate conditions.

```sql
SELECT dept_id, AVG(salary) avg_sal
FROM employees
WHERE hire_date >= '2019-01-01'   -- row filter (before grouping)
GROUP BY dept_id
HAVING AVG(salary) > 90000;       -- group filter (after aggregation)
```

### 4. DISTINCT
Removes duplicate rows from the result. `COUNT(DISTINCT col)` counts unique non-NULL values. `DISTINCT` applies to the whole select list, not one column.

### 5. GROUP BY extensions
- `WITH ROLLUP` — adds super-aggregate (subtotal/grand-total) rows.
- MySQL 8 supports `GROUPING()` to identify rollup rows.

### 6. Counting patterns (interview gold)
```sql
-- Conditional aggregation (pivot without a pivot function)
SELECT
  SUM(status='PAID')      AS paid,
  SUM(status='CANCELLED') AS cancelled,
  COUNT(*)                AS total
FROM orders;                       -- boolean → 1/0, summed

-- Count per group + percentage
SELECT category, COUNT(*) cnt,
       ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) pct
FROM products GROUP BY category;
```

---

## PRACTICE

```sql
USE prep;

-- Headcount & payroll per department (LEFT JOIN to include empty depts)
SELECT d.dept_name,
       COUNT(e.emp_id)        AS headcount,
       IFNULL(SUM(e.salary),0) AS payroll,
       IFNULL(ROUND(AVG(e.salary)),0) AS avg_salary
FROM departments d
LEFT JOIN employees e ON e.dept_id = d.dept_id
GROUP BY d.dept_id, d.dept_name
ORDER BY payroll DESC;

-- COUNT(*) vs COUNT(col): managers (manager_id may be NULL)
SELECT COUNT(*) AS all_emps, COUNT(manager_id) AS has_manager FROM employees;

-- HAVING: departments whose average salary exceeds 90k
SELECT dept_id, ROUND(AVG(salary)) avg_sal
FROM employees GROUP BY dept_id HAVING AVG(salary) > 90000;

-- Conditional aggregation (pivot orders by status)
SELECT
  SUM(status='PAID')      AS paid,
  SUM(status='SHIPPED')   AS shipped,
  SUM(status='PENDING')   AS pending,
  SUM(status='CANCELLED') AS cancelled
FROM orders;

-- DISTINCT cities customers come from
SELECT COUNT(DISTINCT city) AS unique_cities FROM customers;

-- ROLLUP: revenue per category + grand total
SELECT IFNULL(p.category,'== TOTAL ==') AS category,
       SUM(oi.quantity*oi.unit_price)   AS revenue
FROM order_items oi JOIN products p ON p.product_id=oi.product_id
GROUP BY p.category WITH ROLLUP;

-- Top customer by spend
SELECT c.name, SUM(oi.quantity*oi.unit_price) AS spend
FROM customers c
JOIN orders o      ON o.customer_id=c.customer_id AND o.status<>'CANCELLED'
JOIN order_items oi ON oi.order_id=o.order_id
GROUP BY c.customer_id, c.name
ORDER BY spend DESC LIMIT 1;
```

**Exercises:**
1. Find departments with more than 2 employees.
2. For each month, count orders placed (group by `YEAR`,`MONTH`).
3. Use conditional aggregation to show, per customer, how many PAID vs CANCELLED orders they have — one row per customer.
4. Compute each product category's share of total revenue as a percentage.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. `SELECT dept_id, first_name, AVG(salary) FROM employees GROUP BY dept_id` — why does this error in modern MySQL, and what did old MySQL do?**
`first_name` is neither grouped nor aggregated, so its value is ambiguous (which employee's name?). With `ONLY_FULL_GROUP_BY` (default since 5.7) MySQL **rejects** it. Older MySQL silently returned an *arbitrary* row's `first_name` — technically "valid" but a hidden correctness bug.

**Q2. A department has 3 employees but `AVG(commission)` returns a value as if it had fewer. Why?**
`AVG` ignores NULLs — it sums non-NULL commissions and divides by the **count of non-NULL** values, not the row count. If you want NULLs treated as 0, use `AVG(IFNULL(commission,0))` or `SUM(commission)/COUNT(*)`.

**Q3. WHERE vs HAVING — can you always swap them? Give a case where only HAVING works and one where WHERE is mandatory.**
No. Only HAVING can filter on an aggregate (`HAVING SUM(x)>100`). WHERE is mandatory (or strongly preferred) for row-level conditions you want applied *before* grouping — putting them in HAVING still works for non-aggregates but is slower because grouping processes rows you'll throw away.

**Q4. How do you pivot rows into columns in MySQL (no PIVOT keyword)?**
Use **conditional aggregation**: `SUM(CASE WHEN month='Jan' THEN amount ELSE 0 END) AS jan, ...` (or the boolean shorthand `SUM(month='Jan')` for counts). MySQL has no native PIVOT, so this idiom is the standard answer.

**Q5. `COUNT(DISTINCT a, b)` — what does it count?**
The number of **distinct combinations** of (a, b), skipping rows where any of the listed columns is NULL. Useful for counting unique pairs (e.g., distinct (user, day) active sessions).

**Q6. You GROUP BY and the result row count is wrong/inflated. What's the usual culprit?**
A **join fan-out** before grouping: joining to a one-to-many table multiplies rows, so `SUM`/`COUNT` double-counts. Fix by aggregating the child table in a subquery/CTE first, then joining, or use `COUNT(DISTINCT ...)`.

**Q7. What does `GROUP BY ... WITH ROLLUP` produce, and how do you tell a subtotal row apart from a real one?**
It appends super-aggregate rows where grouped columns are set to `NULL` (subtotals and a grand total). Since a real value could also be NULL, use `GROUPING(col)` (returns 1 for a rollup-generated NULL) to distinguish them.

➡ Next: [Day 06 — Joins](day-06-joins.md)
