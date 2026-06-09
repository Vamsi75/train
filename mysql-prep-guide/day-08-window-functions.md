# Day 08 — Set Operations & Window Functions

## THEORY

### 1. Set operations
- `UNION` — combines two result sets, **removes duplicates** (sorts → costs more).
- `UNION ALL` — combines, **keeps duplicates** (faster; use unless you truly need dedup).
- `INTERSECT` and `EXCEPT` — added in **MySQL 8.0.31**. Before that, emulate `INTERSECT` with `IN`/`EXISTS` and `EXCEPT` with `NOT EXISTS`/`LEFT JOIN ... IS NULL`.
- Rules: same number of columns, compatible types, column names come from the first SELECT, single `ORDER BY` at the end.

### 2. Window functions (MySQL 8.0+) — the headline feature
A window function computes across a set of rows **related to the current row** *without collapsing* them (unlike GROUP BY). Syntax:
```sql
func() OVER (
  PARTITION BY ...     -- groups (optional)
  ORDER BY ...         -- ordering within partition (optional)
  ROWS/RANGE BETWEEN ... -- frame (optional)
)
```

### 3. Function categories
- **Ranking:** `ROW_NUMBER()` (unique 1,2,3), `RANK()` (gaps on ties: 1,1,3), `DENSE_RANK()` (no gaps: 1,1,2), `NTILE(n)` (buckets), `PERCENT_RANK`, `CUME_DIST`.
- **Aggregate as window:** `SUM/AVG/COUNT/MIN/MAX OVER (...)` → running totals, moving averages, group totals alongside detail.
- **Value/offset:** `LAG(col, n)`, `LEAD(col, n)` (previous/next row), `FIRST_VALUE`, `LAST_VALUE`, `NTH_VALUE`.

### 4. Frames (ROWS vs RANGE)
- `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` — physical row count (moving window).
- `RANGE BETWEEN ...` — logical value range (ties share a frame).
- Default frame when `ORDER BY` is present: `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` — a subtle source of "running total includes all tied rows" surprises.

### 5. Classic uses
- **Top-N per group** without correlated subqueries: `ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC)` then filter `= 1`.
- **Running totals / moving averages.**
- **Deduplication:** keep `ROW_NUMBER()=1` per key.
- **Row-to-row deltas** with `LAG`.

### 6. WINDOW clause (named windows)
```sql
SELECT ..., RANK() OVER w, SUM(x) OVER w
FROM t WINDOW w AS (PARTITION BY a ORDER BY b);
```

---

## PRACTICE

```sql
USE prep;

-- Rank employees by salary within department
SELECT first_name, dept_id, salary,
  ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rn,
  RANK()       OVER (PARTITION BY dept_id ORDER BY salary DESC) AS rnk,
  DENSE_RANK() OVER (PARTITION BY dept_id ORDER BY salary DESC) AS dense
FROM employees;

-- Top earner per department (the clean way to do "top-N per group")
SELECT * FROM (
  SELECT first_name, dept_id, salary,
         ROW_NUMBER() OVER (PARTITION BY dept_id ORDER BY salary DESC) rn
  FROM employees
) t WHERE rn = 1;

-- Running total of payroll ordered by hire date
SELECT first_name, hire_date, salary,
  SUM(salary) OVER (ORDER BY hire_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative
FROM employees;

-- Group total alongside each row (no GROUP BY collapse)
SELECT first_name, dept_id, salary,
  SUM(salary) OVER (PARTITION BY dept_id) AS dept_payroll,
  ROUND(100*salary/SUM(salary) OVER (PARTITION BY dept_id),1) AS pct_of_dept
FROM employees;

-- LAG: salary difference vs previous hire
SELECT first_name, hire_date, salary,
  LAG(salary) OVER (ORDER BY hire_date) AS prev_salary,
  salary - LAG(salary) OVER (ORDER BY hire_date) AS delta
FROM employees;

-- Moving average over 3 events (frame)
SELECT id, created_at, COUNT(*) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS w3
FROM events LIMIT 10;

-- Set operations
SELECT city FROM customers
UNION
SELECT location FROM departments;        -- distinct combined

-- INTERSECT (8.0.31+); fallback shown below
SELECT city FROM customers INTERSECT SELECT location FROM departments;
-- Fallback: SELECT DISTINCT city FROM customers c WHERE EXISTS (SELECT 1 FROM departments d WHERE d.location=c.city);
```

**Exercises:**
1. Find the 2nd-highest-paid employee per department (filter `rn = 2`).
2. Compute a 7-day moving count of events per `event_type`.
3. For each order, show its rank by value among that customer's orders.
4. Deduplicate `customers` if duplicates existed on `name+city`, keeping the lowest `customer_id` (ROW_NUMBER trick).

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. `ROW_NUMBER` vs `RANK` vs `DENSE_RANK` with ties (salaries 100,100,90)?**
- `ROW_NUMBER`: 1, 2, 3 — always unique, ties broken arbitrarily (or by extra ORDER BY).
- `RANK`: 1, 1, 3 — ties share rank, **next rank skips** (gap).
- `DENSE_RANK`: 1, 1, 2 — ties share rank, **no gap**.
Pick `ROW_NUMBER` for "exactly one per group," `DENSE_RANK` for "distinct value ranking."

**Q2. Window function vs GROUP BY — when must you use a window function?**
When you need **per-row detail *and* an aggregate together** (running total, % of group total, rank). GROUP BY collapses rows; window functions preserve every row while attaching the computed value.

**Q3. Can you put a window function in a `WHERE` clause? Why not, and what's the workaround?**
No — window functions are evaluated *after* WHERE/GROUP BY (around the same stage as SELECT), so the value doesn't exist when WHERE runs. Wrap the query in a derived table/CTE and filter on the alias in the outer query.

**Q4. Default window frame gotcha: `SUM(x) OVER (ORDER BY d)` gives unexpected totals on tied dates. Why?**
With `ORDER BY` and no explicit frame, the default is `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. With `RANGE`, **all rows sharing the current ORDER BY value are in the frame together**, so tied dates all get the same running total (the end-of-group value). Use `ROWS BETWEEN ... CURRENT ROW` for a true row-by-row running total.

**Q5. `UNION` vs `UNION ALL` — performance and when to use each?**
`UNION` removes duplicates, which requires a sort/hash dedup pass — extra cost. `UNION ALL` just concatenates — cheaper. Use `UNION ALL` whenever you know there are no duplicates or duplicates are acceptable; only use `UNION` when dedup is required.

**Q6. How do you get "top 3 per group" efficiently in MySQL 8 vs MySQL 5.7?**
**8.0:** `ROW_NUMBER() OVER (PARTITION BY g ORDER BY metric DESC)` in a subquery, filter `<= 3`. **5.7 (no window functions):** emulate with a correlated subquery counting how many rows in the group rank higher (`WHERE (SELECT COUNT(*) FROM t t2 WHERE t2.g=t.g AND t2.metric>t.metric) < 3`) — correct but slower, or use session variables.

**Q7. `LAST_VALUE()` returns the current row's value instead of the partition's last. Why?**
Because of the default frame ending at `CURRENT ROW`. `LAST_VALUE` over the default frame sees only up to the current row, so the "last" is the current row. Fix by specifying `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`.

➡ Next: [Day 09 — Normalization & Schema Design](day-09-normalization-design.md)
