# Day 02 — DDL: CREATE / ALTER / DROP, Keys & Constraints

## THEORY

### 1. The three SQL sub-languages
- **DDL** (Data Definition): `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, `RENAME`. Defines structure. **Implicitly commits** in MySQL (can't roll back a DDL inside a transaction — important gotcha).
- **DML** (Data Manipulation): `INSERT`, `UPDATE`, `DELETE`, `SELECT`.
- **DCL** (Data Control): `GRANT`, `REVOKE`.
- **TCL** (Transaction Control): `COMMIT`, `ROLLBACK`, `SAVEPOINT`.

### 2. Creating tables
```sql
CREATE TABLE t (
  id   INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(50) NOT NULL,
  ...
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```
- Always set `utf8mb4` (real Unicode incl. emoji; `utf8` in MySQL is the broken 3-byte alias).
- `CREATE TABLE ... LIKE other` copies structure only; `CREATE TABLE ... AS SELECT ...` copies structure + data (but **not** indexes/constraints).

### 3. Constraints (data integrity enforced by the DB)
| Constraint | Purpose |
|-----------|---------|
| `PRIMARY KEY` | Unique + NOT NULL row identifier. One per table. Becomes the clustered index. |
| `UNIQUE` | No duplicate values (NULLs allowed, multiple NULLs permitted in MySQL). |
| `NOT NULL` | Value required. |
| `FOREIGN KEY` | Referential integrity to a parent table. |
| `CHECK` | Boolean condition (enforced from MySQL **8.0.16+**; silently ignored before that!). |
| `DEFAULT` | Value when none supplied. |
| `AUTO_INCREMENT` | Auto-generated increasing integer. |

### 4. Primary key vs Unique key
- PK: one per table, no NULLs, implies clustered index.
- UNIQUE: many allowed, permits NULLs, is a secondary index.
- A **natural key** (e.g., email) vs **surrogate key** (auto-increment id). Interviews love this — surrogate keys are stable and small; natural keys can change and may be wide.

### 5. Foreign keys & referential actions
```sql
FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
  ON DELETE CASCADE      -- delete children with parent
  ON UPDATE RESTRICT;    -- block parent update if children exist
```
Actions: `CASCADE`, `SET NULL`, `RESTRICT`/`NO ACTION` (default), `SET DEFAULT` (not supported by InnoDB). FKs require both tables on InnoDB and an index on the referenced column.

### 6. ALTER TABLE & online DDL
- `ADD/DROP/MODIFY/CHANGE COLUMN`, `ADD/DROP INDEX`, `ADD/DROP CONSTRAINT`.
- MySQL 8 supports **online DDL** (`ALGORITHM=INPLACE/INSTANT`, `LOCK=NONE`) so many ALTERs don't block writes. `ALGORITHM=INSTANT` (8.0.12+) adds a column in metadata only — milliseconds even on huge tables.
- **Production danger:** a naive `ALTER TABLE` on a 500M-row table with `ALGORITHM=COPY` rebuilds the whole table and can lock/replicate-lag for hours. Use `pt-online-schema-change` or `gh-ost` for big tables.

### 7. TRUNCATE vs DELETE vs DROP
| | TRUNCATE | DELETE | DROP |
|--|----------|--------|------|
| Type | DDL | DML | DDL |
| Removes | all rows | rows (WHERE optional) | the table itself |
| Rollback | ❌ (implicit commit) | ✅ | ❌ |
| Resets AUTO_INCREMENT | ✅ | ❌ | n/a |
| Triggers fired | ❌ | ✅ | n/a |
| Speed on full wipe | fast (drops+recreates) | slow (row by row) | fast |

---

## PRACTICE

```sql
USE prep;

-- Create with constraints
CREATE TABLE projects (
  project_id  INT PRIMARY KEY AUTO_INCREMENT,
  title       VARCHAR(100) NOT NULL,
  budget      DECIMAL(12,2) CHECK (budget >= 0),
  lead_emp_id INT,
  start_date  DATE DEFAULT (CURRENT_DATE),
  CONSTRAINT fk_proj_lead FOREIGN KEY (lead_emp_id)
      REFERENCES employees(emp_id) ON DELETE SET NULL
);

-- CHECK constraint in action (8.0.16+)
INSERT INTO projects (title, budget) VALUES ('Apollo', -5);  -- ERROR 3819

-- Add / modify columns
ALTER TABLE projects ADD COLUMN priority TINYINT DEFAULT 3;
ALTER TABLE projects MODIFY COLUMN title VARCHAR(150) NOT NULL;
ALTER TABLE projects ADD INDEX idx_title (title);

-- INSTANT add column (watch it be near-instant)
ALTER TABLE events ADD COLUMN source VARCHAR(20) NULL, ALGORITHM=INSTANT;

-- FK referential action demo
INSERT INTO projects (title, budget, lead_emp_id) VALUES ('Zephyr', 100000, 2);
DELETE FROM employees WHERE emp_id = 2;   -- will fail: emp 2 manages others (RESTRICT)
-- The project's lead would be SET NULL, but the employee self-FK blocks it.

-- TRUNCATE vs DELETE
SELECT MAX(order_id) FROM orders;
-- DELETE keeps the counter; TRUNCATE resets it. (Don't actually truncate orders — FK children exist.)
```

**Exercises:**
1. Add a `CHECK` that `salary > 0` on `employees`. Try to violate it.
2. Create a composite primary key table (`order_items` already is one — recreate it from scratch).
3. Make a FK with `ON DELETE CASCADE`, insert parent+children, delete the parent, confirm children vanish.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Can you ROLLBACK a `TRUNCATE` or an `ALTER TABLE`?**
No. Both are DDL and cause an **implicit COMMIT** in MySQL. Any open transaction is committed before and after the DDL runs. `DELETE` is DML and *can* be rolled back.

**Q2. You ran `ALTER TABLE big_table ADD COLUMN ...` on production and the site froze. Why, and how should you have done it?**
If MySQL chose `ALGORITHM=COPY` (or LOCK wasn't NONE), it rebuilt the entire table holding a metadata/shared lock, blocking writes and ballooning replication lag. Fix: use `ALGORITHM=INSTANT` (for simple column adds in 8.0.12+) or an online schema-change tool (`gh-ost`, `pt-online-schema-change`) that shadow-copies in chunks with triggers and swaps atomically.

**Q3. Difference between a natural key and a surrogate key — which would you pick for a `users` table and why?**
Natural key = a real attribute (email, SSN). Surrogate = synthetic (auto-increment / UUID). Prefer a surrogate PK because natural keys can change (email updates ripple through every FK), may be large (worsening secondary indexes since InnoDB stores the PK in them), and may not be unique forever. Keep email as a `UNIQUE` constraint, not the PK.

**Q4. Multiple NULLs in a UNIQUE column — allowed?**
Yes in MySQL/InnoDB. NULL ≠ NULL, so a UNIQUE index permits *many* NULL rows. If you need "at most one missing value," that's a different design (e.g., NOT NULL + sentinel, or a partial/functional index trick).

**Q5. Auto-increment behavior after a server restart / rollback — does it reuse gaps?**
No, it doesn't reuse gaps. Rolled-back or deleted IDs are *burned*. In MySQL 8.0 the auto-increment counter is **persisted** to the redo log (fixed the old 5.7 bug where it reset to MAX+1 after restart). Gaps are normal and expected — never rely on contiguous IDs.

**Q6. Before 8.0.16, you added a `CHECK (age >= 18)` constraint and bad data still got in. Why?**
Older MySQL **parsed but ignored** CHECK constraints for compatibility. Validation only became real in 8.0.16. Lesson: verify your version; otherwise enforce in the app or via triggers.

**Q7. What index does a FOREIGN KEY require, and what happens if it's missing?**
InnoDB requires an index on the referencing column(s); if you don't create one, it auto-creates it. The referenced (parent) column must be indexed too (the PK or a UNIQUE/regular index). Missing parent index → FK creation fails.

➡ Next: [Day 03 — DML & SELECT basics](day-03-dml-select-basics.md)