# Day 09 — Normalization, Schema Design & Anti-Patterns

## THEORY

### 1. Why normalize?
Normalization organizes data to **eliminate redundancy** and **avoid update/insert/delete anomalies**. Each fact is stored once, so updating it doesn't require touching many rows.

### 2. The normal forms (know 1NF–3NF cold, BCNF by name)
- **1NF:** atomic values (no repeating groups, no comma-lists in a column), each row unique. *Bad:* `phones = '123,456'`. *Good:* a `phones` child table.
- **2NF:** 1NF **+** no partial dependency — every non-key column depends on the **whole** composite key, not part of it. (Only relevant with composite keys.)
- **3NF:** 2NF **+** no transitive dependency — non-key columns depend **only on the key**, not on other non-key columns. *Bad:* `zip` and `city` both in orders where `zip → city`. Move `zip→city` to a lookup.
- **BCNF:** stricter 3NF — every determinant is a candidate key. Handles edge cases 3NF misses.
- **4NF/5NF:** multi-valued / join dependencies — rarely tested beyond name recognition.

Mnemonic: *"Each non-key column depends on **the key, the whole key, and nothing but the key** (so help me Codd)."* — that one sentence is 1NF→2NF→3NF.

### 3. Denormalization — the deliberate trade-off
Introduce controlled redundancy to **speed up reads** (avoid expensive joins), at the cost of write complexity and consistency risk. Examples: storing `order_total` on `orders` instead of summing items each time; a `comment_count` counter on `posts`. Justified for read-heavy, latency-sensitive paths — but you must keep it in sync (triggers, app logic, or batch).

### 4. Relationship modeling
- **1:1** — same PK shared, or a UNIQUE FK. Often a vertical split for rarely-used columns.
- **1:N** — FK on the "many" side (e.g., `orders.customer_id`).
- **M:N** — a **junction/bridge table** with FKs to both (e.g., `student_course(student_id, course_id)` with composite PK).

### 5. Surrogate vs natural keys (recap + design lens)
Surrogate (`AUTO_INCREMENT`/UUID) keys are stable and narrow — best as PK. UUIDs as PK hurt InnoDB clustering (random inserts → page splits); if you must, use **UUID v7 / ordered UUID** or store as `BINARY(16)` to keep them compact and roughly sequential.

### 6. Common anti-patterns (interviewers probe these)
- **EAV (Entity-Attribute-Value):** `(entity, attr_name, value)` — flexible but kills query performance, typing, and constraints. Use JSON columns or proper columns instead.
- **Comma-separated lists** in a column (violates 1NF; can't index/join).
- **Storing money as FLOAT.**
- **Overusing NULLable columns** that really indicate a missing relationship → split into a child table.
- **Wide tables** with dozens of mostly-NULL columns.
- **No indexes on FK columns** → slow joins and FK checks.

---

## PRACTICE

```sql
USE prep;

-- M:N junction table: employees ↔ projects
CREATE TABLE project_assignments (
  project_id INT NOT NULL,
  emp_id     INT NOT NULL,
  role       VARCHAR(40) NOT NULL,
  allocation TINYINT NOT NULL DEFAULT 100,  -- % of time
  PRIMARY KEY (project_id, emp_id),
  FOREIGN KEY (project_id) REFERENCES projects(project_id) ON DELETE CASCADE,
  FOREIGN KEY (emp_id)     REFERENCES employees(emp_id)    ON DELETE CASCADE
);

-- 1NF violation → fix: a multi-valued "skills" column becomes a child table
CREATE TABLE employee_skills (
  emp_id INT NOT NULL,
  skill  VARCHAR(40) NOT NULL,
  PRIMARY KEY (emp_id, skill),
  FOREIGN KEY (emp_id) REFERENCES employees(emp_id) ON DELETE CASCADE
);
INSERT INTO employee_skills VALUES (1,'SQL'),(1,'Java'),(2,'Python');

-- 3NF: zip→city transitive dependency moved to a lookup table
CREATE TABLE zip_lookup (
  zip  CHAR(6) PRIMARY KEY,
  city VARCHAR(50) NOT NULL
);

-- Compact UUID storage if needed
CREATE TABLE api_tokens (
  id    BINARY(16) PRIMARY KEY,   -- store UUID_TO_BIN(uuid, 1) for ordered layout
  label VARCHAR(50)
);
-- INSERT ... VALUES (UUID_TO_BIN(UUID(), 1), 'svc-a');
-- SELECT BIN_TO_UUID(id,1) FROM api_tokens;

-- Denormalization example: cached order_total
ALTER TABLE orders ADD COLUMN order_total DECIMAL(12,2) NULL;
UPDATE orders o
SET order_total = (SELECT IFNULL(SUM(quantity*unit_price),0)
                   FROM order_items oi WHERE oi.order_id=o.order_id);
SELECT order_id, order_total FROM orders;
```

**Exercises:**
1. Given a denormalized `sales(invoice_no, customer_name, customer_city, product, qty, price)`, decompose it into 3NF tables. Draw the FKs.
2. Model a many-to-many "students take courses with a grade" relationship.
3. Identify the normal-form violation in: `orders(order_id, product_id, product_name, qty)`. Which NF and why?
4. Argue for/against adding a denormalized `comment_count` to a `posts` table.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. Explain 2NF vs 3NF with one concrete example each.**
**2NF** violation needs a composite key: `order_items(order_id, product_id, product_name)` — `product_name` depends only on `product_id` (part of the key), a partial dependency. Move it to `products`. **3NF** violation: `employees(emp_id, dept_id, dept_location)` — `dept_location` depends on `dept_id` (a non-key), a transitive dependency. Move it to `departments`.

**Q2. When is denormalization the *right* call, and how do you keep it consistent?**
When read latency on a hot path matters more than write simplicity and joins are too expensive (analytics dashboards, high-QPS read APIs). Keep it consistent via: triggers, application-layer updates in the same transaction, or scheduled reconciliation jobs — and document the source of truth. Accept eventual drift only where tolerable.

**Q3. Why are UUIDs as a PRIMARY KEY problematic in InnoDB, and how do you mitigate it?**
InnoDB clusters data by PK. Random UUID v4 inserts scatter across the B+tree → page splits, fragmentation, poor cache locality, larger secondary indexes (they embed the PK). Mitigate with **time-ordered UUIDs (v7 / `UUID_TO_BIN(uuid, 1)` byte-swap)** stored as compact `BINARY(16)`, restoring sequential insert behavior.

**Q4. What's the EAV anti-pattern and when (if ever) is it acceptable?**
Entity-Attribute-Value stores attributes as rows `(entity_id, attribute, value)` instead of columns. It destroys type safety, constraints, and query performance (every attribute = a self-join). Acceptable only for genuinely sparse, user-defined, rarely-queried metadata — and even then a **JSON column** is usually better in MySQL 8 (validated, indexable via generated columns).

**Q5. Is a fully normalized schema always best?**
No. Normalization optimizes for write integrity and storage, but heavy read workloads with many joins can suffer. Real systems normalize the transactional core (OLTP) and **denormalize selectively** for read paths, or push aggregates to a separate reporting store/materialized tables. It's an engineering trade-off, not a religion.

**Q6. How do you model a hierarchy (e.g., categories with subcategories) in MySQL?**
Options: **adjacency list** (`parent_id` FK — simple, recursive CTE to traverse), **path enumeration** (`/1/4/9/` string), **nested sets** (left/right bounds — fast reads, costly writes), or **closure table** (a row per ancestor-descendant pair — flexible, more storage). For MySQL 8, adjacency list + recursive CTE is usually the pragmatic default.

**Q7. A table has 60 columns, most NULL for any given row. What does that smell like and how do you fix it?**
It smells like **multiple entity types crammed into one table** (or an EAV-in-disguise). Fix by vertical partitioning: split into related tables by entity/usage (1:1 relationships), or use subtype tables (class-table inheritance), or a JSON column for the truly sparse optional attributes.

➡ Next: [Day 10 — Indexes](day-10-indexes.md)
