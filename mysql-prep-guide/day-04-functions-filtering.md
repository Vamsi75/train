# Day 04 — Operators, Filtering, String / Date / Numeric Functions

## THEORY

### 1. WHERE operators
- Comparison: `=  <>  !=  <  >  <=  >=  <=>` (the last is **NULL-safe equality**: `NULL <=> NULL` = 1).
- Range: `BETWEEN a AND b` (inclusive).
- Set: `IN (...)`, `NOT IN (...)`.
- Pattern: `LIKE` (`%` = any string, `_` = one char), `NOT LIKE`. `REGEXP`/`RLIKE` for regex.
- NULL: `IS NULL`, `IS NOT NULL`.
- Logical: `AND`, `OR`, `NOT`, parentheses for precedence (`AND` binds tighter than `OR`).

### 2. The NOT IN + NULL trap (very common bug)
`x NOT IN (1, 2, NULL)` returns **no rows ever** when the list contains NULL, because `x <> NULL` is unknown, and `NOT (unknown)` is unknown → never TRUE. Use `NOT EXISTS` or filter NULLs out.

### 3. String functions
`CONCAT`, `CONCAT_WS(sep,...)`, `LENGTH`(bytes) vs `CHAR_LENGTH`(chars), `SUBSTRING(s,pos,len)`, `LEFT`/`RIGHT`, `TRIM`/`LTRIM`/`RTRIM`, `UPPER`/`LOWER`, `REPLACE`, `LOCATE`/`INSTR`, `LPAD`/`RPAD`, `REVERSE`, `FORMAT(n,d)`, `GROUP_CONCAT` (aggregate).

### 4. Date / time functions
`NOW()`/`CURRENT_TIMESTAMP`, `CURDATE()`, `CURTIME()`, `DATE()`, `YEAR()/MONTH()/DAY()`, `DATE_ADD`/`DATE_SUB`/`+ INTERVAL`, `DATEDIFF(a,b)` (days), `TIMESTAMPDIFF(unit,a,b)`, `DATE_FORMAT(d,'%Y-%m-%d')`, `STR_TO_DATE`, `LAST_DAY`, `WEEKDAY`, `EXTRACT`.

### 5. Numeric / math
`ROUND(n,d)`, `CEIL`/`FLOOR`, `ABS`, `MOD`/`%`, `POW`, `SQRT`, `TRUNCATE(n,d)`, `RAND()`, `SIGN`, `GREATEST`/`LEAST`.

### 6. Conditional / NULL-handling functions
- `IF(cond, a, b)` — single condition.
- `CASE WHEN ... THEN ... ELSE ... END` — multi-branch (SQL standard, portable).
- `IFNULL(x, alt)` — replace NULL.
- `NULLIF(a, b)` — returns NULL if a=b (great for avoiding divide-by-zero: `a / NULLIF(b,0)`).
- `COALESCE(a,b,c,...)` — first non-NULL.

### 7. Type casting
`CAST(x AS DECIMAL(10,2))`, `CONVERT(x, CHAR)`. Implicit conversion in comparisons can **kill indexes** (e.g., comparing an indexed `VARCHAR` to a number forces a scan).

---

## PRACTICE

```sql
USE prep;

-- NOT IN + NULL trap
SELECT * FROM employees WHERE dept_id NOT IN (1, 2, NULL);   -- returns NOTHING
SELECT * FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM (SELECT 1 d UNION SELECT 2) x WHERE x.d = e.dept_id); -- correct

-- NULL-safe equality
SELECT NULL = NULL AS eq, NULL <=> NULL AS nullsafe;

-- String functions
SELECT CONCAT_WS(' ', first_name, last_name) AS full_name,
       UPPER(LEFT(first_name,1)) AS initial,
       CHAR_LENGTH(email) AS email_len
FROM employees;

-- GROUP_CONCAT: list employees per dept on one line
SELECT d.dept_name, GROUP_CONCAT(e.first_name ORDER BY e.first_name SEPARATOR ', ') AS team
FROM departments d LEFT JOIN employees e ON e.dept_id=d.dept_id
GROUP BY d.dept_name;

-- Date math: tenure in years
SELECT first_name, hire_date,
       TIMESTAMPDIFF(YEAR, hire_date, CURDATE()) AS years,
       DATE_FORMAT(hire_date, '%d %b %Y') AS pretty
FROM employees ORDER BY years DESC;

-- CASE: salary bands
SELECT first_name, salary,
  CASE WHEN salary >= 150000 THEN 'A'
       WHEN salary >= 90000  THEN 'B'
       ELSE 'C' END AS band
FROM employees;

-- Safe division with NULLIF
SELECT 100 / NULLIF(0,0) AS safe_div;   -- NULL, not an error

-- Implicit conversion kills index (conceptual)
-- BAD: WHERE varchar_col = 123   → MySQL converts column per row, ignores index
-- GOOD: WHERE varchar_col = '123'
```

**Exercises:**
1. List employees hired in the last 5 years, formatted as `Mon-YYYY`.
2. For each customer, produce a comma-separated list of their order statuses.
3. Write a query that buckets products into price tiers (Low/Mid/High) using CASE.
4. Compute average salary per dept but show `'N/A'` when a dept has no employees.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. `SELECT * FROM t WHERE col NOT IN (1,2,NULL)` returns zero rows even though data exists. Explain.**
The NULL in the list makes the predicate three-valued. `col NOT IN (1,2,NULL)` ≡ `col<>1 AND col<>2 AND col<>NULL`. `col<>NULL` is `UNKNOWN`, so the whole `AND` is never TRUE → no rows. Use `NOT EXISTS`, or ensure the subquery/list has no NULLs.

**Q2. Difference between `LENGTH()` and `CHAR_LENGTH()`?**
`LENGTH` returns the number of **bytes**; `CHAR_LENGTH` returns the number of **characters**. They differ for multi-byte charsets — e.g., a 3-emoji string in utf8mb4 has CHAR_LENGTH 3 but LENGTH 12. For "how many letters," use CHAR_LENGTH.

**Q3. `COALESCE` vs `IFNULL` vs `NULLIF` — when do you use each?**
`IFNULL(a,b)` = 2-arg NULL replacement. `COALESCE(a,b,c,...)` = first non-NULL among many (standard SQL, portable, variadic). `NULLIF(a,b)` returns NULL when a=b — used to turn a sentinel into NULL or guard division: `x / NULLIF(y,0)`.

**Q4. Why does `WHERE DATE(created_at) = '2024-05-01'` perform badly on a large table?**
Wrapping the indexed column in a function (`DATE(...)`) makes the predicate **non-sargable** — the index on `created_at` can't be used, so it's a full scan. Rewrite as a range: `WHERE created_at >= '2024-05-01' AND created_at < '2024-05-02'`, which uses the index.

**Q5. `WHERE phone = 9876543210` where `phone` is `VARCHAR` — what's wrong?**
Comparing a string column to a numeric literal triggers **implicit type conversion**: MySQL converts every row's string to a number, so the index on `phone` is unusable and you get a full scan (plus possible wrong matches like `'09876543210'`). Always quote: `WHERE phone = '9876543210'`.

**Q6. How does `GROUP_CONCAT` silently lose data, and how do you fix it?**
It's capped by `group_concat_max_len` (default 1024 bytes) — longer results are **truncated without error**. Raise it: `SET SESSION group_concat_max_len = 1000000;`. Also remember it skips NULLs and you control ordering/separator explicitly.

**Q7. `ORDER BY RAND()` to get random rows — why is it a performance trap?**
It assigns a random value to **every** row, materializes them, then sorts the entire set — O(n log n) on the full table, no index help. For large tables, sample by random PK range or precompute a random column. Acceptable only on tiny tables.

➡ Next: [Day 05 — Grouping & Aggregation](day-05-grouping-aggregation.md)
