# Day 0 — Environment Setup

Get a working MySQL before Day 1. Pick **one** path.

## Option A — Docker (recommended, cleanest)
```bash
# Pull and run MySQL 8.x
docker run --name mysql-prep \
  -e MYSQL_ROOT_PASSWORD=root123 \
  -e MYSQL_DATABASE=prep \
  -p 3306:3306 \
  -d mysql:8.0

# Connect with the CLI client inside the container
docker exec -it mysql-prep mysql -uroot -proot123
```
Stop / start later with `docker stop mysql-prep` / `docker start mysql-prep`. Data persists as long as you don't `docker rm` it. For durable data, add `-v mysql-prep-data:/var/lib/mysql`.

## Option B — Native install
- **Windows:** Download MySQL Installer from dev.mysql.com → choose "Server only" or "Developer Default". Set root password during config.
- **Mac:** `brew install mysql && brew services start mysql`
- **Ubuntu/Debian:** `sudo apt install mysql-server && sudo mysql_secure_installation`

Connect: `mysql -u root -p`

## Recommended GUI clients
- **MySQL Workbench** (official, free) — great for EXPLAIN visualizations.
- **DBeaver** (free, multi-DB).
- **TablePlus** (polished, freemium).

CLI is still required for interviews — practice in the `mysql>` prompt too.

## First commands to verify
```sql
SELECT VERSION();          -- confirm 8.x
SHOW DATABASES;
SHOW ENGINES;              -- confirm InnoDB is DEFAULT
SELECT @@default_storage_engine;
```

## Load the practice schema
```bash
# from this folder
mysql -u root -p prep < _setup/seed.sql
```
Then:
```sql
USE prep;
SHOW TABLES;
SELECT COUNT(*) FROM employees;
```

## Handy session settings while learning
```sql
-- See full query results without paging weirdness
\P cat                 -- (Linux/mac) pager
-- Vertical output for wide rows — VERY useful for EXPLAIN
SELECT ... \G          -- end statement with \G instead of ;
-- Timing
SET profiling = 1;     -- legacy but handy; prefer EXPLAIN ANALYZE on 8.0
```

You're ready. Go to [Day 01](../day-01-rdbms-architecture-datatypes.md).