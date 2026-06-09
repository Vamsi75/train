# Day 22 — Security, User Management & SQL Injection

## THEORY

### 1. Authentication & users
- Users are `'name'@'host'` — the **host part is part of the identity** (`app@10.0.%` ≠ `app@localhost`).
- Default auth plugin in 8.0: `caching_sha2_password` (stronger than the old `mysql_native_password`).
```sql
CREATE USER 'app'@'10.0.%' IDENTIFIED BY 'StrongP@ss';
ALTER USER 'app'@'10.0.%' IDENTIFIED BY 'NewP@ss';   -- rotate
```

### 2. Authorization — least privilege
Grant the **minimum** privileges needed. An app account should rarely have `DROP`, `ALTER`, `GRANT`, `FILE`, or `SUPER`.
```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON prep.* TO 'app'@'10.0.%';
-- column-level / table-level granularity:
GRANT SELECT (first_name, last_name) ON prep.employees TO 'reporting'@'%';
REVOKE DELETE ON prep.* FROM 'app'@'10.0.%';
SHOW GRANTS FOR 'app'@'10.0.%';
FLUSH PRIVILEGES;   -- needed only after manual mysql.* table edits
```
- **Roles (8.0+):** bundle privileges, assign to users — manage at scale.
```sql
CREATE ROLE 'readonly';
GRANT SELECT ON prep.* TO 'readonly';
GRANT 'readonly' TO 'analyst'@'%';
SET DEFAULT ROLE 'readonly' TO 'analyst'@'%';
```

### 3. SQL Injection — the #1 application DB vulnerability
Untrusted input concatenated into SQL lets an attacker change the query's meaning.
```python
# VULNERABLE
q = "SELECT * FROM users WHERE name = '" + name + "'"
# input:  name = ' OR '1'='1     → returns all rows
# input:  name = '; DROP TABLE users; --
```
**The fix: parameterized queries / prepared statements.** The driver sends SQL and data **separately**; data is never parsed as SQL.
```python
# SAFE
cursor.execute("SELECT * FROM users WHERE name = %s", (name,))
```
Defense in depth:
- **Always parameterize** (never string-concatenate user input). ORMs do this — but raw/`.raw()` queries can reintroduce the hole.
- **Least-privilege DB account** limits blast radius (a SELECT-only account can't DROP).
- **Input validation / allowlists** for things you *can't* parameterize (column/table names, ORDER BY direction) — validate against a fixed set.
- **Escaping** is a last resort and error-prone; prefer parameters.
- Avoid leaking detailed DB errors to users (info disclosure).

### 4. Encryption
- **In transit:** require TLS (`REQUIRE SSL` on the user, or server `require_secure_transport=ON`).
- **At rest:** InnoDB **tablespace encryption** (`ENCRYPTION='Y'`), encrypted binlogs/redo (8.0), plus disk-level encryption.
- **Application-level**: hash passwords with bcrypt/Argon2 (never store plaintext; never use MySQL's `MD5()`/`SHA2()` alone for passwords — no salt/work factor). Consider column encryption for PII.

### 5. Hardening checklist
- Run `mysql_secure_installation` (remove anonymous users, test DB, disallow remote root).
- No app should connect as `root`. Disable/limit remote root.
- Bind to specific interfaces; firewall port 3306; don't expose to the internet.
- Keep `FILE`, `LOAD DATA LOCAL INFILE` (`local_infile=OFF`) restricted — they can read/write server files.
- Audit logging (Enterprise audit plugin / Percona/MariaDB audit).
- Patch regularly; rotate credentials; use a secrets manager (not creds in code).

### 6. Auditing & monitoring
Track logins, privilege changes, and suspicious queries. `performance_schema`, the audit log plugin, and the general query log (heavy — debugging only) help.

---

## PRACTICE

```sql
USE prep;

-- Create a least-privilege app user + a read-only role
CREATE USER IF NOT EXISTS 'app'@'%' IDENTIFIED BY 'Str0ng#Pass!';
GRANT SELECT, INSERT, UPDATE, DELETE ON prep.* TO 'app'@'%';

CREATE ROLE IF NOT EXISTS 'readonly';
GRANT SELECT ON prep.* TO 'readonly';
CREATE USER IF NOT EXISTS 'analyst'@'%' IDENTIFIED BY 'An@lyst123';
GRANT 'readonly' TO 'analyst'@'%';
SET DEFAULT ROLE 'readonly' TO 'analyst'@'%';

SHOW GRANTS FOR 'app'@'%';
SHOW GRANTS FOR 'analyst'@'%' USING 'readonly';

-- Column-level grant (hide salary from reporting)
GRANT SELECT (emp_id, first_name, last_name, dept_id) ON prep.employees TO 'analyst'@'%';

-- Server-side prepared statement (mirrors what a driver does for you)
PREPARE stmt FROM 'SELECT * FROM customers WHERE city = ?';
SET @c = 'Mumbai';
EXECUTE stmt USING @c;     -- @c is data, never parsed as SQL → injection-proof
DEALLOCATE PREPARE stmt;

-- See the injection mechanism (DO NOT do this in code)
-- Imagine: SELECT * FROM customers WHERE name = '<input>'
SELECT * FROM customers WHERE name = '' OR '1'='1';   -- returns everything → that's the attack

-- Require TLS for a user
-- ALTER USER 'app'@'%' REQUIRE SSL;

-- Encrypted tablespace (if keyring configured)
-- CREATE TABLE secrets (...) ENCRYPTION='Y';
```

**Exercises:**
1. Create a reporting user that can read employees but **not** the `salary` or `email` columns. Verify with `SHOW GRANTS`.
2. Rewrite a vulnerable concatenated query (pick any language) as a parameterized one.
3. Explain how a SELECT-only app account limits the damage of a successful injection.
4. List the steps you'd take to harden a fresh MySQL install exposed to an internal network.

---

## TWISTED / IMPORTANT INTERVIEW QUESTIONS

**Q1. How do prepared statements actually prevent SQL injection?**
The SQL **structure** is sent to and parsed by the server **first**, with placeholders (`?`). The parameter **values** are sent separately and bound as data — they're never compiled as part of the SQL grammar. So `' OR '1'='1` becomes the literal string value being compared, not new SQL logic. Concatenation, by contrast, mixes code and data so input can alter the parse tree.

**Q2. You can't parameterize a table or column name (e.g., dynamic ORDER BY column). How do you stay safe?**
Identifiers can't be bound as parameters. **Validate against an allowlist** of known-good column/table names (a fixed map in code), and only ever interpolate the allowlisted value — never the raw input. For sort direction, map input to a literal `ASC`/`DESC`. Quote identifiers with backticks after validation. Never trust the raw string.

**Q3. Is using an ORM enough to prevent SQL injection?**
Mostly, because ORMs parameterize generated queries — but **not automatically safe**. Raw query escapes (`raw()`, `.exec()`, string-built `WHERE` fragments, dynamic column names, or `LIKE` patterns assembled from input) can reintroduce injection. The principle ("separate code from data / parameterize") matters, not the tool. Audit any raw SQL paths.

**Q4. Why should the application database account not have `DROP`/`ALTER`/`GRANT`/`FILE`?**
**Least privilege limits blast radius.** If the app is compromised (injection, leaked creds), an account with only DML can't drop tables, alter schema, escalate privileges, or read/write server files via `FILE`/`LOAD_FILE`. Schema changes should run under a separate, tightly controlled migration account. This turns a potential catastrophe into a contained incident.

**Q5. What's wrong with storing passwords using MySQL's `SHA2(password)`?**
It's a **fast, unsalted** hash — vulnerable to rainbow tables and brute force (GPUs do billions/sec), and identical passwords produce identical hashes. Use a **slow, salted, adaptive** algorithm designed for passwords (**bcrypt, scrypt, Argon2**) with a per-user salt and a tunable work factor, done in the application layer — not a general-purpose DB hash function.

**Q6. `LOAD DATA LOCAL INFILE` — why is it a security concern?**
With `local_infile` enabled, a **malicious or compromised server** (or MITM) can instruct the *client* to read arbitrary files from the client's filesystem and send them to the server — a client-side file disclosure. It can also be abused for data exfiltration/injection paths. Disable it (`local_infile=OFF`) unless explicitly needed, and restrict the `FILE` privilege on the server side.

**Q7. A user is `'app'@'localhost'` but the app connects over TCP from the same machine and auth fails. Why?**
`'app'@'localhost'` typically matches connections via the **Unix socket**, while a TCP connection to `127.0.0.1` matches `'app'@'127.0.0.1'` (or `@'%'`). MySQL treats `localhost` (socket) and `127.0.0.1` (TCP) as **different hosts**. Create the account for the actual connection method/host, or use `@'%'`/the right IP. The host part is integral to the user's identity.

**Q8. Difference between authentication and authorization in MySQL, and where each is enforced?**
**Authentication** = verifying *who* you are (user + host + credentials/auth plugin) at connect time. **Authorization** = what you're *allowed* to do (privileges/roles via `GRANT`), checked per statement against the privilege tables. A user can authenticate successfully yet be denied an operation by authorization. Both live in the `mysql` system schema (`mysql.user`, `mysql.db`, etc.).

➡ Next: [Day 23 — Production Issues Playbook](day-23-production-issues-playbook.md)
