# Day 06 — Joins: INNER, OUTER, SELF, ANTI, and the Pitfalls

## THEORY

### 1. Join types
| Join | Returns |
|------|---------|
| `INNER JOIN` | Only matching rows from both tables. |
| `LEFT [OUTER] JOIN` | All left rows + matched right (NULLs where no match). |
| `RIGHT [OUTER] JOIN` | All right rows + matched left. |
| `FULL OUTER JOIN` | All rows from both. **MySQL has no FULL OUTER** — emulate with `LEFT UNION RIGHT`. |
| `CROSS JOIN` | Cartesian product (every row × every row). |
| `SELF JOIN` | Table joined to itself (e.g., employee → manager). |

### 2. ON vs WHERE in outer joins (critical)
For `LEFT JOIN`, a condition in `ON` filters the *match*; the same condition in `WHERE` filters *after* the join and **turns it back into an inner join** if it references the right table:

```sql
-- Keeps all employees, only joins PAID-status rows
... LEFT JOIN orders o ON o.emp_id=e.id AND o.status='PAID'
-- Drops employees with no PAID order — effectively INNER
... LEFT JOIN orders o ON o.emp_id=e.id WHERE o.status='PAID'
```
The `WHERE o.status='PAID'` rejects the NULL rows the LEFT JOIN produced.

### 3. Anti-join — "rows in A with no match in B"
Three idioms:
```sql
-- LEFT JOIN / IS NULL
SELECT e.* FROM employees e
LEFT JOIN orders o ON o.emp_id=e.id WHERE o.emp_id IS NULL;
-- NOT EXISTS (usually the optimizer's favorite; NULL-safe)
SELECT e.* FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.emp_id=e.id);
-- NOT IN (DANGER if subquery can return NULL)
```

### 4. Semi-join — "rows in A with at least one match" (EXISTS / IN)
`EXISTS` stops at the first match (efficient). MySQL 8 optimizer can transform `IN`/`EXISTS` subqueries into semi-joins automatically.

### 5. Join algorithms (how MySQL executes joins)
- **Nested-Loop Join (NLJ):** for each row in the outer table, probe the inner table (ideally via index). Default.
- **Block Nested-Loop (BNL):** buffers outer rows to reduce inner scans (pre-8.0.20).
- **Hash Join (8.0.18+):** builds a hash table on the smaller input; great when **no usable index** exists on the join column. Replaced BNL for equi-joins.

### 6. The fan-out / row-multiplication trap
Joining a parent to a one-to-many child multiplies parent rows. If you then `SUM` a parent column, it's **double-counted**. Aggregate the child first, or use `COUNT(DISTINCT)`.

---

## PRACTICE

```sql
USE prep;

-- INNER: employees with their department
SELECT e.first_name, d.dept_name
FROM employees e JOIN departments d ON e.dept_id=d.dept_id;

-- LEFT: include employees with no department (Tom)
SELECT e.first_name, d.dept_name
FROM employees e LEFT JOIN departments d ON e.dept_id=d.dept_id;

-- ON vs WHERE demonstration
SELECT e.first_name, o.order_id, o.status
FROM employees e LEFT JOIN orders o ON FALSE;  -- contrived: no employee has orders here
-- Use customers/orders instead:
SELECT c.name, COUNT(o.order_id) AS paid_orders
FROM customers c
LEFT JOIN orders o ON o.customer_id=c.customer_id AND o.status='PAID'
GROUP BY c.customer_id, c.name;   -- customers with 0 PAID still appear (count 0)

-- Anti-join: customers who never ordered
SELECT c.name FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id=c.customer_id);

-- SELF JOIN: employee → manager name
SELECT e.first_name AS emp, m.first_name AS manager
FROM employees e LEFT JOIN employees m ON e.manager_id=m.emp_id;

-- FULL OUTER emulation
SELECT e.emp_id, d.dept_id FROM employees e LEFT JOIN departments d ON e.dept_id=d.dept_id
UNION
SELECT e.emp_id, d.dept_id FROM employees e RIGHT JOIN departments d ON e.dept_id=d.dept_id;

-- Fan-out trap: WRONG total (multiplied by #items)
SELECT o.order_id, o.status, SUM(oi.quantity) FROM orders o
JOIN order_items oi ON oi.order_id=o.order_id GROUP BY o.order_id;  -- ok here
-- but if you also joined another 1-to-many table, totals would inflate.

-- See the join algorithm
EXPLAIN FORMAT=TREE
SELECT * FROM orders o JOIN customers c ON o.customer_id=c.customer_id\G
```

**Exercises:**
1. List every department and its employee count, including departments with zero employees.
2. Find products that have never been ordered (anti-join, two different ways).
3. Self-join to list each employee alongside their manager's salary; flag employees who earn more than their manager.
4. Show order totals per customer without fan-out double-counting (pre-aggregate `order_items`).

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. A `LEFT JOIN` is silently behaving like an `INNER JOIN`. What's the most likely cause?**
A condition on the right-side table moved into the `WHERE` clause (e.g., `WHERE right.col = x`). Because unmatched rows have `right.col = NULL`, the WHERE predicate rejects them, eliminating the very rows LEFT JOIN was meant to preserve. Move that condition into the `ON` clause.

**Q2. MySQL has no `FULL OUTER JOIN`. How do you produce one, and what's the catch with UNION?**
`LEFT JOIN ... UNION ... RIGHT JOIN ...`. `UNION` (not `UNION ALL`) deduplicates the overlap (inner-match rows appear in both halves). If your rows can contain genuine duplicates you must dedupe carefully or use `UNION ALL` + explicit handling.

**Q3. When does MySQL pick a Hash Join over a Nested-Loop Join?**
For equi-joins where **no index** exists on the join column(s) (8.0.18+). Hash join builds an in-memory hash on the smaller table and probes once — far better than O(n·m) block nested loop. If a good index exists, NLJ via index is usually chosen.

**Q4. Three ways to write an anti-join — which is unsafe and why?**
`LEFT JOIN ... IS NULL`, `NOT EXISTS`, and `NOT IN (subquery)`. **`NOT IN` is unsafe** when the subquery can return NULL — it then returns no rows (three-valued logic). `NOT EXISTS` is NULL-safe and usually the cleanest/fastest. Prefer it.

**Q5. You join orders→order_items→shipments (both 1-to-many) and your revenue total is wildly too high. Diagnose.**
Cartesian fan-out: each order row is multiplied by (#items × #shipments), so `SUM(amount)` over-counts. Fix by aggregating each child table separately (in subqueries/CTEs) to a single row per order *before* joining, or compute each metric in its own subquery.

**Q6. `EXISTS` vs `IN` for a subquery filter — performance difference?**
Historically `EXISTS` short-circuits at the first match and IN materialized the list. In MySQL 8 the optimizer often rewrites both into semi-joins, so they perform similarly. Still, `EXISTS` is preferred for correlated checks and is NULL-safe, while `IN` with a large/NULL-containing list can misbehave.

**Q7. Does join order in your SQL text determine execution order?**
No. The **optimizer reorders joins** based on cost/statistics. You can hint/force order with `STRAIGHT_JOIN` or optimizer hints (`JOIN_ORDER`), but normally you let the optimizer decide. Written order matters only for `STRAIGHT_JOIN` and for readability.

➡ Next: [Day 07 — Subqueries & CTEs](day-07-subqueries-cte.md)
