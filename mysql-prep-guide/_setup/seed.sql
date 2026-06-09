-- ============================================================
-- Common practice schema used across the guide.
-- Run:  mysql -u root -p prep < _setup/seed.sql
-- Idempotent: drops & recreates tables.
-- ============================================================

DROP DATABASE IF EXISTS prep;
CREATE DATABASE prep CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE prep;

-- ---------- HR domain ----------
CREATE TABLE departments (
  dept_id     INT PRIMARY KEY AUTO_INCREMENT,
  dept_name   VARCHAR(50) NOT NULL UNIQUE,
  location    VARCHAR(50)
) ENGINE=InnoDB;

CREATE TABLE employees (
  emp_id      INT PRIMARY KEY AUTO_INCREMENT,
  first_name  VARCHAR(50) NOT NULL,
  last_name   VARCHAR(50) NOT NULL,
  email       VARCHAR(100) UNIQUE,
  hire_date   DATE NOT NULL,
  salary      DECIMAL(10,2) NOT NULL,
  dept_id     INT,
  manager_id  INT,
  CONSTRAINT fk_emp_dept FOREIGN KEY (dept_id) REFERENCES departments(dept_id),
  CONSTRAINT fk_emp_mgr  FOREIGN KEY (manager_id) REFERENCES employees(emp_id)
) ENGINE=InnoDB;

INSERT INTO departments (dept_name, location) VALUES
  ('Engineering','Bangalore'),
  ('Sales','Mumbai'),
  ('HR','Delhi'),
  ('Finance','Mumbai'),
  ('Marketing','Bangalore');

INSERT INTO employees (first_name,last_name,email,hire_date,salary,dept_id,manager_id) VALUES
  ('Asha','Rao','asha@corp.com','2019-03-01',180000,1,NULL),
  ('Vikram','Singh','vikram@corp.com','2020-06-15',120000,1,1),
  ('Neha','Patel','neha@corp.com','2021-01-10',95000,1,1),
  ('Rahul','Mehta','rahul@corp.com','2018-11-20',150000,2,NULL),
  ('Sara','Khan','sara@corp.com','2022-02-01',70000,2,4),
  ('Imran','Sheikh','imran@corp.com','2021-09-05',72000,2,4),
  ('Divya','Nair','divya@corp.com','2020-07-22',88000,3,NULL),
  ('Karan','Gupta','karan@corp.com','2023-03-15',60000,3,7),
  ('Meera','Iyer','meera@corp.com','2019-08-30',135000,4,NULL),
  ('Tom','Fernandes','tom@corp.com','2024-01-05',55000,NULL,NULL); -- no dept yet

-- ---------- Shop domain ----------
CREATE TABLE customers (
  customer_id INT PRIMARY KEY AUTO_INCREMENT,
  name        VARCHAR(80) NOT NULL,
  city        VARCHAR(50),
  created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE products (
  product_id  INT PRIMARY KEY AUTO_INCREMENT,
  name        VARCHAR(80) NOT NULL,
  category    VARCHAR(50),
  price       DECIMAL(10,2) NOT NULL,
  stock       INT NOT NULL DEFAULT 0
) ENGINE=InnoDB;

CREATE TABLE orders (
  order_id    INT PRIMARY KEY AUTO_INCREMENT,
  customer_id INT NOT NULL,
  order_date  DATETIME DEFAULT CURRENT_TIMESTAMP,
  status      ENUM('PENDING','PAID','SHIPPED','CANCELLED') DEFAULT 'PENDING',
  CONSTRAINT fk_order_cust FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
) ENGINE=InnoDB;

CREATE TABLE order_items (
  order_id    INT NOT NULL,
  product_id  INT NOT NULL,
  quantity    INT NOT NULL,
  unit_price  DECIMAL(10,2) NOT NULL,
  PRIMARY KEY (order_id, product_id),
  CONSTRAINT fk_oi_order   FOREIGN KEY (order_id) REFERENCES orders(order_id),
  CONSTRAINT fk_oi_product FOREIGN KEY (product_id) REFERENCES products(product_id)
) ENGINE=InnoDB;

INSERT INTO customers (name, city) VALUES
  ('Acme Corp','Mumbai'),('Globex','Delhi'),('Initech','Bangalore'),
  ('Umbrella','Mumbai'),('Soylent','Chennai');

INSERT INTO products (name, category, price, stock) VALUES
  ('Laptop','Electronics',75000,20),
  ('Mouse','Electronics',800,200),
  ('Keyboard','Electronics',1500,150),
  ('Desk','Furniture',12000,30),
  ('Chair','Furniture',8000,45),
  ('Monitor','Electronics',18000,0);  -- out of stock

INSERT INTO orders (customer_id, status, order_date) VALUES
  (1,'PAID','2024-05-01 10:00:00'),
  (1,'SHIPPED','2024-05-03 14:30:00'),
  (2,'PENDING','2024-05-05 09:15:00'),
  (3,'PAID','2024-05-06 16:45:00'),
  (4,'CANCELLED','2024-05-07 11:00:00');

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
  (1,1,1,75000),(1,2,2,800),
  (2,3,1,1500),(2,5,4,8000),
  (3,2,5,800),
  (4,1,2,75000),(4,4,1,12000);

-- A bigger table for index/perf practice
CREATE TABLE events (
  id          BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id     INT NOT NULL,
  event_type  VARCHAR(30) NOT NULL,
  created_at  DATETIME NOT NULL
) ENGINE=InnoDB;

-- Generate ~100k rows for realistic EXPLAIN behavior (MySQL 8 recursive CTE)
INSERT INTO events (user_id, event_type, created_at)
WITH RECURSIVE seq(n) AS (
  SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 100000
)
SELECT
  (n % 5000) + 1,
  ELT((n % 4) + 1, 'login','click','purchase','logout'),
  TIMESTAMP('2024-01-01') + INTERVAL (n % 200) DAY
FROM seq;

SELECT 'Seed complete' AS status, (SELECT COUNT(*) FROM events) AS event_rows;